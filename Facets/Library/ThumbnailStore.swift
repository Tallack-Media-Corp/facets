import CryptoKit
import Foundation
import ImageIO
import MeshKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import UniformTypeIdentifiers

/// Renders and caches model thumbnails. One at a time, so a folder of large models
/// never holds more than one of them in memory. Cached on disk by path, size and date,
/// so an edited file gets a new picture.
///
/// With the library in iCloud Drive, each picture is also kept in the library's own
/// hidden `.thumbnails` folder, keyed by the file's name and date rather than its path,
/// so it syncs: a model that's only in iCloud on this device still shows the picture
/// another device drew.
actor ThumbnailStore {
    static let shared = ThumbnailStore()

    // NSCache is thread-safe; read without hopping onto the actor.
    nonisolated(unsafe) private let memory = NSCache<NSString, PlatformImage>()
    private var snapshotter: ModelSnapshotter?
    private let directory: URL

    init() {
        directory = URL.cachesDirectory.appending(path: "Thumbnails", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 300
        // Costs are decoded bytes (see remember).
        memory.totalCostLimit = 80_000_000
    }

    /// The settings a thumbnail is drawn with, so changing the model colour redraws them.
    struct Look: Sendable, Hashable {
        let colorHex: String
        let usesFileColors: Bool
    }

    /// Bumped when the renderer's look changes (v4: dark colours lifted), so cached
    /// pictures are redrawn.
    private static let renderVersion = 4
    /// Starts every picture's file name, so pictures from an older renderer can be
    /// told apart and cleared (pruneStale).
    private static var versionPrefix: String { "v\(renderVersion)-" }

    static func key(for url: URL, size: Int64?, modified: Date?, pixelSize: Int, look: Look) -> String {
        let raw = "\(url.standardizedFileURL.path)|\(size ?? -1)|\(modified?.timeIntervalSince1970 ?? 0)|\(pixelSize)|\(look.colorHex)|\(look.usesFileColors)"
        return versionPrefix + SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The cached picture, without rendering. Cheap enough to call from a view body.
    nonisolated func cached(_ key: String) -> PlatformImage? {
        memory.object(forKey: key as NSString)
    }

    /// The picture from memory or this device's disk, off the actor so it never waits
    /// behind a render or an iCloud read, and off the main thread as it reads a file.
    @concurrent nonisolated func local(for url: URL, size: Int64?, modified: Date?, pixelSize: Int, look: Look) async -> PlatformImage? {
        let key = Self.key(for: url, size: size, modified: modified, pixelSize: pixelSize, look: look)
        if let image = memory.object(forKey: key as NSString) { return image }
        let file = directory.appending(path: "\(key).png")
        guard let image = Self.image(at: file.path) else { return nil }
        remember(image, forKey: key)
        // Read now, so the local trim drops the least recently used first. (Never in
        // the shared folder: a new date there would sync.)
        try? FileManager.default.setAttributes([.modificationDate: Date.now], ofItemAtPath: file.path)
        // Drawn before the shared copy existed: share it now, without waiting.
        Task { await shareIfMissing(file, for: url, modified: modified, pixelSize: pixelSize, look: look) }
        return image
    }

    func thumbnail(for url: URL, size: Int64?, modified: Date?, pixelSize: Int, look: Look) async -> PlatformImage? {
        let key = Self.key(for: url, size: size, modified: modified, pixelSize: pixelSize, look: look)
        if let image = await local(for: url, size: size, modified: modified, pixelSize: pixelSize, look: look) { return image }
        // The cell scrolled away while it waited its turn.
        guard !Task.isCancelled else { return nil }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // A file that's only in iCloud downloads first, outside this actor: while it
        // does, cached and shared pictures keep coming. At most two at a time.
        guard await Self.ensureLocal(url), !Task.isCancelled else { return nil }
        // Rendering stays one at a time, so only one big model is in memory.
        var model: Model3D?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { readURL in
            model = try? ModelLoader.load(readURL)
        }
        guard let model else { return nil }
        return render(model, key: key, url: url, modified: modified, pixelSize: pixelSize, look: look)
    }

    /// Draws a model the viewer already has open into the library's pictures, at the
    /// sizes the grid and list use. A big model only in iCloud is never downloaded
    /// just for its thumbnail (ModelThumbnail.fetchLimit), so this is how it gets
    /// one, here and, through the shared folder, on the user's other devices.
    func store(_ model: Model3D, for url: URL, size: Int64?, modified: Date?, look: Look) {
        for pixelSize in [256, 512] {
            let key = Self.key(for: url, size: size, modified: modified, pixelSize: pixelSize, look: look)
            if memory.object(forKey: key as NSString) != nil { continue }
            if FileManager.default.fileExists(atPath: directory.appending(path: "\(key).png").path) { continue }
            _ = render(model, key: key, url: url, modified: modified, pixelSize: pixelSize, look: look)
        }
    }

    private func render(_ model: Model3D, key: String, url: URL, modified: Date?, pixelSize: Int, look: Look) -> PlatformImage? {
        if snapshotter == nil { snapshotter = ModelSnapshotter() }
        var appearance = RenderAppearance(baseColor: RenderAppearance.linearColor(hex: look.colorHex) ?? RenderAppearance.defaultColor)
        appearance.usesFileColors = look.usesFileColors
        guard let cgImage = snapshotter?.image(of: model, pixelSize: pixelSize, appearance: appearance) else { return nil }
        let image = PlatformImage.from(cgImage)
        remember(image, forKey: key)
        let file = directory.appending(path: "\(key).png")
        if let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, cgImage, nil)
            CGImageDestinationFinalize(destination)
        }
        shareIfMissing(file, for: url, modified: modified, pixelSize: pixelSize, look: look)
        return image
    }

    /// Reads a picture file, decoded on iOS here rather than on the main thread as it
    /// first draws.
    nonisolated private static func image(at path: String) -> PlatformImage? {
        let image = PlatformImage(contentsOfFile: path)
        #if os(iOS)
        return image?.preparingForDisplay() ?? image
        #else
        return image
        #endif
    }

    /// Caches a picture at its decoded size in bytes, so the memory limit holds.
    nonisolated private func remember(_ image: PlatformImage, forKey key: String) {
        #if os(iOS)
        let pixels = Int(image.size.width * image.scale) * Int(image.size.height * image.scale)
        #else
        let pixels = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh } ?? 0
        #endif
        memory.setObject(image, forKey: key as NSString, cost: pixels * 4)
    }

    private static let downloads = DownloadGate(limit: 2)
    /// Shared pictures still in iCloud fetch a few at a time: each read holds a thread.
    private static let sharedReads = DownloadGate(limit: 2)

    /// Makes sure a file's data is on the device, downloading it from iCloud (or a
    /// storage provider) if need be. Runs off the actor; false if it couldn't.
    nonisolated private static func ensureLocal(_ url: URL) async -> Bool {
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        if status == .current || status == .downloaded { return true }
        // No status: local, unless only an old-style placeholder (".Name.stl.icloud")
        // is there, which the coordinated read below fetches.
        if status == nil, FileManager.default.fileExists(atPath: url.path) { return true }
        await downloads.enter()
        defer { Task { await downloads.leave() } }
        guard !Task.isCancelled else { return false }
        return await Task.detached(priority: .utility) {
            // A coordinated read waits for the download; the block itself needn't read.
            var error: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { _ in }
            return error == nil
        }.value
    }

    // MARK: Shared through iCloud

    /// The library's hidden thumbnail folder, when the library is in iCloud Drive.
    /// (Files hides dot-folders, and the library list skips them.)
    nonisolated private var sharedDirectory: URL? {
        guard LibraryLocation.kind == .iCloud else { return nil }
        return LibraryLocation.current.appending(path: ".thumbnails", directoryHint: .isDirectory)
    }

    /// Path-free, so the same file on another device finds it: name, date, size of
    /// picture and look.
    private static func sharedKey(for url: URL, modified: Date?, pixelSize: Int, look: Look) -> String {
        let raw = "\(url.lastPathComponent)|\(Int(modified?.timeIntervalSince1970 ?? 0))|\(pixelSize)|\(look.colorHex)|\(look.usesFileColors)"
        return versionPrefix + SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Copies a drawn picture into the shared folder, for library files only.
    private func shareIfMissing(_ file: URL, for url: URL, modified: Date?, pixelSize: Int, look: Look) {
        guard let shared = sharedDirectory, url.standardizedFileURL.path.hasPrefix(LibraryLocation.current.path + "/") else { return }
        let destination = shared.appending(path: "\(Self.sharedKey(for: url, modified: modified, pixelSize: pixelSize, look: look)).png")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        try? FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: destination, options: .forReplacing, error: &error) { target in
            try? FileManager.default.copyItem(at: file, to: target)
        }
    }

    /// The picture another device drew for a model that isn't downloaded here. The
    /// thumbnail itself may still be in the cloud; reading it coordinated fetches it,
    /// and it's small.
    /// Tries the size asked for, then larger (scaled down cleanly), then smaller.
    /// Off the actor, like ensureLocal: a read that waits on iCloud holds up nothing else.
    @concurrent nonisolated func sharedThumbnail(for url: URL, modified: Date?, pixelSize: Int, look: Look) async -> PlatformImage? {
        guard let shared = sharedDirectory else { return nil }
        let sizes = [pixelSize] + [512, 256, 128].filter { $0 > pixelSize } + [512, 256, 128].filter { $0 < pixelSize }
        for size in sizes {
            let key = Self.sharedKey(for: url, modified: modified, pixelSize: size, look: look)
            if let image = memory.object(forKey: "shared-\(key)" as NSString) { return image }
            let file = shared.appending(path: "\(key).png")
            // Only ask for files that are there (in the cloud or not); a coordinated
            // read of a missing one would just fail, slowly.
            let placeholder = shared.appending(path: ".\(key).png.icloud")
            let isHere = FileManager.default.fileExists(atPath: file.path)
            guard isHere || FileManager.default.fileExists(atPath: placeholder.path) else { continue }
            if !isHere { await Self.sharedReads.enter() }
            guard !Task.isCancelled else {
                if !isHere { await Self.sharedReads.leave() }
                return nil
            }
            var image: PlatformImage?
            var error: NSError?
            NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &error) { readURL in
                image = Self.image(at: readURL.path)
            }
            if !isHere { await Self.sharedReads.leave() }
            if let image {
                remember(image, forKey: "shared-\(key)")
                return image
            }
        }
        return nil
    }

    /// Empties this device's cache and the library's shared pictures; every device
    /// redraws what it needs.
    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let shared = sharedDirectory {
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: shared, options: .forDeleting, error: &error) { target in
                try? FileManager.default.removeItem(at: target)
            }
        }
    }

    /// Removes pictures an older renderer drew, here and in the library's shared
    /// folder, so each look change doesn't leave a set behind in iCloud Drive.
    /// (Other devices on an older build redraw theirs until they update.)
    func pruneStale() {
        let fileManager = FileManager.default
        let isCurrent = { (name: String) in name.hasPrefix(Self.versionPrefix) || name.hasPrefix(".\(Self.versionPrefix)") }
        for url in (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where !isCurrent(url.lastPathComponent) {
            try? fileManager.removeItem(at: url)
        }
        Self.trim(directory, to: 500_000_000, coordinated: false)
        guard let shared = sharedDirectory else { return }
        for url in (try? fileManager.contentsOfDirectory(at: shared, includingPropertiesForKeys: nil)) ?? [] where !isCurrent(url.lastPathComponent) {
            // A placeholder (".name.png.icloud") stands for the file itself.
            var target = url
            let name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                target = url.deletingLastPathComponent().appending(path: String(name.dropFirst().dropLast(".icloud".count)))
            }
            var error: NSError?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forDeleting, error: &error) { item in
                try? fileManager.removeItem(at: item)
            }
        }
        // Pictures of models since deleted, renamed or recoloured are never asked for
        // again; past a cap the oldest go, and anything still shown is redrawn.
        // shortcut: oldest-first, not per model, and about 3,000 models' pictures fit;
        // remove a model's pictures on purge if redraws ever show.
        Self.trim(shared, to: 300_000_000, coordinated: true)
    }

    private static func trim(_ folder: URL, to limit: Int64, coordinated: Bool) {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        // Placeholders (".name.png.icloud") weigh nothing here; the real ones count.
        let files = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? [])
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .map { ($0, (try? $0.resourceValues(forKeys: keys)) ) }
            .sorted { ($0.1?.contentModificationDate ?? .distantPast) > ($1.1?.contentModificationDate ?? .distantPast) }
        var total: Int64 = 0
        for (url, values) in files {
            total += Int64(values?.fileSize ?? 0)
            guard total > limit else { continue }
            if coordinated {
                var error: NSError?
                NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { item in
                    try? FileManager.default.removeItem(at: item)
                }
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// This device's cache and the library's shared pictures.
    func diskUsage() -> Int64 {
        [directory, sharedDirectory].compactMap { $0 }.reduce(0) { sum, folder in
            let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return sum + urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
    }
}

/// Lets a few downloads run at once and queues the rest.
private actor DownloadGate {
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func enter() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

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

    func thumbnail(for url: URL, size: Int64?, modified: Date?, pixelSize: Int, look: Look) async -> PlatformImage? {
        let key = Self.key(for: url, size: size, modified: modified, pixelSize: pixelSize, look: look)
        if let image = memory.object(forKey: key as NSString) { return image }
        let file = directory.appending(path: "\(key).png")
        if let image = PlatformImage(contentsOfFile: file.path) {
            memory.setObject(image, forKey: key as NSString)
            // Drawn before the shared copy existed: share it now.
            shareIfMissing(file, for: url, modified: modified, pixelSize: pixelSize, look: look)
            return image
        }
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
        memory.setObject(image, forKey: key as NSString)
        let file = directory.appending(path: "\(key).png")
        if let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, cgImage, nil)
            CGImageDestinationFinalize(destination)
        }
        shareIfMissing(file, for: url, modified: modified, pixelSize: pixelSize, look: look)
        return image
    }

    private static let downloads = DownloadGate(limit: 2)

    /// Makes sure a file's data is on the device, downloading it from iCloud (or a
    /// storage provider) if need be. Runs off the actor; false if it couldn't.
    nonisolated private static func ensureLocal(_ url: URL) async -> Bool {
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        if status == nil || status == .current || status == .downloaded { return true }
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
    private var sharedDirectory: URL? {
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
    func sharedThumbnail(for url: URL, modified: Date?, pixelSize: Int, look: Look) async -> PlatformImage? {
        guard let shared = sharedDirectory else { return nil }
        let sizes = [pixelSize] + [512, 256, 128].filter { $0 > pixelSize } + [512, 256, 128].filter { $0 < pixelSize }
        for size in sizes {
            let key = Self.sharedKey(for: url, modified: modified, pixelSize: size, look: look)
            if let image = memory.object(forKey: "shared-\(key)" as NSString) { return image }
            let file = shared.appending(path: "\(key).png")
            // Only ask for files that are there (in the cloud or not); a coordinated
            // read of a missing one would just fail, slowly.
            let placeholder = shared.appending(path: ".\(key).png.icloud")
            guard FileManager.default.fileExists(atPath: file.path) || FileManager.default.fileExists(atPath: placeholder.path) else { continue }
            var image: PlatformImage?
            var error: NSError?
            NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &error) { readURL in
                image = PlatformImage(contentsOfFile: readURL.path)
            }
            if let image {
                memory.setObject(image, forKey: "shared-\(key)" as NSString)
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
    }

    func diskUsage() -> Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
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

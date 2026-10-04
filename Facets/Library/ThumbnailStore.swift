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

    static func key(for url: URL, size: Int64?, modified: Date?, pixelSize: Int, look: Look) -> String {
        let raw = "\(url.standardizedFileURL.path)|\(size ?? -1)|\(modified?.timeIntervalSince1970 ?? 0)|\(pixelSize)|\(look.colorHex)|\(look.usesFileColors)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
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
            shareIfMissing(file, for: url, modified: modified, look: look)
            return image
        }
        // The cell scrolled away while it waited its turn.
        guard !Task.isCancelled else { return nil }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Coordinated, so a file that's only in iCloud downloads first.
        var model: Model3D?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { readURL in
            model = try? ModelLoader.load(readURL)
        }
        guard let model else { return nil }
        if snapshotter == nil { snapshotter = ModelSnapshotter() }
        var appearance = RenderAppearance(baseColor: RenderAppearance.linearColor(hex: look.colorHex) ?? RenderAppearance.defaultColor)
        appearance.usesFileColors = look.usesFileColors
        guard let cgImage = snapshotter?.image(of: model, pixelSize: pixelSize, appearance: appearance) else { return nil }
        let image = PlatformImage.from(cgImage)
        memory.setObject(image, forKey: key as NSString)
        if let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, cgImage, nil)
            CGImageDestinationFinalize(destination)
        }
        shareIfMissing(file, for: url, modified: modified, look: look)
        return image
    }

    // MARK: Shared through iCloud

    /// The library's hidden thumbnail folder, when the library is in iCloud Drive.
    /// (Files hides dot-folders, and the library list skips them.)
    private var sharedDirectory: URL? {
        guard LibraryLocation.kind == .iCloud else { return nil }
        return LibraryLocation.current.appending(path: ".thumbnails", directoryHint: .isDirectory)
    }

    /// Path-free, so the same file on another device finds it: name, date and look.
    private static func sharedKey(for url: URL, modified: Date?, look: Look) -> String {
        let raw = "\(url.lastPathComponent)|\(Int(modified?.timeIntervalSince1970 ?? 0))|\(look.colorHex)|\(look.usesFileColors)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Copies a drawn picture into the shared folder, for library files only.
    private func shareIfMissing(_ file: URL, for url: URL, modified: Date?, look: Look) {
        guard let shared = sharedDirectory, url.standardizedFileURL.path.hasPrefix(LibraryLocation.current.path + "/") else { return }
        let destination = shared.appending(path: "\(Self.sharedKey(for: url, modified: modified, look: look)).png")
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
    func sharedThumbnail(for url: URL, modified: Date?, look: Look) async -> PlatformImage? {
        guard let shared = sharedDirectory else { return nil }
        let key = Self.sharedKey(for: url, modified: modified, look: look)
        if let image = memory.object(forKey: "shared-\(key)" as NSString) { return image }
        let file = shared.appending(path: "\(key).png")
        var image: PlatformImage?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &error) { readURL in
            image = PlatformImage(contentsOfFile: readURL.path)
        }
        if let image { memory.setObject(image, forKey: "shared-\(key)" as NSString) }
        return image
    }

    func clear() {
        memory.removeAllObjects()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func diskUsage() -> Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

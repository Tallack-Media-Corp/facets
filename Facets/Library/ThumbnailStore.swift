import CryptoKit
import Foundation
import ImageIO
import MeshKit
import UIKit
import UniformTypeIdentifiers

/// Renders and caches model thumbnails. One at a time, so a folder of large models
/// never holds more than one of them in memory. Cached on disk by path, size and date,
/// so an edited file gets a new picture.
actor ThumbnailStore {
    static let shared = ThumbnailStore()

    // NSCache is thread-safe; read without hopping onto the actor.
    nonisolated(unsafe) private let memory = NSCache<NSString, UIImage>()
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
    nonisolated func cached(_ key: String) -> UIImage? {
        memory.object(forKey: key as NSString)
    }

    func thumbnail(for url: URL, size: Int64?, modified: Date?, pixelSize: Int, look: Look) async -> UIImage? {
        let key = Self.key(for: url, size: size, modified: modified, pixelSize: pixelSize, look: look)
        if let image = memory.object(forKey: key as NSString) { return image }
        let file = directory.appending(path: "\(key).png")
        if let image = UIImage(contentsOfFile: file.path) {
            memory.setObject(image, forKey: key as NSString)
            return image
        }
        // The cell scrolled away while it waited its turn.
        guard !Task.isCancelled else { return nil }

        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let model = try? ModelLoader.load(url) else { return nil }
        if snapshotter == nil { snapshotter = ModelSnapshotter() }
        var appearance = RenderAppearance(baseColor: RenderAppearance.linearColor(hex: look.colorHex) ?? RenderAppearance.defaultColor)
        appearance.usesFileColors = look.usesFileColors
        guard let cgImage = snapshotter?.image(of: model, pixelSize: pixelSize, appearance: appearance) else { return nil }
        let image = UIImage(cgImage: cgImage)
        memory.setObject(image, forKey: key as NSString)
        if let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, cgImage, nil)
            CGImageDestinationFinalize(destination)
        }
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

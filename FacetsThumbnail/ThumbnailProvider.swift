import MeshKit
import QuickLookThumbnailing
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Thumbnails for STL, 3MF and OBJ in Files and anywhere else the system shows file icons.
/// Rendered the same way as the app's library; very large files fall back to the
/// picture a 3MF carries, because the extension has little memory to work with.
final class ThumbnailProvider: QLThumbnailProvider {
    /// Beyond these file sizes a model won't fit in the extension's memory budget
    /// (a mesh lives twice: in memory and in its Metal buffer). OBJ costs the most
    /// per byte; a 3MF is compressed, so its entries are capped as they inflate too.
    #if os(iOS)
    private static let renderLimitSTL = 20_000_000
    private static let renderLimitOBJ = 8_000_000
    private static let renderLimit3MF = 20_000_000
    private static let inflateLimit = 60_000_000
    #else
    private static let renderLimitSTL = 150_000_000
    private static let renderLimitOBJ = 60_000_000
    private static let renderLimit3MF = 100_000_000
    private static let inflateLimit = 600_000_000
    #endif

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void) {
        let url = request.fileURL
        let maximum = request.maximumSize
        let pixels = Int(max(maximum.width, maximum.height) * request.scale)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let isZip = Self.isZip(url)
        ZipArchive.maximumEntrySize = Self.inflateLimit

        var image: CGImage?
        let limit = isZip ? Self.renderLimit3MF : url.pathExtension.lowercased() == "obj" ? Self.renderLimitOBJ : Self.renderLimitSTL
        if fileSize <= limit, let model = try? ModelLoader.load(url) {
            image = ModelSnapshotter()?.image(of: model, pixelSize: pixels)
        }
        if image == nil, isZip, let data = ThreeMFReader.thumbnailData(at: url) {
            #if os(iOS)
            image = UIImage(data: data)?.cgImage
            #else
            image = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            #endif
        }
        guard let image else {
            handler(nil, ModelError.noGeometry)
            return
        }

        // Fit the picture inside the requested box, keeping its shape.
        let fit = min(maximum.width / CGFloat(max(image.width, 1)), maximum.height / CGFloat(max(image.height, 1)))
        let size = CGSize(width: CGFloat(image.width) * fit, height: CGFloat(image.height) * fit)
        // The drawing block gets a context already scaled to the screen.
        #if os(iOS)
        let picture = UIImage(cgImage: image)
        #else
        let picture = NSImage(cgImage: image, size: size)
        #endif
        let reply = QLThumbnailReply(contextSize: size) {
            picture.draw(in: CGRect(origin: .zero, size: size))
            return true
        }
        handler(reply, nil)
    }

    private static func isZip(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data([0x50, 0x4B, 0x03, 0x04])
    }
}

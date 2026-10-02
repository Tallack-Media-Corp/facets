import MeshKit
import QuickLookThumbnailing
import UIKit

/// Thumbnails for STL, 3MF and OBJ in Files and anywhere else the system shows file icons.
/// Rendered the same way as the app's library; very large files fall back to the
/// picture a 3MF carries, because the extension has little memory to work with.
final class ThumbnailProvider: QLThumbnailProvider {
    /// Beyond these sizes a model won't fit in the extension's memory budget.
    private static let renderLimit3MF = 25_000_000
    private static let renderLimitSTL = 60_000_000

    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void) {
        let url = request.fileURL
        let maximum = request.maximumSize
        let pixels = Int(max(maximum.width, maximum.height) * request.scale)
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let isZip = Self.isZip(url)

        var image: CGImage?
        let limit = isZip ? Self.renderLimit3MF : Self.renderLimitSTL
        if fileSize <= limit, let model = try? ModelLoader.load(url) {
            image = ModelSnapshotter()?.image(of: model, pixelSize: pixels)
        }
        if image == nil, isZip, let data = ThreeMFReader.thumbnailData(at: url) {
            image = UIImage(data: data)?.cgImage
        }
        guard let image else {
            handler(nil, ModelError.noGeometry)
            return
        }

        // Fit the picture inside the requested box, keeping its shape.
        let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        var size = maximum
        if aspect > 1 { size.height = maximum.width / aspect } else { size.width = maximum.height * aspect }
        // The UIKit variant gives a context already scaled to the screen, top-left origin.
        let picture = UIImage(cgImage: image)
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

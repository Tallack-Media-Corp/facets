import MeshKit
import QuickLookThumbnailing
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Thumbnails for STL, 3MF and OBJ in Files and anywhere else the system shows file icons.
/// The same renderer and framing as the app's library, but always in the default
/// Filament Orange with the file's own colours: the extension can't see the app's
/// colour settings. Files past `QuickLookLimits` fall back to the picture a 3MF
/// carries, because the extension has little memory to work with.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void) {
        let url = request.fileURL
        let maximum = request.maximumSize
        let pixels = Int(max(maximum.width, maximum.height) * request.scale)
        let (format, fits) = QuickLookLimits.check(url, for: .thumbnail)

        var image: CGImage?
        if fits, let model = try? ModelLoader.load(url) {
            image = ModelSnapshotter()?.image(of: model, pixelSize: pixels)
        }
        if image == nil, format == .threeMF, let data = ThreeMFReader.thumbnailData(at: url) {
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
}

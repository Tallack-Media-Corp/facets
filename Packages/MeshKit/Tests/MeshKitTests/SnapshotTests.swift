import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MeshKit

/// Renders each file in `MESHKIT_SNAPSHOT_FILES` (colon-separated) to a PNG in
/// `MESHKIT_SNAPSHOT_OUT`, for eyeballing the renderer.
@Suite struct SnapshotTests {
    @Test func rendersSnapshots() throws {
        let env = ProcessInfo.processInfo.environment
        guard let files = env["MESHKIT_SNAPSHOT_FILES"], let out = env["MESHKIT_SNAPSHOT_OUT"] else { return }
        let snapshotter = try #require(ModelSnapshotter())
        for path in files.split(separator: ":") {
            let url = URL(fileURLWithPath: String(path))
            let model = try ModelLoader.load(url)
            let image = try #require(snapshotter.image(of: model, pixelSize: 512))
            let dest = URL(fileURLWithPath: out).appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".png")
            let writer = try #require(CGImageDestinationCreateWithURL(dest as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(writer, image, nil)
            #expect(CGImageDestinationFinalize(writer))
        }
    }
}

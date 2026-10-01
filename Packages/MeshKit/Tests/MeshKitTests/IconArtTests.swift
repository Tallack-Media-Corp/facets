import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MeshKit

/// Draws the app icon artwork, `benchy.png`, from a 3DBenchy STL kept outside the
/// repository. tools/icons/build_icons.py turns it into an Icon Composer document.
///
///     FACETS_BENCHY_STL=~/3DBenchy.stl FACETS_ICON_ART_OUT=tools/icons/art \
///       swift test -Xswiftc -O --filter IconArtTests
@Suite struct IconArtTests {
    /// 15° to port of the classic three-quarter view, a little above the deck.
    static let yaw: Float = 53 * .pi / 180
    static let pitch: Float = 20 * .pi / 180
    static let fill: Float = 0.74

    @Test func drawsBenchyArt() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["FACETS_BENCHY_STL"], let out = env["FACETS_ICON_ART_OUT"] else { return }
        let model = try ModelLoader.load(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
        let folder = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let snapshotter = try #require(ModelSnapshotter())
        let image = try #require(snapshotter.image(of: model, pixelSize: 1024, yaw: Self.yaw, pitch: Self.pitch, fill: Self.fill))
        try writePNG(image, to: folder.appendingPathComponent("benchy.png"))
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
    }
}

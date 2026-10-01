import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import MeshKit

/// Renders a model file to transparent PNGs from several angles, for icon work.
/// Runs only when `FACETS_RENDER_MODEL` (a file) and `FACETS_RENDER_OUT` (a folder)
/// are set; `FACETS_RENDER_YAWS` lists yaw angles in degrees (default 0,45,…,315).
@Suite struct ModelIconTests {
    @Test func rendersAngles() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["FACETS_RENDER_MODEL"], let out = env["FACETS_RENDER_OUT"] else { return }
        let model = try ModelLoader.load(URL(fileURLWithPath: path))
        let snapshotter = try #require(ModelSnapshotter())
        let yaws = (env["FACETS_RENDER_YAWS"] ?? "0,45,90,135,180,225,270,315").split(separator: ",").compactMap { Float($0) }
        let pitch = Float(env["FACETS_RENDER_PITCH"] ?? "22") ?? 22
        let size = Int(env["FACETS_RENDER_SIZE"] ?? "512") ?? 512
        for yaw in yaws {
            let image = try #require(snapshotter.image(of: model, pixelSize: size, yaw: yaw * .pi / 180, pitch: pitch * .pi / 180))
            let url = URL(fileURLWithPath: out).appendingPathComponent("yaw\(Int(yaw)).png")
            let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(dest, image, nil)
            #expect(CGImageDestinationFinalize(dest))
        }
    }
}

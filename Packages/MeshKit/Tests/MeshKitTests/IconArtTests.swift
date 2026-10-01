import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import simd
@testable import MeshKit

/// Draws the app icon artwork from a 3DBenchy STL (kept outside the repository):
/// `benchy.png`, the solid render, and `benchy-wire.svg`, a simplified wireframe in
/// the same pose. tools/icons/build_icons.py turns them into Icon Composer documents.
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

        let target = Int(env["FACETS_WIRE_TRIANGLES"] ?? "400") ?? 400
        let simple = MeshSimplifier.simplify(model.parts[0].geometry, target: target)
        let svg = Self.wireframeSVG(simple)
        try svg.write(to: folder.appendingPathComponent("benchy-wire.svg"), atomically: true, encoding: .utf8)
        print("wireframe: \(simple.triangleCount) triangles")
    }

    /// The simplified mesh as flat SVG on the 1024-point icon canvas: faces lit and
    /// translucent, far to near, each outlined, so nearer facets veil the edges behind.
    static func wireframeSVG(_ geometry: MeshGeometry) -> String {
        let part = ModelPart(id: 0, name: "Benchy", geometry: geometry)
        var camera = OrbitCamera()
        camera.yaw = yaw
        camera.pitch = pitch
        camera.fitTightly([part], aspect: 1, fill: fill)
        let viewMatrix = camera.viewMatrix
        let viewProjection = camera.projectionMatrix(aspect: 1, sceneRadius: geometry.bounds.radius) * viewMatrix
        let p = geometry.positions
        let indices = geometry.indices ?? []

        struct Face { let points: [SIMD2<Float>]; let depth: Float; let light: Float }
        var faces: [Face] = []
        let key = simd_normalize(SIMD3<Float>(-0.45, 0.75, 0.55))
        var t = 0
        while t + 2 < indices.count {
            let world = (0..<3).map { k -> SIMD3<Float> in
                let i = Int(indices[t + k])
                return SIMD3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2])
            }
            t += 3
            let view = world.map { viewMatrix * SIMD4($0, 1) }.map { SIMD3($0.x, $0.y, $0.z) }
            var n = simd_cross(view[1] - view[0], view[2] - view[0])
            guard simd_length(n) > 1e-6 else { continue }
            n = simd_normalize(n)
            let centre = (view[0] + view[1] + view[2]) / 3
            // STL winding faces outward: drop the back of the hull and cabin.
            guard simd_dot(n, -centre) > 0 else { continue }
            let points = world.map { w -> SIMD2<Float> in
                let c = viewProjection * SIMD4(w, 1)
                return SIMD2((c.x / c.w * 0.5 + 0.5) * 1024, (0.5 - c.y / c.w * 0.5) * 1024)
            }
            faces.append(Face(points: points, depth: centre.z, light: max(simd_dot(n, key), 0)))
        }
        faces.sort { $0.depth < $1.depth }

        func f(_ v: Float) -> String { String(format: "%.1f", v) }
        var body = ""
        for face in faces {
            let pts = face.points.map { "\(f($0.x)),\(f($0.y))" }.joined(separator: " ")
            let opacity = 0.16 + 0.5 * face.light
            body += "<polygon points=\"\(pts)\" fill=\"#F59A4A\" fill-opacity=\"\(String(format: "%.2f", opacity))\" stroke=\"#E8742A\" stroke-width=\"7\" stroke-linejoin=\"round\"/>"
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1024\" height=\"1024\" viewBox=\"0 0 1024 1024\">\(body)</svg>\n"
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
    }
}

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import simd
@testable import MeshKit

/// Draws the app icon with the app's own renderer: a faceted icosahedron in the
/// default model colour. Runs only when `FACET_ICON_OUT` names a folder.
@Suite struct IconTests {
    @Test func drawsIcon() throws {
        guard let out = ProcessInfo.processInfo.environment["FACET_ICON_OUT"] else { return }
        let model = Self.icosahedron()
        let snapshotter = try #require(ModelSnapshotter())
        let gem = try #require(snapshotter.image(of: model, pixelSize: 1024))
        try write(icon(gem: gem, top: 0xFFF7EF, bottom: 0xF6DCC6), to: "\(out)/AppIcon.png")
        try write(icon(gem: gem, top: 0x2A2C31, bottom: 0x0C0D10), to: "\(out)/AppIcon-Dark.png")
    }

    static func icosahedron() -> Model3D {
        let phi: Float = (1 + sqrt(5)) / 2
        var v: [SIMD3<Float>] = []
        for a in [-1, 1] as [Float] {
            for b in [-phi, phi] {
                v.append(SIMD3(0, a, b)); v.append(SIMD3(a, b, 0)); v.append(SIMD3(b, 0, a))
            }
        }
        // Faces are the vertex triples two units apart pairwise, wound outward.
        var positions: [Float] = []
        for i in 0..<v.count { for j in (i + 1)..<v.count { for k in (j + 1)..<v.count {
            guard abs(simd_distance(v[i], v[j]) - 2) < 0.01, abs(simd_distance(v[j], v[k]) - 2) < 0.01, abs(simd_distance(v[i], v[k]) - 2) < 0.01 else { continue }
            var tri = [v[i], v[j], v[k]]
            if simd_dot(simd_cross(tri[1] - tri[0], tri[2] - tri[0]), tri[0]) < 0 { tri.swapAt(1, 2) }
            for p in tri { positions += [p.x * 20, p.y * 20, p.z * 20] }
        } } }
        let geometry = MeshGeometry(positions: positions)
        // Tip it so a face, not a point, sits toward the camera.
        let tilt = simd_float4x4(simd_quatf(angle: 0.35, axis: simd_normalize(SIMD3(1, 0.4, 0))))
        return Model3D(format: .stl, parts: [ModelPart(id: 0, name: "Icon", geometry: geometry, transform: tilt)], objects: [ModelObject(id: 0, name: "Icon")])
    }

    private func icon(gem: CGImage, top: UInt32, bottom: UInt32) -> CGImage {
        let size = 1024
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        func color(_ rgb: UInt32) -> CGColor {
            CGColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
        let gradient = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: .zero, options: [])
        // A soft contact shadow under the gem.
        ctx.saveGState()
        ctx.translateBy(x: 512, y: 190)
        ctx.scaleBy(x: 1, y: 0.16)
        let shadow = CGGradient(colorsSpace: space, colors: [CGColor(gray: 0, alpha: 0.28), CGColor(gray: 0, alpha: 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(shadow, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 250, options: [])
        ctx.restoreGState()
        let gemSize: CGFloat = 640
        ctx.draw(gem, in: CGRect(x: (CGFloat(size) - gemSize) / 2, y: 215, width: gemSize, height: gemSize))
        return ctx.makeImage()!
    }

    private func write(_ image: CGImage, to path: String) throws {
        let dest = try #require(CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
    }
}

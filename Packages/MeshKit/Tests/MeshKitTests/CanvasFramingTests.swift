#if canImport(AppKit)
import AppKit
import Foundation
import Testing
import simd
@testable import MeshKit

/// Quick Look picks the plate before the model arrives. Framing that empty plate
/// queued a zoom pulse, which then put the camera back at the origin over the
/// model's framing: multi-plate files showed a corner of the grid, or nothing.
@MainActor @Suite struct CanvasFramingTests {
    @Test func plateChosenBeforeModelStillFramesIt() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        let canvas = ModelCanvasView()
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        window.contentView = canvas
        canvas.renderAppearance.plateID = 1
        // A cube far from the origin, as a plate other than the first sits.
        let model = try ModelLoader.load(binarySTL(cubeTriangles.map { $0.map { $0 + SIMD3(500, 300, 0) } }), name: "Cube")
        canvas.setModel(model)
        #expect(canvas.pulse == nil)
        #expect(simd_distance(canvas.camera.target, SIMD3(500.5, 300.5, 0.5)) < 1)
    }
}
#endif

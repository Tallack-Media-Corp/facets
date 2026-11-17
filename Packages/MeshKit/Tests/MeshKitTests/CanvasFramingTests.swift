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

    /// Reported 17 Nov on iPhone: turned from portrait to landscape, the model stayed
    /// zoomed for the tall view and looked much smaller. A new shape keeps the zoom
    /// relative to a fit: fit before, fit after.
    @Test func newShapeKeepsTheFit() throws {
        let model = try ModelLoader.load(binarySTL(cubeTriangles), name: "Cube")
        func fitted(width: CGFloat, height: CGFloat) -> ModelCanvasView {
            let canvas = ModelCanvasView()
            canvas.frame = NSRect(x: 0, y: 0, width: width, height: height)
            canvas.setModel(model)
            return canvas
        }
        let canvas = fitted(width: 400, height: 800)
        let portrait = canvas.camera.distance
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        canvas.layout()
        let landscape = fitted(width: 800, height: 400).camera.distance
        #expect(landscape < portrait * 0.75)
        #expect(abs(canvas.camera.distance - landscape) < landscape * 0.01)
    }
}
#endif

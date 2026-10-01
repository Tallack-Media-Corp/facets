import Metal
import Testing
@testable import MeshKit

/// The shaders compile from source at runtime, so a typo only shows up as a blank
/// view. Compile them here instead.
@Suite struct ShaderTests {
    @Test func shadersCompile() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        do {
            _ = try device.makeLibrary(source: ShaderSource.metal, options: nil)
        } catch {
            Issue.record("Shader source doesn't compile: \(error)")
        }
        #expect(RenderContext.shared != nil)
    }
}

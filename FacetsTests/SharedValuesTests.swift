import Foundation
import MeshKit
import Testing

/// Values defined once for the app and once for MeshKit or the Quick Look extensions,
/// which must stay the same.
@Suite struct SharedValuesTests {
    /// The One Orange Rule: the app's tint and MeshKit's default model colour.
    @Test func defaultOrangeIsFilamentOrange() {
        #expect(RenderAppearance.linearColor(hex: Palette.filamentOrange) == RenderAppearance.defaultColor)
    }

    /// The Mac's limits (this suite runs on the Mac): the numbers from before the two
    /// extensions shared them, plus the preview's 3MF cap, the same as its thumbnails'.
    @Test func quickLookLimits() {
        let mac = QuickLookLimits.Limits(stl: 150_000_000, obj: 60_000_000, threeMF: 100_000_000, inflate: 600_000_000)
        #expect(QuickLookLimits.limits(for: .preview) == mac)
        #expect(QuickLookLimits.limits(for: .thumbnail) == mac)
    }

    @Test func quickLookTellsA3MFByItsBytes() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let zipNamedSTL = folder.appendingPathComponent("a.stl"), obj = folder.appendingPathComponent("b.obj"), stl = folder.appendingPathComponent("c.STL")
        try Data([0x50, 0x4B, 0x03, 0x04]).write(to: zipNamedSTL)
        try Data("v 0 0 0\n".utf8).write(to: obj)
        try Data("solid x\n".utf8).write(to: stl)
        #expect(QuickLookLimits.format(of: zipNamedSTL) == .threeMF)
        #expect(QuickLookLimits.format(of: obj) == .obj)
        #expect(QuickLookLimits.format(of: stl) == .stl)
    }
}

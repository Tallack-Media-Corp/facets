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

    /// The estimate stays at or above the peak footprints it was fitted to (MeshKit on
    /// the Mac, Metal copy included, after inflated entries were given back as soon as
    /// parsed). Sizes in bytes: file, then each 3MF model entry inflated.
    @Test(arguments: [
        (ModelFormat.threeMF, 2_499_537, [16_949_954], 26_400_000), // 3DBenchy.3mf
        (.threeMF, 19_898_112, [14_207, 2_246, 5_232_307, 8_822_428, 19_435_834, 38_991_202, 37_866_493], 74_000_000), // 4-plate Psyduck
        (.stl, 13_126_084, [], 23_100_000), // Benchy, binary STL
        (.stl, 69_914_784, [], 104_900_000), // Psyduck, binary STL
        (.obj, 8_925_190, [], 29_300_000), // Benchy, OBJ
        (.obj, 48_720_423, [], 119_800_000), // Psyduck, OBJ
    ])
    func quickLookEstimateCoversMeasuredPeaks(format: ModelFormat, fileSize: Int, entries: [Int], measured: Int) {
        let estimate = QuickLookLimits.estimatedPeak(format: format, fileSize: fileSize, modelEntries: entries)
        #expect(estimate >= measured)
        // Not so far over that models that fit are refused.
        #expect(estimate <= measured * 3 / 2)
    }

    @Test func quickLookKeepsAMargin() {
        #expect(QuickLookLimits.fits(estimate: 100_000_000, available: 0))
        #expect(QuickLookLimits.fits(estimate: 100_000_000, available: 116_000_000))
        #expect(!QuickLookLimits.fits(estimate: 100_000_000, available: 115_999_999))
        // The 4-plate Psyduck previewed on an iPhone 15 Pro while its load peaked near
        // 143 MB; the check must never ask for more than that had.
        let psyduck = QuickLookLimits.estimatedPeak(format: .threeMF, fileSize: 19_898_112,
            modelEntries: [14_207, 2_246, 5_232_307, 8_822_428, 19_435_834, 38_991_202, 37_866_493])
        #expect(QuickLookLimits.fits(estimate: psyduck, available: 143_000_000))
        #expect(QuickLookLimits.availableMemory == 0)
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

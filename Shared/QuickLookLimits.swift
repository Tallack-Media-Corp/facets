import Foundation
import MeshKit
import os

/// How large a model the Quick Look extensions (preview and thumbnails) will try to
/// draw. Each has a small memory budget, and a mesh lives twice (in memory and in its
/// Metal buffer); past these, the preview says it's too large and a thumbnail falls
/// back to the picture a 3MF carries, instead of the system stopping them mid-load.
/// OBJ costs the most per byte. A 3MF is compressed, so its entries are also capped as
/// they inflate. The Mac's budgets are larger. Within the limits, the preview also
/// refuses a model whose estimated peak won't fit the memory left (`estimatedPeak`).
enum QuickLookLimits {
    enum Use { case preview, thumbnail }

    /// File sizes, in bytes, and the most one 3MF entry may inflate to.
    struct Limits: Equatable {
        let stl: Int, obj: Int, threeMF: Int, inflate: Int

        func fileSize(for format: ModelFormat) -> Int {
            switch format {
            case .stl, .asciiSTL: stl
            case .obj: obj
            case .threeMF: threeMF
            }
        }
    }

    static func limits(for use: Use) -> Limits {
        #if os(iOS)
        switch use {
        // The preview's 3MF cap is twice the thumbnail's, as its STL cap is.
        case .preview: Limits(stl: 40_000_000, obj: 15_000_000, threeMF: 40_000_000, inflate: 80_000_000)
        case .thumbnail: Limits(stl: 20_000_000, obj: 8_000_000, threeMF: 20_000_000, inflate: 60_000_000)
        }
        #else
        // The Mac's preview has the same budget as its thumbnails.
        switch use {
        case .preview, .thumbnail: Limits(stl: 150_000_000, obj: 60_000_000, threeMF: 100_000_000, inflate: 600_000_000)
        }
        #endif
    }

    /// A 3MF by its bytes, as MeshKit reads it (a 3MF renamed .stl is still a 3MF);
    /// OBJ has nothing to sniff, so it goes by name; anything else reads as STL.
    static func format(of url: URL) -> ModelFormat {
        if ModelLoader.isZip(at: url) { return .threeMF }
        return url.pathExtension.lowercased() == "obj" ? .obj : .stl
    }

    /// The file's format and whether it's small enough to draw: under the size limits,
    /// and for the preview, its estimated peak within the memory it has left. Also sets how
    /// far a 3MF's entries may inflate, so call it before loading.
    static func check(_ url: URL, for use: Use) -> (format: ModelFormat, fits: Bool) {
        let limits = limits(for: use)
        ZipArchive.maximumEntrySize = limits.inflate
        let format = format(of: url)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= limits.fileSize(for: format) else { return (format, false) }
        // shortcut: fitted to the preview only; thumbnails need their own measurements first.
        guard use == .preview else { return (format, true) }
        let estimate = estimatedPeak(format: format, fileSize: size, modelEntries: format == .threeMF ? modelEntrySizes(at: url) : [])
        let available = availableMemory
        let fits = fits(estimate: estimate, available: available)
        // What only a device can tell: how the estimate compares with the budget there.
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "Facets", category: "QuickLook")
            .notice("preview: estimate \(estimate / 1_000_000, privacy: .public) MB, available \(available / 1_000_000, privacy: .public) MB, fits \(fits, privacy: .public)")
        return (format, fits)
    }

    // MARK: Memory

    /// Bytes a load needs at its peak, the mesh's Metal copy included. Fitted to peak
    /// footprints of MeshKit loads measured on the Mac (Benchy and a 1.4M-triangle
    /// project, as 3MF, binary STL and OBJ):
    /// - STL: the mesh is 0.72 × a binary STL and lives twice. ASCII STL makes far less
    ///   mesh per byte, so it's overestimated, which errs safe.
    /// - OBJ: its text becomes vertex lists before the mesh, about 2.5 × the file.
    /// - 3MF: the largest model entry, inflated whole while it's parsed, plus twice the
    ///   mesh, which comes to a quarter of the model XML or less.
    /// Each plus 10 MB for buffers growing as they fill.
    static func estimatedPeak(format: ModelFormat, fileSize: Int, modelEntries: [Int] = []) -> Int {
        let slack = 10_000_000
        return switch format {
        case .stl, .asciiSTL: fileSize * 3 / 2 + slack
        case .obj: fileSize * 5 / 2 + slack
        case .threeMF: (modelEntries.max() ?? 0) + modelEntries.reduce(0, +) / 2 + slack
        }
    }

    /// Whether a load fits what's left, with 16 MB for drawing the first frame. No more
    /// on top: the estimate already runs above every measured peak, and a larger margin
    /// refused files that previewed before (the 4-plate Psyduck on an iPhone 15 Pro).
    /// `available` 0 means unknown (the Mac, the Simulator): then it fits.
    static func fits(estimate: Int, available: Int) -> Bool {
        available == 0 || estimate + 16_000_000 <= available
    }

    /// What the process may still allocate before the system stops it; 0 where there's
    /// no such budget to ask for.
    static var availableMemory: Int {
        #if os(iOS)
        Int(os_proc_available_memory())
        #else
        0
        #endif
    }

    /// What a 3MF's model entries inflate to, read from its ZIP directory without
    /// inflating anything.
    static func modelEntrySizes(at url: URL) -> [Int] {
        guard let archive = try? ZipArchive(url: url) else { return [] }
        return archive.paths.filter { $0.lowercased().hasSuffix(".model") }.compactMap { archive.uncompressedSize(of: $0) }
    }
}

import Foundation
import MeshKit

/// How large a model the Quick Look extensions (preview and thumbnails) will try to
/// draw. Each has a small memory budget, and a mesh lives twice (in memory and in its
/// Metal buffer); past these, the preview says it's too large and a thumbnail falls
/// back to the picture a 3MF carries, instead of the system stopping them mid-load.
/// OBJ costs the most per byte. A 3MF is compressed, so its entries are also capped as
/// they inflate. The Mac's budgets are larger.
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

    /// The file's format and whether it's small enough to draw. Also sets how far a
    /// 3MF's entries may inflate, so call it before loading.
    static func check(_ url: URL, for use: Use) -> (format: ModelFormat, fits: Bool) {
        let limits = limits(for: use)
        ZipArchive.maximumEntrySize = limits.inflate
        let format = format(of: url)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return (format, size <= limits.fileSize(for: format))
    }
}

import CoreGraphics
import Foundation
import Testing

/// Names and paths the library, Spotlight, Recents and thumbnails all go by.
@Suite struct LibraryNamingTests {
    @Test func titleOfAModelTidiesItsFileName() {
        #expect(Format.title(of: URL(filePath: "/x/Eufy_S1_Case_-_Multicolour.stl")) == "Eufy S1 Case – Multicolour")
        // Only the real extension goes.
        #expect(Format.title(of: URL(filePath: "/x/Bracket v1.2.3mf")) == "Bracket v1.2")
    }

    @Test func titleOfAFolderIsItsNameAsTyped() {
        #expect(Format.title(of: URL(filePath: "/x/My_Parts.v2", directoryHint: .isDirectory), isFolder: true) == "My_Parts.v2")
    }

    @Test func placeholderNamesMapBothWays() {
        #expect(ICloudFile.realName(ofPlaceholder: ".Bracket.stl.icloud") == "Bracket.stl")
        #expect(ICloudFile.realName(ofPlaceholder: "Bracket.stl") == nil)
        #expect(ICloudFile.realName(ofPlaceholder: ".DS_Store") == nil)
        #expect(ICloudFile.realName(ofPlaceholder: ".icloud") == nil)
        let real = URL(filePath: "/lib/Parts/Bracket.stl")
        let placeholder = ICloudFile.placeholderURL(for: real)
        #expect(placeholder.path == "/lib/Parts/.Bracket.stl.icloud")
        #expect(ICloudFile.realURL(ofPlaceholder: placeholder) == real)
        #expect(ICloudFile.realURL(ofPlaceholder: real) == nil)
    }

    @Test func downloadedUnlessICloudSaysNot() {
        #expect(ICloudFile.isDownloaded(status: nil))
        #expect(ICloudFile.isDownloaded(status: .current))
        #expect(ICloudFile.isDownloaded(status: .downloaded))
        #expect(!ICloudFile.isDownloaded(status: .notDownloaded))
    }

    @Test func existsHereOrInCloudCountsPlaceholders() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "FacetsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appending(path: ".cloud.stl.icloud"))
        try Data().write(to: folder.appending(path: "here.stl"))
        #expect(ICloudFile.existsHereOrInCloud(folder.appending(path: "cloud.stl")))
        #expect(ICloudFile.existsHereOrInCloud(folder.appending(path: "here.stl")))
        #expect(!ICloudFile.existsHereOrInCloud(folder.appending(path: "gone.stl")))
    }

    @Test func relativePathIsBelowTheLibraryOnly() {
        let root = URL(filePath: "/lib", directoryHint: .isDirectory)
        #expect(LibraryLocation.relativePath(of: URL(filePath: "/lib/a.stl"), in: root) == "a.stl")
        #expect(LibraryLocation.relativePath(of: URL(filePath: "/lib/Parts/./b.stl"), in: root) == "Parts/b.stl")
        #expect(LibraryLocation.relativePath(of: root, in: root) == nil)
        // "/library" isn't inside "/lib".
        #expect(LibraryLocation.relativePath(of: URL(filePath: "/library/a.stl"), in: root) == nil)
        #expect(LibraryLocation.relativePath(of: URL(filePath: "/elsewhere/a.stl"), in: root) == nil)
    }

    @Test func recentlyDeletedIsOutsideUnlessAsked() {
        let root = URL(filePath: "/lib", directoryHint: .isDirectory)
        let deleted = URL(filePath: "/lib/.recently-deleted/1234/a.stl")
        #expect(LibraryLocation.relativePath(of: deleted, in: root) == nil)
        #expect(!LibraryLocation.contains(deleted, in: root))
        #expect(LibraryLocation.relativePath(of: deleted, in: root, includingDeleted: true) == ".recently-deleted/1234/a.stl")
        #expect(LibraryLocation.contains(URL(filePath: "/lib/a.stl"), in: root))
    }

    @Test func relativePathResolvesSymlinks() throws {
        // The temporary folder is under /var, a link to /private/var.
        let root = FileManager.default.temporaryDirectory.appending(path: "FacetsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let resolved = root.resolvingSymlinksInPath().appending(path: "a.stl")
        #expect(LibraryLocation.relativePath(of: resolved, in: root) == "a.stl")
    }
}

/// Thumbnail names are shared through iCloud Drive: a change here makes every device
/// redraw, and devices on different builds stop finding each other's pictures. Bump
/// ThumbnailStore's renderVersion on purpose rather than change these by accident.
@Suite struct ThumbnailKeyTests {
    let look = ThumbnailStore.Look(colorHex: "#FF8800", usesFileColors: true)

    @Test func localKeyIsStable() {
        let key = ThumbnailStore.key(for: URL(filePath: "/Library/Models/Bracket.stl"), size: 1234, modified: Date(timeIntervalSince1970: 1_700_000_000.5), pixelSize: 256, look: look)
        #expect(key == "v4-558b3ac6429632d06fbca07c676afed8a0c2766e668e12f609fd01b680d7c3ee")
        let bare = ThumbnailStore.key(for: URL(filePath: "/Models/a b.3mf"), size: nil, modified: nil, pixelSize: 128, look: .init(colorHex: "#FF8800", usesFileColors: false))
        #expect(bare == "v4-c19a4cf691631f807f69baeac02e80fe32672ad0714aecfe3535bc2fd53ac52d")
    }

    @Test func sharedKeyIsStableAndPathFree() {
        let key = ThumbnailStore.sharedKey(for: URL(filePath: "/Library/Models/Bracket.stl"), modified: Date(timeIntervalSince1970: 1_700_000_000.5), pixelSize: 256, look: look)
        #expect(key == "v4-271af231100c0fafd7843845f4b8863d9faa10c061539291836c33b5a2268bb0")
        // The same file in another device's library.
        #expect(ThumbnailStore.sharedKey(for: URL(filePath: "/elsewhere/Bracket.stl"), modified: Date(timeIntervalSince1970: 1_700_000_000.5), pixelSize: 256, look: look) == key)
        let bare = ThumbnailStore.sharedKey(for: URL(filePath: "/Models/a b.3mf"), modified: nil, pixelSize: 512, look: .init(colorHex: "#FF8800", usesFileColors: false))
        #expect(bare == "v4-8e5d7695c53cea752301ada0ef2437c36b4d4d07a9c72b2fe1af296b665de3c2")
    }

    /// store() draws 512 once and scales it for the 256 copy.
    @Test func scalingKeepsTheShape() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
        let image = try #require(context.makeImage())
        let small = try #require(ThumbnailStore.scaled(image, to: 256))
        #expect(small.width == 256 && small.height == 256)
    }
}

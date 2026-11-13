import Foundation
import Testing

/// Renames, deletes and restores on a temporary library. As an iCloud-kind library,
/// so Recently Deleted lives inside it rather than in Application Support.
@MainActor @Suite final class FileLibraryTests {
    let root: URL
    let library: FileLibrary

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "FacetsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        library = FileLibrary(root: root, location: .iCloud)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ name: String, in folder: URL? = nil) throws -> LibraryItem {
        let url = (folder ?? root).appending(path: name)
        try Data("solid x\nendsolid x\n".utf8).write(to: url)
        return LibraryItem(url: url, isFolder: false, size: nil, modified: nil, childCount: nil)
    }

    private func listed() -> [String] {
        FileLibrary.scan(root, sort: .name, root: root).map(\.url.lastPathComponent).sorted()
    }

    @Test func renameNeverHidesTheFile() throws {
        try library.rename(try file("a.stl"), to: "..old")
        #expect(listed() == ["old.stl"])
    }

    @Test func folderNamedInboxAtTheTopStaysListed() throws {
        let folder = try library.createFolder(in: root, named: "Parts")
        try library.rename(LibraryItem(url: folder, isFolder: true, size: nil, modified: nil, childCount: nil), to: "Inbox")
        #expect(listed() == ["Inbox 2"])
    }

    @Test func capitalsOnlyRenameLeavesNothingBehind() throws {
        let renamed = try library.rename(try file("bracket.stl"), to: "Bracket")
        #expect(renamed.lastPathComponent == "Bracket.stl")
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names == ["Bracket.stl"])
    }

    @Test func deleteSkipsWhatsGoneAndKeepsUndo() throws {
        let present = try file("a.stl")
        let gone = LibraryItem(url: root.appending(path: "gone.stl"), isFolder: false, size: nil, modified: nil, childCount: nil)
        let deleted = try library.delete([gone, present])
        #expect(deleted.count == 1)
        // No empty slot left for the one that failed.
        let slots = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: ".recently-deleted").path)
        #expect(slots.count == 1)
        #expect(library.recentlyDeleted().map(\.name) == ["a"])
        try library.restore(deleted)
        #expect(listed() == ["a.stl"])
    }

    @Test func deleteOfNothingThatExistsThrows() {
        let gone = LibraryItem(url: root.appending(path: "gone.stl"), isFolder: false, size: nil, modified: nil, childCount: nil)
        #expect(throws: (any Error).self) { try library.delete([gone]) }
    }

    @Test func uniqueNameCountsICloudPlaceholders() throws {
        try Data().write(to: root.appending(path: ".a.stl.icloud"))
        #expect(FileLibrary.uniqueURL(for: "a.stl", in: root).lastPathComponent == "a 2.stl")
    }
}

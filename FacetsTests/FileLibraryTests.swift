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

    @Test func deleteSkipsWhatsGoneAndKeepsUndo() async throws {
        let present = try file("a.stl")
        let gone = LibraryItem(url: root.appending(path: "gone.stl"), isFolder: false, size: nil, modified: nil, childCount: nil)
        let deleted = try library.delete([gone, present])
        #expect(deleted.count == 1)
        // No empty slot left for the one that failed.
        let slots = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: ".recently-deleted").path)
        #expect(slots.count == 1)
        #expect(await library.recentlyDeleted().map(\.name) == ["a"])
        try library.restore(deleted)
        #expect(listed() == ["a.stl"])
    }

    @Test func restoreSkipsWhatFailsAndKeepsGoing() async throws {
        let deleted = try library.delete([try file("a.stl"), try file("b.stl")])
        // A read-only slot can't give up its file, so "a" fails first.
        let stuck = try #require(deleted.first { $0.name == "a" }).stored.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: stuck.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stuck.path) }
        let before = library.revision
        let restored = try library.restore(deleted)
        #expect(restored.map(\.lastPathComponent) == ["b.stl"])
        #expect(library.revision > before)
        #expect(listed() == ["b.stl"])
        // The one that failed is still there to restore, note and all.
        #expect(await library.recentlyDeleted().map(\.name) == ["a"])
    }

    @Test func restoreOfNothingThatWorksThrows() throws {
        let deleted = try library.delete([try file("a.stl")])
        let slot = deleted[0].stored.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: slot.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: slot.path) }
        #expect(throws: (any Error).self) { try library.restore(deleted) }
    }

    @Test func deleteOfNothingThatExistsThrows() {
        let gone = LibraryItem(url: root.appending(path: "gone.stl"), isFolder: false, size: nil, modified: nil, childCount: nil)
        #expect(throws: (any Error).self) { try library.delete([gone]) }
    }

    /// What iCloud leaves for a file that isn't downloaded: a small property list
    /// that keeps the real file's size.
    private func placeholder(for name: String, size: Int64, in folder: URL? = nil) throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["NSURLFileSizeKey": size], format: .binary, options: 0)
        try plist.write(to: ICloudFile.placeholderURL(for: (folder ?? root).appending(path: name)))
    }

    @Test func scanListsPlaceholdersByTheirRealNamesAndSizes() throws {
        _ = try file("here.stl")
        try placeholder(for: "cloud.3mf", size: 42_000_000)
        try Data().write(to: root.appending(path: ".DS_Store"))
        try Data().write(to: root.appending(path: "notes.txt"))
        let items = FileLibrary.scan(root, sort: .name, root: root)
        #expect(items.map(\.url.lastPathComponent) == ["cloud.3mf", "here.stl"])
        let cloud = try #require(items.first)
        #expect(cloud.url == root.appending(path: "cloud.3mf"))
        #expect(cloud.size == 42_000_000)
        #expect(!cloud.isDownloaded)
        #expect(items[1].isDownloaded)
    }

    @Test func scanSkipsInboxOnlyAtTheTop() throws {
        try library.createFolder(in: root, named: "Inbox")
        try library.createFolder(in: root, named: "Parts")
        #expect(FileLibrary.scan(root, sort: .name, root: root).map(\.url.lastPathComponent) == ["Parts"])
        let nested = try library.createFolder(in: root.appending(path: "Parts"), named: "Inbox")
        #expect(FileLibrary.scan(nested.deletingLastPathComponent(), sort: .name, root: root).map(\.url.lastPathComponent) == ["Inbox"])
    }

    @Test func scanSortsFoldersFirstThenByTheChosenOrder() throws {
        let fileManager = FileManager.default
        let small = try file("b.stl").url, big = root.appending(path: "a.stl")
        try Data(repeating: 0, count: 4096).write(to: big)
        try library.createFolder(in: root, named: "Z Folder")
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: big.path)
        try fileManager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: small.path)
        let names = { (sort: LibrarySort) in FileLibrary.scan(self.root, sort: sort, root: self.root).map(\.url.lastPathComponent) }
        #expect(names(.name) == ["Z Folder", "a.stl", "b.stl"])
        #expect(names(.size) == ["Z Folder", "a.stl", "b.stl"])
        #expect(names(.modified) == ["Z Folder", "b.stl", "a.stl"])
    }

    @Test func childCountsIncludePlaceholders() throws {
        let parts = try library.createFolder(in: root, named: "Parts")
        _ = try file("a.stl", in: parts)
        try placeholder(for: "b.stl", size: 10, in: parts)
        try Data().write(to: parts.appending(path: ".DS_Store"))
        let counted = FileLibrary.withChildCounts(FileLibrary.scan(root, sort: .name, root: root))
        #expect(counted.first?.childCount == 2)
    }

    @Test func deletedItemsReadOldAbsoluteAndNewRelativeNotes() throws {
        let trash = root.appending(path: ".recently-deleted", directoryHint: .isDirectory)
        // Newer: below the library folder. Older: an absolute path.
        let newer = trash.appending(path: "1", directoryHint: .isDirectory)
        let older = trash.appending(path: "2", directoryHint: .isDirectory)
        for slot in [newer, older] { try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true) }
        try Data("Parts/a.stl".utf8).write(to: newer.appending(path: ".origin"))
        _ = try file("a.stl", in: newer)
        try Data("/old/place/b.stl".utf8).write(to: older.appending(path: ".origin"))
        // Not downloaded here yet: only its placeholder.
        try placeholder(for: "b.stl", size: 10, in: older)
        // A slot without a note is never listed.
        let noted = trash.appending(path: "3", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: noted, withIntermediateDirectories: true)
        _ = try file("c.stl", in: noted)

        let items = FileLibrary.deletedItems(in: [trash], root: root).sorted { $0.name < $1.name }
        #expect(items.map(\.name) == ["a", "b"])
        #expect(items[0].original == root.appending(path: "Parts/a.stl"))
        #expect(items[0].isDownloaded)
        #expect(items[1].original.path == "/old/place/b.stl")
        // Listed under its real name, in its slot.
        #expect(items[1].stored.lastPathComponent == "b.stl")
        #expect(items[1].stored.deletingLastPathComponent().lastPathComponent == older.lastPathComponent)
        #expect(!items[1].isDownloaded)
    }

    @Test func uniqueNameCountsICloudPlaceholders() throws {
        try Data().write(to: root.appending(path: ".a.stl.icloud"))
        #expect(FileLibrary.uniqueURL(for: "a.stl", in: root).lastPathComponent == "a 2.stl")
    }
}

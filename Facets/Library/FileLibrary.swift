import Foundation
import MeshKit
import Observation

/// One entry in a library folder.
struct LibraryItem: Identifiable, Hashable {
    let url: URL
    let isFolder: Bool
    let size: Int64?
    let modified: Date?
    /// Models and subfolders inside a folder.
    let childCount: Int?
    /// False for an iCloud file that's only a placeholder on this device.
    var isDownloaded = true

    var id: URL { url }
    var name: String { isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent }
    /// What a title shows: a model's file name tidied; a folder's name as typed.
    var displayName: String { isFolder ? name : Format.title(fromFileName: name) }
    var fileExtension: String { url.pathExtension.uppercased() }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case name, modified, size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .modified: "Date Modified"
        case .size: "Size"
        }
    }
}

/// The app's Documents folder, which the Files app shows as "On My iPhone › Facets".
/// Only STL and 3MF files and folders are listed; everything else is left alone.
@MainActor
@Observable
final class FileLibrary {
    let root: URL
    /// Bumped after every change made through the app, so open folders reload.
    private(set) var revision = 0

    private let fileManager = FileManager.default

    init() {
        root = URL.documentsDirectory.standardizedFileURL
    }

    func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/")
    }

    func isInInbox(_ url: URL) -> Bool {
        url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root.appending(path: "Inbox").resolvingSymlinksInPath().path + "/")
    }

    func items(in folder: URL, sort: LibrarySort) -> [LibraryItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey]
        // Hidden files aren't skipped by the enumerator, because an iCloud file that
        // isn't downloaded can appear as a hidden ".Name.stl.icloud" placeholder.
        guard let urls = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else {
            return []
        }
        var seen = Set<String>()
        var items: [LibraryItem] = []
        for url in urls {
            var name = url.lastPathComponent
            var isPlaceholder = false
            if name.hasPrefix(".") {
                guard name.hasSuffix(".icloud") else { continue }
                name = String(name.dropFirst().dropLast(".icloud".count))
                isPlaceholder = true
            }
            let realURL = isPlaceholder ? folder.appending(path: name) : url
            guard seen.insert(name).inserted else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                // iOS manages Inbox; it's never a place to browse.
                if folder == root, name == "Inbox" { continue }
                items.append(LibraryItem(url: realURL, isFolder: true, size: nil, modified: values?.contentModificationDate, childCount: childCount(of: realURL)))
                continue
            }
            guard ModelLoader.isSupported(realURL) else { continue }
            let status = values?.ubiquitousItemDownloadingStatus
            let downloaded = !isPlaceholder && (status == nil || status == .current || status == .downloaded)
            items.append(LibraryItem(url: realURL, isFolder: false, size: isPlaceholder ? nil : values?.fileSize.map(Int64.init), modified: values?.contentModificationDate, childCount: nil, isDownloaded: downloaded))
        }
        return items.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            switch sort {
            case .name:
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .modified:
                return (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
            case .size:
                return (a.size ?? 0) > (b.size ?? 0)
            }
        }
    }

    private func childCount(of folder: URL) -> Int {
        let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return urls.filter { url in
            let name = url.lastPathComponent
            if name.hasPrefix(".") {
                // Count iCloud placeholders for models; skip other hidden files.
                return name.hasSuffix(".icloud") && ModelLoader.isSupported(url.deletingPathExtension())
            }
            return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true || ModelLoader.isSupported(url)
        }.count
    }

    /// Every model in the library, for search.
    func allModels() -> [LibraryItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        var result: [LibraryItem] = []
        for case let url as URL in enumerator {
            if url.lastPathComponent == "Inbox", url.deletingLastPathComponent().standardizedFileURL == root {
                enumerator.skipDescendants()
                continue
            }
            guard ModelLoader.isSupported(url) else { continue }
            let values = try? url.resourceValues(forKeys: Set(keys))
            result.append(LibraryItem(url: url, isFolder: false, size: values?.fileSize.map(Int64.init), modified: values?.contentModificationDate, childCount: nil))
        }
        return result
    }

    /// Every folder in the library, root first, for choosing where to move things.
    func allFolders() -> [URL] {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [root] }
        var folders: [URL] = []
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if url.lastPathComponent == "Inbox", url.deletingLastPathComponent().standardizedFileURL == root {
                enumerator.skipDescendants()
                continue
            }
            folders.append(url.standardizedFileURL)
        }
        return [root] + folders.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// The folder path below the library root, for showing where a search hit lives.
    func relativeFolder(of url: URL) -> String? {
        let folder = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath().path
        let base = root.resolvingSymlinksInPath().path
        guard folder.count > base.count, folder.hasPrefix(base) else { return nil }
        return String(folder.dropFirst(base.count + 1))
    }

    // MARK: Changes

    @discardableResult
    func createFolder(in folder: URL, named name: String = "New Folder") throws -> URL {
        let url = uniqueURL(for: name, in: folder)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        revision += 1
        return url
    }

    @discardableResult
    func rename(_ item: LibraryItem, to newName: String) throws -> URL {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !trimmed.isEmpty else { return item.url }
        let fileName = item.isFolder ? trimmed : "\(trimmed).\(item.url.pathExtension)"
        guard fileName != item.url.lastPathComponent else { return item.url }
        let destination = uniqueURL(for: fileName, in: item.url.deletingLastPathComponent())
        try fileManager.moveItem(at: item.url, to: destination)
        revision += 1
        return destination
    }

    // MARK: Recently Deleted

    /// A deleted file or folder, kept for 30 days so it can come back.
    struct DeletedItem: Identifiable, Hashable {
        /// Where it lives in the trash.
        let stored: URL
        /// Where it was in the library.
        let original: URL
        let deletedAt: Date
        let isFolder: Bool

        var id: URL { stored }
        var name: String { isFolder ? original.lastPathComponent : original.deletingPathExtension().lastPathComponent }
        var displayName: String { isFolder ? name : Format.title(fromFileName: name) }
    }

    /// Outside Documents, so the Files app never shows it.
    private var trash: URL { URL.applicationSupportDirectory.appending(path: "Recently Deleted", directoryHint: .isDirectory) }
    static let keepDeletedFor: TimeInterval = 30 * 24 * 60 * 60

    /// Moves items to Recently Deleted. Returns what's needed to put them back.
    @discardableResult
    func delete(_ items: [LibraryItem]) throws -> [DeletedItem] {
        var deleted: [DeletedItem] = []
        for item in items {
            // Each in its own folder, with a note of where it came from, so two files
            // of the same name never collide and a restore knows where to go.
            let slot = trash.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: slot, withIntermediateDirectories: true)
            let stored = slot.appending(path: item.url.lastPathComponent)
            try fileManager.moveItem(at: item.url, to: stored)
            try Data(item.url.path.utf8).write(to: slot.appending(path: ".origin"))
            deleted.append(DeletedItem(stored: stored, original: item.url, deletedAt: .now, isFolder: item.isFolder))
        }
        revision += 1
        return deleted
    }

    /// Puts deleted items back where they were, or under a new name if that spot is
    /// taken now, or at the library root if their folder is gone.
    @discardableResult
    func restore(_ items: [DeletedItem]) throws -> [URL] {
        var restored: [URL] = []
        for item in items where fileManager.fileExists(atPath: item.stored.path) {
            var folder = item.original.deletingLastPathComponent()
            if !fileManager.fileExists(atPath: folder.path) { folder = root }
            let destination = uniqueURL(for: item.original.lastPathComponent, in: folder)
            try fileManager.moveItem(at: item.stored, to: destination)
            try? fileManager.removeItem(at: item.stored.deletingLastPathComponent())
            restored.append(destination)
        }
        revision += 1
        return restored
    }

    func recentlyDeleted() -> [DeletedItem] {
        let slots = (try? fileManager.contentsOfDirectory(at: trash, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return slots.compactMap { slot -> DeletedItem? in
            guard let originPath = try? String(contentsOf: slot.appending(path: ".origin"), encoding: .utf8),
                  let stored = (try? fileManager.contentsOfDirectory(at: slot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]))?.first else { return nil }
            let date = (try? slot.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
            let isFolder = (try? stored.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return DeletedItem(stored: stored, original: URL(fileURLWithPath: originPath), deletedAt: date, isFolder: isFolder)
        }
        .sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Deletes for good.
    func purge(_ items: [DeletedItem]) {
        for item in items {
            try? fileManager.removeItem(at: item.stored.deletingLastPathComponent())
        }
        revision += 1
    }

    /// Clears anything kept longer than 30 days. Called at launch.
    func purgeExpired() {
        let cutoff = Date.now.addingTimeInterval(-Self.keepDeletedFor)
        purge(recentlyDeleted().filter { $0.deletedAt < cutoff })
    }

    /// True if the library root already has a file with this name and size, so a
    /// browsed model shows as saved.
    func hasCopy(of url: URL) -> Bool {
        let candidate = root.appending(path: url.lastPathComponent)
        guard let mine = try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              let theirs = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return mine == theirs
    }

    @discardableResult
    func duplicate(_ item: LibraryItem) throws -> URL {
        let base = item.url.deletingPathExtension().lastPathComponent
        let name = item.isFolder ? "\(item.url.lastPathComponent) copy" : "\(base) copy.\(item.url.pathExtension)"
        let destination = uniqueURL(for: name, in: item.url.deletingLastPathComponent())
        try fileManager.copyItem(at: item.url, to: destination)
        revision += 1
        return destination
    }

    func move(_ items: [LibraryItem], to folder: URL) throws {
        for item in items where item.url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL {
            // A folder can't go inside itself.
            if item.isFolder, folder.standardizedFileURL.path.hasPrefix(item.url.standardizedFileURL.path) { continue }
            try fileManager.moveItem(at: item.url, to: uniqueURL(for: item.url.lastPathComponent, in: folder))
        }
        revision += 1
    }

    /// Copies files picked from elsewhere into a library folder. Returns the copies.
    @discardableResult
    func importFiles(_ urls: [URL], into folder: URL) throws -> [URL] {
        var copied: [URL] = []
        var firstError: Error?
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let destination = uniqueURL(for: url.lastPathComponent, in: folder)
                // Coordinate, so an iCloud file is downloaded before it's copied.
                var coordinatorError: NSError?
                var copyError: Error?
                NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { readURL in
                    do { try fileManager.copyItem(at: readURL, to: destination) } catch { copyError = error }
                }
                if let error = coordinatorError ?? copyError { throw error }
                copied.append(destination)
            } catch {
                firstError = firstError ?? error
            }
        }
        revision += 1
        if copied.isEmpty, let firstError { throw firstError }
        return copied
    }

    func adoptFromInbox(_ url: URL) throws -> URL {
        let destination = uniqueURL(for: url.lastPathComponent, in: root)
        try fileManager.moveItem(at: url, to: destination)
        revision += 1
        return destination
    }

    /// Something outside the app changed the folder (Files, Finder, a drop).
    func noteExternalChange() {
        revision += 1
    }

    /// "Name.stl", then "Name 2.stl", "Name 3.stl"…
    func uniqueURL(for fileName: String, in folder: URL) -> URL {
        let candidate = folder.appending(path: fileName)
        guard fileManager.fileExists(atPath: candidate.path) else { return candidate }
        let ext = (fileName as NSString).pathExtension
        let base = (fileName as NSString).deletingPathExtension
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let url = folder.appending(path: name)
            if !fileManager.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }
}

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

    var id: URL { url }
    var name: String { isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent }
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
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]
        guard let urls = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return []
        }
        let items = urls.compactMap { url -> LibraryItem? in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isFolder = values?.isDirectory ?? false
            if isFolder {
                // iOS manages Inbox; it's never a place to browse.
                if folder == root, url.lastPathComponent == "Inbox" { return nil }
                return LibraryItem(url: url, isFolder: true, size: nil, modified: values?.contentModificationDate, childCount: childCount(of: url))
            }
            guard ModelLoader.isSupported(url) else { return nil }
            return LibraryItem(url: url, isFolder: false, size: values?.fileSize.map(Int64.init), modified: values?.contentModificationDate, childCount: nil)
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
        let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        return urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true || ModelLoader.isSupported(url)
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

    func delete(_ items: [LibraryItem]) throws {
        for item in items {
            try fileManager.removeItem(at: item.url)
        }
        revision += 1
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

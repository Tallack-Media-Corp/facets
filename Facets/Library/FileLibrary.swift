import Foundation
import MeshKit
import Observation

/// One entry in a library folder.
struct LibraryItem: Identifiable, Hashable, Sendable {
    let url: URL
    let isFolder: Bool
    let size: Int64?
    let modified: Date?
    /// Models and subfolders inside a folder.
    /// Nil until counted: counting means listing every subfolder, which is slow in
    /// iCloud, so a folder's list shows first and the counts follow.
    var childCount: Int?
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

/// The library folder: the app's folder in iCloud Drive, or on the device without
/// iCloud (see `LibraryLocation`). Only STL, 3MF and OBJ files and folders are
/// listed; everything else is left alone.
@MainActor
@Observable
final class FileLibrary {
    private(set) var root: URL
    private(set) var location: LibraryLocation.Kind
    /// Bumped after every change made through the app, so open folders reload.
    private(set) var revision = 0

    private let fileManager = FileManager.default

    init() {
        root = LibraryLocation.current
        location = LibraryLocation.kind
    }

    /// Finds iCloud Drive and moves the library there, bringing any models saved on
    /// the device along. Falls back to the device folder when iCloud is off.
    func connectToICloud() async {
        if let cloud = await LibraryLocation.resolveICloud() {
            let moved = await LibraryLocation.moveDeviceFiles(into: cloud)
            LibraryLocation.use(cloud, kind: .iCloud)
            if root != cloud || moved > 0 {
                root = cloud
                location = .iCloud
                revision += 1
            }
        } else if location == .iCloud {
            LibraryLocation.use(LibraryLocation.deviceRoot, kind: .device)
            root = LibraryLocation.deviceRoot
            location = .device
            revision += 1
        }
    }

    func contains(_ url: URL) -> Bool {
        url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/")
    }

    func isInInbox(_ url: URL) -> Bool {
        url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(LibraryLocation.deviceRoot.appending(path: "Inbox").resolvingSymlinksInPath().path + "/")
    }

    func items(in folder: URL, sort: LibrarySort) -> [LibraryItem] {
        Self.withChildCounts(Self.scan(folder, sort: sort, root: root))
    }

    /// Lists a folder's models and subfolders, without counting what's in the
    /// subfolders. Doesn't touch the main actor, so it runs in the background.
    nonisolated static func scan(_ folder: URL, sort: LibrarySort, root: URL) -> [LibraryItem] {
        let fileManager = FileManager.default
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
                items.append(LibraryItem(url: realURL, isFolder: true, size: nil, modified: values?.contentModificationDate, childCount: nil))
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

    /// Fills in how many models and subfolders each folder holds.
    nonisolated static func withChildCounts(_ items: [LibraryItem]) -> [LibraryItem] {
        items.map { item in
            guard item.isFolder, item.childCount == nil else { return item }
            var counted = item
            counted.childCount = childCount(of: item.url)
            return counted
        }
    }

    nonisolated private static func childCount(of folder: URL) -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return urls.filter { url in
            let name = url.lastPathComponent
            if name.hasPrefix(".") {
                // Count iCloud placeholders for models; skip other hidden files.
                return name.hasSuffix(".icloud") && ModelLoader.isSupported(url.deletingPathExtension())
            }
            return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true || ModelLoader.isSupported(url)
        }.count
    }

    /// Every model in the library, for search, including ones only in iCloud. Walks
    /// the whole tree, so callers run it off the main thread.
    nonisolated static func allModels(in root: URL) -> [LibraryItem] {
        var result: [LibraryItem] = []
        var pending = [root]
        while let folder = pending.popLast() {
            for item in scan(folder, sort: .name, root: root) {
                if item.isFolder { pending.append(item.url) } else { result.append(item) }
            }
        }
        return result
    }

    /// Every folder in the library, root first, for choosing where to move things.
    nonisolated static func allFolders(in root: URL) -> [URL] {
        var folders: [URL] = []
        var pending = [root]
        while let folder = pending.popLast() {
            for item in scan(folder, sort: .name, root: root) where item.isFolder {
                folders.append(item.url.standardizedFileURL)
                pending.append(item.url)
            }
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
    /// Recently Deleted: inside the library when it's in iCloud Drive (hidden), so a
    /// delete is a move within iCloud that needs no download, works offline and
    /// syncs; on the device otherwise.
    private var trash: URL {
        location == .iCloud
            ? root.appending(path: ".recently-deleted", directoryHint: .isDirectory)
            : deviceTrash
    }
    /// Where Recently Deleted always was before iCloud; still read, so nothing in it
    /// is lost.
    private var deviceTrash: URL { URL.applicationSupportDirectory.appending(path: "Recently Deleted", directoryHint: .isDirectory) }
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
            var coordinatorError: NSError?
            var moveError: Error?
            NSFileCoordinator().coordinate(writingItemAt: item.url, options: .forMoving, writingItemAt: stored, options: .forReplacing, error: &coordinatorError) { from, to in
                do { try fileManager.moveItem(at: from, to: to) } catch { moveError = error }
            }
            if let error = coordinatorError ?? moveError { throw error }
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
            // Deleted before the library moved to iCloud Drive: back into the library
            // as it is now, not the old device folder.
            let devicePath = LibraryLocation.deviceRoot.path
            if location == .iCloud, folder.path == devicePath || folder.path.hasPrefix(devicePath + "/") {
                folder = root.appending(path: String(folder.path.dropFirst(devicePath.count)))
            }
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
        let folders = trash == deviceTrash ? [trash] : [trash, deviceTrash]
        let slots = folders.flatMap { (try? fileManager.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.creationDateKey])) ?? [] }
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
    /// `size` is the browsed file's, already read when its folder was listed, so this
    /// touches only the library's side (the other may be slow storage).
    func hasCopy(of url: URL, size: Int64?) -> Bool {
        let candidate = root.appending(path: url.lastPathComponent)
        guard let size, let mine = try? candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return Int64(mine) == size
    }

    /// Off the main thread and coordinated, so a model that's only in iCloud
    /// downloads before it's copied.
    @discardableResult
    func duplicate(_ item: LibraryItem) async throws -> URL {
        let base = item.url.deletingPathExtension().lastPathComponent
        let name = item.isFolder ? "\(item.url.lastPathComponent) copy" : "\(base) copy.\(item.url.pathExtension)"
        let destination = uniqueURL(for: name, in: item.url.deletingLastPathComponent())
        let source = item.url
        try await Task.detached(priority: .userInitiated) {
            var coordinatorError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], writingItemAt: destination, options: .forReplacing, error: &coordinatorError) { readURL, writeURL in
                do { try FileManager.default.copyItem(at: readURL, to: writeURL) } catch { copyError = error }
            }
            if let error = coordinatorError ?? copyError { throw error }
        }.value
        revision += 1
        return destination
    }

    func move(_ items: [LibraryItem], to folder: URL) throws {
        for item in items where item.url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL {
            // A folder can't go inside itself.
            let target = folder.standardizedFileURL.path, source = item.url.standardizedFileURL.path
            if item.isFolder, target == source || target.hasPrefix(source + "/") {
                throw CocoaError(.fileWriteInvalidFileName, userInfo: [NSLocalizedDescriptionKey: "A folder can't go inside itself."])
            }
            try fileManager.moveItem(at: item.url, to: uniqueURL(for: item.url.lastPathComponent, in: folder))
        }
        revision += 1
    }

    /// Copies files picked from elsewhere into a library folder. Returns the copies.
    /// Off the main thread and coordinated: a source that's only in iCloud or a
    /// storage provider downloads first, without freezing the screen.
    @discardableResult
    func importFiles(_ urls: [URL], into folder: URL) async throws -> [URL] {
        let result = await Task.detached(priority: .userInitiated) {
            Self.copyIn(urls, to: folder)
        }.value
        revision += 1
        if result.copied.isEmpty, let error = result.error { throw error }
        return result.copied
    }

    nonisolated private static func copyIn(_ urls: [URL], to folder: URL) -> (copied: [URL], error: Error?) {
        let fileManager = FileManager.default
        var copied: [URL] = []
        var firstError: Error?
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let destination = uniqueURL(for: url.lastPathComponent, in: folder)
            var coordinatorError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { readURL in
                do { try fileManager.copyItem(at: readURL, to: destination) } catch { copyError = error }
            }
            if let error = coordinatorError ?? copyError {
                firstError = firstError ?? error
            } else {
                copied.append(destination)
            }
        }
        return (copied, firstError)
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
        Self.uniqueURL(for: fileName, in: folder)
    }

    nonisolated static func uniqueURL(for fileName: String, in folder: URL) -> URL {
        let fileManager = FileManager.default
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

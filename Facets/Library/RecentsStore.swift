import Foundation
import Observation
import os

/// Files opened recently, inside or outside the library. External files are kept as
/// security-scoped bookmarks, so a model opened from iCloud Drive or another app's
/// folder can be reopened without picking it again.
@MainActor
@Observable
final class RecentsStore {
    struct Entry: Codable, Identifiable, Hashable {
        let id: UUID
        var name: String
        var displayName: String { Format.title(fromFileName: name) }
        var fileExtension: String
        var bookmark: Data
        var lastOpened: Date
        var isExternal: Bool
        /// For a file in the library: its path below the library's folder. The
        /// app's container can move (an update, a restore, iCloud turned on), and a
        /// bookmark into it doesn't survive that; a path inside the library does.
        var libraryPath: String?
    }

    private(set) var entries: [Entry] = []
    private let file = URL.applicationSupportDirectory.appending(path: "recents.json")
    private let limit = 40

    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    /// Call while the URL is accessible (inside its security scope).
    func record(_ file: ModelFileRef) {
        guard !SampleModels.isSample(file.url) else { return }
        guard let bookmark = try? Bookmark.make(file.url) else { return }
        let path = file.url.standardizedFileURL.path
        let libraryPath = LibraryLocation.relativePath(of: file.url)
        // The same file, however it was remembered, and dead rows of the same name
        // (left from before the container moved). Each bookmark resolved once: this
        // runs on the main thread as a model opens.
        entries.removeAll { entry in
            if let libraryPath, entry.libraryPath == libraryPath { return true }
            guard let resolved = resolve(entry) else {
                return entry.name == file.name && entry.fileExtension == file.url.pathExtension.uppercased()
            }
            return resolved.standardizedFileURL.path == path
        }
        entries.insert(Entry(
            id: UUID(),
            name: file.name,
            fileExtension: file.url.pathExtension.uppercased(),
            bookmark: bookmark,
            lastOpened: .now,
            isExternal: file.isExternal,
            libraryPath: libraryPath
        ), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    func resolve(_ entry: Entry) -> URL? {
        Self.location(of: entry.libraryPath, bookmark: entry.bookmark)
    }

    nonisolated private static func location(of libraryPath: String?, bookmark: Data) -> URL? {
        if let libraryPath { return LibraryLocation.current.appending(path: libraryPath) }
        var stale = false
        return try? Bookmark.resolve(bookmark, isStale: &stale)
    }

    /// Whether the entry's file is still there and openable (in iCloud counts: it
    /// downloads when opened).
    func isAvailable(_ entry: Entry) -> Bool {
        guard let url = resolve(entry) else { return false }
        return url.withSecurityScope { ICloudFile.existsHereOrInCloud(url) }
    }

    /// What a row shows about an entry's file. Resolving a bookmark and reading the
    /// file's details can be slow (another app's storage, iCloud), so rows do it off
    /// the main thread.
    struct FileState: Sendable, Equatable {
        var url: URL?
        var isAvailable = false
        var size: Int64?
        var modified: Date?
        var isDownloaded = true
    }

    nonisolated static func fileState(for entry: Entry) -> FileState {
        guard let url = location(of: entry.libraryPath, bookmark: entry.bookmark) else { return FileState() }
        return url.withSecurityScope {
            if !FileManager.default.fileExists(atPath: url.path) {
                return FileState(url: url, isAvailable: ICloudFile.existsHereOrInCloud(url), isDownloaded: false)
            }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey])
            return FileState(url: url, isAvailable: true, size: values?.fileSize.map(Int64.init), modified: values?.contentModificationDate,
                             isDownloaded: ICloudFile.isDownloaded(status: values?.ubiquitousItemDownloadingStatus))
        }
    }

    func contains(fileAt url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return entries.contains { resolve($0)?.standardizedFileURL.path == path }
    }

    /// Removes whichever entry points at this file.
    func remove(fileAt url: URL) {
        let path = url.standardizedFileURL.path
        entries.removeAll { resolve($0)?.standardizedFileURL.path == path }
        save()
    }

    /// After a delete: entries for these files, or for anything inside these folders,
    /// so Recents doesn't open them from Recently Deleted.
    func remove(under urls: [URL]) {
        let paths = urls.map { $0.standardizedFileURL.path }
        let before = entries.count
        entries.removeAll { entry in
            guard let path = resolve(entry)?.standardizedFileURL.path else { return false }
            return paths.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
        if entries.count != before { save() }
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// Drops entries whose files are gone for good (deleted, or a bookmark that no
    /// longer resolves). Files only in iCloud count as there. Checked off the main
    /// thread: bookmarks into other apps' storage can be slow to resolve.
    func pruneMissing() async {
        let snapshot = entries
        let gone = await Task.detached(priority: .utility) {
            Set(snapshot.filter { !RecentsStore.fileState(for: $0).isAvailable }.map(\.id))
        }.value
        guard !gone.isEmpty else { return }
        entries.removeAll { gone.contains($0.id) }
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        } catch {
            Logger(subsystem: "Facets", category: "recents").error("Couldn't save Recents: \(error as NSError, privacy: .public)")
        }
    }
}

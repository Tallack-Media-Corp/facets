import Foundation
import Observation

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
        entries.removeAll { resolve($0)?.standardizedFileURL.path == path }
        entries.insert(Entry(
            id: UUID(),
            name: file.name,
            fileExtension: file.url.pathExtension.uppercased(),
            bookmark: bookmark,
            lastOpened: .now,
            isExternal: file.isExternal
        ), at: 0)
        if entries.count > limit { entries.removeLast(entries.count - limit) }
        save()
    }

    func resolve(_ entry: Entry) -> URL? {
        var stale = false
        guard let url = try? Bookmark.resolve(entry.bookmark, isStale: &stale) else { return nil }
        return url
    }

    /// Whether the entry's file is still there and openable.
    func isAvailable(_ entry: Entry) -> Bool {
        guard let url = resolve(entry) else { return false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return FileManager.default.fileExists(atPath: url.path)
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

    nonisolated static func fileState(for bookmark: Data) -> FileState {
        var stale = false
        guard let url = try? Bookmark.resolve(bookmark, isStale: &stale) else { return FileState() }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let fileManager = FileManager.default
        let placeholder = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud")
        if !fileManager.fileExists(atPath: url.path) {
            return FileState(url: url, isAvailable: fileManager.fileExists(atPath: placeholder.path), isDownloaded: false)
        }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey])
        let status = values?.ubiquitousItemDownloadingStatus
        return FileState(url: url, isAvailable: true, size: values?.fileSize.map(Int64.init), modified: values?.contentModificationDate,
                         isDownloaded: status == nil || status == .current || status == .downloaded)
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

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    /// Drops entries whose files are gone (deleted, or a bookmark that no longer resolves).
    func prune() {
        let before = entries.count
        entries.removeAll { entry in
            guard let url = resolve(entry) else { return true }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            return !FileManager.default.fileExists(atPath: url.path)
        }
        if entries.count != before { save() }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

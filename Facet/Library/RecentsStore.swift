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
        guard let bookmark = try? file.url.bookmarkData() else { return }
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
        guard let url = try? URL(resolvingBookmarkData: entry.bookmark, bookmarkDataIsStale: &stale) else { return nil }
        return url
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

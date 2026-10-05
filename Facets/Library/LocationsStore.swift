import Foundation
import Observation

/// Folders outside the app that the user chose to browse: iCloud Drive, On My
/// iPhone, or any storage provider in Files. iOS only lets an app see what the user
/// picks, so each is kept as a security-scoped bookmark and opened on demand.
@MainActor
@Observable
final class LocationsStore {
    struct Location: Codable, Identifiable, Hashable {
        let id: UUID
        var name: String
        var bookmark: Data
        var isCloud: Bool
    }

    private(set) var locations: [Location] = []
    /// Folders currently opened, so access is started once and kept while the app runs.
    // Not observed: filled in while views draw (url(for:)), which mustn't re-render them.
    @ObservationIgnored private var open: [UUID: URL] = [:]
    private let file = URL.applicationSupportDirectory.appending(path: "locations.json")

    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Location].self, from: data) {
            // Earlier builds could add a file as a location; drop any that resolve
            // to one. Ones that don't resolve stay, to show "Add it again".
            locations = saved.filter { location in
                var stale = false
                guard let url = try? Bookmark.resolve(location.bookmark, isStale: &stale) else { return true }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                // Only a definite file goes. A provider that's offline or slow to
                // answer reads as nothing, and the location must survive that.
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                guard let isDirectory = values?.isDirectory else { return true }
                return isDirectory && values?.isPackage != true
            }
            if locations.count != saved.count { save() }
        }
    }

    /// Whether the picked or resolved URL is a folder (a package counts as a file).
    static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    /// Adds a folder picked in the system picker. Picking one that's already listed
    /// just keeps the existing entry.
    @discardableResult
    func add(_ url: URL) throws -> Location {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard Self.isFolder(url) else { throw CocoaError(.fileReadUnsupportedScheme) }
        let path = url.standardizedFileURL.path
        if let existing = locations.first(where: { self.url(for: $0)?.standardizedFileURL.path == path }) {
            return existing
        }
        let bookmark = try Bookmark.make(url)
        let location = Location(id: UUID(), name: Self.displayName(of: url), bookmark: bookmark, isCloud: Self.isCloud(url))
        locations.append(location)
        save()
        return location
    }

    /// The folder's URL with access started, or nil if it's gone or access was revoked.
    func url(for location: Location) -> URL? {
        if let url = open[location.id] { return url }
        var stale = false
        guard let url = try? Bookmark.resolve(location.bookmark, isStale: &stale) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let fresh = try? Bookmark.make(url), let index = locations.firstIndex(where: { $0.id == location.id }) {
            locations[index].bookmark = fresh
            save()
        }
        open[location.id] = url
        return url
    }

    func remove(_ location: Location) {
        open.removeValue(forKey: location.id)?.stopAccessingSecurityScopedResource()
        locations.removeAll { $0.id == location.id }
        save()
    }

    func rename(_ location: Location, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = locations.firstIndex(where: { $0.id == location.id }) else { return }
        locations[index].name = trimmed
        save()
    }

    /// "iCloud Drive" rather than "com~apple~CloudDocs".
    static func displayName(of url: URL) -> String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent
    }

    static func isCloud(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
            || url.path.contains("/Mobile Documents/")
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(locations) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

import Foundation
import Observation

/// A model file to show, and whether it lives outside the app (opened in place from
/// Files or another app), which means it needs security-scoped access.
struct ModelFileRef: Identifiable, Hashable {
    let url: URL
    let isExternal: Bool

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var displayName: String { Format.title(fromFileName: name) }
}

/// App-wide navigation: the selected tab, and a file another app asked us to open.
@MainActor
@Observable
final class Router {
    enum Tab: Hashable {
        case library, recents, settings, search
    }

    var tab: Tab = .library
    /// Shown full screen over everything.
    var presented: ModelFileRef?

    func open(_ url: URL, library: FileLibrary) {
        guard url.isFileURL else { return }
        // "Copy to Facets" from a share sheet lands in Documents/Inbox, which iOS owns
        // and empties. Move it into the library proper so it stays.
        if library.isInInbox(url), let moved = try? library.adoptFromInbox(url) {
            presented = ModelFileRef(url: moved, isExternal: false)
            return
        }
        presented = ModelFileRef(url: url, isExternal: !library.contains(url))
    }
}

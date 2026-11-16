import Foundation

/// Calls back when a folder's contents change on disk, so a file saved from the Files
/// app or another app appears without pulling to refresh.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?

    init?(url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { onChange() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    /// Watches the subfolders among `items`, whose cards show how much each holds: a
    /// file arriving in one (from the Finder, Files or another device through iCloud)
    /// changes no entry of the folder on screen, so its own watcher never hears of it
    /// and the count stayed stale.
    /// shortcut: the first `subfolderLimit` subfolders only, to keep open descriptors
    /// few; watch the rest too if people keep hundreds of folders at one level.
    static func subfolders(of items: [LibraryItem], onChange: @escaping @MainActor @Sendable () -> Void) -> [FolderWatcher] {
        items.filter(\.isFolder).prefix(subfolderLimit).compactMap { FolderWatcher(url: $0.url, onChange: onChange) }
    }

    static let subfolderLimit = 64

    deinit {
        source?.cancel()
    }
}

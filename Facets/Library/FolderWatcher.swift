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

    deinit {
        source?.cancel()
    }
}

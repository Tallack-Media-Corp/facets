import Foundation
import os

/// Where the library lives: the app's folder in iCloud Drive when iCloud is on, so
/// iPhone, iPad and Mac share one library; otherwise the app's own Documents folder
/// (On My iPhone › Facets in Files). iCloud does the syncing; Facets itself still
/// makes no network connections.
enum LibraryLocation {
    enum Kind: String, Sendable {
        case iCloud, device
    }

    /// The app's Documents folder. The share sheet's Inbox is always here, even when
    /// the library is in iCloud.
    static let deviceRoot = URL.documentsDirectory.standardizedFileURL

    private static let state = OSAllocatedUnfairLock(initialState: initial())
    private static let cachedKey = "library.icloudRoot"

    /// The library folder now. Readable from any thread (Spotlight, Shortcuts).
    static var current: URL { state.withLock { $0.root } }
    static var kind: Kind { state.withLock { $0.kind } }

    /// The last iCloud folder seen, so a launch starts where the last one ended
    /// rather than flashing the device folder while iCloud answers.
    private static func initial() -> (root: URL, kind: Kind) {
        if let path = UserDefaults.standard.string(forKey: cachedKey) {
            let url = URL(filePath: path, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: url.path) { return (url, .iCloud) }
        }
        return (deviceRoot, .device)
    }

    /// Asks iCloud for the app's container. Slow the first time on a device (it can
    /// block while iCloud sets the container up), so it runs off the main thread.
    /// Nil when the user isn't signed in to iCloud or has iCloud Drive off for Facets.
    static func resolveICloud() async -> URL? {
        await Task.detached(priority: .userInitiated) {
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
            let documents = container.appending(path: "Documents", directoryHint: .isDirectory).standardizedFileURL
            try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            return documents
        }.value
    }

    static func use(_ root: URL, kind: Kind) {
        state.withLock { $0 = (root, kind) }
        if kind == .iCloud {
            UserDefaults.standard.set(root.path, forKey: cachedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: cachedKey)
        }
    }

    /// Moves what's in the device folder into iCloud Drive, once iCloud is there:
    /// models saved before iCloud was on, or before this version. The Inbox stays
    /// (iOS owns it). Names that clash get a number, as imports do.
    static func moveDeviceFiles(into cloud: URL) async -> Int {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard let items = try? fileManager.contentsOfDirectory(at: deviceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return 0 }
            var moved = 0
            for item in items where item.lastPathComponent != "Inbox" {
                var destination = cloud.appending(path: item.lastPathComponent)
                var n = 2
                let ext = item.pathExtension
                let base = item.deletingPathExtension().lastPathComponent
                while fileManager.fileExists(atPath: destination.path) {
                    destination = cloud.appending(path: ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
                    n += 1
                }
                if (try? fileManager.setUbiquitous(true, itemAt: item, destinationURL: destination)) != nil {
                    moved += 1
                }
            }
            return moved
        }.value
    }
}

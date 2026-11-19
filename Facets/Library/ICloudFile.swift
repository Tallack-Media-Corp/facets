import Foundation

/// iCloud Drive's stand-in for a file that isn't downloaded on this device: a hidden
/// ".Name.stl.icloud" beside where the file would be (older systems, and some folders
/// still). The library lists, counts, names and finds files through these.
enum ICloudFile {
    private static let suffix = ".icloud"

    /// "Name.stl" for ".Name.stl.icloud"; nil for any other name.
    static func realName(ofPlaceholder name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(suffix), name.count > suffix.count + 1 else { return nil }
        return String(name.dropFirst().dropLast(suffix.count))
    }

    /// The file a placeholder stands for, in the same folder; nil if it isn't one.
    static func realURL(ofPlaceholder url: URL) -> URL? {
        realName(ofPlaceholder: url.lastPathComponent).map { url.deletingLastPathComponent().appending(path: $0) }
    }

    /// Where a file's placeholder would be.
    static func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent)\(suffix)")
    }

    /// There, or in iCloud as a placeholder (it downloads when opened).
    static func existsHereOrInCloud(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: placeholderURL(for: url).path)
    }

    /// No status is a file iCloud doesn't manage: local.
    static func isDownloaded(status: URLUbiquitousItemDownloadingStatus?) -> Bool {
        status == nil || status == .current || status == .downloaded
    }
}

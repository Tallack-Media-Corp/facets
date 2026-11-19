import CryptoKit
import Foundation

/// A digest of the library's models, so Spotlight is reindexed only when one is
/// added, removed, renamed or edited (or the app's language changes the descriptions).
enum LibraryFingerprint {
    static func of(_ models: [(url: URL, modified: Date?)], language: String) -> String {
        let lines = models.map { "\($0.url.path)|\($0.modified?.timeIntervalSince1970 ?? 0)" }.sorted()
        let raw = ([language] + lines).joined(separator: "\n")
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

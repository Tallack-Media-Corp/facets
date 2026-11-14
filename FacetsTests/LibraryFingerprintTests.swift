import Foundation
import Testing

/// Spotlight reindexes only when the fingerprint changes.
@Suite struct LibraryFingerprintTests {
    let a = URL(fileURLWithPath: "/Library/a.stl")
    let b = URL(fileURLWithPath: "/Library/b.stl")
    let date = Date(timeIntervalSince1970: 1_000)

    @Test func sameModelsInAnyOrderMatch() {
        #expect(LibraryFingerprint.of([(a, date), (b, nil)], language: "en") == LibraryFingerprint.of([(b, nil), (a, date)], language: "en"))
    }

    @Test func anEditRenameRemovalOrLanguageChangesIt() {
        let base = LibraryFingerprint.of([(a, date), (b, nil)], language: "en")
        #expect(LibraryFingerprint.of([(a, date.addingTimeInterval(1)), (b, nil)], language: "en") != base)
        #expect(LibraryFingerprint.of([(a, date), (URL(fileURLWithPath: "/Library/c.stl"), nil)], language: "en") != base)
        #expect(LibraryFingerprint.of([(a, date)], language: "en") != base)
        #expect(LibraryFingerprint.of([(a, date), (b, nil)], language: "fr") != base)
    }
}

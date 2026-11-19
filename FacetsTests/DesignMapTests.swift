import Foundation
import Testing

/// DESIGN.md's Shared pieces table against the code: every piece it names exists, and
/// every shared file (Facets/UI, Shared) is in it, so the map can't go stale.
@Suite struct DesignMapTests {
    /// The table's rows, from "## Shared pieces" to the next heading.
    static let rows: [String] = {
        guard let text = try? String(contentsOf: RepoSources.root.appendingPathComponent("DESIGN.md"), encoding: .utf8),
              let start = text.range(of: "\n## Shared pieces\n") else { return [] }
        let section = text[start.upperBound...].components(separatedBy: "\n## ").first ?? ""
        return section.components(separatedBy: "\n").filter { $0.hasPrefix("|") && !$0.hasPrefix("|---") && !$0.hasPrefix("| Job") }
    }()

    /// What's in backticks in the Use column.
    static let used: [String] = rows.flatMap { row -> [String] in
        let cells = row.components(separatedBy: "|")
        guard cells.count > 2 else { return [] }
        return cells[2].components(separatedBy: "`").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
    }

    static func isIdentifier(_ name: Substring) -> Bool {
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Names to look for in a backticked piece: `Motion.animation(_:reduceMotion:)` is
    /// Motion and animation, `.glassCard(...)` is glassCard, `url.withSecurityScope { }`
    /// is withSecurityScope (a variable's name isn't a piece), `aboveBottomToolbar:` a label.
    static func names(in piece: String) -> [String] {
        var text = Substring(piece)
        if text.hasPrefix(".") { text = text.dropFirst() }
        let path = text.prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "<" || $0 == ">" }
        let parts = path.split(separator: ".")
        var names: [Substring] = []
        if let first = parts.first, first.first?.isUppercase == true { names.append(first) }
        if parts.count > 1, let last = parts.last { names.append(last) }
        if parts.count == 1, let only = parts.first, only.first?.isUppercase == false { names.append(only) }
        return names.filter(isIdentifier).map(String.init)
    }

    /// The app's sources and MeshKit's, where a piece may be declared.
    static let source: String = {
        let meshKit = RepoSources.root.appendingPathComponent("Packages/MeshKit/Sources")
        let walk = FileManager.default.enumerator(at: meshKit, includingPropertiesForKeys: nil)
        let packaged = (walk?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
        return (RepoSources.files.map(\.text) + packaged).joined(separator: "\n")
    }()

    static func isDeclared(_ name: String) -> Bool {
        ["struct", "enum", "class", "protocol", "typealias", "func", "var", "let", "case"].contains { source.contains("\($0) \(name)") }
            || source.contains("(\(name):") || source.contains(", \(name):")
    }

    @Test func theTableWasRead() {
        #expect(Self.rows.count > 20)
        #expect(Self.used.contains("ThumbnailRow"))
    }

    @Test func everyPieceExists() {
        let fileNames = Set(RepoSources.files.map { ($0.path as NSString).lastPathComponent })
        let missingFiles = Self.used.filter { $0.hasSuffix(".swift") && !fileNames.contains($0) }
        let missing = Set(Self.used.filter { !$0.hasSuffix(".swift") }.flatMap(Self.names)).filter { !Self.isDeclared($0) }
        #expect(missingFiles.isEmpty, "DESIGN.md's Shared pieces names files that don't exist: \(missingFiles)")
        #expect(missing.isEmpty, "DESIGN.md's Shared pieces names pieces that aren't in the code: \(missing.sorted())")
    }

    @Test func everySharedFileIsMapped() {
        let table = Self.rows.joined(separator: "\n")
        let shared = RepoSources.files.map(\.path).filter { $0.hasPrefix("Facets/UI/") || $0.hasPrefix("Shared/") }
        let unmapped = shared.filter { !table.contains("`\(($0 as NSString).lastPathComponent)`") }
        #expect(!shared.isEmpty)
        #expect(unmapped.isEmpty, "add these to DESIGN.md's Shared pieces table (the job, the piece, what it replaces): \(unmapped)")
    }

    @Test func namesAreReadFromPieces() {
        #expect(Self.names(in: "Motion.animation(_:reduceMotion:)") == ["Motion", "animation"])
        #expect(Self.names(in: ".glassChip(interactive:)") == ["glassChip"])
        #expect(Self.names(in: "url.withSecurityScope { }") == ["withSecurityScope"])
        #expect(Self.names(in: "Symbol.<concept>") == ["Symbol"])
        #expect(Self.names(in: "aboveBottomToolbar:") == ["aboveBottomToolbar"])
    }
}

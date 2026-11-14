import Foundation
import Testing

/// The app's Swift sources, read from the repository at test time (the tests run on
/// the Mac from the checkout, so the root is found from this file's own path).
enum RepoSources {
    struct Line {
        let file: String
        let number: Int
        let text: String
        var location: String { "\(file):\(number)" }
        var isComment: Bool { text.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    static let folders = ["Facets", "FacetsPreview", "FacetsThumbnail", "Shared"]

    /// Every Swift file under `folders`, by path relative to the root.
    static let files: [(path: String, text: String)] = folders.flatMap { folder -> [(path: String, text: String)] in
        let base = root.appendingPathComponent(folder).resolvingSymlinksInPath()
        guard let walk = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        return walk.compactMap { item in
            guard let url = (item as? URL)?.resolvingSymlinksInPath(), url.pathExtension == "swift",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (folder + url.path.dropFirst(base.path.count), text)
        }
    }.sorted { $0.path < $1.path }

    static let lines: [Line] = files.flatMap { file in
        file.text.components(separatedBy: "\n").enumerated().map { Line(file: file.path, number: $0.offset + 1, text: $0.element) }
    }
}

/// Hand-built forms of the jobs DESIGN.md's Shared pieces table gives to one piece,
/// checked over the source so a screen can't go around the piece again. A line opts
/// out with a trailing `// rule-ok: <reason>` when the pattern is deliberate there.
@Suite struct SourceRulesTests {
    typealias Line = RepoSources.Line

    static func violations(except allowed: Set<String> = [], _ matches: (Line) -> Bool) -> [String] {
        RepoSources.lines
            .filter { !$0.text.contains("rule-ok:") && !$0.isComment && !allowed.contains(($0.file as NSString).lastPathComponent) && matches($0) }
            .map { "\($0.location): \($0.text.trimmingCharacters(in: .whitespaces))" }
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Number literals in `text`, other than 0 (which needs no token).
    static func nonZeroNumbers(_ text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_.])\d+(?:\.\d+)?(?![A-Za-z0-9_])"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
            .filter { Double($0) != 0 }
    }

    /// What's inside the parentheses of every `.padding(` on the line.
    static func paddingArguments(_ text: String) -> [String] {
        var found: [String] = []
        var rest = text[...]
        while let start = rest.range(of: ".padding(") {
            var depth = 1, end = start.upperBound
            while end < rest.endIndex, depth > 0 {
                if rest[end] == "(" { depth += 1 } else if rest[end] == ")" { depth -= 1 }
                end = rest.index(after: end)
            }
            found.append(String(rest[start.upperBound..<rest.index(before: end)]))
            rest = rest[end...]
        }
        return found
    }

    /// The rules must actually read the code.
    @Test func sourcesWereFound() {
        #expect(RepoSources.files.count > 50)
        #expect(RepoSources.files.contains { $0.path == "Facets/UI/Symbols.swift" })
    }

    /// One glyph per concept (batch 2 found the same concept drawn with different
    /// symbols). App Shortcuts' metadata needs literals, so those lines opt out.
    @Test func symbolsComeFromSymbols() {
        let found = Self.violations(except: ["Symbols.swift"]) { Self.matches(#"\b(systemImage|systemName|systemImageName|systemSymbolName)\s*:\s*""#, $0.text) }
        #expect(found.isEmpty, "use a Symbol constant (Facets/UI/Symbols.swift): \(found)")
    }

    /// Floating glass is a card or a chip, so every card and chip has the same shape and glass.
    @Test func glassComesFromCardOrChip() {
        let found = Self.violations(except: ["GlassCard.swift", "GlassChip.swift"]) { $0.text.contains("glassEffect(") }
        #expect(found.isEmpty, "use .glassCard(...) or .glassChip(...): \(found)")
    }

    /// A Bool binding round an optional: one helper, so setting false always clears it.
    @Test func optionalBindingsUseIsPresent() {
        let found = Self.violations { Self.matches(#"Binding\s*\(\s*get:\s*\{[^}]*[!=]=\s*nil"#, $0.text) }
        #expect(found.isEmpty, "use $optional.isPresent (Alerts.swift): \(found)")
    }

    /// Security scope is started and stopped in one place, so it can't leak. The few
    /// long-lived holds (a Browse location, an external file open in the viewer) opt out.
    @Test func securityScopeIsBalanced() {
        let found = Self.violations(except: ["Platform.swift"]) { $0.text.contains("startAccessingSecurityScopedResource") }
        #expect(found.isEmpty, "use url.withSecurityScope { } (Platform.swift): \(found)")
    }

    /// iCloud placeholders (".Name.stl.icloud") are read in one place.
    @Test func iCloudPlaceholdersComeFromICloudFile() {
        let found = Self.violations(except: ["ICloudFile.swift"]) { $0.text.contains(#".icloud""#) }
        #expect(found.isEmpty, "use ICloudFile: \(found)")
    }

    /// An error alert is one piece, with one title rule and one button.
    @Test func errorAlertsComeFromAlerts() {
        let found = Self.violations(except: ["Alerts.swift"]) { $0.text.contains(#"Button("OK", role: .cancel)"#) }
        #expect(found.isEmpty, "use .errorAlert(...) (Alerts.swift): \(found)")
    }

    /// Radii, spacing and padding are tokens (batch 2 replaced dozens of typed-in values).
    @Test func sizesAreTokens() {
        let found = Self.violations(except: ["Tokens.swift"]) { line in
            if let m = line.text.range(of: #"(cornerRadius|spacing)\s*:\s*-?\d+(\.\d+)?"#, options: .regularExpression),
               !Self.nonZeroNumbers(String(line.text[m])).isEmpty { return true }
            return Self.paddingArguments(line.text).contains { !Self.nonZeroNumbers($0).isEmpty }
        }
        #expect(found.isEmpty, "use Spacing, Radius, ChipPadding or CardPadding (Shared/Tokens.swift): \(found)")
    }

    /// Motion is a token, so it can honour Reduce Motion in one place.
    @Test func animationsAreTokens() {
        let found = Self.violations(except: ["Tokens.swift"]) { Self.matches(#"(withAnimation|\.animation)\(\s*\.[a-z]"#, $0.text) }
        #expect(found.isEmpty, "use Motion and Motion.animation(_:reduceMotion:) (Shared/Tokens.swift): \(found)")
    }

    /// A toast's clearance is worked out by the host, never passed in by a screen.
    @Test func toastHostWorksOutItsClearance() {
        let found = Self.violations { $0.text.contains(".toastHost(clearance") }
        #expect(found.isEmpty, "use .toastHost() or .toastHost(aboveBottomToolbar:) (Toasts.swift): \(found)")
    }

    /// The text from a `.sheet(` or `.popover(` to the end of its content closure.
    static func presentedContent(in text: String) -> [(line: Int, text: Substring)] {
        var found: [(line: Int, text: Substring)] = []
        var from = text.startIndex
        while let start = text.range(of: #"\.(sheet|popover)\("#, options: .regularExpression, range: from..<text.endIndex) {
            from = start.upperBound
            guard let open = text[start.upperBound...].firstIndex(of: "{") else { break }
            var depth = 0, end = open
            repeat {
                if text[end] == "{" { depth += 1 } else if text[end] == "}" { depth -= 1 }
                end = text.index(after: end)
            } while depth > 0 && end < text.endIndex
            found.append((text[..<start.lowerBound].filter { $0 == "\n" }.count + 1, text[start.lowerBound..<end]))
        }
        return found
    }

    /// A Mac sheet takes its content's ideal size: the Move sheet showed no folders and
    /// the printer list ran off the window (batch 3 sweep). Every sheet or popover's
    /// content goes through `.sheetSize()`; one that isn't a list or form opts out.
    @Test func sheetsAreSized() {
        let found = RepoSources.files.flatMap { file in
            Self.presentedContent(in: file.text)
                .filter { !$0.text.contains("sheetSize()") && !$0.text.prefix { $0 != "\n" }.contains("rule-ok:") }
                .map { "\(file.path):\($0.line)" }
        }
        #expect(found.isEmpty, "end the sheet's content with .sheetSize() (Platform.swift): \(found)")
    }

    /// The rules themselves: each catches its form, and an opt-out or a zero passes.
    @Test func rulesCatchWhatTheyShould() {
        #expect(Self.nonZeroNumbers("geometry.size.width * 0.2") == ["0.2"])
        #expect(Self.nonZeroNumbers("isSelected ? Spacing.xs : 0").isEmpty)
        #expect(Self.paddingArguments(#".padding(.top, 8).padding(f(x))"#) == [".top, 8", "f(x)"])
        #expect(Self.matches(#"Binding\s*\(\s*get:\s*\{[^}]*[!=]=\s*nil"#, "Binding(get: { item != nil }, set: { _ in })"))
        #expect(Self.matches(#"(withAnimation|\.animation)\(\s*\.[a-z]"#, "withAnimation(.snappy) {"))
        let sheets = Self.presentedContent(in: "a\n.sheet(item: $x) { y in\n  Z { w }\n}\n.sheet(isPresented: $b) { V().sheetSize() }")
        #expect(sheets.map(\.line) == [2, 5])
        #expect(!sheets[0].text.contains("sheetSize()") && sheets[1].text.contains("sheetSize()"))
    }
}

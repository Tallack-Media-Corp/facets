import AppIntents
import CoreSpotlight
import MeshKit
import SwiftUI
import UniformTypeIdentifiers

/// The library as Spotlight and Shortcuts see it: models by their path below the
/// library folder, which stays the same across launches.
enum LibraryIndex {
    static var root: URL { LibraryLocation.current }

    /// Every model in the library, including ones only in iCloud (by their real
    /// names), skipping the share sheet's Inbox and Recently Deleted.
    static func models() -> [URL] {
        let root = root
        // Hidden files aren't skipped: an evicted model is a ".Name.stl.icloud" placeholder.
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if (name == "Inbox" && url.deletingLastPathComponent().standardizedFileURL == root) || name == ".recently-deleted" || name == ".thumbnails" {
                enumerator.skipDescendants()
                continue
            }
            if let real = ICloudFile.realURL(ofPlaceholder: url) {
                if ModelLoader.isSupported(real) { result.append(real.standardizedFileURL) }
            } else if !name.hasPrefix("."), ModelLoader.isSupported(url) {
                result.append(url.standardizedFileURL)
            }
        }
        return result
    }

    static func id(for url: URL) -> String {
        LibraryLocation.relativePath(of: url, in: root) ?? url.lastPathComponent
    }

    static func url(for id: String) -> URL {
        root.appending(path: id)
    }

    /// "In Brackets" for a model in a folder; nil at the top of the library.
    static func folderName(of url: URL) -> String? {
        let folder = url.deletingLastPathComponent().standardizedFileURL
        return folder.resolvingSymlinksInPath() == root.resolvingSymlinksInPath() ? nil : folder.lastPathComponent
    }
}

// MARK: - Spotlight

/// Puts library models in Spotlight, so a search on the Home Screen finds them by
/// name and opens them in Facets.
enum SpotlightIndexer {
    static let domain = "library"

    /// Brings the index up to date with the library. Run on launch, whenever the app
    /// goes to the background and per Mac window, so it does nothing when nothing
    /// changed since this launch indexed. Once per launch regardless: the system can
    /// wipe the index without telling us.
    static func reindex() {
        Task.detached(priority: .utility) {
            let models = LibraryIndex.models().map { url in
                (url: url, modified: try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            }
            let defaults = UserDefaults.standard
            let fingerprint = LibraryFingerprint.of(models, language: Bundle.main.preferredLocalizations.first ?? "")
            // Done already, or another call (launch and first window) is on it.
            guard await fingerprints.claim(fingerprint) else { return }
            let items = models.map { url, modified -> CSSearchableItem in
                let type = UTType(filenameExtension: url.pathExtension) ?? .data
                let attributes = CSSearchableItemAttributeSet(contentType: type)
                attributes.title = Format.title(of: url)
                let format = url.pathExtension.uppercased()
                attributes.contentDescription = LibraryIndex.folderName(of: url).map { String(localized: "\(format) model in \($0)", comment: "Spotlight: a model's format and folder, as in 'STL model in Brackets'") } ?? String(localized: "\(format) model", comment: "Spotlight: a model's format, as in 'STL model'")
                attributes.contentURL = url
                attributes.contentModificationDate = modified
                return CSSearchableItem(uniqueIdentifier: LibraryIndex.id(for: url), domainIdentifier: domain, attributeSet: attributes)
            }
            let ids = items.map(\.uniqueIdentifier)
            let index = CSSearchableIndex.default()
            // Indexed before what's gone is removed, so a suspension midway never leaves
            // the index empty. Without a list from last time (an older build), clear first.
            let previous = defaults.stringArray(forKey: idsKey)
            let gone = Set(previous ?? []).subtracting(ids)
            do {
                if previous == nil { try await index.deleteSearchableItems(withDomainIdentifiers: [domain]) }
                try await index.indexSearchableItems(items)
                if !gone.isEmpty { try await index.deleteSearchableItems(withIdentifiers: Array(gone)) }
            } catch {
                await fingerprints.finish(fingerprint, succeeded: false) // The next call tries again.
                return
            }
            // shortcut: the ids sit in UserDefaults (tens of KB at a few thousand models);
            // move them to a file if libraries grow far beyond that.
            defaults.set(ids, forKey: idsKey)
            await fingerprints.finish(fingerprint, succeeded: true)
            // Siri phrases that name a model ("Open Benchy in Facets") need the names.
            FacetsShortcuts.updateAppShortcutParameters()
        }
    }

    private static let idsKey = "spotlight.ids"
    private static let fingerprints = Fingerprints()

    /// What this launch has indexed, and what a call is indexing now. In memory only.
    private actor Fingerprints {
        private var done: String?
        private var running: String?

        /// True when this library still needs indexing and no other call has it.
        func claim(_ fingerprint: String) -> Bool {
            guard fingerprint != done, fingerprint != running else { return false }
            running = fingerprint
            return true
        }

        func finish(_ fingerprint: String, succeeded: Bool) {
            if running == fingerprint { running = nil }
            if succeeded { done = fingerprint }
        }
    }

    /// The library file a Spotlight result stands for.
    static func url(for activity: NSUserActivity) -> URL? {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        let url = LibraryIndex.url(for: id)
        return ICloudFile.existsHereOrInCloud(url) ? url : nil
    }
}

// MARK: - Shortcuts

/// A model in the library, for Shortcuts and Siri.
struct ModelEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Model"
    static let defaultQuery = ModelEntityQuery()

    /// Its path below the library folder.
    let id: String
    let name: String
    let folder: String?

    init(url: URL) {
        id = LibraryIndex.id(for: url)
        name = Format.title(of: url)
        folder = LibraryIndex.folderName(of: url)
    }

    var url: URL { LibraryIndex.url(for: id) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: folder.map { "\($0)" },
            image: .init(systemName: "cube")
        )
    }
}

struct ModelEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ModelEntity] {
        identifiers.compactMap { id in
            let url = LibraryIndex.url(for: id)
            return ICloudFile.existsHereOrInCloud(url) ? ModelEntity(url: url) : nil
        }
    }

    func entities(matching string: String) async throws -> [ModelEntity] {
        let terms = string.split(separator: " ").map(String.init)
        return LibraryIndex.models()
            .map(ModelEntity.init(url:))
            .filter { entity in terms.allSatisfy { entity.name.localizedStandardContains($0) || entity.id.localizedStandardContains($0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The most recently changed models first.
    func suggestedEntities() async throws -> [ModelEntity] {
        let dated = LibraryIndex.models().map { url in
            (url, (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        return dated.sorted { $0.1 > $1.1 }.prefix(30).map { ModelEntity(url: $0.0) }
    }
}

struct OpenModelIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Model"
    static let description = IntentDescription("Opens a model from your Facets library in 3D.")

    @Parameter(title: "Model")
    var target: ModelEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        #if os(macOS)
        // Its own window, like a Finder open: a library window may not be open to take it.
        MacOpener.shared.open([target.url])
        #else
        PendingOpen.shared.file = ModelFileRef(url: target.url, isExternal: false)
        #endif
        return .result()
    }
}

struct GetModelDimensionsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Model Dimensions"
    static let description = IntentDescription("Gives a model's width, depth and height, in the units set in Facets. For a project with several plates, it's the first plate, as Facets opens it.")

    @Parameter(title: "Model")
    var model: ModelEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Get the dimensions of \(\.$model)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let url = model.url
        let loaded = try await Task.detached(priority: .userInitiated) { try CoordinatedRead.model(at: url) }.value
        let units = MeasurementUnits.saved()
        // A multi-plate project is laid out across several plates; measure the one
        // the viewer opens on, not the whole layout.
        let plate = loaded.plates.first?.id
        let size = loaded.bounds(of: loaded.visibleParts(plateID: plate, hidden: [])).size
        let text = Format.dimensions(size, units: units)
        let spoken = Format.spokenDimensions(size, units: units)
        let answer = plate.map { String(localized: "Plate \($0) of \(model.name) is \(spoken).", comment: "Siri: a plate's size") }
            ?? String(localized: "\(model.name) is \(spoken).", comment: "Siri: a model's size")
        return .result(value: text, dialog: IntentDialog(stringLiteral: answer))
    }
}

struct FacetsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenModelIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)",
                "Open a model in \(.applicationName)",
            ],
            shortTitle: "Open Model",
            systemImageName: "cube"
        )
        AppShortcut(
            intent: GetModelDimensionsIntent(),
            phrases: [
                "How big is \(\.$model) in \(.applicationName)",
                "Get model dimensions in \(.applicationName)",
            ],
            shortTitle: "Model Dimensions",
            systemImageName: "ruler"
        )
    }
}

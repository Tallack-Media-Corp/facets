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
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                let real = url.deletingLastPathComponent().appending(path: String(name.dropFirst().dropLast(".icloud".count)))
                if ModelLoader.isSupported(real) { result.append(real.standardizedFileURL) }
            } else if !name.hasPrefix("."), ModelLoader.isSupported(url) {
                result.append(url.standardizedFileURL)
            }
        }
        return result
    }

    /// There, or only in iCloud.
    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
            || FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud").path)
    }

    /// Reads a model through a file coordinator, which downloads one only in iCloud.
    static func load(_ url: URL) throws -> Model3D {
        var coordinatorError: NSError?
        var result: Result<Model3D, Error> = .failure(ModelError.emptyFile)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            result = Result { try ModelLoader.load(readURL) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }

    static func id(for url: URL) -> String {
        let base = root.resolvingSymlinksInPath().path + "/"
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : url.lastPathComponent
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

    /// Replaces the index with what's in the library now. Cheap enough to run on
    /// launch and whenever the app goes to the background.
    static func reindex() {
        Task.detached(priority: .utility) {
            let items = LibraryIndex.models().map { url -> CSSearchableItem in
                let type = UTType(filenameExtension: url.pathExtension) ?? .data
                let attributes = CSSearchableItemAttributeSet(contentType: type)
                attributes.title = Format.title(fromFileName: url.deletingPathExtension().lastPathComponent)
                let format = url.pathExtension.uppercased()
                attributes.contentDescription = LibraryIndex.folderName(of: url).map { "\(format) model in \($0)" } ?? "\(format) model"
                attributes.contentURL = url
                attributes.contentModificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return CSSearchableItem(uniqueIdentifier: LibraryIndex.id(for: url), domainIdentifier: domain, attributeSet: attributes)
            }
            let index = CSSearchableIndex.default()
            try? await index.deleteSearchableItems(withDomainIdentifiers: [domain])
            try? await index.indexSearchableItems(items)
            // Siri phrases that name a model ("Open Benchy in Facets") need the names.
            FacetsShortcuts.updateAppShortcutParameters()
        }
    }

    /// The library file a Spotlight result stands for.
    static func url(for activity: NSUserActivity) -> URL? {
        guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        let url = LibraryIndex.url(for: id)
        return LibraryIndex.exists(url) ? url : nil
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
        name = Format.title(fromFileName: url.deletingPathExtension().lastPathComponent)
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
            return LibraryIndex.exists(url) ? ModelEntity(url: url) : nil
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
        PendingOpen.shared.file = ModelFileRef(url: target.url, isExternal: false)
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
        let loaded = try await Task.detached(priority: .userInitiated) { try LibraryIndex.load(url) }.value
        let units = MeasurementUnits(rawValue: UserDefaults.standard.string(forKey: "viewer.units") ?? "") ?? .millimetres
        // A multi-plate project is laid out across several plates; measure the one
        // the viewer opens on, not the whole layout.
        let plate = loaded.plates.first?.id
        let size = loaded.bounds(of: loaded.visibleParts(plateID: plate, hidden: [])).size
        let text = Format.dimensions(size, units: units)
        let subject = plate == nil ? model.name : "Plate \(plate!) of \(model.name)"
        return .result(value: text, dialog: "\(subject) is \(Format.spokenDimensions(size, units: units)).")
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

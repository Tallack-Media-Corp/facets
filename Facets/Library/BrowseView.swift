import SwiftUI
import UniformTypeIdentifiers

/// Models outside the library: folders the user added from Files, and a one-off
/// "Open a File…" through the system picker.
struct BrowseView: View {
    @Binding var path: [LibraryRoute]

    @Environment(LocationsStore.self) private var locations
    @Environment(\.openModel) private var openModel
    @State private var pickingFolder = false
    @State private var pickingFile = false
    @State private var renaming: LocationsStore.Location?
    @State private var renameText = ""
    @State private var failure: (title: String, message: String)?

    var body: some View {
        List {
            Section {
                LibrarySectionPicker().sectionPickerRow()
            }
            if !locations.locations.isEmpty {
                Section("Locations") {
                    ForEach(locations.locations) { location in
                        row(for: location)
                    }
                }
            }
            Section {
                // Each button has its own picker on its own view: one shared importer
                // whose types change between presentations can come up with the other
                // button's types, which let a file be added as a location.
                Button("Add Location…", systemImage: Symbol.addLocation) { pickingFolder = true }
                    .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { handle($0, failureTitle: Self.addFailed) }
                Button("Open a File…", systemImage: Symbol.openFile) { pickingFile = true }
                    .fileImporter(isPresented: $pickingFile, allowedContentTypes: UTType.models) { handle($0, failureTitle: String(localized: "Couldn't Open That")) }
            } footer: {
                Text("Add a folder from iCloud Drive, On My iPhone or any storage app in Files to browse its STL, 3MF and OBJ files here. Facets can only see folders you choose.")
            }
        }
        .navigationTitle("Browse")
        .renameAlert("Rename Location", item: $renaming, text: $renameText) { locations.rename($0, to: renameText) }
        .errorAlert($failure)
    }

    /// The title when a folder can't be added, as on the Mac's Add Location.
    private static var addFailed: String { String(localized: "Couldn't Add That Folder") }

    private func handle(_ result: Result<URL, Error>, failureTitle: String) {
        switch result {
        case .success(let url):
            picked(url)
        case .failure(let error):
            failure = (failureTitle, FriendlyError(file: error).message)
        }
    }

    /// Goes by what was picked, not which button picked it: a folder becomes a
    /// location, a model opens.
    private func picked(_ url: URL) {
        let isFolder = url.withSecurityScope { LocationsStore.isFolder(url) || url.hasDirectoryPath }
        guard isFolder else {
            openModel(ModelFileRef(url: url, isExternal: true))
            return
        }
        do {
            let location = try locations.add(url)
            if let folder = locations.url(for: location) {
                path.append(.browse(folder, title: location.name))
            }
        } catch {
            failure = (Self.addFailed, FriendlyError(file: error).message)
        }
    }

    @ViewBuilder
    private func row(for location: LocationsStore.Location) -> some View {
        let symbol = location.isCloud ? Symbol.cloudFolder : Symbol.folder
        Group {
            if let url = locations.url(for: location) {
                NavigationLink(value: LibraryRoute.browse(url, title: location.name)) {
                    Label(location.name, systemImage: symbol)
                }
            } else {
                // The folder moved, was deleted, or its provider revoked access.
                Button {
                    pickingFolder = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: Spacing.hair) {
                            Text(location.name)
                            Text("The folder was moved or deleted, or Facets no longer has access to it. Add it again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: Symbol.missing)
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .swipeActions {
            RowAction.remove { locations.remove(location) }
        }
        .contextMenu {
            RowAction.rename {
                renameText = location.name
                renaming = location
            }
            RowAction.remove("Remove from Browse") { locations.remove(location) }
        }
    }
}

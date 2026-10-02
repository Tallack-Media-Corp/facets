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
    @State private var errorMessage: String?

    var body: some View {
        List {
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
                Button("Add Location…", systemImage: "folder.badge.plus") { pickingFolder = true }
                    .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder], onCompletion: handle)
                Button("Open a File…", systemImage: "doc.badge.ellipsis") { pickingFile = true }
                    .fileImporter(isPresented: $pickingFile, allowedContentTypes: UTType.models, onCompletion: handle)
            } footer: {
                Text("Add a folder from iCloud Drive, On My iPhone or any storage app in Files to browse its STL, 3MF and OBJ files here. Facets can only see folders you choose.")
            }
        }
        .navigationTitle("Browse")
        .alert("Rename Location", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let location = renaming { locations.rename(location, to: renameText) }
            }
        }
        .alert("Couldn't Open That", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func handle(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            picked(url)
        case .failure(let error):
            errorMessage = FriendlyError(file: error).message
        }
    }

    /// Goes by what was picked, not which button picked it: a folder becomes a
    /// location, a model opens.
    private func picked(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        let isFolder = LocationsStore.isFolder(url) || url.hasDirectoryPath
        if scoped { url.stopAccessingSecurityScopedResource() }
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
            errorMessage = FriendlyError(file: error).message
        }
    }

    @ViewBuilder
    private func row(for location: LocationsStore.Location) -> some View {
        let symbol = location.isCloud ? "icloud" : "folder"
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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(location.name)
                            Text("Can't open this folder. Add it again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .swipeActions {
            Button("Remove", systemImage: "minus.circle", role: .destructive) { locations.remove(location) }
        }
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameText = location.name
                renaming = location
            }
            Button("Remove from Browse", systemImage: "minus.circle", role: .destructive) { locations.remove(location) }
        }
    }
}

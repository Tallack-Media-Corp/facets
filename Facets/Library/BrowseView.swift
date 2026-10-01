import SwiftUI
import UniformTypeIdentifiers

/// Models outside the library: folders the user added from Files, and a one-off
/// "Open a File…" through the system picker.
struct BrowseView: View {
    @Binding var path: [LibraryRoute]

    @Environment(LocationsStore.self) private var locations
    private enum Picking {
        case folder, file
    }

    @State private var picking = Picking.folder
    @State private var showingPicker = false
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
                Button("Add Location…", systemImage: "folder.badge.plus") { pick(.folder) }
                Button("Open a File…", systemImage: "doc.badge.ellipsis") { pick(.file) }
            } footer: {
                Text("Add a folder from iCloud Drive, On My iPhone or any storage app in Files to browse its STL and 3MF files here. Facets can only see folders you choose.")
            }
        }
        .navigationTitle("Browse")
        // One importer for both: SwiftUI ignores all but one `fileImporter` in a view.
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: picking == .folder ? [.folder] : UTType.models) { result in
            switch result {
            case .success(let url):
                picked(url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .alert("Rename Location", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let location = renaming { locations.rename(location, to: renameText) }
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func pick(_ kind: Picking) {
        picking = kind
        showingPicker = true
    }

    private func picked(_ url: URL) {
        switch picking {
        case .folder:
            do {
                let location = try locations.add(url)
                if let folder = locations.url(for: location) {
                    path.append(.browse(folder, title: location.name))
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        case .file:
            path.append(.model(ModelFileRef(url: url, isExternal: true)))
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
                    pick(.folder)
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

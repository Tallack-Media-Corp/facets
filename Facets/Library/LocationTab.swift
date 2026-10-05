#if os(macOS)
import SwiftUI

/// A Browse location as a sidebar item of its own on the Mac, the way the Finder
/// lists folders: look through its models, open them, save them to the library.
struct LocationTab: View {
    let location: LocationsStore.Location

    @Environment(LocationsStore.self) private var locations
    @Namespace private var zoom
    @State private var path: [LibraryRoute] = []
    @State private var relinking = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let url = locations.url(for: location) {
                    FolderView(folder: url, title: location.name, isBrowsing: true)
                        .id(url)
                } else {
                    ContentUnavailableView {
                        Label("Can't Open \(location.name)", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("The folder was moved or deleted, or Facets no longer has access to it.")
                    } actions: {
                        Button("Choose the Folder Again…") { relinking = true }
                            .buttonStyle(.glassProminent)
                        Button("Remove from Sidebar", role: .destructive) { locations.remove(location) }
                    }
                    .navigationTitle(location.name)
                }
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .folder(let url):
                    FolderView(folder: url, title: url.lastPathComponent, isBrowsing: true)
                case .browse(let url, let title):
                    FolderView(folder: url, title: title, isBrowsing: true)
                }
            }
        }
        .presentsModels()
        .environment(\.zoomNamespace, zoom)
        .environment(\.openFolder) { path.append($0) }
        .fileImporter(isPresented: $relinking, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result, (try? locations.add(url)) != nil else { return }
            locations.remove(location)
        }
    }
}

/// The sidebar's foot: add a folder to browse.
struct AddLocationButton: View {
    @Environment(LocationsStore.self) private var locations
    @Environment(Router.self) private var router
    @State private var picking = false
    @State private var errorMessage: String?

    var body: some View {
        Button { picking = true } label: {
            Label {
                // One line: the sidebar bar offers less width than the sidebar shows.
                Text("Add Location…").fixedSize()
            } icon: {
                Image(systemName: "folder.badge.plus")
            }
        }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
            .help("Browse a folder's STL, 3MF and OBJ files without importing them")
            .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    do {
                        router.tab = .location(try locations.add(url).id)
                    } catch {
                        errorMessage = FriendlyError(file: error).message
                    }
                case .failure(let error):
                    errorMessage = FriendlyError(file: error).message
                }
            }
            .alert("Couldn't Add That Folder", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }
}
#endif

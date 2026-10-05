#if os(macOS)
import SwiftUI
import TipKit
import os

/// A Browse location as a sidebar item of its own on the Mac, the way the Finder
/// lists folders: look through its models, open them, save them to the library.
struct LocationTab: View {
    let location: LocationsStore.Location

    @Environment(LocationsStore.self) private var locations
    @Environment(Router.self) private var router
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
                        Button("Remove from Sidebar", role: .destructive) {
                            router.tab = .library
                            locations.remove(location)
                        }
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
        .onChange(of: relinking) {
            guard relinking else { return }
            relinking = false
            guard let url = LocationPanel.choose(), let fresh = try? locations.add(url) else { return }
            // The new entry takes the old one's place, and stays the one showing.
            router.tab = .location(fresh.id)
            // Picking the same folder hands back this very entry: keep it.
            if fresh.id != location.id { locations.remove(location) }
        }
    }
}

/// The folder picker for Browse locations. An open panel of its own rather than
/// SwiftUI's file importer: the window already has importers (the library's Add
/// Models), and the sidebar's own one failed straight away beside them, showing an
/// error before any panel appeared.
@MainActor
enum LocationPanel {
    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a folder to browse its STL, 3MF and OBJ files without importing them."
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// The sidebar's foot: add a folder to browse, and Settings for anyone who
/// wouldn't look for it in the app menu.
struct SidebarFoot: View {
    var body: some View {
        HStack {
            AddLocationButton()
            Spacer(minLength: 8)
            SettingsLink {
                Image(systemName: "gear")
                    .frame(width: 24, height: 24)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
    }
}

/// Add a folder to browse.
struct AddLocationButton: View {
    @Environment(LocationsStore.self) private var locations
    @Environment(Router.self) private var router
    @State private var errorMessage: String?

    var body: some View {
        Button {
            BrowseTip().invalidate(reason: .actionPerformed)
            guard let url = LocationPanel.choose() else { return }
            do {
                router.tab = .location(try locations.add(url).id)
            } catch {
                Logger(subsystem: "Facets", category: "locations").error("Add Location failed: \(error as NSError, privacy: .public)")
                errorMessage = FriendlyError(file: error).message
            }
        } label: {
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
            .alert("Couldn't Add That Folder", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }
}
#endif

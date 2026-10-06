import SwiftUI
import TipKit

extension EnvironmentValues {
    /// Pushes a folder onto the library's stack, for opening one without a link
    /// (a double-click on the Mac).
    @Entry var openFolder: (LibraryRoute) -> Void = { _ in }
}

enum LibraryRoute: Hashable {
    case folder(URL)
    /// A folder outside the library, reached through Browse.
    case browse(URL, title: String)
}

/// The library's navigation stack, with Library and Browse side by side at the root.
/// Folders push inside it; a model opens over it in the viewer, zooming from its card.
struct LibraryTab: View {
    enum Section: String, CaseIterable, Identifiable {
        case library = "Library"
        case browse = "Browse"
        var id: String { rawValue }
        /// "My Models", not a third "Library" under the tab and the title.
        var title: String { self == .library ? "My Models" : "Browse" }
    }

    @Environment(FileLibrary.self) private var library
    @Namespace private var zoom
    @State private var path: [LibraryRoute] = []
    @AppStorage("library.section") private var section: Section = .library

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                #if os(macOS)
                // Browse locations are sidebar items on the Mac; no switch here.
                FolderView(folder: library.root, title: "Library")
                    .id(library.root)
                #else
                switch section {
                case .library:
                    FolderView(folder: library.root, title: "Library", showsSectionPicker: true)
                        // Moving to iCloud Drive changes the folder underneath.
                        .id(library.root)
                case .browse: BrowseView(path: $path)
                }
                #endif
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                Group {
                    switch route {
                    case .folder(let url):
                        FolderView(folder: url, title: url.lastPathComponent)
                    case .browse(let url, let title):
                        FolderView(folder: url, title: title, isBrowsing: true)
                    }
                }
                .folderActions(zoom: zoom) { path.append($0) }
            }
        }
        .folderActions(zoom: zoom) { path.append($0) }
        // Read the path here, not only hand the stack a binding: otherwise a folder
        // opened from a pushed folder changed it without redrawing this tab, and the
        // Mac showed the new folder only when something else redrew, seconds later.
        .onChange(of: path) {}
        // The library moved (to or from iCloud Drive): folders open from the old one are gone.
        .onChange(of: library.root) { path = [] }
    }
}

extension View {
    /// What a folder screen needs from its tab: opening models, opening folders in
    /// the tab's stack, and the zoom transition's namespace. Applied to the stack and
    /// again to each pushed folder, because on the Mac a pushed destination doesn't
    /// see values set on its NavigationStack: without it, a double-click in a
    /// subfolder reached the empty default and did nothing.
    func folderActions(zoom: Namespace.ID, open: @escaping (LibraryRoute) -> Void) -> some View {
        presentsModels()
            .environment(\.zoomNamespace, zoom)
            .environment(\.openFolder, open)
    }
}

/// Library | Browse, at the top of each root list's own content, under the large
/// title. It scrolls with the list, so pulling to refresh moves it with the title
/// instead of leaving it pinned above the spinner.
struct LibrarySectionPicker: View {

    /// Where an inset grouped list puts its first row below the title. The grid and
    /// the empty library are scroll views, so they add it themselves, keeping the
    /// switch in the same place whichever side is showing (measured on iPhone and
    /// iPad).
    static let listTopMargin: CGFloat = 8.5

    @AppStorage("library.section") private var section: LibraryTab.Section = .library

    var body: some View {
        Picker("Section", selection: $section) {
            ForEach(LibraryTab.Section.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .onChange(of: section) { if section == .browse { BrowseTip().invalidate(reason: .actionPerformed) } }
        .labelsHidden()
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity)
    }
}

extension View {
    /// The section picker as a list's first row: no background, no separator.
    func sectionPickerRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
    }
}

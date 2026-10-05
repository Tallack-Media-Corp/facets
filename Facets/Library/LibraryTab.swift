import SwiftUI

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
    }

    @Environment(FileLibrary.self) private var library
    @Namespace private var zoom
    @State private var path: [LibraryRoute] = []
    @AppStorage("library.section") private var section: Section = .library

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch section {
                case .library:
                    FolderView(folder: library.root, title: "Library", showsSectionPicker: true)
                        // Moving to iCloud Drive changes the folder underneath.
                        .id(library.root)
                case .browse: BrowseView(path: $path)
                }
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .folder(let url):
                    FolderView(folder: url, title: url.lastPathComponent)
                case .browse(let url, let title):
                    FolderView(folder: url, title: title, isBrowsing: true)
                }
            }
        }
        .presentsModels()
        .environment(\.zoomNamespace, zoom)
        .environment(\.openFolder) { path.append($0) }
    }
}

/// Library | Browse, at the top of each root list's own content, under the large
/// title. It scrolls with the list, so pulling to refresh moves it with the title
/// instead of leaving it pinned above the spinner.
struct LibrarySectionPicker: View {
    @AppStorage("library.section") private var section: LibraryTab.Section = .library

    var body: some View {
        Picker("Section", selection: $section) {
            ForEach(LibraryTab.Section.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
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

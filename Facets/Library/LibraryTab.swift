import SwiftUI

enum LibraryRoute: Hashable {
    case folder(URL)
    /// A folder outside the library, reached through Browse.
    case browse(URL, title: String)
    case model(ModelFileRef)
}

/// The library's navigation stack, with Library and Browse side by side at the root.
/// Folders push inside it; a model opens in the viewer with a zoom from its card.
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
                case .library: FolderView(folder: library.root, title: "Library")
                case .browse: BrowseView(path: $path)
                }
            }
            // Under the large title, like the other tabs, rather than in its place.
            .safeAreaBar(edge: .top) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                switch route {
                case .folder(let url):
                    FolderView(folder: url, title: url.lastPathComponent)
                case .browse(let url, let title):
                    FolderView(folder: url, title: title, isBrowsing: true)
                case .model(let file):
                    ViewerScreen(file: file)
                        .zoomDestination(id: file.url, in: zoom)
                }
            }
        }
        .environment(\.zoomNamespace, zoom)
    }
}

import SwiftUI

enum LibraryRoute: Hashable {
    case folder(URL)
    case model(ModelFileRef)
}

/// The library's navigation stack. Folders push inside it; a model opens in the
/// viewer with a zoom from its card.
struct LibraryTab: View {
    @Environment(FileLibrary.self) private var library
    @Namespace private var zoom
    @State private var path: [LibraryRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            FolderView(folder: library.root, title: "Library")
                .navigationDestination(for: LibraryRoute.self) { route in
                    switch route {
                    case .folder(let url):
                        FolderView(folder: url, title: url.lastPathComponent)
                    case .model(let file):
                        ViewerScreen(file: file)
                            .zoomDestination(id: file.url, in: zoom)
                    }
                }
        }
        .environment(\.zoomNamespace, zoom)
    }
}

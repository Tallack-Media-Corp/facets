import SwiftUI

/// Finds models by name anywhere in the library.
struct SearchView: View {
    @Environment(FileLibrary.self) private var library
    @State private var query = ""
    @State private var all: [LibraryItem] = []
    @Namespace private var zoom

    private var results: [LibraryItem] {
        let terms = query.split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        return all
            .filter { item in terms.allSatisfy { item.name.localizedStandardContains($0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(results) { item in
                NavigationLink(value: ModelFileRef(url: item.url, isExternal: false)) {
                    VStack(alignment: .leading, spacing: 2) {
                        LibraryRow(item: item)
                        if let folder = library.relativeFolder(of: item.url) {
                            Label(folder, systemImage: "folder")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 64)
                                .lineLimit(2)
                        }
                    }
                }
                .zoomSource(id: item.url, in: zoom)
            }
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Search Your Library", systemImage: "magnifyingglass", description: Text("Find STL and 3MF files by name, in every folder."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            .navigationDestination(for: ModelFileRef.self) { file in
                ViewerScreen(file: file)
                    .zoomDestination(id: file.url, in: zoom)
            }
            .searchable(text: $query, prompt: "Models")
            .onAppear { all = library.allModels() }
            .onChange(of: library.revision) { all = library.allModels() }
        }
    }
}

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
            // Match the tidy name as well, so "Eufy S1" finds "Eufy_S1_Case".
            .filter { item in terms.allSatisfy { item.name.localizedStandardContains($0) || item.displayName.localizedStandardContains($0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(results) { item in
                OpenModelButton(file: ModelFileRef(url: item.url, isExternal: false)) {
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
                    ContentUnavailableView("Search Your Library", systemImage: "magnifyingglass", description: Text("Find STL, 3MF and OBJ files by name, in every folder."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Models")
            .task(id: library.revision) {
                // An iCloud sync changes many files in a burst; wait for it to settle
                // rather than walk the whole library for each change.
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                let root = library.root
                all = await Task.detached(priority: .userInitiated) { FileLibrary.allModels(in: root) }.value
            }
        }
        .presentsModels()
        .environment(\.zoomNamespace, zoom)
    }
}

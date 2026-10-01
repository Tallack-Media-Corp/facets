import SwiftUI

struct RecentsView: View {
    @Environment(RecentsStore.self) private var recents
    @Environment(Router.self) private var router
    @Environment(FileLibrary.self) private var library
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(recents.entries) { entry in
                    Button {
                        open(entry)
                    } label: {
                        RecentRow(entry: entry, url: recents.resolve(entry))
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Remove", systemImage: "minus.circle", role: .destructive) { recents.remove(entry) }
                    }
                    .contextMenu {
                        Button("Remove from Recents", systemImage: "minus.circle", role: .destructive) { recents.remove(entry) }
                    }
                }
            }
            .overlay {
                if recents.entries.isEmpty {
                    ContentUnavailableView("No Recent Models", systemImage: "clock", description: Text("Models you open, here or from other apps, appear here."))
                }
            }
            .navigationTitle("Recents")
            .toolbar {
                if !recents.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear", systemImage: "trash") { confirmingClear = true }
                    }
                }
            }
            .confirmationDialog("Clear the list of recent models?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear Recents", role: .destructive) { recents.clear() }
            } message: {
                Text("The files themselves aren't touched.")
            }
            .onAppear { recents.prune() }
        }
    }

    private func open(_ entry: RecentsStore.Entry) {
        guard let url = recents.resolve(entry) else {
            recents.remove(entry)
            return
        }
        router.presented = ModelFileRef(url: url, isExternal: !library.contains(url))
    }
}

private struct RecentRow: View {
    let entry: RecentsStore.Entry
    let url: URL?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let url {
                    ModelThumbnail(url: url, size: nil, modified: entry.lastOpened, cornerRadius: 10)
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(.thumbnailBackground)
                }
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if entry.isExternal {
                        Image(systemName: "arrow.up.forward.app")
                            .accessibilityLabel("Opened from another app")
                    }
                    Text("\(entry.fileExtension) · \(entry.lastOpened.formatted(.relative(presentation: .named)))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

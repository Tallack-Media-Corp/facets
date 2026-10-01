import SwiftUI

struct RecentsView: View {
    @Environment(RecentsStore.self) private var recents
    @Environment(Router.self) private var router
    @Environment(FileLibrary.self) private var library
    @State private var confirmingClear = false
    @State private var missing: RecentsStore.Entry?

    var body: some View {
        NavigationStack {
            List {
                ForEach(recents.entries) { entry in
                    Button {
                        open(entry)
                    } label: {
                        RecentRow(entry: entry, url: recents.resolve(entry), isAvailable: recents.isAvailable(entry))
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
                        // Words, not a bin: clearing the list doesn't delete any files.
                        Button("Clear") { confirmingClear = true }
                    }
                }
            }
            .confirmationDialog("Clear the list of recent models?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Clear Recents", role: .destructive) { recents.clear() }
            } message: {
                Text("The files themselves aren't touched.")
            }
            .alert("File Not Found", isPresented: Binding(get: { missing != nil }, set: { if !$0 { missing = nil } })) {
                Button("Remove from Recents", role: .destructive) {
                    if let missing { recents.remove(missing) }
                }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("\(missing?.name ?? "This model") was moved, renamed or deleted, or Facets no longer has access to it.")
            }
        }
    }

    private func open(_ entry: RecentsStore.Entry) {
        guard let url = recents.resolve(entry), recents.isAvailable(entry) else {
            missing = entry
            return
        }
        router.presented = ModelFileRef(url: url, isExternal: !library.contains(url))
    }
}

private struct RecentRow: View {
    let entry: RecentsStore.Entry
    let url: URL?
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let url, isAvailable {
                    ModelThumbnail(url: url, size: nil, modified: entry.lastOpened, cornerRadius: 10)
                } else if !isAvailable {
                    RoundedRectangle(cornerRadius: 10).fill(.thumbnailBackground)
                        .overlay {
                            Image(systemName: "questionmark.folder")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
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
                    if !isAvailable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("File not found")
                    } else {
                        if entry.isExternal {
                            Image(systemName: "arrow.up.forward.app")
                                .accessibilityLabel("Opened from another app")
                        }
                        Text("\(entry.fileExtension) · \(entry.lastOpened.formatted(.relative(presentation: .named)))")
                    }
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

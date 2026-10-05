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
                        RecentRow(entry: entry)
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
            // Files deleted or gone since last time drop out, rather than piling up.
            .task { await recents.pruneMissing() }
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
                Text("\(missing?.displayName ?? "This model") was moved, renamed or deleted, or Facets no longer has access to it.")
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
    @State private var state: RecentsStore.FileState?
    private var isAvailable: Bool { state?.isAvailable ?? true }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var thumbnailSize: CGFloat = 52

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let state, let url = state.url, state.isAvailable {
                    // Keyed on the file itself, as the library is, so the two share
                    // one cached picture and reopening doesn't redraw it.
                    ModelThumbnail(url: url, size: state.size, modified: state.modified, cornerRadius: 10, showsBackdrop: false, isDownloaded: state.isDownloaded)
                } else if !isAvailable {
                    Image(systemName: "questionmark.folder")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    Color.clear
                }
            }
            .frame(width: min(thumbnailSize, 88), height: min(thumbnailSize, 88))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.displayName)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                HStack(spacing: 4) {
                    if !isAvailable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Moved or deleted")
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
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isAvailable ? "Opens the model" : "Offers to remove it from Recents")
        .task(id: entry) {
            let entry = entry
            state = await Task.detached(priority: .userInitiated) { RecentsStore.fileState(for: entry) }.value
        }
    }
}

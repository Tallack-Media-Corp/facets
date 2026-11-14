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
                        RowAction.remove { recents.remove(entry) }
                    }
                    .contextMenu {
                        RowAction.remove("Remove from Recents") { recents.remove(entry) }
                    }
                }
            }
            .overlay {
                if recents.entries.isEmpty {
                    ContentUnavailableView("No Recent Models", systemImage: Symbol.noRecents, description: Text("Models you open, here or from other apps, appear here."))
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
            .alert("File Not Found", isPresented: $missing.isPresent) {
                Button("Remove from Recents", role: .destructive) {
                    if let missing { recents.remove(missing) }
                }
                Button("Keep", role: .cancel) {}
            } message: {
                Text("It was moved, renamed or deleted, or Facets no longer has access to it.")
            }
        }
    }

    private func open(_ entry: RecentsStore.Entry) {
        guard let url = recents.resolve(entry), recents.isAvailable(entry) else {
            missing = entry
            return
        }
        router.presented = ModelFileRef(url: url, libraryRoot: library.root)
    }
}

private struct RecentRow: View {
    let entry: RecentsStore.Entry
    @State private var state: RecentsStore.FileState?
    private var isAvailable: Bool { state?.isAvailable ?? true }

    var body: some View {
        ThumbnailRow(title: entry.displayName) {
            if let state, let url = state.url, state.isAvailable {
                // Keyed on the file itself, as the library is, so the two share
                // one cached picture and reopening doesn't redraw it. The row rounds
                // the corners.
                ModelThumbnail(url: url, size: state.size, modified: state.modified, cornerRadius: 0, showsBackdrop: false, isDownloaded: state.isDownloaded)
            } else if !isAvailable {
                Image(systemName: Symbol.missing)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Color.clear
            }
        } caption: {
            HStack(spacing: Spacing.xs) {
                if !isAvailable {
                    // A warning beside the words, as for a printer the model doesn't fit.
                    Image(systemName: Symbol.warning)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("Moved or deleted")
                } else {
                    if entry.isExternal {
                        Image(systemName: Symbol.fromAnotherApp)
                            .accessibilityLabel("Opened from another app")
                    }
                    Text("\(entry.fileExtension) · \(entry.lastOpened.formatted(.relative(presentation: .named)))")
                }
            }
        }
        .accessibilityHint(isAvailable ? "Opens the model" : "Offers to remove it from Recents")
        .task(id: entry) {
            let entry = entry
            state = await Task.detached(priority: .userInitiated) { RecentsStore.fileState(for: entry) }.value
        }
    }
}

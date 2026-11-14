import SwiftUI

/// Models and folders deleted in the last 30 days, ready to put back.
struct RecentlyDeletedView: View {
    @Environment(FileLibrary.self) private var library
    @Environment(ToastCenter.self) private var toasts
    @State private var items: [FileLibrary.DeletedItem] = []
    /// Not "Nothing Deleted" before the first read is in.
    @State private var loaded = false
    @State private var confirmingEmpty = false
    /// Deleting for good can't be undone, so even one item asks first.
    @State private var purging: FileLibrary.DeletedItem?

    var body: some View {
        List {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    HStack(spacing: 12) {
                        RowThumbnail {
                            if item.isFolder {
                                FolderTile(showsBackdrop: false)
                            } else {
                                // Drawn from the file where it waits; a cube while it renders.
                                ModelThumbnail(url: item.stored, cornerRadius: 10, showsBackdrop: false, isDownloaded: item.isDownloaded)
                            }
                        }
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName)
                                .font(.headline)
                                .lineLimit(3)
                            Text(detail(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 8)
                    // In sight on every row, not only behind a swipe or a right-click.
                    Button("Restore") { restore([item]) }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(String(localized: "Restore \(item.displayName)"))
                }
                .swipeActions(edge: .leading) {
                    Button("Restore", systemImage: "arrow.uturn.backward") { restore([item]) }
                        .tint(.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete Now", systemImage: "trash", role: .destructive) { purging = item }
                }
                .contextMenu {
                    Button("Restore", systemImage: "arrow.uturn.backward") { restore([item]) }
                    Button("Delete Now", systemImage: "trash", role: .destructive) { purging = item }
                }
            }
        }
        .overlay {
            if loaded, items.isEmpty {
                ContentUnavailableView("Nothing Deleted", systemImage: "trash", description: Text("Models and folders you delete stay here for 30 days, so you can put them back."))
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .listActions(shown: !items.isEmpty) {
            Button("Restore All") { restore(items) }
        } trailing: {
            Button("Delete All", role: .destructive) { confirmingEmpty = true }
        }
        .hidesTabBar()
        .confirmationDialog(items.count == 1 ? String(localized: "Delete this item for good?") : String(localized: "Delete all \(items.count) items for good?"), isPresented: $confirmingEmpty, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { purge(items) }
        } message: {
            Text("They can't be restored after this.")
        }
        .confirmationDialog(String(localized: "Delete \"\(purging?.displayName ?? "")\" for good?"), isPresented: Binding(get: { purging != nil }, set: { if !$0 { purging = nil } }), titleVisibility: .visible) {
            Button("Delete Now", role: .destructive) {
                if let purging { purge([purging]) }
            }
        } message: {
            Text("It can't be restored after this.")
        }
        // On appear and each change; a newer change cancels the older read's result.
        .task(id: library.revision) {
            let found = await library.recentlyDeleted()
            guard !Task.isCancelled else { return }
            items = found
            loaded = true
        }
    }

    private func detail(for item: FileLibrary.DeletedItem) -> String {
        let daysLeft = max(0, Int(ceil(item.deletedAt.addingTimeInterval(FileLibrary.keepDeletedFor).timeIntervalSinceNow / 86_400)))
        let deleted = item.deletedAt.formatted(.relative(presentation: .named))
        // Two strings, so each has one placeholder and the days can take a plural.
        let when = String(localized: "Deleted \(deleted)", comment: "When an item was deleted, as in 'Deleted yesterday'")
        let left = String(localized: "\(daysLeft) days left", comment: "Days until a deleted item is gone for good")
        return "\(when) · \(left)"
    }

    private func restore(_ chosen: [FileLibrary.DeletedItem]) {
        do {
            let restored = try library.restore(chosen)
            if restored.count == 1, let first = restored.first {
                toasts.show(String(localized: "Restored \(Format.title(fromFileName: first.deletingPathExtension().lastPathComponent))"))
            } else {
                toasts.show(String(localized: "Restored \(restored.count) items"))
            }
        } catch {
            toasts.show(String(localized: "Couldn't restore. There may not be enough space."), symbol: "exclamationmark.triangle.fill")
        }
    }

    private func purge(_ chosen: [FileLibrary.DeletedItem]) {
        library.purge(chosen)
    }
}

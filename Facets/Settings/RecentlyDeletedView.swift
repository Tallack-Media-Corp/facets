import SwiftUI

/// Models and folders deleted in the last 30 days, ready to put back.
struct RecentlyDeletedView: View {
    @Environment(FileLibrary.self) private var library
    @Environment(ToastCenter.self) private var toasts
    @State private var items: [FileLibrary.DeletedItem] = []
    @State private var confirmingEmpty = false

    var body: some View {
        List {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.isFolder ? "folder" : "cube")
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.headline)
                            .lineLimit(3)
                        Text(detail(for: item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .swipeActions(edge: .leading) {
                    Button("Restore", systemImage: "arrow.uturn.backward") { restore([item]) }
                        .tint(.accentColor)
                }
                .swipeActions(edge: .trailing) {
                    Button("Delete Now", systemImage: "trash", role: .destructive) { purge([item]) }
                }
                .contextMenu {
                    Button("Restore", systemImage: "arrow.uturn.backward") { restore([item]) }
                    Button("Delete Now", systemImage: "trash", role: .destructive) { purge([item]) }
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Nothing Deleted", systemImage: "trash", description: Text("Models and folders you delete stay here for 30 days, so you can put them back."))
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button("Restore All") { restore(items) }
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("Delete All", role: .destructive) { confirmingEmpty = true }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .confirmationDialog("Delete \(items.count == 1 ? "this item" : "all \(items.count) items") for good?", isPresented: $confirmingEmpty, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { purge(items) }
        } message: {
            Text("They can't be restored after this.")
        }
        .onAppear(perform: reload)
        .onChange(of: library.revision) { reload() }
    }

    private func detail(for item: FileLibrary.DeletedItem) -> String {
        let daysLeft = max(0, Int(ceil(item.deletedAt.addingTimeInterval(FileLibrary.keepDeletedFor).timeIntervalSinceNow / 86_400)))
        let deleted = item.deletedAt.formatted(.relative(presentation: .named))
        return "Deleted \(deleted) · \(daysLeft == 1 ? "1 day" : "\(daysLeft) days") left"
    }

    private func reload() {
        items = library.recentlyDeleted()
    }

    private func restore(_ chosen: [FileLibrary.DeletedItem]) {
        do {
            let restored = try library.restore(chosen)
            if restored.count == 1, let first = restored.first {
                toasts.show("Restored \(first.deletingPathExtension().lastPathComponent)")
            } else {
                toasts.show("Restored \(restored.count) items")
            }
        } catch {
            toasts.show("Couldn't restore. There may not be enough space.", symbol: "exclamationmark.triangle.fill")
        }
    }

    private func purge(_ chosen: [FileLibrary.DeletedItem]) {
        library.purge(chosen)
    }
}

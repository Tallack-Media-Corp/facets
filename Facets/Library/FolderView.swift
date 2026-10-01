import SwiftUI
import UniformTypeIdentifiers

enum LibraryLayout: String {
    case grid, list
}

/// One folder: models and subfolders as a grid of rendered cards or a list. In the
/// library it can be changed; while browsing a folder elsewhere it's look-and-save.
struct FolderView: View {
    let folder: URL
    let title: String
    /// Outside the library (Browse): no renaming, moving or deleting someone else's
    /// files, and models open with Save to Library.
    var isBrowsing = false

    @Environment(FileLibrary.self) private var library
    @Environment(\.zoomNamespace) private var zoom
    @AppStorage("library.layout") private var layout: LibraryLayout = .grid
    @AppStorage("library.sort") private var sort: LibrarySort = .name

    @State private var items: [LibraryItem] = []
    @State private var loaded = false
    @State private var importing = false
    @State private var renaming: LibraryItem?
    @State private var renameText = ""
    @State private var deleting: LibraryItem?
    @State private var moving: LibraryItem?
    @State private var errorMessage: String?
    @State private var watcher: FolderWatcher?
    @State private var dropTargeted = false
    @State private var savedName: String?

    var body: some View {
        content
            .navigationTitle(title)
            .toolbar { toolbar }
            .fileImporter(isPresented: $importing, allowedContentTypes: UTType.models, allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): perform { try library.importFiles(urls, into: folder) }
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .onDrop(of: UTType.models, isTargeted: $dropTargeted) { providers in
                !isBrowsing && acceptDrop(providers)
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .onAppear(perform: reload)
            .onChange(of: library.revision) { reload() }
            .onChange(of: sort) { reload() }
            .refreshable { reload() }
            .task {
                if watcher == nil {
                    watcher = FolderWatcher(url: folder) { [library] in library.noteExternalChange() }
                }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    if let item = renaming { perform { try library.rename(item, to: renameText) } }
                }
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let item = deleting { perform { try library.delete([item]) } }
                }
            } message: {
                Text("This can't be undone.")
            }
            .sheet(item: $moving) { item in
                MoveSheet(item: item) { destination in
                    perform { try library.move([item], to: destination) }
                }
            }
            .overlay(alignment: .bottom) {
                if let savedName {
                    SavedToast(name: savedName)
                }
            }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty, loaded, isBrowsing {
            ContentUnavailableView("No Models Here", systemImage: "cube.transparent", description: Text("This folder has no STL or 3MF files. Subfolders show up here too."))
        } else if items.isEmpty, loaded {
            ScrollView {
                ContentUnavailableView {
                    Label(folder == library.root ? "No Models Yet" : "Empty Folder", systemImage: "cube.transparent")
                } description: {
                    Text("Import STL and 3MF files, or save them to Facets from the Files app, Mail or any app's share sheet.")
                } actions: {
                    Button("Import Files") { importing = true }
                        .buttonStyle(.glassProminent)
                }
                .padding(.top, 80)
            }
        } else if layout == .grid {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16, alignment: .top)], spacing: 20) {
                    ForEach(items) { item in
                        NavigationLink(value: route(for: item)) {
                            LibraryCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .zoomSource(id: item.url, in: zoom)
                        .contextMenu { actions(for: item) } preview: {
                            if !item.isFolder {
                                ModelThumbnail(url: item.url, size: item.size, modified: item.modified, cornerRadius: 0)
                                    .frame(width: 300, height: 300)
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
        } else {
            List {
                ForEach(items) { item in
                    NavigationLink(value: route(for: item)) {
                        LibraryRow(item: item)
                    }
                    .zoomSource(id: item.url, in: zoom)
                    .contextMenu { actions(for: item) }
                    .swipeActions(edge: .trailing) {
                        if isBrowsing {
                            if !item.isFolder {
                                Button("Save to Library", systemImage: "plus") { save(item) }
                                    .tint(.accentColor)
                            }
                        } else {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
                            Button("Rename", systemImage: "pencil") { beginRename(item) }
                        }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Layout", selection: $layout) {
                    Label("Icons", systemImage: "square.grid.2x2").tag(LibraryLayout.grid)
                    Label("List", systemImage: "list.bullet").tag(LibraryLayout.list)
                }
                Picker("Sort By", selection: $sort) {
                    ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label("View Options", systemImage: "ellipsis")
            }
        }
        if !isBrowsing {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Import Files…", systemImage: "square.and.arrow.down") { importing = true }
                Button("New Folder", systemImage: "folder.badge.plus") {
                    perform {
                        let url = try library.createFolder(in: folder)
                        beginRename(LibraryItem(url: url, isFolder: true, size: nil, modified: nil, childCount: 0))
                    }
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
        }
    }

    @ViewBuilder
    private func actions(for item: LibraryItem) -> some View {
        if !item.isFolder {
            ShareLink(item: item.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        if isBrowsing {
            if !item.isFolder {
                Button("Save to Library", systemImage: "plus") { save(item) }
            }
        } else {
            libraryActions(for: item)
        }
    }

    @ViewBuilder
    private func libraryActions(for item: LibraryItem) -> some View {
        Button("Rename", systemImage: "pencil") { beginRename(item) }
        Button("Duplicate", systemImage: "plus.square.on.square") { perform { try library.duplicate(item) } }
        Button("Move…", systemImage: "folder") { moving = item }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
    }

    private var deleteTitle: String {
        guard let deleting else { return "" }
        if deleting.isFolder {
            return "Delete \"\(deleting.name)\" and everything in it?"
        }
        return "Delete \"\(deleting.name)\"?"
    }

    private func route(for item: LibraryItem) -> LibraryRoute {
        if item.isFolder {
            return isBrowsing ? .browse(item.url, title: item.url.lastPathComponent) : .folder(item.url)
        }
        return .model(ModelFileRef(url: item.url, isExternal: isBrowsing))
    }

    private func save(_ item: LibraryItem) {
        perform {
            guard let copy = try library.importFiles([item.url], into: library.root).first else { return }
            withAnimation(.snappy) { savedName = copy.deletingPathExtension().lastPathComponent }
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.snappy) { savedName = nil }
            }
        }
    }

    private func beginRename(_ item: LibraryItem) {
        renameText = item.name
        renaming = item
    }

    private func reload() {
        items = library.items(in: folder, sort: sort)
        loaded = true
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Files dragged in from Files or another app (iPad). Each provider hands over a
    /// temporary copy that only lives for the callback, so it's copied straight away.
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let destination = folder
        var accepted = false
        for provider in providers {
            guard let type = UTType.models.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else { continue }
            accepted = true
            let suggested = provider.suggestedName
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { return }
                let staging = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                let name = suggested.map { $0.hasSuffix(".\(url.pathExtension)") ? $0 : "\($0).\(url.pathExtension)" } ?? url.lastPathComponent
                let copy = staging.appending(path: name)
                do {
                    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: copy)
                } catch {
                    return
                }
                Task { @MainActor in
                    _ = try? library.importFiles([copy], into: destination)
                    try? FileManager.default.removeItem(at: staging)
                }
            }
        }
        return accepted
    }
}

/// A grid card: the rendered model (or a folder), its name and details.
struct LibraryCard: View {
    let item: LibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if item.isFolder {
                    FolderTile(count: item.childCount)
                } else if !item.isDownloaded {
                    CloudTile()
                } else {
                    ModelThumbnail(url: item.url, size: item.size, modified: item.modified)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(LibraryRow.subtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.isFolder ? "Opens the folder" : "Opens the model")
    }
}

struct FolderTile: View {
    let count: Int?

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.thumbnailBackground)
            .overlay {
                Image(systemName: "folder.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.tint.opacity(0.85))
                    .padding(36)
            }
    }
}

/// A model in iCloud that isn't on the device yet; it downloads when opened.
struct CloudTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.thumbnailBackground)
            .overlay {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("In iCloud, downloads when opened")
    }
}

/// "Saved to Library" confirmation that floats above the content for a moment.
struct SavedToast: View {
    let name: String

    var body: some View {
        Label("Saved to Library as \(name)", systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct LibraryRow: View {
    let item: LibraryItem

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if item.isFolder {
                    FolderTile(count: item.childCount)
                } else if !item.isDownloaded {
                    CloudTile()
                } else {
                    ModelThumbnail(url: item.url, size: item.size, modified: item.modified, cornerRadius: 10)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(Self.subtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    static func subtitle(for item: LibraryItem) -> String {
        if item.isFolder {
            let count = item.childCount ?? 0
            return count == 1 ? "1 item" : "\(count) items"
        }
        return [item.fileExtension, Format.fileSize(item.size), Format.date(item.modified)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// Picks a folder to move an item into.
struct MoveSheet: View {
    let item: LibraryItem
    let onMove: (URL) -> Void

    @Environment(FileLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(library.allFolders(), id: \.self) { folder in
                let isCurrent = folder.standardizedFileURL == item.url.deletingLastPathComponent().standardizedFileURL
                let isSelf = item.isFolder && folder.path.hasPrefix(item.url.standardizedFileURL.path)
                Button {
                    onMove(folder)
                    dismiss()
                } label: {
                    Label(name(of: folder), systemImage: folder == library.root ? "tray.full" : "folder")
                }
                .disabled(isCurrent || isSelf)
            }
            .navigationTitle("Move \"\(item.name)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func name(of folder: URL) -> String {
        if folder == library.root { return "Library" }
        return library.relativeFolder(of: folder.appending(path: "x")) ?? folder.lastPathComponent
    }
}

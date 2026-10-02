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
    @Environment(ToastCenter.self) private var toasts
    @Environment(ViewerSettings.self) private var settings
    @Environment(\.undoManager) private var undoManager
    @Environment(\.zoomNamespace) private var zoom
    @AppStorage("library.layout") private var layout: LibraryLayout = .grid
    @AppStorage("library.sort") private var sort: LibrarySort = .name
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var items: [LibraryItem] = []
    @State private var loaded = false
    @State private var importing = false
    @State private var renaming: LibraryItem?
    @State private var renameText = ""
    @State private var deleting: LibraryItem?
    @State private var moving: LibraryItem?
    @State private var failure: (title: String, message: String)?
    @State private var watcher: FolderWatcher?
    @State private var dropTargeted = false
    /// Browsed models copied to the library this visit, on top of `hasCopy`.
    @State private var saved: Set<URL> = []

    var body: some View {
        content
            .navigationTitle(title)
            .toolbar { toolbar }
            .fileImporter(isPresented: $importing, allowedContentTypes: UTType.models, allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): perform("Couldn't Import") { try library.importFiles(urls, into: folder) }
                case .failure(let error): failure = ("Couldn't Import", FriendlyError(file: error).message)
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
                    if let item = renaming { perform("Couldn't Rename") { try library.rename(item, to: renameText) } }
                }
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let item = deleting { delete(item) }
                }
            } message: {
                Text("You can undo this, or restore it from Settings › Recently Deleted for 30 days.")
            }
            .sheet(item: $moving) { item in
                MoveSheet(item: item) { destination in
                    perform("Couldn't Move") { try library.move([item], to: destination) }
                }
            }
            .alert(failure?.title ?? "", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure?.message ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty, loaded, isBrowsing {
            ContentUnavailableView("No Models Here", systemImage: "cube.transparent", description: Text("This folder has no STL, 3MF or OBJ files. Subfolders show up here too."))
        } else if items.isEmpty, loaded {
            ScrollView {
                ContentUnavailableView {
                    Label(folder == library.root ? "No Models Yet" : "Empty Folder", systemImage: "cube.transparent")
                } description: {
                    Text("Import STL, 3MF and OBJ files, or save them to Facets from the Files app, Mail or any app's share sheet.")
                        .frame(maxWidth: 480)
                } actions: {
                    Button("Import Files") { importing = true }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                }
                .padding(.top, 80)
            }
        } else if layout == .grid, !dynamicTypeSize.isAccessibilitySize {
            // At accessibility text sizes two columns can't hold a name; rows can.
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
                                    // Previews render outside this view's environment.
                                    .environment(settings)
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
                            if !item.isFolder, !isSaved(item) {
                                Button("Save to Library", systemImage: "plus") { save(item) }
                                    .tint(.accentColor)
                            }
                        } else {
                            Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(item) }
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
                    perform("Couldn't Create Folder") {
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
                if isSaved(item) {
                    Button("Saved to Library", systemImage: "checkmark") {}
                        .disabled(true)
                } else {
                    Button("Save to Library", systemImage: "plus") { save(item) }
                }
            }
        } else {
            libraryActions(for: item)
        }
    }

    @ViewBuilder
    private func libraryActions(for item: LibraryItem) -> some View {
        Button("Rename", systemImage: "pencil") { beginRename(item) }
        Button("Duplicate", systemImage: "plus.square.on.square") { perform("Couldn't Duplicate") { try library.duplicate(item) } }
        Button("Move…", systemImage: "folder") { moving = item }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(item) }
    }

    private var deleteTitle: String {
        guard let deleting else { return "" }
        if deleting.isFolder {
            return "Delete \"\(deleting.displayName)\" and everything in it?"
        }
        return "Delete \"\(deleting.displayName)\"?"
    }

    private func route(for item: LibraryItem) -> LibraryRoute {
        if item.isFolder {
            return isBrowsing ? .browse(item.url, title: item.url.lastPathComponent) : .folder(item.url)
        }
        return .model(ModelFileRef(url: item.url, isExternal: isBrowsing))
    }

    private func isSaved(_ item: LibraryItem) -> Bool {
        saved.contains(item.url) || library.hasCopy(of: item.url)
    }

    private func save(_ item: LibraryItem) {
        perform("Couldn't Save to Library") {
            guard let copy = try library.importFiles([item.url], into: library.root).first else { return }
            saved.insert(item.url)
            toasts.show("Saved to Library as \(Format.title(fromFileName: copy.deletingPathExtension().lastPathComponent))")
        }
    }

    /// A file goes straight away, with Undo; a folder asks first, because it may hold
    /// a lot more than it shows.
    private func requestDelete(_ item: LibraryItem) {
        if item.isFolder {
            deleting = item
        } else {
            delete(item)
        }
    }

    private func delete(_ item: LibraryItem) {
        perform("Couldn't Delete") {
            let deleted = try library.delete([item])
            let undo = { [library, toasts] in
                do {
                    try library.restore(deleted)
                } catch {
                    toasts.show("Couldn't put \(item.displayName) back. It's still in Settings › Recently Deleted.", symbol: "exclamationmark.triangle.fill")
                }
            }
            undoManager?.registerUndo(withTarget: library) { _ in
                MainActor.assumeIsolated { undo() }
            }
            undoManager?.setActionName("Delete \(item.displayName)")
            toasts.show("Deleted \(item.displayName)", symbol: "trash.fill", actionTitle: "Undo", action: undo)
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

    /// Runs a file operation; if it fails, says which one and why in plain words.
    private func perform(_ title: String, _ action: () throws -> Void) {
        do {
            try action()
        } catch {
            failure = (title, FriendlyError(file: error).message)
        }
    }

    /// Files dragged in from Files or another app (iPad). Each provider hands over a
    /// temporary copy that only lives for its callback, so it's copied out straight
    /// away; then everything is imported together and the result reported.
    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        let supported = providers.compactMap { provider -> (NSItemProvider, UTType)? in
            UTType.models.first { provider.hasItemConformingToTypeIdentifier($0.identifier) }.map { (provider, $0) }
        }
        guard !supported.isEmpty else { return false }
        let destination = folder
        let total = providers.count
        Task {
            var staged: [URL] = []
            for (provider, type) in supported {
                if let url = await Self.stage(provider, type: type) { staged.append(url) }
            }
            var added = 0
            if !staged.isEmpty, let copies = try? library.importFiles(staged, into: destination) {
                added = copies.count
            }
            for url in staged { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let missed = total - added
            switch (added, missed) {
            case (0, _):
                toasts.show(total == 1 ? "Couldn't add that file. Only STL, 3MF and OBJ files can go in the library." : "Couldn't add those files. Only STL, 3MF and OBJ files can go in the library.", symbol: "exclamationmark.triangle.fill")
            case (_, 0):
                toasts.show(added == 1 ? "Added 1 model" : "Added \(added) models")
            default:
                toasts.show("Added \(added) of \(total). The others aren't STL, 3MF or OBJ files.", symbol: "exclamationmark.triangle.fill")
            }
        }
        return true
    }

    /// Copies a dropped file somewhere it outlives the provider's callback.
    private static func stage(_ provider: NSItemProvider, type: UTType) async -> URL? {
        let suggested = provider.suggestedName
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let staging = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                let name = suggested.map { $0.hasSuffix(".\(url.pathExtension)") ? $0 : "\($0).\(url.pathExtension)" } ?? url.lastPathComponent
                let copy = staging.appending(path: name)
                do {
                    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

/// A grid card: the rendered model (or a folder), its name and details.
struct LibraryCard: View {
    let item: LibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if item.isFolder {
                    FolderTile()
                } else if !item.isDownloaded {
                    CloudTile()
                } else {
                    ModelThumbnail(url: item.url, size: item.size, modified: item.modified)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
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
    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(.thumbnailBackground)
            .overlay {
                // Inset in proportion, so the glyph fills a 52pt row tile and a grid tile alike.
                GeometryReader { geometry in
                    Image(systemName: "folder.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.tint.opacity(0.85))
                        .padding(geometry.size.width * 0.2)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
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

struct LibraryRow: View {
    let item: LibraryItem

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Grows with the text, up to a point, so the picture still reads beside big type.
    @ScaledMetric(relativeTo: .headline) private var thumbnailSize: CGFloat = 52

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if item.isFolder {
                    FolderTile()
                } else if !item.isDownloaded {
                    CloudTile()
                } else {
                    ModelThumbnail(url: item.url, size: item.size, modified: item.modified, cornerRadius: 10)
                }
            }
            .frame(width: min(thumbnailSize, 88), height: min(thumbnailSize, 88))
            .clipShape(.rect(cornerRadius: 10))

            // At accessibility sizes names wrap rather than truncate; that's the point
            // of showing rows there.
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.headline)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                Text(Self.subtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
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
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(library.allFolders(), id: \.self) { folder in
                let isCurrent = folder.standardizedFileURL == item.url.deletingLastPathComponent().standardizedFileURL
                // The folder itself or anything inside it; "Parts 2" isn't inside "Parts".
                let moving = item.url.standardizedFileURL.path
                let isSelf = item.isFolder && (folder.standardizedFileURL.path == moving || folder.standardizedFileURL.path.hasPrefix(moving + "/"))
                Button {
                    onMove(folder)
                    dismiss()
                } label: {
                    Label(name(of: folder), systemImage: folder == library.root ? "tray.full" : "folder")
                }
                .disabled(isCurrent || isSelf)
            }
            .navigationTitle("Move \"\(item.displayName)\"")
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

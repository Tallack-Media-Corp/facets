import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import QuickLook
#endif

enum LibraryLayout: String {
    case grid, list
}

/// One folder: models and subfolders as a grid of rendered cards or a list. In the
/// library it can be changed; while browsing a folder elsewhere it's look-and-save.
struct FolderView: View {
    #if os(macOS)
    private static let emptyHint = "Import STL, 3MF and OBJ files, or drag them here from the Finder."
    #else
    private static let emptyHint = "Import STL, 3MF and OBJ files, or save them to Facets from the Files app, Mail or any app's share sheet."
    #endif

    let folder: URL
    let title: String
    /// Outside the library (Browse): no renaming, moving or deleting someone else's
    /// files, and models open with Save to Library.
    var isBrowsing = false
    /// The library's root: Library | Browse sits at the top of the content.
    var showsSectionPicker = false

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
    /// Waiting on "Delete … and everything in it?": only asked when there's a folder.
    @State private var deleting: [LibraryItem] = []
    @State private var moving: LibraryItem?
    @State private var failure: (title: String, message: String)?
    @State private var watcher: FolderWatcher?
    /// Bumped per reload, so a slow read finishing late can't replace a newer one.
    @State private var loadGeneration = 0
    @State private var dropTargeted = false
    /// Browsed models copied to the library this visit, on top of `hasCopy`.
    @State private var saved: Set<URL> = []

    #if os(macOS)
    // The Mac selects with a click and opens with a double-click, as the Finder does.
    @State private var selection: Set<URL> = []
    /// Where a shift-click range starts, and where the arrow keys move from.
    @State private var anchor: URL?
    @State private var quickLook: URL?
    @State private var columnCount = 1
    @State private var viewportHeight: CGFloat = 0
    @FocusState private var gridFocused: Bool
    @Environment(\.openModel) private var openModel
    @Environment(\.openFolder) private var openFolder
    #endif

    var body: some View {
        keyedContent
            .navigationTitle(title)
            .toolbar { toolbar }
            .fileImporter(isPresented: $importing, allowedContentTypes: UTType.models, allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): perform("Couldn't Import") { try await library.importFiles(urls, into: folder) }
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
            .overlay {
                if !loaded {
                    ProgressView()
                        .controlSize(.large)
                        .accessibilityLabel("Loading folder")
                }
            }
            .onAppear(perform: reload)
            .onChange(of: library.revision) { reload() }
            .onChange(of: sort) { reload() }
            .refreshable { await load() }
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
                isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    delete(deleting)
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

    private var keyedContent: some View {
        #if os(macOS)
        selectionKeys(content)
        #else
        content
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty, loaded, isBrowsing {
            ContentUnavailableView("No Models Here", systemImage: "cube.transparent", description: Text("This folder has no STL, 3MF or OBJ files. Subfolders show up here too."))
        } else if items.isEmpty, loaded {
            ScrollView {
                if showsSectionPicker {
                    LibrarySectionPicker()
                        .padding(.horizontal)
                        .padding(.top, LibrarySectionPicker.listTopMargin)
                }
                ContentUnavailableView {
                    Label(folder == library.root ? "No Models Yet" : "Empty Folder", systemImage: "cube.transparent")
                } description: {
                    Text(Self.emptyHint)
                        .frame(maxWidth: 480)
                } actions: {
                    Button("Import Files") { importing = true }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                    // Something to look at before there are files of your own.
                    if folder == library.root {
                        OpenSampleButton(title: "Try the Sample Model")
                            .buttonStyle(.glass)
                            .controlSize(.large)
                    }
                }
                .padding(.top, 80)
            }
        } else if layout == .grid, !dynamicTypeSize.isAccessibilitySize {
            // At accessibility text sizes two columns can't hold a name; rows can.
            ScrollView {
                if showsSectionPicker {
                    LibrarySectionPicker()
                        .padding(.horizontal)
                        .padding(.top, LibrarySectionPicker.listTopMargin)
                        .padding(.bottom, 8)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 16, alignment: .top)], spacing: 20) {
                    ForEach(items) { item in
                        #if os(macOS)
                        macCard(item)
                        #else
                        open(item) {
                            LibraryCard(item: item)
                        }
                        .buttonStyle(.plain)
                        .zoomSource(id: item.url, in: zoom)
                        .contextMenu { actions(for: item) } preview: {
                            if !item.isFolder {
                                ModelThumbnail(url: item.url, size: item.size, modified: item.modified, cornerRadius: 0, isDownloaded: item.isDownloaded)
                                    .frame(width: 300, height: 300)
                                    // Previews render outside this view's environment.
                                    .environment(settings)
                            }
                        }
                        #endif
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                #if os(macOS)
                .onGeometryChange(for: Int.self) { geometry in
                    // As the adaptive grid fits them: 150 pt minimum, 16 pt apart.
                    max(1, Int((geometry.size.width - 32 + 16) / (150 + 16)))
                } action: { columnCount = $0 }
                // A click on the background, between or below the cards, clears the
                // selection. It sits behind the cards, filling the visible area, so
                // a click on a card never reaches it.
                .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .top)
                .background {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { selection = [] }
                }
                #endif
            }
            .background(Color.groupedBackground)
            #if os(macOS)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
            // Keys go to the grid: arrows, Return, Space, Command-Delete, Escape.
            .focusable()
            .focused($gridFocused)
            .focusEffectDisabled()
            #endif
        } else {
            #if os(macOS)
            macList
            #else
            List {
                if showsSectionPicker {
                    LibrarySectionPicker().sectionPickerRow()
                }
                ForEach(items) { item in
                    open(item) {
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
            #endif
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
            .toolbarMenuIndicator()
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
            .toolbarMenuIndicator()
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
        Button("Duplicate", systemImage: "plus.square.on.square") { perform("Couldn't Duplicate") { try await library.duplicate(item) } }
        Button("Move…", systemImage: "folder") { moving = item }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { requestDelete(item) }
    }

    private var deleteTitle: String {
        guard let first = deleting.first else { return "" }
        if deleting.count > 1 {
            return "Delete \(deleting.count) items and everything in them?"
        }
        if first.isFolder {
            return "Delete \"\(first.displayName)\" and everything in it?"
        }
        return "Delete \"\(first.displayName)\"?"
    }

    /// A folder pushes; a model opens in the viewer over the tab.
    @ViewBuilder
    private func open(_ item: LibraryItem, @ViewBuilder label: () -> some View) -> some View {
        if item.isFolder {
            NavigationLink(value: isBrowsing ? LibraryRoute.browse(item.url, title: item.url.lastPathComponent) : .folder(item.url), label: label)
        } else {
            let content = label()
            OpenModelButton(file: ModelFileRef(url: item.url, isExternal: isBrowsing)) { content }
        }
    }

    private func isSaved(_ item: LibraryItem) -> Bool {
        saved.contains(item.url) || library.hasCopy(of: item.url, size: item.size)
    }

    private func save(_ item: LibraryItem) {
        perform("Couldn't Save to Library") {
            guard let copy = try await library.importFiles([item.url], into: library.root).first else { return }
            saved.insert(item.url)
            toasts.show("Saved to Library as \(Format.title(fromFileName: copy.deletingPathExtension().lastPathComponent))")
        }
    }

    /// A file goes straight away, with Undo; a folder asks first, because it may hold
    /// a lot more than it shows.
    private func requestDelete(_ item: LibraryItem) {
        requestDelete([item])
    }

    private func requestDelete(_ items: [LibraryItem]) {
        guard !items.isEmpty else { return }
        if items.contains(where: \.isFolder) {
            deleting = items
        } else {
            delete(items)
        }
    }

    private func delete(_ items: [LibraryItem]) {
        let name = items.count == 1 ? items[0].displayName : "\(items.count) items"
        perform("Couldn't Delete") {
            let deleted = try library.delete(items)
            let undo = { [library, toasts] in
                do {
                    try library.restore(deleted)
                } catch {
                    toasts.show("Couldn't put \(name) back. It's still in Settings › Recently Deleted.", symbol: "exclamationmark.triangle.fill")
                }
            }
            undoManager?.registerUndo(withTarget: library) { _ in
                MainActor.assumeIsolated { undo() }
            }
            undoManager?.setActionName("Delete \(name)")
            toasts.show("Deleted \(name)", symbol: "trash.fill", actionTitle: "Undo", action: undo)
            #if os(macOS)
            selection.subtract(items.map(\.url))
            #endif
        }
    }

    private func beginRename(_ item: LibraryItem) {
        renameText = item.name
        renaming = item
    }

    /// Reads the folder in the background, so a slow one (iCloud Drive, a big
    /// Downloads) never freezes the screen; a frozen screen queues taps that then
    /// land on whatever row appears under them. Names show first, counts after.
    private func reload() {
        Task { await load() }
    }

    /// Lists the folder; returns once the list is showing (pull to refresh waits for
    /// it), with the folder counts following on their own.
    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let folder = folder, sort = sort, root = library.root
        let listed = await Task.detached(priority: .userInitiated) {
            FileLibrary.scan(folder, sort: sort, root: root)
        }.value
        guard generation == loadGeneration else { return }
        items = listed
        loaded = true
        guard listed.contains(where: \.isFolder) else { return }
        Task {
            let counted = await Task.detached(priority: .utility) {
                FileLibrary.withChildCounts(listed)
            }.value
            guard generation == loadGeneration else { return }
            items = counted
        }
    }

    /// Runs a file operation; if it fails, says which one and why in plain words.
    private func perform(_ title: String, _ action: () throws -> Void) {
        do {
            try action()
        } catch {
            failure = (title, FriendlyError(file: error).message)
        }
    }

    /// The same, for work that copies files (and may wait on iCloud) in the background.
    private func perform(_ title: String, _ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                failure = (title, FriendlyError(file: error).message)
            }
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
            if !staged.isEmpty, let copies = try? await library.importFiles(staged, into: destination) {
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
    /// Selected on the Mac: an outline round the picture and the name highlighted,
    /// as the Finder shows it.
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if item.isFolder {
                    FolderTile()
                } else {
                    ModelThumbnail(url: item.url, size: item.size, modified: item.modified, isDownloaded: item.isDownloaded)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.tint, lineWidth: 3)
                        .padding(-3)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    // Primary text on a tint wash: white on Filament Orange falls short
                    // of 4.5:1 at this size.
                    .padding(.horizontal, isSelected ? 4 : 0)
                    .background(isSelected ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 4))
                    .padding(.horizontal, isSelected ? -4 : 0)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct FolderTile: View {
    var showsBackdrop = true
    @Environment(ViewerSettings.self) private var settings: ViewerSettings?

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(showsBackdrop ? AnyShapeStyle(Palette.tileGradient(pureBlack: settings?.pureBlack ?? false)) : AnyShapeStyle(.clear))
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

struct LibraryRow: View {
    let item: LibraryItem

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Grows with the text, up to a point, so the picture still reads beside big type.
    @ScaledMetric(relativeTo: .headline) private var thumbnailSize: CGFloat = 52

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if item.isFolder {
                    FolderTile(showsBackdrop: false)
                } else {
                    ModelThumbnail(url: item.url, size: item.size, modified: item.modified, cornerRadius: 10, showsBackdrop: false, isDownloaded: item.isDownloaded)
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
            guard let count = item.childCount else { return "Folder" }
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
    @State private var folders: [URL]?

    var body: some View {
        NavigationStack {
            List(folders ?? [], id: \.self) { folder in
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
        .overlay { if folders == nil { ProgressView() } }
        .task {
            let root = library.root
            folders = await Task.detached(priority: .userInitiated) { FileLibrary.allFolders(in: root) }.value
        }
    }

    private func name(of folder: URL) -> String {
        if folder == library.root { return "Library" }
        return library.relativeFolder(of: folder.appending(path: "x")) ?? folder.lastPathComponent
    }
}

#if os(macOS)
// MARK: Selection on the Mac

extension FolderView {
    private var selectedItems: [LibraryItem] { items.filter { selection.contains($0.url) } }

    /// A grid card: click to select, double-click to open, drag out to the Finder or
    /// a slicer.
    fileprivate func macCard(_ item: LibraryItem) -> some View {
        LibraryCard(item: item, isSelected: selection.contains(item.url))
            .gesture(TapGesture(count: 2).onEnded { activate([item]) })
            .simultaneousGesture(TapGesture().onEnded { click(item) })
            .draggable(item.url)
            .contextMenu { selectionMenu(for: selection.contains(item.url) ? selectedItems : [item]) }
            // No longer a Button on the Mac, so say it can be opened.
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { activate([item]) }
    }

    /// The list: the system's own selection, double-click and Return to open.
    fileprivate var macList: some View {
        List(selection: $selection) {
            if showsSectionPicker {
                LibrarySectionPicker().sectionPickerRow()
            }
            ForEach(items) { item in
                LibraryRow(item: item)
                    .tag(item.url)
                    .draggable(item.url)
            }
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            selectionMenu(for: items.filter { urls.contains($0.url) })
        } primaryAction: { urls in
            activate(items.filter { urls.contains($0.url) })
        }
    }

    @ViewBuilder
    private func selectionMenu(for chosen: [LibraryItem]) -> some View {
        if chosen.count == 1, let item = chosen.first {
            Button("Open") { activate([item]) }
            Divider()
            actions(for: item)
        } else if chosen.count > 1 {
            let models = chosen.filter { !$0.isFolder }
            if !models.isEmpty {
                Button(models.count == 1 ? "Open" : "Open \(models.count) Models") { activate(models) }
            }
            if !isBrowsing {
                Divider()
                Button("Delete \(chosen.count) Items", systemImage: "trash", role: .destructive) { requestDelete(chosen) }
            }
        }
    }

    private func click(_ item: LibraryItem) {
        gridFocused = true
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(item.url) { selection.remove(item.url) } else { selection.insert(item.url) }
        } else if flags.contains(.shift), let anchor, let from = index(of: anchor), let to = index(of: item.url) {
            selection = Set(items[min(from, to)...max(from, to)].map(\.url))
            return
        } else {
            selection = [item.url]
        }
        anchor = item.url
    }

    /// A folder opens in place (only when it's the one thing chosen); each model in
    /// a window of its own.
    private func activate(_ chosen: [LibraryItem]) {
        if chosen.count == 1, let folder = chosen.first, folder.isFolder {
            openFolder(isBrowsing ? .browse(folder.url, title: folder.url.lastPathComponent) : .folder(folder.url))
            return
        }
        for model in chosen where !model.isFolder {
            openModel(ModelFileRef(url: model.url, isExternal: isBrowsing))
        }
    }

    private func index(of url: URL) -> Int? {
        items.firstIndex { $0.url == url }
    }

    private func move(_ key: KeyEquivalent) -> KeyPress.Result {
        guard !items.isEmpty else { return .ignored }
        let step = switch key {
        case .leftArrow: -1
        case .rightArrow: 1
        case .upArrow: -columnCount
        default: columnCount
        }
        let current = anchor.flatMap(index(of:))
        let next = current.map { min(max($0 + step, 0), items.count - 1) } ?? 0
        selection = [items[next].url]
        anchor = items[next].url
        if quickLook != nil, !items[next].isFolder { quickLook = items[next].url }
        return .handled
    }

    fileprivate func selectionKeys(_ content: some View) -> some View {
        content
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                // The list moves its own selection; only the grid needs this.
                guard layout == .grid, !dynamicTypeSize.isAccessibilitySize else { return .ignored }
                return move(press.key)
            }
            .onKeyPress(.return) {
                guard !selection.isEmpty, layout == .grid else { return .ignored }
                activate(selectedItems)
                return .handled
            }
            .onKeyPress(.space) {
                if quickLook != nil {
                    quickLook = nil
                } else if let first = selectedItems.first(where: { !$0.isFolder }) {
                    quickLook = first.url
                } else {
                    return .ignored
                }
                return .handled
            }
            .onKeyPress(.escape) {
                guard !selection.isEmpty else { return .ignored }
                selection = []
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward]) { press in
                guard press.modifiers.contains(.command), !isBrowsing, !selection.isEmpty else { return .ignored }
                requestDelete(selectedItems)
                return .handled
            }
            .quickLookPreview($quickLook, in: selectedItems.filter { !$0.isFolder }.map(\.url))
            // A selection doesn't outlive its folder's contents.
            .onChange(of: items) { selection.formIntersection(items.map(\.url)) }
    }
}
#endif

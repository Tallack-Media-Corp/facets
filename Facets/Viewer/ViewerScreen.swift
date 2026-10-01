import MeshKit
import SwiftUI

/// The full-screen 3D view of one file.
struct ViewerScreen: View {
    let file: ModelFileRef
    /// True when presented over the app (opened from another app), not pushed.
    var showsCloseButton = false

    private enum Phase {
        case loading
        case loaded(Model3D)
        case failed(String)
    }

    @Environment(ViewerSettings.self) private var settings
    @Environment(RecentsStore.self) private var recents
    @Environment(FileLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var phase = Phase.loading
    @State private var appearance = RenderAppearance()
    @State private var controller = ModelCanvasController()
    @State private var showingInfo = false
    @State private var fileSize: Int64?
    @State private var isAccessing = false
    @State private var savedName: String?
    @State private var isSaved = false
    @State private var saveError: String?

    var body: some View {
        ZStack {
            ViewerBackground()
            switch phase {
            case .loading:
                ProgressView("Opening \(file.name)…")
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            case .failed(let message):
                ContentUnavailableView("Can't Open This Model", systemImage: "exclamationmark.triangle", description: Text(message))
            case .loaded(let model):
                ModelCanvas(model: model, appearance: appearance, controller: controller)
                    .ignoresSafeArea()
                    .accessibilityLabel("\(file.name), \(Format.dimensions(visibleBounds(model).size, units: settings.units))")
                    .accessibilityHint("Drag to turn, pinch to zoom, double tap to fit.")
            }
        }
        .overlay(alignment: .top) {
            if case .loaded(let model) = phase {
                ViewerChips(model: model, plateID: $appearance.plateID, dimensions: Format.dimensions(visibleBounds(model).size, units: settings.units))
                    .padding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if let savedName {
                SavedToast(name: savedName)
            }
        }
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbar }
        .sheet(isPresented: $showingInfo) {
            if case .loaded(let model) = phase {
                ModelInfoSheet(model: model, file: file, fileSize: fileSize, units: settings.units, appearance: $appearance)
            }
        }
        .alert("Couldn't Save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        .task { await load() }
        .onDisappear {
            if isAccessing {
                file.url.stopAccessingSecurityScopedResource()
                isAccessing = false
            }
        }
        .onChange(of: settings.colorHex) { syncSettings() }
        .onChange(of: settings.usesFileColors) { syncSettings() }
        .onChange(of: colorScheme) { syncSettings() }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if showsCloseButton {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
        }
        // A file from Browse or another app gets a plus beside Share to keep a copy.
        // It stays as a tick once saved, so the bar doesn't jump.
        if file.isExternal {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaved ? "Saved to Library" : "Save to Library", systemImage: isSaved ? "checkmark" : "plus") {
                    saveToLibrary()
                }
                .contentTransition(.symbolEffect(.replace))
                .disabled(isSaved)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            ShareLink(item: file.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }

        if case .loaded = phase {
            ToolbarItem(placement: .bottomBar) {
                Button("Fit", systemImage: "arrow.down.left.and.arrow.up.right.rectangle") {
                    controller.frameModel()
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    ForEach(OrbitCamera.Preset.allCases) { preset in
                        Button(preset.title, systemImage: symbol(for: preset)) { controller.show(preset) }
                    }
                } label: {
                    Label("Views", systemImage: "cube")
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Toggle(isOn: $appearance.wireframe) {
                    Label("Wireframe", systemImage: "cube.transparent")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Toggle(isOn: $appearance.showsGrid) {
                    Label("Build Plate Grid", systemImage: "grid")
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button("Info", systemImage: "info.circle") { showingInfo = true }
            }
        }
    }

    private func symbol(for preset: OrbitCamera.Preset) -> String {
        switch preset {
        case .isometric: "cube"
        case .front: "square.bottomhalf.filled"
        case .back: "square.tophalf.filled"
        case .left: "square.lefthalf.filled"
        case .right: "square.righthalf.filled"
        case .top: "arrow.down.to.line"
        case .bottom: "arrow.up.to.line"
        }
    }

    private func visibleBounds(_ model: Model3D) -> Bounds {
        let parts = model.visibleParts(plateID: appearance.plateID, hidden: appearance.hiddenObjects)
        return model.bounds(of: parts.isEmpty ? model.parts : parts)
    }

    private func syncSettings() {
        let base = settings.appearance
        appearance.baseColor = base.baseColor
        appearance.usesFileColors = base.usesFileColors
        appearance.gridColor = RenderAppearance.gridColor(dark: colorScheme == .dark)
    }

    private func load() async {
        guard case .loading = phase else { return }
        appearance = settings.appearance
        syncSettings()
        let url = file.url
        if file.isExternal, !isAccessing {
            isAccessing = url.startAccessingSecurityScopedResource()
        }
        fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        recents.record(file)
        do {
            let model = try await Task.detached(priority: .userInitiated) {
                try Self.loadCoordinated(url)
            }.value
            // A multi-plate project opens on its first plate, like the slicer.
            appearance.plateID = model.plates.first?.id
            phase = .loaded(model)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Reads through a file coordinator, so a file in iCloud Drive downloads first.
    nonisolated private static func loadCoordinated(_ url: URL) throws -> Model3D {
        var coordinatorError: NSError?
        var result: Result<Model3D, Error> = .failure(ModelError.emptyFile)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            result = Result { try ModelLoader.load(readURL) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }

    private func saveToLibrary() {
        do {
            let copies = try library.importFiles([file.url], into: library.root)
            guard let copy = copies.first else { return }
            withAnimation(.snappy) {
                isSaved = true
                savedName = copy.deletingPathExtension().lastPathComponent
            }
            Task {
                try? await Task.sleep(for: .seconds(3))
                withAnimation(.snappy) { savedName = nil }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }
}

/// Size, and the plate picker for multi-plate projects, floating over the model.
private struct ViewerChips: View {
    let model: Model3D
    @Binding var plateID: Int?
    let dimensions: String

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                if !model.plates.isEmpty {
                    Menu {
                        Picker("Plate", selection: $plateID) {
                            Text("All Plates").tag(Int?.none)
                            ForEach(model.plates) { plate in
                                Text(plate.title).tag(Optional(plate.id))
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up")
                            Text(plateTitle)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityLabel("Plate: \(plateTitle)")
                }
                Text(dimensions)
                    .font(.footnote.weight(.medium).monospacedDigit())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .accessibilityLabel("Size \(dimensions)")
            }
        }
    }

    private var plateTitle: String {
        model.plates.first { $0.id == plateID }?.title ?? "All Plates"
    }
}

/// A soft studio backdrop behind the transparent 3D view.
struct ViewerBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(light: 0xF6F7F9, dark: 0x2C2E33), Color(light: 0xD9DCE1, dark: 0x111214)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        func color(_ rgb: UInt32) -> UIColor {
            UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) })
    }
}

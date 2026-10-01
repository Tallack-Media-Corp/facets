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
        case failed(FriendlyError)
    }

    @Environment(ViewerSettings.self) private var settings
    @Environment(RecentsStore.self) private var recents
    @Environment(FileLibrary.self) private var library
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var phase = Phase.loading
    @State private var appearance = RenderAppearance()
    @State private var controller = ModelCanvasController()
    @State private var showingInfo = false
    @State private var infoDetent = PresentationDetent.medium
    /// How many times someone has moved a model; the gesture hint stops after that.
    @AppStorage("viewer.interactions") private var interactions = 0
    @State private var showingHint = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var fileSize: Int64?
    @State private var isAccessing = false
    @State private var isSaved = false
    @State private var saveError: String?

    var body: some View {
        ZStack {
            ViewerBackground()
            switch phase {
            case .loading:
                ProgressView("Opening \(displayName)…")
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            case .failed(let error):
                ContentUnavailableView {
                    Label(error.title, systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.message)
                } actions: {
                    Button("Try Again") { Task { await load(retrying: true) } }
                        .buttonStyle(.glassProminent)
                    if error.kind == .missing || error.kind == .noAccess, recents.contains(fileAt: file.url) {
                        Button("Remove from Recents") {
                            recents.remove(fileAt: file.url)
                            dismiss()
                        }
                    }
                }
            case .loaded(let model):
                ModelCanvas(model: model, appearance: staged(appearance, for: model), controller: controller, bottomObscured: obscuredBySheet) {
                    noteInteraction()
                }
                    .ignoresSafeArea()
                    .accessibilityLabel("\(displayName), \(Format.spokenDimensions(visibleBounds(model).size, units: settings.units))\(fitNote(for: model).map { ". \($0.text)" } ?? "")")
                    .accessibilityHint("Drag to turn, pinch to zoom, double tap to fit.")
            }
        }
        .overlay(alignment: .top) {
            if case .loaded(let model) = phase {
                ViewerChips(
                    model: model,
                    plateID: $appearance.plateID,
                    dimensions: Format.dimensions(visibleBounds(model).size, units: settings.units),
                    spokenDimensions: Format.spokenDimensions(visibleBounds(model).size, units: settings.units),
                    fitNote: fitNote(for: model)
                )
                    .padding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if showingHint {
                GestureHint()
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        // Small confirmations for changes that happen out of the finger's sight.
        .sensoryFeedback(.selection, trigger: appearance.plateID)
        .sensoryFeedback(.selection, trigger: appearance.wireframe)
        .sensoryFeedback(.selection, trigger: appearance.showsGrid)
        .sensoryFeedback(.selection, trigger: settings.bedID)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbar }
        .sheet(isPresented: $showingInfo) {
            if case .loaded(let model) = phase {
                ModelInfoSheet(model: model, file: file, fileSize: fileSize, units: settings.units, appearance: $appearance, detent: $infoDetent)
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
        // It stays as a tick once saved, so the bar doesn't jump. Neither shows for a
        // file that didn't open.
        if file.isExternal, isLoaded {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaved ? "Saved to Library" : "Save to Library", systemImage: isSaved ? "checkmark" : "plus") {
                    saveToLibrary()
                }
                .contentTransition(.symbolEffect(.replace))
                .disabled(isSaved)
            }
        }
        if isLoaded {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: file.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }

        if case .loaded = phase {
            ToolbarItem(placement: .bottomBar) {
                Button("Fit to Screen", systemImage: "arrow.down.left.and.arrow.up.right.rectangle") {
                    controller.frameModel()
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    ForEach(OrbitCamera.Preset.allCases) { preset in
                        Button(preset.title, systemImage: symbol(for: preset)) { controller.show(preset) }
                    }
                } label: {
                    Label("Preset Views", systemImage: "rotate.3d")
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Toggle(isOn: $appearance.wireframe) {
                    Label("Wireframe", systemImage: "cube.transparent")
                }
            }
            ToolbarItem(placement: .bottomBar) {
                buildPlateMenu
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

    private var displayName: String { Format.title(fromFileName: file.name) }

    /// The grid and printer bed, together in one menu: try another printer without
    /// leaving the model. A chosen bed is remembered, like in Settings.
    private var buildPlateMenu: some View {
        Menu {
            Toggle("Show Grid", isOn: $appearance.showsGrid)
            Picker("Printer Bed", selection: Binding(
                get: { settings.bedID },
                set: { id in
                    settings.bedID = id
                    if id != nil { appearance.showsGrid = true }
                }
            )) {
                Text("No Printer Bed").tag(String?.none)
                ForEach(PrinterBed.byMake, id: \.make) { group in
                    Section(group.make) {
                        ForEach(group.beds) { bed in
                            Text(bed.name).tag(Optional(bed.id))
                        }
                    }
                }
                if settings.customBedWidth > 0 {
                    Text("Custom (\(Format.dimension(settings.customBedWidth, units: settings.units)) × \(Format.dimension(settings.customBedDepth, units: settings.units)))").tag(Optional(PrinterBed.customID))
                }
            }
        } label: {
            Label("Build Plate", systemImage: appearance.showsGrid ? "grid" : "square.dashed")
        }
    }

    /// The appearance with the chosen bed placed under what's showing.
    private func staged(_ appearance: RenderAppearance, for model: Model3D) -> RenderAppearance {
        var staged = appearance
        if let bed = settings.bed {
            staged.bed = model.bedFit(width: bed.width, depth: bed.depth, height: bed.height, plateID: appearance.plateID, hidden: appearance.hiddenObjects)
        }
        return staged
    }

    /// What the chosen bed makes of the model, naming the side that's over:
    /// "Fits the Bambu Lab A1", "Fits the Prusa MK4S turned 90°",
    /// "Too tall for the Bambu Lab A1 by 12.0 mm", or for a slicer project laid out
    /// partly off its plate, "Fits the Bambu Lab A1, but runs off the plate as arranged".
    private func fitNote(for model: Model3D) -> (text: String, tooBig: Bool)? {
        guard let bed = settings.bed,
              let fit = model.bedFit(width: bed.width, depth: bed.depth, height: bed.height, plateID: appearance.plateID, hidden: appearance.hiddenObjects) else { return nil }
        let name = bed.id == PrinterBed.customID ? "your custom bed" : "the \(bed.title)"
        let units = settings.units
        switch fit.verdict {
        case .fits:
            return ("Fits \(name)", false)
        case .fitsTurned:
            return ("Fits \(name) turned 90°", false)
        case .offPlate:
            return ("Fits \(name), but runs off the plate as arranged", true)
        case .tooBig(let over):
            var sides: [(String, Float)] = []
            if over.width > 0.05 { sides.append(("wide", over.width)) }
            if over.depth > 0.05 { sides.append(("deep", over.depth)) }
            if over.height > 0.05 { sides.append(("tall", over.height)) }
            if sides.count == 1, let side = sides.first {
                return ("Too \(side.0) for \(name) by \(Format.dimension(side.1, units: units))", true)
            }
            let detail = sides.map { "\(Format.dimension($0.1, units: units)) too \($0.0)" }.joined(separator: ", ")
            return ("Too big for \(name): \(detail)", true)
        }
    }

    /// On iPhone the info sheet's medium detent covers the lower half; keep the model
    /// in view above it so hiding an object shows what changed.
    private var obscuredBySheet: CGFloat {
        showingInfo && infoDetent == .medium && sizeClass == .compact ? 0.5 : 0
    }

    /// The first few times a model opens, show how to move it, until it's been moved.
    private func offerGestureHint() {
        guard interactions < 2, !UIAccessibility.isVoiceOverRunning else { return }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(.easeOut(duration: 0.3)) { showingHint = true }
            try? await Task.sleep(for: .seconds(6))
            withAnimation(.easeIn(duration: 0.3)) { showingHint = false }
        }
    }

    private func noteInteraction() {
        if showingHint {
            withAnimation(.easeIn(duration: 0.25)) { showingHint = false }
        }
        if interactions < 2 { interactions += 1 }
    }

    private var isLoaded: Bool {
        if case .loaded = phase { return true }
        return false
    }

    private func load(retrying: Bool = false) async {
        if retrying {
            phase = .loading
        } else {
            guard case .loading = phase else { return }
        }
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
            offerGestureHint()
            #if DEBUG
            if ProcessInfo.processInfo.environment["FACETS_INFO"] == "1" { showingInfo = true }
            #endif
        } catch {
            phase = .failed(FriendlyError(opening: error))
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
            withAnimation(.snappy) { isSaved = true }
            toasts.show("Saved to Library as \(copy.deletingPathExtension().lastPathComponent)")
        } catch {
            saveError = FriendlyError(file: error).message
        }
    }

}

/// Size, and the plate picker for multi-plate projects, floating over the model.
private struct ViewerChips: View {
    let model: Model3D
    @Binding var plateID: Int?
    let dimensions: String
    let spokenDimensions: String
    let fitNote: (text: String, tooBig: Bool)?

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
                VStack(spacing: 2) {
                    Text(dimensions)
                        .font(.footnote.weight(.medium).monospacedDigit())
                    if let fitNote {
                        Label(fitNote.text, systemImage: fitNote.tooBig ? "exclamationmark.triangle.fill" : "checkmark.circle")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(fitNote.tooBig ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: fitNote == nil ? AnyShape(.capsule) : AnyShape(.rect(cornerRadius: 16)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Size: \(spokenDimensions)\(fitNote.map { ". \($0.text)" } ?? "")")
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
        LinearGradient(colors: [Color(Palette.stage.top), Color(Palette.stage.floor)], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
    }
}

/// How to move a model, shown the first few times one opens.
private struct GestureHint: View {
    var body: some View {
        Label("Drag to turn · Pinch to zoom", systemImage: "hand.draw")
            .font(.subheadline.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

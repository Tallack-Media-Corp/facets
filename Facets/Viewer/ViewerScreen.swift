import MeshKit
import SwiftUI
import UniformTypeIdentifiers
import simd

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
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var phase = Phase.loading
    @State private var appearance = RenderAppearance()
    @State private var controller = ModelCanvasController()
    @State private var showingInfo = false
    @State private var infoDetent = PresentationDetent.medium
    /// Which gesture hint is next: 0 the basics, 1 the recovery gesture, 2 none.
    /// A stage is passed once the model has been moved while its hint was shown.
    @AppStorage("viewer.hintStage") private var hintStage = 0
    /// Earlier builds counted interactions; anyone past two has seen the basics.
    @AppStorage("viewer.interactions") private var legacyInteractions = 0
    @State private var showingHint = false
    @State private var shownHintStage: Int?
    @State private var findingFile = false
    @State private var choosingPrinter = false
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var fileSize: Int64?
    @State private var isAccessing = false
    @State private var isSaved = false
    @State private var saveError: String?
    /// The open tool, if any.
    @State private var tool: ViewerTool?
    @State private var measurePoints: [SIMD3<Float>] = []
    /// The model turned or laid flat by the user; nil while it's as the file has it.
    @State private var arranged: Model3D?
    /// Cross-section height as a fraction of the model's height.
    @State private var sectionFraction = 1.0

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
                    // Lead with the action that can work: a moved file needs finding,
                    // a flaky download needs another go.
                    switch error.kind {
                    case .missing, .noAccess:
                        Button("Find in Files…") { findingFile = true }
                            .buttonStyle(.glassProminent)
                        if recents.contains(fileAt: file.url) {
                            Button("Remove from Recents") {
                                recents.remove(fileAt: file.url)
                                dismiss()
                            }
                        }
                    case .notDownloaded, .noSpace, .other:
                        Button("Try Again") { Task { await load(retrying: true) } }
                            .buttonStyle(.glassProminent)
                    case .notAModel, .empty, .damaged, .noShapes:
                        EmptyView()
                    }
                }
            case .loaded(let base):
                let model = arranged ?? base
                ModelCanvas(
                    model: model,
                    appearance: staged(appearance, for: model),
                    controller: controller,
                    bottomObscured: obscuredBySheet,
                    tool: tool?.canvasTool ?? .none,
                    markers: tool == .measure ? measurePoints : [],
                    onSurfaceTap: { hit, point in surfaceTapped(hit, point, in: model) }
                ) {
                    noteInteraction()
                }
                    .ignoresSafeArea()
                    .accessibilityLabel("\(displayName), \(Format.spokenDimensions(visibleBounds(model).size, units: settings.units))\(fitNote(for: model).map { ". \($0.text)" } ?? "")")
                    .accessibilityHint("Swipe up or down to turn the model or change the view.")
            }
        }
        .overlay(alignment: .top) {
            if let model = shownModel {
                ViewerChips(
                    model: model,
                    plateID: $appearance.plateID,
                    dimensions: Format.dimensions(visibleBounds(model).size, units: settings.units),
                    spokenDimensions: Format.spokenDimensions(visibleBounds(model).size, units: settings.units),
                    fitNote: fitNote(for: model),
                    checksFit: settings.checksFit,
                    hasPrinter: settings.fitBed != nil,
                    choosePrinter: { choosingPrinter = true }
                )
                // Overlays on the model stop growing at the first accessibility
                // size; beyond that they'd cover what they describe.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .padding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if let tool, let model = shownModel {
                ToolPanel(
                    tool: tool,
                    units: settings.units,
                    points: measurePoints,
                    sectionFraction: $sectionFraction,
                    sectionHeight: sectionHeight(in: model) ?? visibleBounds(model).max.z,
                    isTurned: arranged != nil,
                    clearPoints: { measurePoints = [] },
                    turn: { axis in reorient(by: quarterTurn(about: axis)) },
                    resetOrientation: resetOrientation,
                    close: { closeTool() }
                )
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if showingHint {
                GestureHint(stage: shownHintStage ?? 0)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
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
            if let model = shownModel {
                ModelInfoSheet(model: model, file: file, fileSize: fileSize, units: settings.units, material: settings.material, appearance: $appearance, detent: $infoDetent)
            }
        }
        .background { keyboardShortcuts }
        .animation(.snappy(duration: 0.25), value: tool)
        .onChange(of: appearance.plateID) {
            // Another plate is another arrangement: start it as the file has it.
            arranged = nil
            measurePoints = []
        }
        .alert("Couldn't Save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
        // Relink a moved file: open the one picked, and point Recents at it instead.
        .fileImporter(isPresented: $findingFile, allowedContentTypes: UTType.models) { result in
            guard case .success(let url) = result else { return }
            recents.remove(fileAt: file.url)
            dismiss()
            router.presented = ModelFileRef(url: url, isExternal: !library.contains(url))
        }
        .sheet(isPresented: $choosingPrinter) {
            NavigationStack {
                PrinterBedPicker(fits: shownModel.map { model in { bed in fits(model, on: bed) } })
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", systemImage: "checkmark") { choosingPrinter = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: settings.bedID) { _, id in
            // Choosing a printer means wanting to see its bed.
            if id != nil { appearance.showsGrid = true }
            announceFit()
        }
        .onChange(of: appearance.plateID) { announceFit() }
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
                    Label("Preset Views", systemImage: "view.3d")
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                toolsMenu
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

    /// Measure, Lay Flat and Cross-Section. The button shows the open tool.
    private var toolsMenu: some View {
        Menu {
            ForEach(ViewerTool.allCases) { option in
                Button {
                    open(option)
                } label: {
                    Label(option.title, systemImage: option.symbol)
                    if option == tool { Text("Open") }
                }
            }
        } label: {
            Label(tool?.title ?? "Tools", systemImage: tool?.symbol ?? "wrench.and.screwdriver")
        }
        .tint(tool == nil ? nil : Color.accentColor)
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

    private var displayName: String { file.displayName }

    /// The grid and the printer, in the bottom bar where a thumb can reach them.
    /// Printers used lately are one tap away; the full list is behind "Other Printer…".
    /// How the model's drawn: wireframe, the grid, and (with fit checks on) the
    /// printer, with recent printers one tap away.
    private var buildPlateMenu: some View {
        Menu {
            Toggle(isOn: $appearance.wireframe) {
                Label("Wireframe", systemImage: "cube.transparent")
            }
            Toggle(isOn: $appearance.showsGrid) {
                Label("Build Plate Grid", systemImage: "grid")
            }
            if settings.checksFit {
                printerSection
            }
        } label: {
            Label("Display", systemImage: "square.grid.3x3.square")
        }
    }

    @ViewBuilder
    private var printerSection: some View {
        Section("Printer") {
            Picker("Printer", selection: Binding(get: { settings.bedID }, set: { settings.bedID = $0 })) {
                Text("None").tag(String?.none)
                ForEach(settings.recentBeds) { bed in
                    Text(bed.id == PrinterBed.customID ? "Custom Bed" : bed.title).tag(Optional(bed.id))
                }
            }
            .pickerStyle(.inline)
            Button("Other Printer…", systemImage: "printer") { choosingPrinter = true }
        }
    }

    /// The model as shown: turned or laid flat by the user, or as the file has it.
    private var shownModel: Model3D? {
        guard case .loaded(let base) = phase else { return nil }
        return arranged ?? base
    }

    /// The appearance with the chosen bed placed under what's showing, and the
    /// cross-section cut while that tool is open.
    private func staged(_ appearance: RenderAppearance, for model: Model3D) -> RenderAppearance {
        var staged = appearance
        if let bed = settings.fitBed {
            staged.bed = model.bedFit(width: bed.width, depth: bed.depth, height: bed.height, plateID: appearance.plateID, hidden: appearance.hiddenObjects)
        }
        if tool == .section {
            staged.sectionHeight = sectionHeight(in: model)
        }
        return staged
    }

    /// What the chosen bed makes of the model, naming the side that's over:
    /// "Fits the Bambu Lab A1 as oriented", "Fits the Prusa MK4S turned 90°",
    /// "Too tall for the Bambu Lab A1 by 12.0 mm", or for a slicer project laid out
    /// partly off its plate, "Fits the Bambu Lab A1, but runs off the plate as arranged".
    private func fitNote(for model: Model3D) -> (text: String, tooBig: Bool)? {
        guard let bed = settings.fitBed,
              let fit = model.bedFit(width: bed.width, depth: bed.depth, height: bed.height, plateID: appearance.plateID, hidden: appearance.hiddenObjects) else { return nil }
        let name = bed.id == PrinterBed.customID ? "your custom bed" : "the \(bed.title)"
        let units = settings.units
        switch fit.verdict {
        case .fits:
            return ("Fits \(name) as oriented", false)
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

    /// A plate or printer change rewrites the verdict where VoiceOver can't see it.
    private func announceFit() {
        guard UIAccessibility.isVoiceOverRunning, let model = shownModel,
              let note = fitNote(for: model) else { return }
        UIAccessibility.post(notification: .announcement, argument: note.text)
    }

    // MARK: Tools

    private func open(_ option: ViewerTool) {
        if tool == option {
            closeTool()
            return
        }
        tool = option
        measurePoints = []
        sectionFraction = option == .section ? 0.5 : sectionFraction
        noteInteraction()
    }

    private func closeTool() {
        tool = nil
        measurePoints = []
    }

    /// The cut's height in mm: a fraction of the way up what's showing. Nil at the
    /// very top, where nothing is cut.
    private func sectionHeight(in model: Model3D) -> Float? {
        guard sectionFraction < 0.999 else { return nil }
        let bounds = visibleBounds(model)
        return bounds.min.z + Float(sectionFraction) * bounds.size.z
    }

    private func surfaceTapped(_ hit: SurfaceHit, _ point: SIMD3<Float>, in model: Model3D) {
        switch tool {
        case .measure:
            // A third tap starts a new measurement.
            if measurePoints.count >= 2 { measurePoints = [] }
            measurePoints.append(point)
            if measurePoints.count == 2 {
                let distance = Format.dimension(simd_distance(measurePoints[0], measurePoints[1]), units: settings.units)
                UIAccessibility.post(notification: .announcement, argument: distance)
            }
        case .layFlat:
            reorient(by: layFlatRotation(for: hit.normal))
        default:
            break
        }
    }

    /// Turns what's showing, keeping each turn on top of the last.
    private func reorient(by rotation: simd_float3x3) {
        guard let model = shownModel else { return }
        arranged = model.reoriented(by: rotation, plateID: appearance.plateID, hidden: appearance.hiddenObjects)
        measurePoints = []
        announceFit()
    }

    private func resetOrientation() {
        arranged = nil
        measurePoints = []
        announceFit()
    }

    /// Whether the model as shown fits a bed, for marking the printer list.
    private func fits(_ model: Model3D, on bed: PrinterBed) -> Bool? {
        model.bedFit(width: bed.width, depth: bed.depth, height: bed.height, plateID: appearance.plateID, hidden: appearance.hiddenObjects)?.fits
    }

    /// Keyboard commands for iPad (and anything with a keyboard), listed in the
    /// Command-key overlay. Invisible buttons carry them.
    private var keyboardShortcuts: some View {
        Group {
            if isLoaded {
                Button("Fit to Screen") { controller.frameModel() }
                    .keyboardShortcut("0", modifiers: .command)
                ForEach(Array(OrbitCamera.Preset.allCases.enumerated()), id: \.element) { index, preset in
                    Button("\(preset.title) View") { controller.show(preset) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Button("Info") { showingInfo = true }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Build Plate Grid") { appearance.showsGrid.toggle() }
                    .keyboardShortcut("g", modifiers: .command)
                Button("Wireframe") { appearance.wireframe.toggle() }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                Button("Measure") { open(.measure) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Lay Flat") { open(.layFlat) }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Cross-Section") { open(.section) }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
            }
            if tool != nil {
                Button("Close Tool") { closeTool() }
                    .keyboardShortcut(.escape, modifiers: [])
            } else if showsCloseButton {
                Button("Close") { dismiss() }
                    .keyboardShortcut("w", modifiers: .command)
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// On iPhone the info sheet's medium detent covers the lower half; keep the model
    /// in view above it so hiding an object shows what changed.
    private var obscuredBySheet: CGFloat {
        showingInfo && infoDetent == .medium && sizeClass == .compact ? 0.5 : 0
    }

    /// Teach the gestures in two short beats across the first models opened: drag and
    /// pinch, then double-tap to fit (the way back when the model's lost off-screen).
    private func offerGestureHint() {
        if hintStage == 0, legacyInteractions >= 2 { hintStage = 1 }
        guard hintStage < 2, !UIAccessibility.isVoiceOverRunning else { return }
        shownHintStage = hintStage
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
        // One stage per model opened: the next hint waits for the next model.
        if let shown = shownHintStage {
            hintStage = max(hintStage, shown + 1)
            shownHintStage = nil
        }
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
            toasts.show("Saved to Library as \(Format.title(fromFileName: copy.deletingPathExtension().lastPathComponent))")
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
    /// No printer chosen yet: offer one, quietly, for the first few models.
    /// Off: the readout is just the dimensions.
    let checksFit: Bool
    /// Without a printer the readout says so, and tapping it picks one.
    let hasPrinter: Bool
    let choosePrinter: () -> Void

    /// iPad's canvas is much larger; the chips step up two sizes to match.
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var wide: Bool { sizeClass == .regular }

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
                        .font((wide ? Font.title3 : .subheadline).weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityLabel("Plate: \(plateTitle)")
                }
                // The readout is also the printer control: it says which printer the
                // model's measured against (or that none is chosen), and tapping it
                // picks another.
                if checksFit {
                    Button(action: choosePrinter) { readout }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(readoutLabel)
                        .accessibilityHint(hasPrinter ? "Changes the printer" : "Chooses a printer to check the model fits")
                        .accessibilityAddTraits(.isButton)
                } else {
                    readout
                        .glassEffect(.regular, in: .capsule)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(readoutLabel)
                }
            }
        }
    }

    private var readout: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(dimensions)
                    .font((wide ? Font.body : .footnote).weight(.medium).monospacedDigit())
                    .foregroundStyle(Color.primary)
                if let fitNote {
                    // Orange text on glass is too faint to read; the symbol carries the
                    // warning (with the dashed outline) and the words stay in ink.
                    Label {
                        Text(fitNote.text)
                            .foregroundStyle(fitNote.tooBig ? Color.primary : Color.secondary)
                    } icon: {
                        Image(systemName: fitNote.tooBig ? "exclamationmark.triangle.fill" : "checkmark.circle")
                            .foregroundStyle(fitNote.tooBig ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
                    }
                    .font((wide ? Font.subheadline : .caption).weight(.medium).monospacedDigit())
                    .multilineTextAlignment(.center)
                } else if checksFit, !hasPrinter {
                    Label("No printer selected", systemImage: "printer")
                        .font((wide ? Font.subheadline : .caption).weight(.medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            if checksFit {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    private var readoutLabel: String {
        "Size: \(spokenDimensions)\(fitNote.map { ". \($0.text)" } ?? (hasPrinter || !checksFit ? "" : ". No printer selected"))"
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
    let stage: Int

    var body: some View {
        Label(stage == 0 ? "Drag to turn · Pinch to zoom" : "Double-tap to fit the model", systemImage: stage == 0 ? "hand.draw" : "hand.tap")
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

import MeshKit
import SwiftUI
import TipKit
import UniformTypeIdentifiers
import simd

/// The full-screen 3D view of one file.
struct ViewerScreen: View {
    let file: ModelFileRef
    /// Shows a Close button: the viewer is presented full screen over the app. The
    /// Mac's model windows have their own close button instead.
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
    /// The model as the file has it, before any change of unit.
    @State private var original: Model3D?
    /// The scale applied for a file saved in metres or inches (1: as saved).
    @State private var unitScale: Float = 1
    /// Units to offer when the model looks too small to be in millimetres.
    @State private var unitSuggestions: [UnitGuess] = []
    /// Cross-section height as a fraction of the model's height.
    @State private var sectionFraction = 1.0
    /// Bumped per turn, so a slow turn finishing late doesn't undo a newer one.
    @State private var turnGeneration = 0
    /// The turn being worked out; the next one builds on its result, so quick taps
    /// add up instead of the last one replacing the others.
    @State private var pendingTurn: Task<Model3D, Never>?
    /// A unit change being applied; turns wait for it rather than turn the old size.
    @State private var rescaling = false
    /// The new-user tour of the viewer, one control at a time, in toolbar order.
    @State private var viewerTips = TipGroup(.ordered) {
        SizeTip()
        FitTip()
        PresetViewsTip()
        ToolsTip()
        DisplayTip()
        InfoTip()
    }
    /// Tips wait for the gesture hint (the first opens) so the two never overlap.
    @State private var tipsReady = false
    /// Counts Fit presses that found the model already framed, for a light tap (the
    /// canvas gives a small zoom pulse; with Reduce Motion the tap is all there is).
    @State private var alreadyFitTaps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The tool panel's height and the screen's, for keeping the model above it.
    @State private var panelHeight: CGFloat = 0
    @State private var viewHeight: CGFloat = 1
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        // Two halves, so the compiler can type-check each; both are this view's own
        // methods, run in its body, so their state is live.
        lifecycle(viewerStage)
    }

    /// The model, its chips and panels, and the toolbar.
    private var viewerStage: some View {
        ZStack {
            ViewerBackground(pureBlack: settings.pureBlack)
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
                        // Nothing to retry; the way on is another file.
                        Button("Open Another File…") { findingFile = true }
                            .buttonStyle(.glass)
                    }
                }
            case .loaded(let base):
                let model = arranged ?? base
                ModelCanvas(
                    model: model,
                    appearance: staged(appearance, for: model),
                    controller: controller,
                    bottomObscured: obscured,
                    tool: tool?.canvasTool ?? .none,
                    markers: tool == .measure ? measurePoints : [],
                    onSurfaceTap: { hit, point in surfaceTapped(hit, point, in: model) }
                ) {
                    noteInteraction()
                }
                    // Under the bars, but beside an open inspector rather than behind it.
                    .ignoresSafeArea(edges: showingInfo && infoAsInspector ? .vertical : .all)
                    .accessibilityLabel("\(displayName), \(Format.spokenDimensions(visibleBounds(model).size, units: settings.units))\(unitSuggestions.isEmpty ? fitNote(for: model).map { ". \($0.text)" } ?? "" : "")")
                    .accessibilityHint("Swipe up or down to turn the model or change the view.")
            }
        }
        .overlay(alignment: .top) { topOverlay }
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: unitSuggestions)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewHeight = max($0, 1) }
        .overlay(alignment: dockedPanel ? .bottomTrailing : .bottom) { bottomOverlay }
        // Small confirmations for changes that happen out of the finger's sight.
        .sensoryFeedback(.selection, trigger: appearance.plateID)
        .sensoryFeedback(.selection, trigger: appearance.wireframe)
        .sensoryFeedback(.selection, trigger: appearance.showsGrid)
        .sensoryFeedback(.selection, trigger: settings.bedID)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: alreadyFitTaps)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar()
        .toolbar { toolbar }
    }

    /// Sheets, alerts and the reactions to changes, kept apart from the stage so the
    /// compiler can type-check each half.
    private func lifecycle(_ content: some View) -> some View {
        reactions(presentations(content))
    }

    /// Loading, and keeping the stage in step with settings and the plate.
    private func reactions(_ content: some View) -> some View {
        content
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

    /// The info sheet or inspector, alerts, pickers, and state that follows them.
    private func presentations(_ content: some View) -> some View {
        content
        // A sheet on iPhone, where the model glides up above it; an inspector beside
        // the model on iPad and Mac, so hiding an object shows what changed.
        .modifier(InfoPresentation(asInspector: infoAsInspector, isPresented: $showingInfo) { infoSheet(showsDone: $0) })
        .onChange(of: showingInfo) {
            // The canvas narrows or widens with the inspector; reframe once it has.
            guard infoAsInspector else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                controller.frameModel()
            }
        }
        .background { escapeKey }
        .focusedSceneValue(\.viewerActions, isLoaded ? viewerActions : nil)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: tool)
        .onChange(of: appearance.plateID) {
            // Another plate is another arrangement: start it as the file has it.
            arranged = nil
            turnGeneration += 1
            pendingTurn = nil
            measurePoints = []
        }
        // Points on an object that's been hidden would float over nothing.
        .onChange(of: appearance.hiddenObjects) { measurePoints = [] }
        .onChange(of: tool) { panelHeight = 0 }
        .onChange(of: unitSuggestions) { panelHeight = 0 }
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
                PrinterBedPicker(verdict: shownModel.map { model in { bed in verdict(model, on: bed) } }, onPick: { choosingPrinter = false })
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
                Button(isSaved ? "Saved to Library" : "Save to Library", systemImage: isSaved ? "checkmark" : "tray.and.arrow.down") {
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
            ToolbarItem(placement: .bottomControls) {
                Button("Fit to Screen", systemImage: "viewfinder") {
                    if !controller.frameModel() { alreadyFitTaps += 1 }
                    FitTip().invalidate(reason: .actionPerformed)
                }
            }
            ToolbarItem(placement: .bottomControls) {
                Menu {
                    ForEach(OrbitCamera.Preset.allCases) { preset in
                        Button(preset.title, systemImage: symbol(for: preset)) { controller.show(preset) }
                    }
                } label: {
                    Label("Preset Views", systemImage: "move.3d")
                }
                .toolbarMenuIndicator()
            }
            ToolbarSpacer(.flexible, placement: .bottomControls)
            ToolbarItem(placement: .bottomControls) {
                toolsMenu
            }
            ToolbarItem(placement: .bottomControls) {
                buildPlateMenu
            }
            ToolbarSpacer(.flexible, placement: .bottomControls)
            ToolbarItem(placement: .bottomControls) {
                // Toggles, so it also closes the inspector on iPad and Mac.
                Button("Info", systemImage: "info.circle") {
                    showingInfo.toggle()
                    InfoTip().invalidate(reason: .actionPerformed)
                }
            }
        }
    }

    /// Measure, Lay Flat and Cross-Section. The button shows the open tool.
    /// Panels rise from the bottom; with Reduce Motion they fade.
    private var panelTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var toolsMenu: some View {
        Menu {
            ForEach(ViewerTool.allCases) { option in
                Toggle(isOn: Binding(get: { tool == option }, set: { _ in open(option) })) {
                    Label(option.title, systemImage: option.symbol)
                }
            }
        } label: {
            Label(tool?.title ?? "Tools", systemImage: tool?.symbol ?? "wrench.and.screwdriver")
        }
        .tint(tool == nil ? nil : Color.accentColor)
        // The unit card takes the panel's place; settle the size before measuring.
        .disabled(!unitSuggestions.isEmpty)
        .toolbarMenuIndicator()
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
            // Always the view-options glyph: the menu holds wireframe and the grid as
            // well as the printer, and the chosen printer is named on the size chip.
            Label("Display", systemImage: "slider.horizontal.3")
        }
        .toolbarMenuIndicator()
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
            Button { choosingPrinter = true } label: {
                Label("Other Printer…", image: "printer3d")
            }
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
        // While the file's unit is in question, a bed under it would be a verdict
        // on a size that's probably wrong.
        if let bed = settings.fitBed, unitSuggestions.isEmpty {
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
        // While the units are in question, the fit isn't worth saying.
        guard Spoken.isVoiceOverRunning, unitSuggestions.isEmpty, let model = shownModel,
              let note = fitNote(for: model) else { return }
        Spoken.announce(note.text)
    }

    /// The size readout and plate picker over the top of the model.
    @ViewBuilder
    private var topOverlay: some View {
        if let model = shownModel {
            let size = visibleBounds(model).size
            ViewerChips(
                model: model,
                plateID: $appearance.plateID,
                dimensions: Format.dimensions(size, units: settings.units),
                spokenDimensions: Format.spokenDimensions(size, units: settings.units),
                fitNote: fitNote(for: model),
                checksFit: settings.checksFit,
                hasPrinter: settings.fitBed != nil,
                unsureOfUnits: !unitSuggestions.isEmpty,
                sizeTip: tip(SizeTip.self),
                choosePrinter: {
                    choosingPrinter = true
                    SizeTip().invalidate(reason: .actionPerformed)
                }
            )
            // Overlays on the model stop growing at the first accessibility
            // size; beyond that they'd cover what they describe.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.top, 8)
        }
    }

    /// Above the bottom toolbar: the unit question, the open tool's panel, or the
    /// gesture hint, in that order.
    @ViewBuilder
    private var bottomOverlay: some View {
        if !unitSuggestions.isEmpty, let model = shownModel {
            // Down where a thumb can answer it; the model reframes above it, as
            // it does for a tool panel.
            UnitSuggestionCard(
                size: model.bounds.size,
                suggestions: unitSuggestions,
                units: settings.units,
                choose: { applyUnit($0) },
                keep: { keepUnit() }
            )
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .frame(maxWidth: dockedPanel ? 360 : nil)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
            .transition(panelTransition)
        } else if let tool, let model = shownModel {
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
            .frame(maxWidth: dockedPanel ? 340 : nil)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
            .transition(panelTransition)
        } else if let card = toolbarTip {
            FloatingTip(tip: card)
                .padding(.bottom, 12)
        } else if showingHint {
            GestureHint(stage: shownHintStage ?? 0)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .padding(.bottom, 12)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    @ViewBuilder
    private func infoSheet(showsDone: Bool) -> some View {
        if let model = shownModel {
            ModelInfoSheet(
                model: model, file: file, fileSize: fileSize, units: settings.units, material: settings.material,
                printer: settings.bed, unsureOfUnits: !unitSuggestions.isEmpty,
                fitsPrinter: settings.fitBed.flatMap { verdict(model, on: $0) }.map { $0 == .fits || $0 == .fitsTurned },
                unitScale: unitScale, originalSize: original?.bounds.size ?? model.bounds.size, setUnitScale: setUnit,
                close: { showingInfo = false },
                showsDone: showsDone,
                appearance: $appearance, detent: $infoDetent
            )
        }
    }

    private var infoAsInspector: Bool {
        #if os(macOS)
        true
        #else
        sizeClass == .regular
        #endif
    }

    // MARK: Units

    private var unitKey: String { UnitChoices.key(for: file, size: fileSize) }

    /// STL and OBJ don't say their unit. A model under 2 mm across was almost
    /// certainly saved in metres or inches: apply what the user chose before, or ask.
    private func checkUnits(of model: Model3D) {
        guard [.stl, .asciiSTL, .obj].contains(model.format) else { return }
        if let factor = UnitChoices.factor(for: unitKey) {
            if factor != 1 { rescale(to: factor) }
            return
        }
        unitSuggestions = UnitGuess.suggestions(for: model.bounds.size)
        if let first = unitSuggestions.first {
            Spoken.announce("This model is very small. It may be in \(first.title.lowercased()). Options are below the size.")
        }
    }

    private func applyUnit(_ unit: UnitGuess) {
        UnitChoices.set(unit.factor, for: unitKey)
        unitSuggestions = []
        rescale(to: unit.factor)
    }

    private func keepUnit() {
        UnitChoices.set(1, for: unitKey)
        unitSuggestions = []
    }

    /// From the Info sheet: any unit, always applied to the file as saved.
    private func setUnit(_ factor: Float) {
        UnitChoices.set(factor, for: unitKey)
        unitSuggestions = []
        rescale(to: factor)
    }

    /// Scaling a big mesh takes a moment, so it happens off the main thread; a turn
    /// still in flight is dropped, since it was of the old size.
    private func rescale(to factor: Float) {
        guard let original else { return }
        unitScale = factor
        turnGeneration += 1
        pendingTurn = nil
        let generation = turnGeneration
        arranged = nil
        measurePoints = []
        guard factor != 1 else {
            phase = .loaded(original)
            return
        }
        rescaling = true
        Task {
            let scaled = await Task.detached(priority: .userInitiated) { original.scaled(by: factor) }.value
            guard generation == turnGeneration, unitScale == factor else { return }
            phase = .loaded(scaled)
            rescaling = false
        }
    }

    // MARK: Tools

    private func open(_ option: ViewerTool) {
        ToolsTip().invalidate(reason: .actionPerformed)
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
                Spoken.announce(distance)
            }
        case .layFlat:
            reorient(by: layFlatRotation(for: hit.normal))
        default:
            break
        }
    }

    /// Turns what's showing, keeping each turn on top of the last. The new
    /// arrangement is worked out off the main thread: every vertex moves.
    private func reorient(by rotation: simd_float3x3) {
        guard !rescaling, let model = shownModel else { return }
        turnGeneration += 1
        let generation = turnGeneration
        let plateID = appearance.plateID, hidden = appearance.hiddenObjects
        let previous = pendingTurn
        let turn = Task { () -> Model3D in
            // On top of a turn still being worked out, not the arrangement before it.
            let base = await previous?.value ?? model
            return await Task.detached(priority: .userInitiated) {
                base.reoriented(by: rotation, plateID: plateID, hidden: hidden)
            }.value
        }
        pendingTurn = turn
        Task {
            let turned = await turn.value
            guard generation == turnGeneration else { return }
            pendingTurn = nil
            arranged = turned
            measurePoints = []
            announceArrangement(turned)
        }
    }

    private func resetOrientation() {
        turnGeneration += 1
        pendingTurn = nil
        arranged = nil
        measurePoints = []
        if let model = shownModel { announceArrangement(model) }
    }

    /// After a turn: the new size, and the fit when there's a printer.
    private func announceArrangement(_ model: Model3D) {
        guard Spoken.isVoiceOverRunning else { return }
        var text = "Now \(Format.spokenDimensions(visibleBounds(model).size, units: settings.units))"
        if let note = fitNote(for: model) { text += ". \(note.text)" }
        Spoken.announce(text)
    }

    /// What the model as shown makes of a bed, for marking the printer list.
    private func verdict(_ model: Model3D, on bed: PrinterBed) -> BedFit.Verdict? {
        model.bedFit(width: bed.width, depth: bed.depth, height: bed.height, plateID: appearance.plateID, hidden: appearance.hiddenObjects)?.verdict
    }

    /// The panel sits at the side, not the bottom, when height is short (iPhone in
    /// landscape), so it doesn't cover the model.
    private var dockedPanel: Bool { verticalSizeClass == .compact }

    /// How much of the canvas is covered from the bottom: the Info sheet on iPhone,
    /// or the tool panel. The model reframes into what's left.
    private var obscured: CGFloat {
        let bottomCard = tool != nil || !unitSuggestions.isEmpty
        let panel = bottomCard && !dockedPanel ? min((panelHeight + 8) / viewHeight, 0.45) : 0
        return max(obscuredBySheet, panel)
    }

    private var viewerActions: ViewerActions {
        ViewerActions(
            fit: { controller.frameModel() },
            show: { controller.show($0) },
            info: { showingInfo = true },
            toggleGrid: { appearance.showsGrid.toggle() },
            toggleWireframe: { appearance.wireframe.toggle() },
            toggleTool: { open($0) },
            openTool: tool,
            showsGrid: appearance.showsGrid,
            wireframe: appearance.wireframe
        )
    }

    /// Escape closes the open tool, or a viewer opened from another app. The rest of
    /// the keyboard commands are in the menu bar's Model menu (ViewerCommands).
    private var escapeKey: some View {
        Button(tool != nil ? "Close Tool" : "Close") {
            if tool != nil { closeTool() } else if showsCloseButton { dismiss() }
        }
        .keyboardShortcut(.escape, modifiers: [])
        .disabled(tool == nil && !showsCloseButton)
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
        // The size tip is about choosing a printer; with fit checks off there's none.
        if !settings.checksFit { SizeTip().invalidate(reason: .tipClosed) }
        if hintStage == 0, legacyInteractions >= 2 { hintStage = 1 }
        guard hintStage < 2, !Spoken.isVoiceOverRunning else {
            tipsReady = true
            return
        }
        shownHintStage = hintStage
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { showingHint = true }
            try? await Task.sleep(for: .seconds(6))
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.3)) { showingHint = false }
            tipsReady = true
        }
    }

    /// The tour's current tip when it's about a bar control (the size tip is a
    /// popover on its chip instead).
    private var toolbarTip: (any Tip)? {
        guard tipsReady, unitSuggestions.isEmpty, tool == nil, !(viewerTips.currentTip is SizeTip) else { return nil }
        return viewerTips.currentTip
    }

    /// The tour's tip for one control, when it's that tip's turn and nothing else
    /// is in the way (the gesture hint, the unit card, an open tool).
    private func tip<T: Tip>(_ type: T.Type) -> (any Tip)? {
        guard tipsReady, TipsState.shared.isOn, unitSuggestions.isEmpty, tool == nil else { return nil }
        return viewerTips.currentTip as? T
    }

    private func noteInteraction() {
        if showingHint {
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.25)) { showingHint = false }
            tipsReady = true
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
            original = model
            phase = .loaded(model)
            checkUnits(of: model)
            storeThumbnail(of: model)
            offerGestureHint()
            #if DEBUG
            if ProcessInfo.processInfo.environment["FACETS_INFO"] == "1" { showingInfo = true }
            #endif
        } catch {
            phase = .failed(FriendlyError(opening: error))
        }
    }

    /// The model is in memory now: draw its library thumbnail from it, so a file too
    /// big to fetch just for a picture gets one (and other devices share it).
    private func storeThumbnail(of model: Model3D) {
        let url = file.url
        guard !SampleModels.isSample(url) else { return }
        // Drawing it uploads the mesh a second time; only with memory to spare (this
        // runs after the viewer's own upload, so it counts that one already).
        guard let context = RenderContext.shared, context.canDisplay(model) else { return }
        let look = ThumbnailStore.Look(colorHex: settings.colorHex, usesFileColors: settings.usesFileColors)
        let size = fileSize
        Task.detached(priority: .background) {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            await ThumbnailStore.shared.store(model, for: url, size: size, modified: modified, look: look)
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
        let model = try result.get()
        if let context = RenderContext.shared, !context.canDisplay(model) { throw ModelError.tooLarge }
        return model
    }

    private func saveToLibrary() {
        Task {
            do {
                let copies = try await library.importFiles([file.url], into: library.root)
                guard let copy = copies.first else { return }
                withAnimation(.snappy) { isSaved = true }
                toasts.show("Saved to Library as \(Format.title(fromFileName: copy.deletingPathExtension().lastPathComponent))")
            } catch {
                saveError = FriendlyError(file: error).message
            }
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
    /// No printer chosen: the readout says so and opens the printer list.
    /// Off: the readout is just the dimensions.
    let checksFit: Bool
    /// Without a printer the readout says so, and tapping it picks one.
    let hasPrinter: Bool
    /// The file's unit is in question (the unit card is up): no verdict yet.
    let unsureOfUnits: Bool
    /// The tour's tip for the readout, while it's that tip's turn.
    let sizeTip: (any Tip)?
    let choosePrinter: () -> Void
    /// The printer glyph is an image, not a symbol, so it's sized with the text by hand.
    @ScaledMetric(relativeTo: .caption) private var glyph: CGFloat = 14

    /// iPad's canvas is much larger; the chips step up a size or two to match.
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
                        // The plates straight in the menu, not a "Plate" submenu (the Mac's default).
                        .pickerStyle(.inline)
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
                        .popoverTip(sizeTip)
                        .tipViewStyle(FacetsTipStyle())
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
                if unsureOfUnits {
                    Label("Check the file's units", systemImage: "ruler")
                        .font((wide ? Font.subheadline : .caption).weight(.medium))
                        .foregroundStyle(Color.secondary)
                } else if let fitNote {
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
                    Label {
                        Text("No printer selected")
                    } icon: {
                        Image("printer3d")
                            .resizable()
                            .scaledToFit()
                            .frame(width: glyph * (wide ? 1.2 : 1), height: glyph * (wide ? 1.2 : 1))
                    }
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
        if unsureOfUnits { return "Size: \(spokenDimensions). Check the file's units" }
        return "Size: \(spokenDimensions)\(fitNote.map { ". \($0.text)" } ?? (hasPrinter || !checksFit ? "" : ". No printer selected"))"
    }

    private var plateTitle: String {
        model.plates.first { $0.id == plateID }?.title ?? "All Plates"
    }
}

/// A soft studio backdrop behind the transparent 3D view.
struct ViewerBackground: View {
    var pureBlack = false

    var body: some View {
        let stage = Palette.stage(pureBlack: pureBlack)
        LinearGradient(colors: [Color(stage.top), Color(stage.floor)], startPoint: .top, endPoint: .bottom)
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

/// Info as a sheet on iPhone; as an inspector beside the model on iPad and Mac. Both
/// are always attached, so the canvas keeps its identity when an iPad window changes
/// size class; each only ever sees `isPresented` when it's the one in use. The
/// inspector's copy never has a Done button, so nothing leaks into the viewer's bar.
private struct InfoPresentation<Info: View>: ViewModifier {
    let asInspector: Bool
    @Binding var isPresented: Bool
    @ViewBuilder let info: (_ showsDone: Bool) -> Info

    func body(content: Content) -> some View {
        content
            .inspector(isPresented: gated(asInspector)) {
                info(false).inspectorColumnWidth(min: 320, ideal: 360, max: 440)
            }
            .sheet(isPresented: gated(!asInspector)) { info(true) }
    }

    private func gated(_ active: Bool) -> Binding<Bool> {
        Binding(get: { active && isPresented }, set: { if active { isPresented = $0 } })
    }
}

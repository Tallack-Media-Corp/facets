import SwiftUI
import TipKit

/// A short tour of each screen for new users, with TipKit: one tip at a time, each
/// pointing at its control, each shown once. Every tip has "Turn Off Tips", for
/// anyone who'd rather find their own way; Settings turns them back on or shows
/// them all again.
enum FacetsTips {
    /// All tips, on or off.
    @Parameter static var enabled: Bool = true

    private static let enabledKey = "tips.enabled"
    private static let generationKey = "tips.generation"

    /// Bumped by "Show All Tips Again": every tip's id carries it, so TipKit sees
    /// fresh tips that haven't been dismissed.
    static var generation: Int { UserDefaults.standard.integer(forKey: generationKey) }

    static var isOn: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    static func configure() {
        enabled = isOn
        #if DEBUG
        // Screenshots and quick checks: FACETS_TIPS=0 keeps the tour out of the way
        // for this launch only (the setting itself is left alone).
        if ProcessInfo.processInfo.environment["FACETS_TIPS"] == "0" {
            enabled = false
            Task { @MainActor in TipsState.shared.isOn = false }
        }
        #endif
        try? Tips.configure([.displayFrequency(.immediate)])
        #if DEBUG
        // FACETS_TIPS_DONE=size,fit marks those tips seen, to step through the tour.
        let done = Set((ProcessInfo.processInfo.environment["FACETS_TIPS_DONE"] ?? "").split(separator: ",").map(String.init))
        let all: [any FacetsTip] = [AddModelsTip(), BrowseTip(), ViewOptionsTip(), SizeTip(), FitTip(), PresetViewsTip(), ToolsTip(), DisplayTip(), InfoTip()]
        for tip in all where done.contains(tip.name) { tip.invalidate(reason: .tipClosed) }
        #endif
    }

    static func setOn(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: enabledKey)
        enabled = on
        Task { @MainActor in TipsState.shared.isOn = on }
    }

    static func showAllAgain() {
        UserDefaults.standard.set(generation + 1, forKey: generationKey)
        setOn(true)
    }

    static let turnOffID = "turn-off"

    /// What a tip's "Turn Off Tips" button does.
    static func handle(_ action: Tips.Action) {
        if action.id == turnOffID { setOn(false) }
    }
}

/// The parts every Facets tip shares: on only while tips are on, a fresh id after a
/// reset, and the button to turn them all off.
protocol FacetsTip: Tip {
    var name: String { get }
}

extension FacetsTip {
    var id: String { "\(name)-\(FacetsTips.generation)" }
    var rules: [Rule] { [#Rule(FacetsTips.$enabled) { $0 }] }
    var actions: [Action] {
        [Action(id: FacetsTips.turnOffID, title: "Turn Off Tips") { FacetsTips.setOn(false) }]
    }
}

/// Facets' tip card: the control's own glyph, the title and a line or two, a small
/// close button, and "Turn Off Tips" as a quiet link rather than a big button (it
/// isn't what most people should press). Used inline above the bars, and in the
/// size chip's popover.
struct FacetsTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let image = configuration.image {
                image
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                configuration.title?
                    .font(.headline)
                configuration.message?
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(configuration.actions) { action in
                    Button(action: action.handler) {
                        action.label()
                            .font(.footnote.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
            Button {
                configuration.tip.invalidate(reason: .tipClosed)
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Tip")
        }
        .padding(16)
    }
}

/// Tips on or off, observed by views: TipKit applies a rule change a moment later,
/// and a card shouldn't flash the next tip after "Turn Off Tips".
@MainActor
@Observable
final class TipsState {
    static let shared = TipsState()
    var isOn = FacetsTips.isOn
}

/// The current tip of a tour as a card floating above the bars, or nothing. Toolbar
/// buttons can't anchor tip popovers on iOS 26, so the card shows the control's own
/// glyph instead of pointing at it.
struct FloatingTip: View {
    let tip: (any Tip)?

    var body: some View {
        if let tip, TipsState.shared.isOn {
            TipView(tip)
                .tipViewStyle(FacetsTipStyle())
                .tipBackground(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .frame(maxWidth: 440)
                .padding(.horizontal)
                // One card out, the next in, rather than their text cross-fading.
                .id(tip.id)
                .transition(.opacity)
        }
    }
}

// MARK: Library

struct AddModelsTip: FacetsTip {
    let name = "add-models"
    var title: Text { Text("Add Models") }
    var message: Text? {
        #if os(macOS)
        Text("Import STL, 3MF and OBJ files or make a folder. You can also drag files in from the Finder.")
        #else
        Text("Import STL, 3MF and OBJ files or make a folder. In Files, Mail or any app, Share › Facets saves one here too.")
        #endif
    }
    var image: Image? { Image(systemName: "plus") }
}

struct BrowseTip: FacetsTip {
    let name = "browse"
    var title: Text { Text("Browse Without Importing") }
    var message: Text? {
        #if os(macOS)
        Text("Add Location… at the foot of the sidebar lets you look through a folder's models where they are, and save the ones you want.")
        #else
        Text("Add a folder from Files to look through its models where they are, and save the ones you want.")
        #endif
    }
    var image: Image? { Image(systemName: "folder") }
}

struct ViewOptionsTip: FacetsTip {
    let name = "view-options"
    var title: Text { Text("Icons or a List") }
    var message: Text? {
        #if os(macOS)
        Text("Change how the library is shown and sorted. Double-click a model to open it; Space shows a quick look.")
        #else
        Text("Change how the library is shown and sorted. Touch and hold a model to rename, move or share it.")
        #endif
    }
    var image: Image? { Image(systemName: "ellipsis") }
}

// MARK: Viewer

struct SizeTip: FacetsTip {
    let name = "size"
    var title: Text { Text("Size and Fit") }
    var message: Text? {
        #if os(macOS)
        Text("The model's real size. Click it to choose your printer and see whether the model fits its bed.")
        #else
        Text("The model's real size. Tap it to choose your printer and see whether the model fits its bed.")
        #endif
    }
    var image: Image? { Image(systemName: "ruler") }
}

struct FitTip: FacetsTip {
    let name = "fit"
    var title: Text { Text("Fit to Screen") }
    var message: Text? {
        #if os(macOS)
        Text("Brings the whole model back into view. Double-clicking the model does the same.")
        #else
        Text("Brings the whole model back into view. Double-tapping the model does the same.")
        #endif
    }
    var image: Image? { Image(systemName: "viewfinder") }
}

struct PresetViewsTip: FacetsTip {
    let name = "preset-views"
    var title: Text { Text("Preset Views") }
    var message: Text? { Text("Jump straight to the front, back, sides, top or bottom.") }
    var image: Image? { Image(systemName: "move.3d") }
}

struct ToolsTip: FacetsTip {
    let name = "tools"
    var title: Text { Text("Tools") }
    var message: Text? { Text("Measure between two points, lay a face flat on the plate, or cut a cross-section to see inside.") }
    var image: Image? { Image(systemName: "wrench.and.screwdriver") }
}

struct DisplayTip: FacetsTip {
    let name = "display"
    var title: Text { Text("Display") }
    var message: Text? { Text("Wireframe, the build plate grid, and the printers you've used lately.") }
    var image: Image? { Image(systemName: "slider.horizontal.3") }
}

struct InfoTip: FacetsTip {
    let name = "info"
    var title: Text { Text("Info") }
    var message: Text? { Text("Volume, a print estimate, the file's units, and the objects in a project, which you can hide.") }
    var image: Image? { Image(systemName: "info.circle") }
}

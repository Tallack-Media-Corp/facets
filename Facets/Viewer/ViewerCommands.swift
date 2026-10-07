import MeshKit
import SwiftUI

/// What the viewer in front can do, for the menu bar.
struct ViewerActions {
    var fit: () -> Void
    var show: (OrbitCamera.Preset) -> Void
    var info: () -> Void
    var toggleGrid: () -> Void
    var toggleWireframe: () -> Void
    var toggleTool: (ViewerTool) -> Void
    var autoOrient: () -> Void
    var openTool: ViewerTool?
    var showsGrid: Bool
    var wireframe: Bool
}

extension FocusedValues {
    @Entry var viewerActions: ViewerActions?
}

/// The Model menu: on iPad it lives in the menu bar, where keyboard commands are
/// found, and is greyed out until a model is open in the window.
struct ViewerCommands: Commands {
    @FocusedValue(\.viewerActions) private var actions

    var body: some Commands {
        CommandMenu("Model") {
            Group {
                Button("Fit to Screen") { actions?.fit() }
                    .keyboardShortcut("0", modifiers: .command)
                Menu("Preset Views") {
                    ForEach(Array(OrbitCamera.Preset.allCases.enumerated()), id: \.element) { index, preset in
                        Button(preset.localizedTitle) { actions?.show(preset) }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    }
                }
                Divider()
                Toggle("Build Plate Grid", isOn: Binding(get: { actions?.showsGrid ?? false }, set: { _ in actions?.toggleGrid() }))
                    .keyboardShortcut("g", modifiers: .command)
                Toggle("Wireframe", isOn: Binding(get: { actions?.wireframe ?? false }, set: { _ in actions?.toggleWireframe() }))
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                ForEach(ViewerTool.allCases) { tool in
                    Toggle(tool.title, isOn: Binding(get: { actions?.openTool == tool }, set: { _ in actions?.toggleTool(tool) }))
                        .keyboardShortcut(tool.keyEquivalent, modifiers: [.command, .shift])
                }
                Button("Auto Orient") { actions?.autoOrient() }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Divider()
                Button("Model Info") { actions?.info() }
                    .keyboardShortcut("i", modifiers: .command)
            }
            .disabled(actions == nil)
        }
    }
}

extension ViewerTool {
    var keyEquivalent: KeyEquivalent {
        switch self {
        case .measure: "m"
        case .layFlat: "l"
        case .section: "x"
        }
    }
}

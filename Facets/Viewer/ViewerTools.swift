import MeshKit
import SwiftUI
import simd

/// The viewer's tools: one at a time, each with a panel above the toolbar.
enum ViewerTool: String, CaseIterable, Identifiable {
    case measure, layFlat, section

    var id: String { rawValue }

    var title: String {
        switch self {
        case .measure: String(localized: "Measure", comment: "Viewer tool")
        case .layFlat: String(localized: "Lay Flat", comment: "Viewer tool")
        case .section: String(localized: "Cross-Section", comment: "Viewer tool")
        }
    }

    var symbol: String {
        switch self {
        case .measure: "ruler"
        case .layFlat: "rotate.right"
        case .section: "square.split.1x2"
        }
    }

    /// What a tap on the model does while this tool is open.
    var canvasTool: ModelCanvasView.Tool {
        switch self {
        case .measure: .measure
        case .layFlat: .face
        case .section: .none
        }
    }
}

/// The open tool's controls, floating over the bottom of the model.
struct ToolPanel: View {
    let tool: ViewerTool
    let units: MeasurementUnits
    /// Measure: the points picked so far (0, 1 or 2).
    let points: [SIMD3<Float>]
    /// Cross-section: 0 (cut at the base) to 1 (whole model), and the height it means.
    @Binding var sectionFraction: Double
    let sectionHeight: Float
    let isTurned: Bool
    let autoState: AutoOrientState
    let clearPoints: () -> Void
    let autoOrient: () -> Void
    let turn: (SIMD3<Float>) -> Void
    let resetOrientation: () -> Void
    let close: () -> Void

    /// With VoiceOver on, the model takes direct touch while a tool is open, so the
    /// instructions say how to use it that way.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    /// VoiceOver lands on the panel when it opens, so its instructions are read.
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(tool.title, systemImage: tool.symbol)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
                Spacer()
                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
                    .padding(.vertical, -12)
                    .padding(.trailing, -10)
                    .accessibilityLabel("Close \(tool.title)")
            }
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal, 12)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .onAppear { titleFocused = true }
        .onChange(of: tool) { titleFocused = true }
    }

    @ViewBuilder
    private var content: some View {
        switch tool {
        case .measure: measure
        case .layFlat: layFlat
        case .section: section
        }
    }

    // MARK: Measure

    @ViewBuilder
    private var measure: some View {
        if points.count == 2 {
            let delta = abs(points[1] - points[0])
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.dimension(simd_distance(points[0], points[1]), units: units))
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text("X \(Format.dimension(delta.x, units: units)) · Y \(Format.dimension(delta.y, units: units)) · Z \(Format.dimension(delta.z, units: units))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Button(action: clearPoints) {
                    Text("Clear").frame(minHeight: 44).padding(.horizontal, 4)
                }
                .buttonStyle(.glass)
            }
        } else {
            Text(measureHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var measureHint: String {
        if voiceOver {
            return points.isEmpty
                ? String(localized: "Touch the model directly and lift your finger where the first point goes. Points snap to a nearby corner.")
                : String(localized: "Touch the model again and lift your finger on the second point.")
        }
        return points.isEmpty ? String(localized: "Tap a point on the model. Points snap to a nearby corner.") : String(localized: "Tap a second point.")
    }

    // MARK: Lay flat

    private var layFlat: some View {
        VStack(alignment: .leading, spacing: 10) {
            Group {
                if autoState == .alreadyBest {
                    Label("Already the best way up to print.", systemImage: "checkmark")
                        .foregroundStyle(.primary)
                } else {
                    Text(voiceOver
                         ? "Touch the model directly and lift your finger on a face to rest the model on it, or use the buttons below."
                         : "Tap a face to rest the model on it, choose Auto, or turn it a quarter at a time.")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: autoState)
            HStack(spacing: 8) {
                Button(action: autoOrient) {
                    toolLabel("Auto") {
                        if autoState == .working {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "wand.and.sparkles")
                        }
                    }
                }
                .buttonStyle(.glass)
                .disabled(autoState == .working)
                .accessibilityHint("Turns the model onto the face a slicer would print it on")
                turnButton("Turn", symbol: "arrow.clockwise", axis: [0, 0, 1], hint: "A quarter turn on the bed")
                turnButton("Tip", symbol: "arrow.down.forward", axis: [1, 0, 0], hint: "A quarter turn, front edge down")
                turnButton("Roll", symbol: "arrow.turn.right.down", axis: [0, 1, 0], hint: "A quarter turn onto its side")
                Button(action: resetOrientation) {
                    toolLabel("Reset", symbol: "arrow.uturn.backward")
                }
                .buttonStyle(.glass)
                .disabled(!isTurned)
                .accessibilityHint("Back to how the file has it")
            }
        }
    }

    private func turnButton(_ title: LocalizedStringResource, symbol: String, axis: SIMD3<Float>, hint: LocalizedStringResource) -> some View {
        Button { turn(axis) } label: {
            toolLabel(title, symbol: symbol)
        }
        .buttonStyle(.glass)
        .accessibilityHint(Text(hint))
    }

    // Resources rather than strings, so each button's title is picked up for translation.
    private func toolLabel(_ title: LocalizedStringResource, symbol: String) -> some View {
        toolLabel(title) { Image(systemName: symbol) }
    }

    /// The glyphs sit in one height, so every title lines up (and Auto's doesn't
    /// jump while it works).
    private func toolLabel(_ title: LocalizedStringResource, @ViewBuilder icon: () -> some View) -> some View {
        VStack(spacing: 2) {
            icon().frame(height: 22)
            // One line that shrinks a little to fit ("Zurücksetzen", "Restablecer"),
            // rather than wrapping or cutting off.
            Text(title).font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    // MARK: Section

    private var section: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cut at \(Format.dimension(sectionHeight, units: units))")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(value: $sectionFraction, in: 0...1) {
                Text("Cut height")
            } minimumValueLabel: {
                Image(systemName: "square.bottomhalf.filled").accessibilityHidden(true)
            } maximumValueLabel: {
                Image(systemName: "square.fill").accessibilityHidden(true)
            }
            .accessibilityValue(Format.dimension(sectionHeight, units: units))
        }
    }
}

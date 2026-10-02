import MeshKit
import SwiftUI
import simd

/// The viewer's tools: one at a time, each with a panel above the toolbar.
enum ViewerTool: String, CaseIterable, Identifiable {
    case measure, layFlat, section

    var id: String { rawValue }

    var title: String {
        switch self {
        case .measure: "Measure"
        case .layFlat: "Lay Flat"
        case .section: "Cross-Section"
        }
    }

    var symbol: String {
        switch self {
        case .measure: "ruler"
        case .layFlat: "square.and.arrow.down"
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
    let clearPoints: () -> Void
    let turn: (SIMD3<Float>) -> Void
    let resetOrientation: () -> Void
    let close: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(tool.title, systemImage: tool.symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Done", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
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
                Button("Clear", action: clearPoints)
                    .buttonStyle(.glass)
            }
        } else {
            Text(points.isEmpty ? "Tap a point on the model. Points snap to a nearby corner." : "Tap a second point.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Lay flat

    private var layFlat: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tap a face to rest the model on it, or turn it a quarter at a time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
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

    private func turnButton(_ title: String, symbol: String, axis: SIMD3<Float>, hint: String) -> some View {
        Button { turn(axis) } label: {
            toolLabel(title, symbol: symbol)
        }
        .buttonStyle(.glass)
        .accessibilityHint(hint)
    }

    private func toolLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol)
            Text(title).font(.caption2.weight(.medium))
        }
        .frame(maxWidth: .infinity, minHeight: 36)
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

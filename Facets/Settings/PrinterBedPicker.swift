import SwiftUI

/// Settings › Printer Bed: which bed the viewer outlines under a model.
struct PrinterBedPicker: View {
    @Environment(ViewerSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                row(title: "None", id: nil)
            } footer: {
                Text("Pick your printer to see its bed under every model, and whether the model fits.")
            }
            ForEach(PrinterBed.byMake, id: \.make) { group in
                Section(group.make) {
                    ForEach(group.beds) { bed in
                        row(title: bed.name, detail: size(bed.width, bed.depth, bed.height), id: bed.id)
                    }
                }
            }
            Section {
                row(title: "Custom", id: PrinterBed.customID)
                if settings.bedID == PrinterBed.customID {
                    LabeledContent("Width") {
                        TextField("Width", value: lengthBinding($settings.customBedWidth), format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                        Text(settings.units.symbol).foregroundStyle(.secondary)
                    }
                    LabeledContent("Depth") {
                        TextField("Depth", value: lengthBinding($settings.customBedDepth), format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                        Text(settings.units.symbol).foregroundStyle(.secondary)
                    }
                    LabeledContent("Height") {
                        TextField("Height", value: lengthBinding($settings.customBedHeight), format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                        Text(settings.units.symbol).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Other Printer")
            }
        }
        .navigationTitle("Printer Bed")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(title: String, detail: String? = nil, id: String?) -> some View {
        Button {
            settings.bedID = id
        } label: {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if let detail { Text(detail).foregroundStyle(.secondary).monospacedDigit() }
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .opacity(settings.bedID == id ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(settings.bedID == id ? .isSelected : [])
    }

    /// "256 × 256 × 250 mm".
    private func size(_ width: Float, _ depth: Float, _ height: Float) -> String {
        "\(Format.dimension(width, units: settings.units)) × \(Format.dimension(depth, units: settings.units)) × \(Format.dimension(height, units: settings.units))"
            .replacingOccurrences(of: " \(settings.units.symbol) ×", with: " ×")
    }

    /// Shows and edits millimetres in the user's units.
    private func lengthBinding(_ mm: Binding<Float>) -> Binding<Double> {
        let factor: Double = settings.units == .inches ? 25.4 : 1
        return Binding(
            get: { Double(mm.wrappedValue) / factor },
            set: { mm.wrappedValue = Float(max($0, 1) * factor) }
        )
    }
}

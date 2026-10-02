import MeshKit
import SwiftUI

/// Settings › Printer Bed: which bed the viewer outlines under a model.
struct PrinterBedPicker: View {
    /// Opened from the viewer: what the model there makes of each bed, so the list
    /// can say which printers would take it.
    var verdict: ((PrinterBed) -> BedFit.Verdict?)? = nil
    /// Opened from the viewer: called after a printer is picked, to close the sheet.
    /// Custom stays open for its sizes.
    var onPick: (() -> Void)? = nil

    @Environment(ViewerSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                row(title: "None", id: nil)
            } footer: {
                Text(verdict == nil
                     ? "Pick your printer to see its bed under every model, and whether the model fits."
                     : "Each printer says whether the model you're viewing fits it, as it's oriented now.")
            }
            ForEach(PrinterBed.byMake, id: \.make) { group in
                Section(group.make) {
                    ForEach(group.beds) { bed in
                        row(title: bed.name, detail: size(bed.width, bed.depth, bed.height), id: bed.id, verdict: verdict?(bed))
                    }
                }
            }
            Section {
                row(title: "Custom", id: PrinterBed.customID)
                if settings.bedID == PrinterBed.customID {
                    LabeledContent("Width") {
                        TextField("Width", value: lengthBinding($settings.customBedWidth), format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing)
                            .decimalKeyboard()
                        Text(settings.units.symbol).foregroundStyle(.secondary)
                    }
                    LabeledContent("Depth") {
                        TextField("Depth", value: lengthBinding($settings.customBedDepth), format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing)
                            .decimalKeyboard()
                        Text(settings.units.symbol).foregroundStyle(.secondary)
                    }
                    LabeledContent("Height") {
                        TextField("Height", value: lengthBinding($settings.customBedHeight), format: .number.precision(.fractionLength(0...1)))
                            .multilineTextAlignment(.trailing)
                            .decimalKeyboard()
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

    private func row(title: String, detail: String? = nil, id: String?, verdict: BedFit.Verdict? = nil) -> some View {
        let note = verdict.map(Self.note(for:))
        return Button {
            settings.bedID = id
            if id != PrinterBed.customID { onPick?() }
        } label: {
            HStack {
                // Colour, not hierarchical styles: inside a button those resolve to the tint.
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Color.primary)
                    if let note {
                        HStack(spacing: 4) {
                            Image(systemName: note.symbol)
                            Text(note.text)
                        }
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    }
                }
                Spacer()
                if let detail { Text(detail).foregroundStyle(Color.secondary).monospacedDigit() }
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .opacity(settings.bedID == id ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(settings.bedID == id ? .isSelected : [])
        .accessibilityValue(note?.text ?? "")
    }

    /// The short form of a fit verdict, for a row in the list.
    private static func note(for verdict: BedFit.Verdict) -> (text: String, symbol: String) {
        switch verdict {
        case .fits: ("Fits", "checkmark.circle")
        case .fitsTurned: ("Fits turned 90°", "checkmark.circle")
        case .tooBig: ("Too small", "exclamationmark.triangle.fill")
        case .offPlate: ("Fits, but runs off the plate as arranged", "exclamationmark.triangle.fill")
        }
    }

    /// "256 × 256 × 250 mm": whole millimetres, since beds are specified that way.
    private func size(_ width: Float, _ depth: Float, _ height: Float) -> String {
        let factor: Float = settings.units == .inches ? 25.4 : 1
        let digits = settings.units == .inches ? 1 : 0
        let parts = [width, depth, height].map { ($0 / factor).formatted(.number.precision(.fractionLength(digits))) }
        return parts.joined(separator: " × ") + " " + settings.units.symbol
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

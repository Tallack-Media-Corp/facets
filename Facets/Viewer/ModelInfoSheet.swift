import MeshKit
import SwiftUI

/// What's in the file: size, volume, triangle count, and the objects, which can be
/// hidden one by one.
struct ModelInfoSheet: View {
    let model: Model3D
    let file: ModelFileRef
    let fileSize: Int64?
    let units: MeasurementUnits
    let material: FilamentMaterial
    /// The printer chosen in Facets, for the estimate's speeds.
    let printer: PrinterBed?
    /// The unit card is up: no estimate until the size is settled.
    let unsureOfUnits: Bool
    /// Whether the model fits the chosen printer as oriented (nil: no printer).
    let fitsPrinter: Bool?
    /// The scale applied for the file's unit (1: as saved), the size as saved, and
    /// a way to change it. Always relative to the file, so choices don't compound.
    let unitScale: Float
    let originalSize: SIMD3<Float>
    let setUnitScale: (Float) -> Void
    /// Closes the sheet or inspector (an inspector doesn't answer to `dismiss`).
    let close: () -> Void
    /// A Done button: in a sheet. An inspector has none (the Info button toggles it),
    /// since its toolbar items would land in the viewer's own bar.
    var showsDone = true
    @Binding var appearance: RenderAppearance
    @Binding var detent: PresentationDetent


    private var shownParts: [ModelPart] {
        model.visibleParts(plateID: appearance.plateID, hidden: appearance.hiddenObjects)
    }

    private var plateObjects: [ModelObject] {
        model.objects(onPlate: appearance.plateID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Model") {
                    let bounds = model.bounds(of: shownParts)
                    LabeledContent("Width", value: Format.dimension(bounds.size.x, units: units))
                    LabeledContent("Depth", value: Format.dimension(bounds.size.y, units: units))
                    LabeledContent("Height", value: Format.dimension(bounds.size.z, units: units))
                    LabeledContent("Volume", value: Format.volume(abs(shownParts.reduce(0) { $0 + $1.volume }), units: units))
                    LabeledContent("Triangles", value: Format.count(shownParts.reduce(0) { $0 + $1.geometry.triangleCount }))
                    if model.plates.count > 1 {
                        LabeledContent("Plates", value: Format.count(model.plates.count))
                    }
                }

                printSection

                if plateObjects.count > 1 {
                    Section {
                        ForEach(plateObjects) { object in
                            ObjectRow(
                                object: object,
                                label: label(for: object),
                                color: color(of: object),
                                isVisible: Binding(
                                    get: { !appearance.hiddenObjects.contains(object.id) },
                                    set: { visible in
                                        if visible { appearance.hiddenObjects.remove(object.id) } else { appearance.hiddenObjects.insert(object.id) }
                                    }
                                )
                            )
                        }
                    } header: {
                        Text("Objects")
                    } footer: {
                        Text("Hidden objects aren't counted in the size and volume above.")
                    }
                }

                Section {
                    LabeledContent("Name", value: file.url.lastPathComponent)
                    LabeledContent("Format", value: model.format.rawValue)
                    // 3MF states its units, so only STL and OBJ can be read at the wrong scale.
                    if model.format != .threeMF {
                        Picker("File Units", selection: Binding(get: { unitScale }, set: { setUnitScale($0) })) {
                            Text("As Saved · \(largestSide(1))").tag(Float(1))
                            ForEach(UnitGuess.allCases) { unit in
                                Text("\(unit.title) · \(largestSide(unit.factor))").tag(unit.factor)
                            }
                        }
                    }
                    if let fileSize {
                        LabeledContent("Size", value: Format.fileSize(fileSize))
                    }
                    if let title = model.title, title != file.name, title != file.displayName {
                        LabeledContent("Title", value: title)
                    }
                    if let application = model.application {
                        LabeledContent("Made With", value: application.replacingOccurrences(of: "-", with: " "))
                    }
                    LabeledContent("Location", value: file.isExternal ? "Not saved in Facets" : "In your Facets library")
                } header: {
                    Text("File")
                } footer: {
                    if model.format != .threeMF {
                        Text("File Units sets what one unit in the file means, for a model saved in metres, centimetres or inches. Facets remembers it for this file; the file itself isn't changed.")
                    }
                }
            }
            .navigationTitle(file.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDone {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark", action: close)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    /// What printing it takes: the slicer's own numbers when the project was saved
    /// sliced, otherwise the weight it would be printed solid, as an upper bound.
    @ViewBuilder
    private var printSection: some View {
        if let estimate = model.estimate(plateID: appearance.plateID) {
            Section {
                if let seconds = estimate.seconds {
                    LabeledContent("Print Time", value: Format.duration(seconds: seconds))
                }
                if let grams = estimate.grams {
                    LabeledContent("Filament", value: [Format.grams(grams), estimate.meters.map { Format.filamentLength($0, units: units) }].compactMap { $0 }.joined(separator: " · "))
                }
                if estimate.filaments.count > 1 {
                    ForEach(Array(estimate.filaments.enumerated()), id: \.offset) { _, filament in
                        FilamentRow(filament: filament, units: units)
                    }
                }
                if estimate.usesSupports {
                    LabeledContent("Supports", value: "Yes")
                }
            } header: {
                Text("Print Estimate")
            } footer: {
                Text(appearance.plateID == nil && model.plates.count > 1
                     ? "From the slicer, for every plate together, as of when the project was last sliced."
                     : "From the slicer, as of when the project was last sliced.")
            }
        } else if unsureOfUnits {
            Section("Print Estimate") {
                Text("Choose the file's units to see an estimate.")
                    .foregroundStyle(.secondary)
            }
        } else if let estimate = model.shapeEstimate(plateID: appearance.plateID, hidden: appearance.hiddenObjects, density: material.density, machine: printer?.machine ?? .bambuCoreXY) {
            Section {
                // Rounded to what the estimate can claim; slicer figures stay exact.
                LabeledContent("Print Time", value: "about \(Format.roughDuration(seconds: estimate.seconds))")
                LabeledContent("Filament", value: "about \(Format.roughGrams(estimate.grams))")
            } header: {
                Text(model.plates.count > 1 && appearance.plateID == nil ? "Print Estimate, All Plates" : "Print Estimate")
            } footer: {
                Text("Estimated from the model's shape for \(printerName), with typical settings: 0.2 mm layers, two walls and 15% \(material.title) infill. Your slicer will typically be within 10% on filament and \(timeMargin)% on time, more if the model needs supports.\(fitsPrinter == false ? " It doesn't fit this printer as it sits." : "")")
            }
        }
    }

    /// The median time error for this kind of printer (docs/print-estimates.md), rounded.
    private var timeMargin: Int {
        switch printer?.machine ?? .bambuCoreXY {
        case .bambuCoreXY, .bambuBedSlinger: 15
        case .coreXY: 20
        default: 25
        }
    }

    /// An object's name, numbered when several share it ("Roller (2)"), so each
    /// switch can be told apart, VoiceOver included.
    private func label(for object: ModelObject) -> String {
        let same = plateObjects.filter { $0.name == object.name }
        guard same.count > 1, let index = same.firstIndex(of: object) else { return object.name }
        return "\(object.name) (\(index + 1))"
    }

    /// The largest side at a scale, for the File Units choices.
    private func largestSide(_ factor: Float) -> String {
        Format.dimension(max(originalSize.x, originalSize.y, originalSize.z) * factor, units: units)
    }

    private var printerName: String {
        guard let printer, printer.id != PrinterBed.customID else { return "a Bambu Lab printer" }
        return "the \(printer.title)"
    }

    /// The object's colour as drawn: its file colour, or the model colour.
    private func color(of object: ModelObject) -> Color {
        let part = model.parts.first { $0.objectID == object.id }
        let linear = (appearance.usesFileColors ? part?.color : nil) ?? appearance.baseColor
        return Color(.sRGBLinear, red: Double(linear.x), green: Double(linear.y), blue: Double(linear.z))
    }
}

/// One filament in a multi-colour print: its colour, type and how much.
private struct FilamentRow: View {
    let filament: SliceEstimate.Filament
    let units: MeasurementUnits

    var body: some View {
        LabeledContent {
            Text([filament.grams.map(Format.grams), filament.meters.map { Format.filamentLength($0, units: units) }].compactMap { $0 }.joined(separator: " · "))
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(filament.colorHex.flatMap { Color(hex: $0) } ?? .gray)
                    .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(filament.type ?? "Filament")
            }
        }
    }
}

private struct ObjectRow: View {
    let object: ModelObject
    let label: String
    let color: Color
    @Binding var isVisible: Bool

    var body: some View {
        Toggle(isOn: $isVisible) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                Text(label)
                    .lineLimit(2)
                    .foregroundStyle(isVisible ? .primary : .secondary)
            }
        }
        .accessibilityLabel("Show \(label)")
    }
}

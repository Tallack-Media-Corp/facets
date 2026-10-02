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
    @Binding var appearance: RenderAppearance
    @Binding var detent: PresentationDetent

    @Environment(\.dismiss) private var dismiss

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

                Section("File") {
                    LabeledContent("Name", value: file.url.lastPathComponent)
                    LabeledContent("Format", value: model.format.rawValue)
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
                }
            }
            .navigationTitle(file.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
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
        } else if let estimate = model.shapeEstimate(plateID: appearance.plateID, hidden: appearance.hiddenObjects, density: material.density, machine: printer?.machine ?? .bambuCoreXY) {
            Section {
                LabeledContent("Print Time", value: "about \(Format.duration(seconds: estimate.seconds))")
                LabeledContent("Filament", value: "about \(Format.grams(estimate.grams)) · \(Format.filamentLength(estimate.meters, units: units))")
            } header: {
                Text("Print Estimate")
            } footer: {
                Text("Worked out from the model's shape for \(printerName), assuming 0.2 mm layers, two walls and 15% \(material.title) infill. Weight is usually within a tenth of the slicer's; time within a fifth. Supports add more. A project saved after slicing in Bambu Studio or Orca shows the slicer's own figures here.")
            }
        }
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
                Text(object.name)
                    .lineLimit(2)
                    .foregroundStyle(isVisible ? .primary : .secondary)
            }
        }
        .accessibilityLabel("Show \(object.name)")
    }
}

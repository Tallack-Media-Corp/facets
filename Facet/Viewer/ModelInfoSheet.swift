import MeshKit
import SwiftUI

/// What's in the file: size, volume, triangle count, and the objects, which can be
/// hidden one by one.
struct ModelInfoSheet: View {
    let model: Model3D
    let file: ModelFileRef
    let fileSize: Int64?
    let units: MeasurementUnits
    @Binding var appearance: RenderAppearance

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
                    if let title = model.title, title != file.name {
                        LabeledContent("Title", value: title)
                    }
                    if let application = model.application {
                        LabeledContent("Made With", value: application.replacingOccurrences(of: "-", with: " "))
                    }
                    LabeledContent("Location", value: file.isExternal ? "Another app" : "Facet library")
                }
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    /// The object's colour as drawn: its file colour, or the model colour.
    private func color(of object: ModelObject) -> Color {
        let part = model.parts.first { $0.objectID == object.id }
        let linear = (appearance.usesFileColors ? part?.color : nil) ?? appearance.baseColor
        return Color(.sRGBLinear, red: Double(linear.x), green: Double(linear.y), blue: Double(linear.z))
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

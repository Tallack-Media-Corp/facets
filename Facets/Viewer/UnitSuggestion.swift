import MeshKit
import SwiftUI

/// What the user decided about a file's unit, so it's asked once. Keyed by name and
/// size: enough to tell files apart without holding on to them.
enum UnitChoices {
    private static let key = "viewer.unitChoices"

    static func key(for file: ModelFileRef, size: Int64?) -> String {
        "\(file.url.lastPathComponent)|\(size ?? -1)"
    }

    /// The scale chosen for a file: 1 for "keep as saved", nil if never asked.
    static func factor(for fileKey: String) -> Float? {
        (UserDefaults.standard.dictionary(forKey: key)?[fileKey] as? NSNumber)?.floatValue
    }

    static func set(_ factor: Float, for fileKey: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        all[fileKey] = factor
        UserDefaults.standard.set(all, forKey: key)
    }
}

/// Offered under the size readout when a model is too small to be in millimetres:
/// the likelier unit first, each with the size it would give.
struct UnitSuggestionCard: View {
    let size: SIMD3<Float>
    let suggestions: [UnitGuess]
    let units: MeasurementUnits
    let choose: (UnitGuess) -> Void
    let keep: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var largest: Float { max(size.x, size.y, size.z) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Saved in another unit?", systemImage: "ruler")
                    .font(.subheadline.weight(.semibold))
                Text("It's only \(Format.dimension(largest, units: units)) across, smaller than anything a printer makes. Files in metres or inches open this way. You can change this later in Info.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach(suggestions) { unit in
                    Button { choose(unit) } label: {
                        VStack(spacing: 1) {
                            Text(unit.title).font(.footnote.weight(.semibold))
                            Text(Format.dimension(largest * unit.factor, units: units))
                                .font(.caption2.monospacedDigit())
                                .opacity(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    // Equal weight: size alone can't tell metres from inches.
                    .buttonStyle(.glass)
                    .accessibilityLabel("\(unit.title), \(Format.dimension(largest * unit.factor, units: units)) across")
                }
                Button("Keep", action: keep)
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
                    .padding(.horizontal, 6)
                    .buttonStyle(.glass)
                    .accessibilityHint("Shows the model at the size the file says")
            }
        }
        .padding(14)
        .frame(maxWidth: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 12)
    }
}


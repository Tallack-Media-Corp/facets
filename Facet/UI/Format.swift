import Foundation
import MeshKit

enum Format {
    static func fileSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "" }
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    static func count(_ n: Int) -> String {
        n.formatted(.number)
    }

    private static func length(_ mm: Float, units: MeasurementUnits) -> String {
        switch units {
        case .millimetres:
            return mm.formatted(.number.precision(.fractionLength(mm >= 100 ? 0...1 : 1...1)))
        case .inches:
            return (mm / 25.4).formatted(.number.precision(.fractionLength(2)))
        }
    }

    /// "120.0 × 40.5 × 22.0 mm", width × depth × height.
    static func dimensions(_ size: SIMD3<Float>, units: MeasurementUnits) -> String {
        "\(length(size.x, units: units)) × \(length(size.y, units: units)) × \(length(size.z, units: units)) \(units.symbol)"
    }

    static func dimension(_ mm: Float, units: MeasurementUnits) -> String {
        "\(length(mm, units: units)) \(units.symbol)"
    }

    /// Cubic millimetres to cm³ or in³.
    static func volume(_ mm3: Float, units: MeasurementUnits) -> String {
        switch units {
        case .millimetres:
            return "\((mm3 / 1000).formatted(.number.precision(.fractionLength(mm3 < 10_000 ? 2 : 1)))) cm³"
        case .inches:
            return "\((mm3 / 16_387.064).formatted(.number.precision(.fractionLength(2)))) in³"
        }
    }
}

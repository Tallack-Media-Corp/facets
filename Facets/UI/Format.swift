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
            // Always one decimal, so a readout never mixes "176" with "79.6".
            return mm.formatted(.number.precision(.fractionLength(1)))
        case .inches:
            return (mm / 25.4).formatted(.number.precision(.fractionLength(2)))
        }
    }

    /// "W 120.0 · D 40.5 · H 22.0 mm": labelled, so nobody has to guess which is height.
    static func dimensions(_ size: SIMD3<Float>, units: MeasurementUnits) -> String {
        "W \(length(size.x, units: units)) · D \(length(size.y, units: units)) · H \(length(size.z, units: units)) \(units.symbol)"
    }

    /// The same, for VoiceOver: "120.0 millimetres wide, 40.5 deep, 22.0 high".
    static func spokenDimensions(_ size: SIMD3<Float>, units: MeasurementUnits) -> String {
        let unitName = units == .millimetres ? "millimetres" : "inches"
        return "\(length(size.x, units: units)) \(unitName) wide, \(length(size.y, units: units)) deep, \(length(size.z, units: units)) high"
    }

    /// A file name for a title: "Eufy_S1_Case_-_Multicolour" reads as
    /// "Eufy S1 Case – Multicolour". The real name still shows in Info › File and in
    /// the rename field.
    static func title(fromFileName name: String) -> String {
        name.replacingOccurrences(of: "_-_", with: " – ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)
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

    /// "1 h 23 min", "48 min", "under a minute".
    static func duration(seconds: Int) -> String {
        if seconds < 60 { return "under a minute" }
        let minutes = (seconds + 30) / 60
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .short
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
    }

    /// "6.5 g"; whole grams from 100 up; two decimals under a gram, so a tiny part
    /// doesn't read as nothing.
    static func grams(_ grams: Float) -> String {
        if grams >= 100 { return "\(Int(grams.rounded())) g" }
        if grams >= 1 { return String(format: "%.1f g", grams) }
        if grams >= 0.01 { return String(format: "%.2f g", grams) }
        return "under 0.01 g"
    }

    /// Filament length: "2.13 m", or feet in inch mode.
    static func filamentLength(_ meters: Float, units: MeasurementUnits) -> String {
        switch units {
        case .millimetres: String(format: "%.2f m", meters)
        case .inches: String(format: "%.1f ft", meters * 3.28084)
        }
    }

    /// An estimate's time, no finer than it can claim: to 5 minutes under an hour,
    /// to the quarter hour up to 10 hours ("9¼ hours"), then to the hour.
    static func roughDuration(seconds: Int) -> String {
        let minutes = Double(seconds) / 60
        if minutes < 60 {
            let m = max(5, Int((minutes / 5).rounded()) * 5)
            return m >= 60 ? "1 hour" : "\(m) min"
        }
        let hours = minutes / 60
        if hours < 10 {
            let quarters = Int((hours * 4).rounded())
            let whole = quarters / 4
            let fraction = ["", "¼", "½", "¾"][quarters % 4]
            return "\(whole)\(fraction) hour\(quarters == 4 ? "" : "s")"
        }
        return "\(Int(hours.rounded())) hours"
    }

    /// An estimate's weight to two significant figures ("120 g", "8.4 g").
    static func roughGrams(_ grams: Float) -> String {
        guard grams >= 0.01 else { return "under 0.01 g" }
        let digits = Int(floor(log10(Double(grams))))
        let step = pow(10, Double(digits - 1))
        let rounded = (Double(grams) / step).rounded() * step
        return digits >= 1 ? "\(Int(rounded)) g" : String(format: "%.\(max(0, 1 - digits))f g", rounded)
    }
}

import Foundation

/// STL and OBJ files don't say what unit they're in, and every slicer reads them as
/// millimetres. A file saved in metres or inches therefore opens a thousand or 25.4
/// times too small. This spots that the way Bambu Studio and PrusaSlicer do, from the
/// size alone, and suggests the likelier unit first.
public enum UnitGuess: String, Sendable, CaseIterable, Identifiable {
    case metres, centimetres, inches

    public var id: String { rawValue }

    public var factor: Float {
        switch self {
        case .metres: 1000
        case .centimetres: 10
        case .inches: 25.4
        }
    }

    public var title: String {
        switch self {
        case .metres: "Metres"
        case .centimetres: "Centimetres"
        case .inches: "Inches"
        }
    }

    /// Below this, in mm, a model is almost certainly in another unit: nothing a
    /// printer makes is that small.
    public static let threshold: Float = 2

    /// Units to offer for a model this size, the one whose largest side lands
    /// nearer 100 mm (the middle of what desktop printers make) first; empty when it
    /// looks right. Only metres and inches: they're what files are really saved in,
    /// and size alone can't tell which, so both are offered.
    public static func suggestions(for size: SIMD3<Float>) -> [UnitGuess] {
        let largest = max(size.x, size.y, size.z)
        guard largest > 0, largest < threshold else { return [] }
        return [UnitGuess.metres, .inches].sorted { a, b in
            abs(log(largest * a.factor / 100)) < abs(log(largest * b.factor / 100))
        }
    }
}

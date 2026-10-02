import Foundation

/// STL and OBJ files don't say what unit they're in, and every slicer reads them as
/// millimetres. A file saved in metres or inches therefore opens a thousand or 25.4
/// times too small. This spots that the way Bambu Studio and PrusaSlicer do, from the
/// size alone, and suggests the likelier unit first.
public enum UnitGuess: String, Sendable, CaseIterable, Identifiable {
    case metres, inches

    public var id: String { rawValue }

    public var factor: Float {
        switch self {
        case .metres: 1000
        case .inches: 25.4
        }
    }

    public var title: String {
        switch self {
        case .metres: "Metres"
        case .inches: "Inches"
        }
    }

    /// Below this, in mm, a model is almost certainly in another unit: nothing a
    /// printer makes is that small.
    public static let threshold: Float = 2

    /// Units to offer for a model this size, likeliest first; empty when it looks
    /// right. The likeliest is the one whose largest side lands nearest 100 mm, the
    /// middle of what desktop printers make.
    public static func suggestions(for size: SIMD3<Float>) -> [UnitGuess] {
        let largest = max(size.x, size.y, size.z)
        guard largest > 0, largest < threshold else { return [] }
        return allCases.sorted { a, b in
            abs(log(largest * a.factor / 100)) < abs(log(largest * b.factor / 100))
        }
    }
}

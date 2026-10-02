import Foundation

/// A slicer-free guess at weight and print time, from the model's shape alone.
///
/// A slicer turns a model into walls round its sides, solid skins on what faces up
/// and down, and sparse infill inside. How much of each a model gets depends on its
/// shape: a thin bracket is nearly all wall, a chunky block mostly infill. So this
/// splits the volume the same way, assuming common settings (0.2 mm layers, two
/// 0.45 mm walls, 5 top and 3 bottom layers, 15% infill), and times the paths.
///
/// The constants were fitted to 34 plates sliced by Bambu Studio for X1C, P1S, P1P
/// and A1 printers (docs/print-estimates.md). Cross-validated by project, the median
/// error was about 17% for weight and 17% for time, against 28% for the best single
/// "percent of solid" and 83% for solid. Supports and other settings aren't modelled.
public struct PrintEstimate: Sendable, Equatable {
    public let grams: Float
    public let meters: Float
    public let seconds: Int

    /// The settings the estimate assumes, for saying so.
    public static let layerHeight: Float = 0.2
    public static let infill: Float = 0.15
    public static let walls: Float = 2

    static let lineWidth: Float = 0.45
    static let topLayers: Float = 5
    static let bottomLayers: Float = 3
    /// 1.75 mm filament.
    static let filamentArea: Float = .pi * 0.875 * 0.875

    // Fitted (see the doc comment).
    static let shellMass: Float = 0.875
    static let infillMass: Float = 0.808
    static let secondsPerShellMM: Float = 0.00972
    static let secondsPerInfillMM: Float = 0.00906
    static let secondsPerPartLayer: Float = 0.972
    static let minimumLayerSeconds: Float = 12
    static let startSeconds: Float = 930

    /// - Parameters:
    ///   - volume: solid volume, mm³.
    ///   - surface: the surface by facing.
    ///   - height: how tall the print is, mm.
    ///   - parts: separate pieces on the plate (each adds travel every layer).
    ///   - density: filament density, g/cm³.
    public init?(volume: Float, surface: SurfaceStats, height: Float, parts: Int, density: Float) {
        guard volume > 0, height > 0 else { return nil }
        var wall = surface.side * Self.walls * Self.lineWidth
        var skin = surface.up * Self.topLayers * Self.layerHeight + surface.down * Self.bottomLayers * Self.layerHeight
        // A thin part is all shell: scale walls and skins down to fit the solid.
        if wall + skin > volume {
            let k = volume / (wall + skin)
            wall *= k
            skin *= k
        }
        let shell = wall + skin
        let infill = max(volume - shell, 0) * Self.infill

        let gramsPerMM3 = density / 1000
        let mass = (shell * Self.shellMass + infill * Self.infillMass) * gramsPerMM3
        grams = mass
        meters = mass / gramsPerMM3 / Self.filamentArea / 1000

        let pathArea = Self.lineWidth * Self.layerHeight
        let layers = height / Self.layerHeight
        let work = shell / pathArea * Self.secondsPerShellMM + infill / pathArea * Self.secondsPerInfillMM
        // Small layers are slowed so each has time to cool.
        let printing = max(work, layers * Self.minimumLayerSeconds)
        let total = printing + layers * Float(parts) * Self.secondsPerPartLayer + Self.startSeconds
        seconds = Int(total.rounded())
    }
}

extension Model3D {
    /// The shape-based estimate for what's showing, for a filament of `density`
    /// (g/cm³). Each object on the plate counts as one piece.
    public func shapeEstimate(plateID: Int?, hidden: Set<Int>, density: Float) -> PrintEstimate? {
        let shown = visibleParts(plateID: plateID, hidden: hidden)
        guard !shown.isEmpty else { return nil }
        let volume = abs(shown.reduce(0) { $0 + $1.volume })
        let surface = shown.reduce(SurfaceStats()) { $0 + $1.surface }
        let pieces = Set(shown.map(\.objectID)).count
        return PrintEstimate(volume: volume, surface: surface, height: bounds(of: shown).size.z, parts: pieces, density: density)
    }
}

import Foundation

/// A slicer-free guess at weight and print time, from the model's shape alone.
///
/// A slicer turns a model into walls round its sides, solid skins on what faces up
/// and down, and sparse infill inside. How much of each a model gets depends on its
/// shape: a thin bracket is nearly all wall, a chunky block mostly infill. So this
/// splits the volume the same way, assuming common settings (0.2 mm layers, two
/// 0.45 mm walls, 5 top and 3 bottom layers, 15% infill), and times the paths at the
/// speeds of the kind of printer it's for.
///
/// Calibrated against 34 plates sliced by Bambu Studio and 259 sliced by Orca Slicer
/// for an X1C, A1, K1 and Ender-3 V3 (docs/print-estimates.md). Cross-validated by
/// model, the median error is under 10% for weight and about 14–23% for time,
/// depending on the printer. Supports and settings other than those above aren't
/// modelled.
public struct PrintEstimate: Sendable, Equatable {
    public let grams: Float
    public let meters: Float
    public let seconds: Int

    /// How fast a kind of printer lays down plastic, fitted per kind.
    public struct Machine: Sendable, Equatable {
        /// Seconds per mm of wall and skin path, and of infill path.
        let shell: Float
        let infill: Float
        /// Travel, retraction and seam per separate piece, per layer.
        let pieceLayer: Float
        /// The slowest a layer is allowed to go, so it can cool.
        let minimumLayer: Float
        /// Heating, homing and the printer's own checks before the first layer.
        let start: Float

        /// X1C, P1S, P1P, P2S, H2D, H2S: Orca's path speeds, and the start-up Bambu
        /// Studio's own estimates include (its calibration routine).
        public static let bambuCoreXY = Machine(shell: 0.01061, infill: 0.008598, pieceLayer: 0.005182, minimumLayer: 12, start: 600)
        /// A1 and A1 mini.
        public static let bambuBedSlinger = Machine(shell: 0.01074, infill: 0.01276, pieceLayer: 0.02589, minimumLayer: 12, start: 360)
        /// Fast CoreXY printers from other makers (fitted on a Creality K1).
        public static let coreXY = Machine(shell: 0.01035, infill: 0.004619, pieceLayer: 0.03712, minimumLayer: 8, start: 177)
        /// Bed-slingers from other makers (fitted on a Creality Ender-3 V3).
        public static let bedSlinger = Machine(shell: 0.01077, infill: 0.01234, pieceLayer: 0.007125, minimumLayer: 8, start: 38)
    }

    /// The settings the estimate assumes, for saying so.
    public static let layerHeight: Float = 0.2
    public static let infill: Float = 0.15
    public static let walls: Float = 2

    static let lineWidth: Float = 0.45
    static let topLayers: Float = 5
    static let bottomLayers: Float = 3
    /// 1.75 mm filament.
    static let filamentArea: Float = .pi * 0.875 * 0.875

    // Fitted: slicers overlap wall lines a little, and lay infill denser than its
    // nominal percentage (and solid where it's narrow).
    static let shellMass: Float = 0.78
    static let infillMass: Float = 1.30

    /// - Parameters:
    ///   - volume: solid volume, mm³.
    ///   - surface: the surface by facing.
    ///   - height: how tall the print is, mm.
    ///   - parts: separate pieces on the plate (each adds travel every layer).
    ///   - density: filament density, g/cm³.
    ///   - machine: the kind of printer, for the time.
    public init?(volume: Float, surface: SurfaceStats, height: Float, parts: Int, density: Float, machine: Machine = .bambuCoreXY) {
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
        let work = shell / pathArea * machine.shell + infill / pathArea * machine.infill
        // Small layers are slowed so each has time to cool.
        let printing = max(work, layers * machine.minimumLayer)
        let total = printing + layers * Float(parts) * machine.pieceLayer + machine.start
        // A damaged file can still reach here with absurd sizes; no estimate then.
        guard total.isFinite, total < 1e8, mass.isFinite, mass < 1e7 else { return nil }
        seconds = Int(total.rounded())
    }
}

extension Model3D {
    /// The shape-based estimate for what's showing, for a filament of `density`
    /// (g/cm³). Each object on the plate counts as one piece.
    public func shapeEstimate(plateID: Int?, hidden: Set<Int>, density: Float, machine: PrintEstimate.Machine = .bambuCoreXY) -> PrintEstimate? {
        let shown = visibleParts(plateID: plateID, hidden: hidden)
        guard !shown.isEmpty else { return nil }
        let volume = abs(shown.reduce(0) { $0 + $1.volume })
        let surface = shown.reduce(SurfaceStats()) { $0 + $1.surface }
        let pieces = Set(shown.map(\.objectID)).count
        return PrintEstimate(volume: volume, surface: surface, height: bounds(of: shown).size.z, parts: pieces, density: density, machine: machine)
    }
}

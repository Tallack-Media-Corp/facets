import Foundation
import simd

/// An axis-aligned box. Starts empty and grows as points are added.
public struct Bounds: Sendable, Hashable {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>

    public static let empty = Bounds(min: SIMD3(repeating: .infinity), max: SIMD3(repeating: -.infinity))

    public init(min: SIMD3<Float>, max: SIMD3<Float>) {
        self.min = min
        self.max = max
    }

    public var isEmpty: Bool { min.x > max.x || min.y > max.y || min.z > max.z }
    public var size: SIMD3<Float> { isEmpty ? .zero : max - min }
    public var center: SIMD3<Float> { isEmpty ? .zero : (min + max) / 2 }
    /// Radius of the sphere that encloses the box.
    public var radius: Float { simd_length(size) / 2 }

    public mutating func add(_ point: SIMD3<Float>) {
        min = simd_min(min, point)
        max = simd_max(max, point)
    }

    public func union(_ other: Bounds) -> Bounds {
        if isEmpty { return other }
        if other.isEmpty { return self }
        return Bounds(min: simd_min(min, other.min), max: simd_max(max, other.max))
    }
}

/// A mesh's surface split by which way it faces, in mm². What a slicer does with a
/// surface depends on that: walls go round the sides, solid skins go on what faces
/// up or down. Each is projected: `side` is area × the horizontal part of the normal
/// (per layer that's the perimeter's length), `up` and `down` are area × the vertical
/// part (the footprint of the skins).
public struct SurfaceStats: Sendable, Equatable {
    public var side: Float = 0
    public var up: Float = 0
    public var down: Float = 0
    public var total: Float = 0
    /// Footprint of faces that point down more steeply than 45°: what a slicer
    /// would hold up with supports (the bed contact counts too; see `supportVolume`).
    public var overhang: Float = 0
    /// Σ overhang footprint × height, so the column of support under the overhangs
    /// is `overhangMoment − bed height × overhang`.
    public var overhangMoment: Float = 0

    public init() {}

    public static func + (a: SurfaceStats, b: SurfaceStats) -> SurfaceStats {
        var s = SurfaceStats()
        s.side = a.side + b.side
        s.up = a.up + b.up
        s.down = a.down + b.down
        s.total = a.total + b.total
        s.overhang = a.overhang + b.overhang
        s.overhangMoment = a.overhangMoment + b.overhangMoment
        return s
    }

    /// The same surface moved up by `dz`.
    func raised(by dz: Float) -> SurfaceStats {
        var s = self
        s.overhangMoment += overhang * dz
        return s
    }

    /// Volume of the support columns under the overhangs, down to a bed at `bedZ`.
    public func supportVolume(bedZ: Float) -> Float {
        max(overhangMoment - bedZ * overhang, 0)
    }

    /// Adds a triangle. Winding can't be trusted for up versus down, so the side the
    /// triangle faces is judged from the volume's sign the caller passes (`outward`).
    mutating func add(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, outward: Double) {
        let n = simd_cross(b - a, c - a) * outward
        let length = simd_length(n)
        guard length > 0 else { return }
        let area = length / 2
        let nz = n.z / length
        total += Float(area)
        side += Float(area * (1 - nz * nz).squareRoot())
        if nz > 0 { up += Float(area * nz) } else { down += Float(area * -nz) }
        if nz < -0.7071 {
            let footprint = area * -nz
            overhang += Float(footprint)
            overhangMoment += Float(footprint * (a.z + b.z + c.z) / 3)
        }
    }
}

/// Triangles in model units (millimetres). Positions are packed xyz floats so they
/// upload to the GPU as they are. Immutable once built, so it's shared freely between
/// parts that place the same mesh more than once.
public final class MeshGeometry: Sendable {
    public let positions: [Float]
    /// Nil for a triangle soup (STL), where every three positions are a triangle.
    public let indices: [UInt32]?
    public let bounds: Bounds
    /// Signed volume in cubic model units; positive for outward-facing triangles.
    public let volume: Float
    /// Surface by facing, in the mesh's own coordinates.
    public let surface: SurfaceStats

    public var vertexCount: Int { positions.count / 3 }
    public var triangleCount: Int { (indices?.count ?? vertexCount) / 3 }
    /// Bytes the geometry takes on the GPU.
    public var byteCount: Int { positions.count * 4 + (indices?.count ?? 0) * 4 }

    /// Beyond this (10 km, in model units) a coordinate is damage, not a model.
    static let coordinateLimit: Float = 1e7

    public init(positions: [Float], indices: [UInt32]? = nil) {
        let (positions, indices) = Self.sanitized(positions, indices)
        self.positions = positions
        self.indices = indices
        var bounds = Bounds.empty
        var volume: Double = 0
        positions.withUnsafeBufferPointer { p in
            let count = p.count / 3
            if let indices {
                // Only the vertices triangles use: an unused stray point isn't part of the model.
                for i in indices where Int(i) < count {
                    let v = Int(i) * 3
                    bounds.add(SIMD3(p[v], p[v + 1], p[v + 2]))
                }
            } else {
                for i in 0..<count {
                    bounds.add(SIMD3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]))
                }
            }
            func vertex(_ i: Int) -> SIMD3<Double> {
                SIMD3(Double(p[i * 3]), Double(p[i * 3 + 1]), Double(p[i * 3 + 2]))
            }
            if let indices {
                indices.withUnsafeBufferPointer { idx in
                    var t = 0
                    while t + 2 < idx.count {
                        let a = Int(idx[t]), b = Int(idx[t + 1]), c = Int(idx[t + 2])
                        if a < count, b < count, c < count {
                            volume += simd_dot(vertex(a), simd_cross(vertex(b), vertex(c)))
                        }
                        t += 3
                    }
                }
            } else {
                var t = 0
                while t + 2 < count {
                    volume += simd_dot(vertex(t), simd_cross(vertex(t + 1), vertex(t + 2)))
                    t += 3
                }
            }
        }
        self.bounds = bounds
        self.volume = Float(volume / 6)
        self.surface = Self.surface(positions: positions, indices: indices, transform: nil, outward: volume < 0 ? -1 : 1)
    }

    /// Drops triangles with a non-finite or absurdly large coordinate ("nan", "1e39"
    /// in a damaged or hostile file), which would otherwise make the size, the camera
    /// and the estimates infinite. Unchanged (and uncopied) when nothing is wrong.
    static func sanitized(_ positions: [Float], _ indices: [UInt32]?) -> ([Float], [UInt32]?) {
        let limit = coordinateLimit
        func bad(_ x: Float) -> Bool { !(abs(x) <= limit) }
        guard positions.contains(where: bad) else { return (positions, indices) }
        if let indices {
            let count = positions.count / 3
            var badVertex = [Bool](repeating: false, count: count)
            for v in 0..<count where bad(positions[v * 3]) || bad(positions[v * 3 + 1]) || bad(positions[v * 3 + 2]) {
                badVertex[v] = true
            }
            var kept: [UInt32] = []
            kept.reserveCapacity(indices.count)
            var t = 0
            while t + 2 < indices.count {
                let a = Int(indices[t]), b = Int(indices[t + 1]), c = Int(indices[t + 2])
                if a < count, b < count, c < count, !badVertex[a], !badVertex[b], !badVertex[c] {
                    kept.append(contentsOf: indices[t...(t + 2)])
                }
                t += 3
            }
            // The bad vertices stay in the array (indices refer to them by position)
            // but are zeroed so nothing downstream ever meets an infinity.
            var cleaned = positions
            for v in 0..<count where badVertex[v] {
                cleaned[v * 3] = 0; cleaned[v * 3 + 1] = 0; cleaned[v * 3 + 2] = 0
            }
            return (cleaned, kept)
        }
        var kept: [Float] = []
        kept.reserveCapacity(positions.count)
        var t = 0
        while t + 8 < positions.count {
            let triangle = positions[t..<(t + 9)]
            if !triangle.contains(where: bad) { kept.append(contentsOf: triangle) }
            t += 9
        }
        return (kept, nil)
    }

    /// Surface stats, optionally after a transform. A second pass over the triangles,
    /// as cheap as the volume pass, and only for meshes that are placed turned.
    static func surface(positions: [Float], indices: [UInt32]?, transform: simd_float4x4?, outward: Double) -> SurfaceStats {
        var stats = SurfaceStats()
        let m = transform.map { t in
            simd_double4x4(SIMD4<Double>(t.columns.0), SIMD4<Double>(t.columns.1), SIMD4<Double>(t.columns.2), SIMD4<Double>(t.columns.3))
        }
        positions.withUnsafeBufferPointer { p in
            let count = p.count / 3
            func vertex(_ i: Int) -> SIMD3<Double> {
                let v = SIMD3(Double(p[i * 3]), Double(p[i * 3 + 1]), Double(p[i * 3 + 2]))
                guard let m else { return v }
                let w = m * SIMD4(v, 1)
                return SIMD3(w.x, w.y, w.z)
            }
            if let indices {
                indices.withUnsafeBufferPointer { idx in
                    var t = 0
                    while t + 2 < idx.count {
                        let a = Int(idx[t]), b = Int(idx[t + 1]), c = Int(idx[t + 2])
                        if a < count, b < count, c < count { stats.add(vertex(a), vertex(b), vertex(c), outward: outward) }
                        t += 3
                    }
                }
            } else {
                var t = 0
                while t + 2 < count {
                    stats.add(vertex(t), vertex(t + 1), vertex(t + 2), outward: outward)
                    t += 3
                }
            }
        }
        return stats
    }
}

/// One placed mesh: a geometry, where it sits, and how it's coloured.
public struct ModelPart: Sendable, Identifiable {
    public let id: Int
    public var name: String
    public let geometry: MeshGeometry
    public let transform: simd_float4x4
    /// Linear-light RGBA from the file, if it says.
    public var color: SIMD4<Float>?
    /// The build item (3MF) this part belongs to. Parts of one object share it.
    public var objectID: Int
    /// Multi-colour painting from a slicer. Drawn a hair in front of the rest of its
    /// object, as the slicers draw paint over the mesh, so where a model has
    /// coincident faces the paint shows rather than flickering with them.
    public var isPaint: Bool
    /// World-space bounds of the transformed triangles.
    public let bounds: Bounds
    /// World-space surface by facing, for print estimates.
    public let surface: SurfaceStats

    public init(id: Int, name: String, geometry: MeshGeometry, transform: simd_float4x4 = matrix_identity_float4x4, color: SIMD4<Float>? = nil, objectID: Int = 0, isPaint: Bool = false) {
        self.id = id
        self.isPaint = isPaint
        self.name = name
        self.geometry = geometry
        self.transform = transform
        self.color = color
        self.objectID = objectID
        let linear = simd_float3x3(
            SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )
        // Moved but not turned or scaled: the mesh's own surface stats hold.
        if linear == matrix_identity_float3x3 {
            surface = geometry.surface.raised(by: transform.columns.3.z)
        } else {
            let outward: Double = geometry.volume * simd_determinant(linear) < 0 ? -1 : 1
            surface = MeshGeometry.surface(positions: geometry.positions, indices: geometry.indices, transform: transform, outward: outward)
        }
        if transform == matrix_identity_float4x4 {
            bounds = geometry.bounds
        } else {
            var b = Bounds.empty
            geometry.positions.withUnsafeBufferPointer { p in
                for i in 0..<(p.count / 3) {
                    let v = transform * SIMD4(p[i * 3], p[i * 3 + 1], p[i * 3 + 2], 1)
                    b.add(SIMD3(v.x, v.y, v.z))
                }
            }
            bounds = b
        }
    }

    /// Volume after the transform scales it.
    public var volume: Float {
        let m = simd_float3x3(
            SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )
        return geometry.volume * simd_determinant(m)
    }
}

/// A slicer plate (Bambu Studio / Orca): a named group of objects printed together.
public struct Plate: Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String?
    public let objectIDs: Set<Int>

    public init(id: Int, name: String?, objectIDs: Set<Int>) {
        self.id = id
        self.name = name
        self.objectIDs = objectIDs
    }

    public var title: String {
        if let name, !name.isEmpty { return "Plate \(id): \(name)" }
        return "Plate \(id)"
    }
}

/// A named object as the file lists it: one STL, or one 3MF build item.
public struct ModelObject: Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
}

public enum ModelFormat: String, Sendable {
    case stl = "STL"
    case asciiSTL = "STL (ASCII)"
    case threeMF = "3MF"
    case obj = "OBJ"
}

/// What a slicer worked out when it last sliced a plate (Bambu Studio and Orca save it
/// in `Metadata/slice_info.config`).
public struct SliceEstimate: Sendable, Equatable {
    public struct Filament: Sendable, Equatable {
        /// "PLA", "PETG-CF".
        public let type: String?
        /// "#00AE42".
        public let colorHex: String?
        public let meters: Float?
        public let grams: Float?

        public init(type: String?, colorHex: String?, meters: Float?, grams: Float?) {
            self.type = type
            self.colorHex = colorHex
            self.meters = meters
            self.grams = grams
        }
    }

    /// Plate number, matching `Plate.id` (1 for a single-plate project).
    public let plate: Int
    public let seconds: Int?
    public let grams: Float?
    public let filaments: [Filament]
    public let usesSupports: Bool

    public init(plate: Int, seconds: Int?, grams: Float?, filaments: [Filament], usesSupports: Bool = false) {
        self.plate = plate
        self.seconds = seconds
        self.grams = grams
        self.filaments = filaments
        self.usesSupports = usesSupports
    }

    public var meters: Float? {
        let lengths = filaments.compactMap(\.meters)
        return lengths.isEmpty ? nil : lengths.reduce(0, +)
    }

    /// Several plates' estimates as one, for "All Plates". Filaments of the same type
    /// and colour are added together.
    public static func combined(_ estimates: [SliceEstimate]) -> SliceEstimate? {
        guard let first = estimates.first else { return nil }
        if estimates.count == 1 { return first }
        func sum(_ values: [Float?]) -> Float? {
            let known = values.compactMap { $0 }
            return known.isEmpty ? nil : known.reduce(0, +)
        }
        var filaments: [Filament] = []
        for filament in estimates.flatMap(\.filaments) {
            if let index = filaments.firstIndex(where: { $0.type == filament.type && $0.colorHex == filament.colorHex }) {
                let existing = filaments[index]
                filaments[index] = Filament(type: existing.type, colorHex: existing.colorHex, meters: sum([existing.meters, filament.meters]), grams: sum([existing.grams, filament.grams]))
            } else {
                filaments.append(filament)
            }
        }
        let seconds = estimates.compactMap(\.seconds)
        return SliceEstimate(
            plate: 0,
            seconds: seconds.isEmpty ? nil : seconds.reduce(0, +),
            grams: sum(estimates.map(\.grams)),
            filaments: filaments,
            usesSupports: estimates.contains { $0.usesSupports }
        )
    }
}

/// The printer bed a slicer project was laid out on, read from the project's own
/// settings (Bambu Studio and Orca `printable_area`, PrusaSlicer `bed_shape`).
public struct SlicerBed: Sendable, Equatable {
    public let width: Float
    public let depth: Float
    /// "Bambu Lab X1 Carbon", when the project says.
    public let printer: String?
    /// Plates in the project, including empty ones; the layout depends on it.
    public let plateCount: Int
    /// Printable height in mm, when the project says (Bambu `printable_height`).
    public let height: Float?

    public init(width: Float, depth: Float, height: Float? = nil, printer: String?, plateCount: Int) {
        self.width = width
        self.depth = depth
        self.height = height
        self.printer = printer
        self.plateCount = max(plateCount, 1)
    }

    /// Bambu Studio and Orca lay plates out in a grid ⌈√n⌉ wide, rows running toward
    /// −Y, each step 1.2 bed-widths (the slicers' 1/5 plate gap). Checked against real
    /// multi-plate projects on 256 and 350 × 320 mm beds.
    public func origin(ofPlate plateID: Int) -> SIMD2<Float> {
        let index = max(plateID - 1, 0)
        let columns = Int(Float(plateCount).squareRoot().rounded(.up))
        let column = index % max(columns, 1), row = index / max(columns, 1)
        return SIMD2(Float(column) * width * 1.2, -Float(row) * depth * 1.2)
    }
}

/// Where a chosen printer bed sits under the model, and whether the model fits.
public struct BedFit: Sendable, Equatable {
    /// How far the model is over in each direction, in mm (zero where it's within).
    public struct Overflow: Sendable, Equatable {
        public let width: Float
        public let depth: Float
        public let height: Float

        public init(width: Float, depth: Float, height: Float) {
            self.width = width
            self.depth = depth
            self.height = height
        }
    }

    public enum Verdict: Sendable, Equatable {
        case fits
        /// Fits only turned a quarter turn on the bed; the outline is drawn turned.
        case fitsTurned
        case tooBig(Overflow)
        /// Small enough, but a slicer project's parts sit partly off its plate.
        case offPlate
    }

    /// The bed's corners in model coordinates (millimetres).
    public let min: SIMD2<Float>
    public let max: SIMD2<Float>
    public let verdict: Verdict

    public var fits: Bool { verdict == .fits || verdict == .fitsTurned }
}

/// Everything read from one file.
public struct Model3D: Sendable, Identifiable {
    /// New for every arrangement, so views know to redraw.
    public let id: UUID
    /// The file this came from; kept when the model is turned or laid flat.
    public let sourceID: UUID
    public let format: ModelFormat
    public let parts: [ModelPart]
    public let objects: [ModelObject]
    public let plates: [Plate]
    /// Title or application from the file's metadata, when it has one.
    public let title: String?
    public let application: String?
    /// The bed a slicer project was arranged on; nil for STL and plain 3MF.
    public let slicerBed: SlicerBed?
    /// The slicer's time and filament estimates, per plate; empty unless the project
    /// was sliced before it was saved.
    public let estimates: [SliceEstimate]

    public init(format: ModelFormat, parts: [ModelPart], objects: [ModelObject], plates: [Plate] = [], title: String? = nil, application: String? = nil, slicerBed: SlicerBed? = nil, estimates: [SliceEstimate] = [], sourceID: UUID? = nil) {
        let id = UUID()
        self.id = id
        self.sourceID = sourceID ?? id
        self.estimates = estimates
        self.format = format
        self.parts = parts
        self.objects = objects
        self.plates = plates
        self.title = title
        self.application = application
        self.slicerBed = slicerBed
    }

    /// Places a `width` × `depth` × `height` bed under what's visible and checks it
    /// fits: straight, or failing that turned a quarter turn, and tall enough (a zero
    /// height isn't checked). A slicer project keeps its real layout, the bed centred
    /// on the plate the project used; when that bed matches the project's own, parts
    /// hanging off the plate as arranged are reported too. Anything else centres the
    /// bed under the model. Nil when several plates are showing at once.
    public func bedFit(width: Float, depth: Float, height: Float = 0, plateID: Int?, hidden: Set<Int>) -> BedFit? {
        guard width > 0, depth > 0 else { return nil }
        if !plates.isEmpty, plateID == nil { return nil }
        let footprint = bounds(of: visibleParts(plateID: plateID, hidden: hidden))
        guard !footprint.isEmpty else { return nil }
        let size = footprint.size
        let tolerance: Float = 0.05

        let centre: SIMD2<Float>
        if let slicerBed {
            let origin = slicerBed.origin(ofPlate: plateID ?? 1)
            centre = origin + SIMD2(slicerBed.width, slicerBed.depth) / 2
        } else {
            centre = SIMD2(footprint.center.x, footprint.center.y)
        }
        func outline(_ w: Float, _ d: Float) -> (SIMD2<Float>, SIMD2<Float>) {
            let half = SIMD2(w, d) / 2
            return (centre - half, centre + half)
        }

        let straight = size.x <= width + tolerance && size.y <= depth + tolerance
        // A loose part can be turned on the bed; a slicer project's layout can't.
        let turned = slicerBed == nil && size.y <= width + tolerance && size.x <= depth + tolerance
        let tallEnough = height <= 0 || size.z <= height + tolerance

        if !tallEnough || (!straight && !turned) {
            // Report whichever orientation is over by less.
            let a = SIMD2(Swift.max(size.x - width, 0), Swift.max(size.y - depth, 0))
            let b = SIMD2(Swift.max(size.x - depth, 0), Swift.max(size.y - width, 0))
            let useTurned = slicerBed == nil && (b.x + b.y) < (a.x + a.y)
            let over = useTurned ? b : a
            let (lo, hi) = useTurned ? outline(depth, width) : outline(width, depth)
            let overflow = BedFit.Overflow(width: over.x, depth: over.y, height: height > 0 ? Swift.max(size.z - height, 0) : 0)
            return BedFit(min: lo, max: hi, verdict: .tooBig(overflow))
        }
        if !straight {
            let (lo, hi) = outline(depth, width)
            return BedFit(min: lo, max: hi, verdict: .fitsTurned)
        }
        let (lo, hi) = outline(width, depth)
        if let slicerBed, abs(slicerBed.width - width) < 1, abs(slicerBed.depth - depth) < 1 {
            let inside = footprint.min.x >= lo.x - 0.5 && footprint.min.y >= lo.y - 0.5
                && footprint.max.x <= hi.x + 0.5 && footprint.max.y <= hi.y + 0.5
            if !inside { return BedFit(min: lo, max: hi, verdict: .offPlate) }
        }
        return BedFit(min: lo, max: hi, verdict: .fits)
    }

    public var bounds: Bounds { bounds(of: parts) }
    public var triangleCount: Int { parts.reduce(0) { $0 + $1.geometry.triangleCount } }
    public var volume: Float { abs(parts.reduce(0) { $0 + $1.volume }) }

    public func bounds(of parts: [ModelPart]) -> Bounds {
        parts.reduce(Bounds.empty) { $0.union($1.bounds) }
    }

    /// The parts a plate shows, or all of them.
    public func parts(on plate: Plate?) -> [ModelPart] {
        guard let plate else { return parts }
        return parts.filter { plate.objectIDs.contains($0.objectID) }
    }

    /// The parts shown for a plate choice and a set of hidden objects.
    public func visibleParts(plateID: Int?, hidden: Set<Int>) -> [ModelPart] {
        let plate = plates.first { $0.id == plateID }
        return parts(on: plate).filter { !hidden.contains($0.objectID) }
    }

    /// Objects on a plate, or all of them.
    public func objects(onPlate plateID: Int?) -> [ModelObject] {
        guard let plate = plates.first(where: { $0.id == plateID }) else { return objects }
        return objects.filter { plate.objectIDs.contains($0.id) }
    }

    /// The slicer's estimate for what's showing: one plate, or every plate added up.
    public func estimate(plateID: Int?) -> SliceEstimate? {
        if let plateID { return estimates.first { $0.plate == plateID } }
        if plates.isEmpty { return estimates.first { $0.plate == 1 } ?? estimates.first }
        return SliceEstimate.combined(estimates)
    }

    /// The same model with every part turned by `rotation` about the centre of the
    /// parts shown, then set down so the lowest of them rests on the bed (z = 0) where
    /// it was. Plates, objects and estimates carry over; the slicer's bed doesn't,
    /// since its layout no longer applies.
    public func reoriented(by rotation: simd_float3x3, plateID: Int?, hidden: Set<Int>) -> Model3D {
        let shown = bounds(of: visibleParts(plateID: plateID, hidden: hidden))
        guard !shown.isEmpty else { return self }
        let pivot = shown.center
        var turn = matrix_identity_float4x4
        turn.columns.0 = SIMD4(rotation.columns.0, 0)
        turn.columns.1 = SIMD4(rotation.columns.1, 0)
        turn.columns.2 = SIMD4(rotation.columns.2, 0)
        func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
            var m = matrix_identity_float4x4
            m.columns.3 = SIMD4(t, 1)
            return m
        }
        let about = translation(pivot) * turn * translation(-pivot)
        var turned = parts.map { part in
            ModelPart(id: part.id, name: part.name, geometry: part.geometry, transform: about * part.transform, color: part.color, objectID: part.objectID, isPaint: part.isPaint)
        }
        let shownIDs = Set(visibleParts(plateID: plateID, hidden: hidden).map(\.id))
        let lowest = turned.filter { shownIDs.contains($0.id) }.reduce(Bounds.empty) { $0.union($1.bounds) }.min.z
        let drop = translation(SIMD3(0, 0, shown.min.z - lowest))
        turned = turned.map { part in
            ModelPart(id: part.id, name: part.name, geometry: part.geometry, transform: drop * part.transform, color: part.color, objectID: part.objectID, isPaint: part.isPaint)
        }
        return Model3D(format: format, parts: turned, objects: objects, plates: plates, title: title, application: application, slicerBed: nil, estimates: estimates, sourceID: sourceID)
    }

    /// The same model scaled up or down by `factor` (for a file saved in metres or
    /// inches rather than millimetres). Everything scales from the origin, so a
    /// model resting on the bed still does. The slicer's bed doesn't carry over.
    public func scaled(by factor: Float) -> Model3D {
        guard factor > 0, factor != 1 else { return self }
        var scale = matrix_identity_float4x4
        scale.columns.0.x = factor
        scale.columns.1.y = factor
        scale.columns.2.z = factor
        let resized = parts.map { part in
            ModelPart(id: part.id, name: part.name, geometry: part.geometry, transform: scale * part.transform, color: part.color, objectID: part.objectID, isPaint: part.isPaint)
        }
        return Model3D(format: format, parts: resized, objects: objects, plates: plates, title: title, application: application, slicerBed: nil, estimates: estimates, sourceID: sourceID)
    }

    /// Where a ray first meets what's showing, in world space.
    public func hit(origin: SIMD3<Float>, direction: SIMD3<Float>, plateID: Int?, hidden: Set<Int>) -> SurfaceHit? {
        var best: SurfaceHit?
        for part in visibleParts(plateID: plateID, hidden: hidden) {
            if let hit = part.hit(origin: origin, direction: direction), hit.distance < (best?.distance ?? .infinity) {
                best = hit
            }
        }
        return best
    }

    /// Unique geometries, for counting what the file actually holds.
    public var uniqueGeometryCount: Int {
        Set(parts.map { ObjectIdentifier($0.geometry) }).count
    }
}

public enum ModelError: LocalizedError, Equatable {
    case unsupportedFormat
    case emptyFile
    case corrupt(String)
    case noGeometry
    /// More than this device (or a Quick Look extension) can hold.
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "This isn't an STL, 3MF or OBJ file."
        case .emptyFile: "The file is empty."
        case .corrupt(let detail): "The file couldn't be read: \(detail)."
        case .noGeometry: "The file has no triangles to show."
        case .tooLarge: "This model is too large to show here."
        }
    }
}

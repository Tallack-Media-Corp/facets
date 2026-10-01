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

    public var vertexCount: Int { positions.count / 3 }
    public var triangleCount: Int { (indices?.count ?? vertexCount) / 3 }
    /// Bytes the geometry takes on the GPU.
    public var byteCount: Int { positions.count * 4 + (indices?.count ?? 0) * 4 }

    public init(positions: [Float], indices: [UInt32]? = nil) {
        self.positions = positions
        self.indices = indices
        var bounds = Bounds.empty
        var volume: Double = 0
        positions.withUnsafeBufferPointer { p in
            let count = p.count / 3
            for i in 0..<count {
                bounds.add(SIMD3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]))
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
    /// World-space bounds of the transformed triangles.
    public let bounds: Bounds

    public init(id: Int, name: String, geometry: MeshGeometry, transform: simd_float4x4 = matrix_identity_float4x4, color: SIMD4<Float>? = nil, objectID: Int = 0) {
        self.id = id
        self.name = name
        self.geometry = geometry
        self.transform = transform
        self.color = color
        self.objectID = objectID
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
    public let id = UUID()
    public let format: ModelFormat
    public let parts: [ModelPart]
    public let objects: [ModelObject]
    public let plates: [Plate]
    /// Title or application from the file's metadata, when it has one.
    public let title: String?
    public let application: String?
    /// The bed a slicer project was arranged on; nil for STL and plain 3MF.
    public let slicerBed: SlicerBed?

    public init(format: ModelFormat, parts: [ModelPart], objects: [ModelObject], plates: [Plate] = [], title: String? = nil, application: String? = nil, slicerBed: SlicerBed? = nil) {
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

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: "This isn't an STL or 3MF file."
        case .emptyFile: "The file is empty."
        case .corrupt(let detail): "The file couldn't be read: \(detail)."
        case .noGeometry: "The file has no triangles to show."
        }
    }
}

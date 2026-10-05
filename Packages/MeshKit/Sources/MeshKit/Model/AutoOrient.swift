import Foundation
import simd

/// Chooses the face to print on by the method of Bambu Studio's and Orca Slicer's
/// Auto Orient (libslic3r/Orient.cpp, itself after Tweaker-3), with their tuned
/// constants. Written afresh for Facets: the hull, sampling and data flow are its own.
///
/// It isn't just "the biggest flat face". Each candidate direction (the biggest
/// groups of same-facing area on the mesh and on its convex hull, plus 18 fixed
/// directions) is scored as if turned to face the plate:
/// - more area in the first layer, and a wider footprint on the hull, is better;
/// - more overhang (faces tipped more than 60° past vertical, which need support)
///   and more nearly-flat faces just off the plate (which print badly) are worse;
/// - almost no contact (under 0.1 mm²) is ruled out.
/// The lowest score wins; a tie keeps the model as it is.
public enum AutoOrient {
    // Orient.hpp's OrientParams, with min_volume off and use_low_angle_face on.
    static let tarC: Float = 0.24308070476924726
    static let tarD: Float = 0.6284515508160871
    static let relativeF: Float = 6.610621027964314
    static let contourF: Float = 0.23228623269775997
    static let bottomF: Float = 1.167152017941474
    static let bottomHullF: Float = 0.1
    static let tarLAF: Float = 0.01
    static let lafMin: Float = 0.9703
    static let lafMax: Float = 0.999
    static let firstLayer: Float = 0.2
    static let bottomMin: Float = 0.1
    /// cos(180° − 60°): a face whose normal points further down than this overhangs.
    static let ascent: Float = cos(.pi - 60 * .pi / 180)

    /// The direction that should face the plate, or nil when what's showing is best
    /// left as it is (or there's nothing to orient). In world space, so pass it to
    /// `layFlatRotation(for:)`.
    public static func downDirection(for model: Model3D, plateID: Int?, hidden: Set<Int>) -> SIMD3<Float>? {
        let parts = model.visibleParts(plateID: plateID, hidden: hidden)
        guard !parts.isEmpty else { return nil }
        let faces = Faces(parts)
        guard faces.count > 0 else { return nil }
        let hull = ConvexHull(points: faces.hullPoints(directions: 256))

        var candidates: [SIMD3<Float>] = [SIMD3(0, 0, -1)]
        candidates += faces.biggestDirections(10)
        candidates += hull.biggestDirections(14)
        candidates += supplements
        candidates = deduplicated(candidates)

        var best: (direction: SIMD3<Float>, cost: Float)?
        var current: Float?
        for direction in candidates {
            let cost = score(up: -direction, faces: faces, hull: hull)
            if simd_dot(direction, SIMD3(0, 0, -1)) > 0.9999 { current = cost }
            if best == nil || cost < best!.cost { best = (direction, cost) }
        }
        guard let best else { return nil }
        // As it sits is as good (to within rounding): leave it.
        if let current, current - best.cost <= max(abs(best.cost) * 1e-4, 1e-6) { return nil }
        // Or the winner is the face it's already on, give or take rounding in the
        // normals (a face laid flat a moment ago comes out a hair off straight down).
        if simd_dot(best.direction, SIMD3(0, 0, -1)) > cos(Float.pi / 180) { return nil }
        return best.direction
    }

    /// Orient.cpp's target function for one candidate, `up` being the direction that
    /// would point up.
    static func score(up: SIMD3<Float>, faces: Faces, hull: ConvexHull) -> Float {
        terms(up: up, faces: faces, hull: hull).cost
    }

    /// The score and what went into it.
    static func terms(up: SIMD3<Float>, faces: Faces, hull: ConvexHull) -> (cost: Float, bottom: Float, overhang: Float, lowAngle: Float, bottomHull: Float) {
        let minZ = faces.minimum(along: up)
        var firstLayer: Float = 0, halfLayer: Float = 0, overhang: Float = 0, lowAngle: Float = 0
        faces.forEach { a, b, c, area, normal in
            let zMax = max(simd_dot(a, up), simd_dot(b, up), simd_dot(c, up))
            let facing = simd_dot(normal, up)
            let inFirst = zMax < minZ + Self.firstLayer - 1e-6
            let inHalf = zMax < minZ + Self.firstLayer / 2 - 1e-6
            if inFirst { firstLayer += area }
            if inHalf { halfLayer += area }
            if facing < ascent, !inHalf { overhang += area }
            if abs(facing) > lafMin, abs(facing) < lafMax, zMax > minZ + Self.firstLayer { lowAngle += area }
        }
        let bottom = firstLayer * 0.5 + halfLayer
        let contour = 4 * sqrt(bottom)
        let bottomHull = hull.area(within: Self.firstLayer, of: minZ, along: up)
        var cost = relativeF * (overhang * tarC + tarD + tarLAF * lowAngle)
            / (tarD + contourF * contour + bottomF * bottom + bottomHullF * bottomHull)
        if bottom < bottomMin { cost += 100 }
        return (cost, bottom, overhang, lowAngle, bottomHull)
    }

    /// Orient.cpp's add_supplements: down, the four 45° tilts, the eight sides, and
    /// the four upward tilts and straight up.
    static let supplements: [SIMD3<Float>] = {
        let h: Float = 0.70710678
        return [
            SIMD3(0, 0, -1), SIMD3(h, 0, -h), SIMD3(0, h, -h), SIMD3(-h, 0, -h), SIMD3(0, -h, -h),
            SIMD3(1, 0, 0), SIMD3(h, h, 0), SIMD3(0, 1, 0), SIMD3(-h, h, 0), SIMD3(-1, 0, 0),
            SIMD3(-h, -h, 0), SIMD3(0, -1, 0), SIMD3(h, -h, 0),
            SIMD3(h, 0, h), SIMD3(0, h, h), SIMD3(-h, 0, h), SIMD3(0, -h, h), SIMD3(0, 0, 1),
        ]
    }()

    static func deduplicated(_ directions: [SIMD3<Float>]) -> [SIMD3<Float>] {
        var kept: [SIMD3<Float>] = []
        for d in directions where simd_length(d) > 0.5 {
            let n = simd_normalize(d)
            if !kept.contains(where: { simd_distance($0, n) < 1e-4 }) { kept.append(n) }
        }
        return kept
    }

    /// Facing directions with the most area behind them: normals grouped to 0.001
    /// (as Orient.cpp quantizes), each group keeping its largest face's exact normal.
    static func biggestDirections(_ count: Int, of faces: [(normal: SIMD3<Float>, area: Float)]) -> [SIMD3<Float>] {
        struct Key: Hashable { let x: Int32, y: Int32, z: Int32 }
        var groups: [Key: (total: Float, largest: Float, normal: SIMD3<Float>)] = [:]
        for face in faces where face.area > 0 {
            let key = Key(x: Int32((face.normal.x * 1000).rounded(.down)), y: Int32((face.normal.y * 1000).rounded(.down)), z: Int32((face.normal.z * 1000).rounded(.down)))
            var group = groups[key] ?? (0, 0, face.normal)
            group.total += face.area
            if face.area > group.largest { group.largest = face.area; group.normal = face.normal }
            groups[key] = group
        }
        return groups.values.sorted { $0.total > $1.total }.prefix(count).map(\.normal)
    }

    /// The visible triangles in world space, read straight from each part's mesh and
    /// transform rather than copied (a model can be millions of triangles).
    struct Faces {
        let parts: [ModelPart]
        let count: Int
        /// Past this many triangles every nth is read: the scores are sums of area, so
        /// an even sample ranks the candidates the same.
        let stride: Int

        init(_ parts: [ModelPart]) {
            self.parts = parts
            let total = parts.reduce(0) { $0 + $1.geometry.triangleCount }
            count = total
            stride = max(1, total / 1_500_000)
        }

        func forEach(_ body: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, Float, SIMD3<Float>) -> Void) {
            for part in parts {
                let m = part.transform
                let p = part.geometry.positions
                func world(_ i: Int) -> SIMD3<Float> {
                    (m * SIMD4(p[i * 3], p[i * 3 + 1], p[i * 3 + 2], 1)).xyz
                }
                func visit(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
                    let cross = simd_cross(b - a, c - a)
                    let length = simd_length(cross)
                    guard length > 0 else { return }
                    // Weighted up by the stride, so sampled sums keep their scale.
                    body(a, b, c, length / 2 * Float(stride), cross / length)
                }
                let vertexCount = p.count / 3
                if let indices = part.geometry.indices {
                    var t = 0
                    while t + 2 < indices.count {
                        let i0 = Int(indices[t]), i1 = Int(indices[t + 1]), i2 = Int(indices[t + 2])
                        if i0 < vertexCount, i1 < vertexCount, i2 < vertexCount { visit(world(i0), world(i1), world(i2)) }
                        t += 3 * stride
                    }
                } else {
                    var v = 0
                    while v + 2 < vertexCount {
                        visit(world(v), world(v + 1), world(v + 2))
                        v += 3 * stride
                    }
                }
            }
        }

        func minimum(along up: SIMD3<Float>) -> Float {
            var lowest = Float.infinity
            for part in parts {
                let m = part.transform
                let p = part.geometry.positions
                var i = 0
                while i + 2 < p.count {
                    lowest = min(lowest, simd_dot((m * SIMD4(p[i], p[i + 1], p[i + 2], 1)).xyz, up))
                    i += 3
                }
            }
            return lowest
        }

        func biggestDirections(_ count: Int) -> [SIMD3<Float>] {
            var list: [(normal: SIMD3<Float>, area: Float)] = []
            list.reserveCapacity(min(self.count, 1_500_000))
            forEach { _, _, _, area, normal in list.append((normal, area)) }
            return AutoOrient.biggestDirections(count, of: list)
        }

        /// Points for the hull: from an even sample of up to 20,000 vertices, the one
        /// furthest along each of `directions` directions spread over a sphere. Each
        /// is on the hull, so the hull is built from few, well-separated points, which
        /// keeps it quick and its arithmetic well-behaved on any mesh.
        func hullPoints(directions: Int) -> [SIMD3<Float>] {
            let vertices = parts.reduce(0) { $0 + $1.geometry.positions.count / 3 }
            let step = max(1, vertices / 20_000)
            var sample: [SIMD3<Float>] = []
            sample.reserveCapacity(min(vertices, 20_100))
            for part in parts {
                let m = part.transform
                let p = part.geometry.positions
                var v = 0
                while v * 3 + 2 < p.count {
                    sample.append((m * SIMD4(p[v * 3], p[v * 3 + 1], p[v * 3 + 2], 1)).xyz)
                    v += step
                }
            }
            guard !sample.isEmpty else { return [] }
            // A Fibonacci sphere: `directions` directions, evenly spread.
            let golden = Float.pi * (3 - sqrt(5))
            var extremes: [SIMD3<Float>] = []
            for k in 0..<directions {
                let z = 1 - 2 * (Float(k) + 0.5) / Float(directions)
                let r = sqrt(max(0, 1 - z * z))
                let direction = SIMD3(r * cos(golden * Float(k)), r * sin(golden * Float(k)), z)
                var best = sample[0]
                var bestDot = simd_dot(best, direction)
                for point in sample {
                    let d = simd_dot(point, direction)
                    if d > bestDot { bestDot = d; best = point }
                }
                extremes.append(best)
            }
            return extremes
        }
    }
}

/// A 3D convex hull, built incrementally. Given a few hundred points that are all on
/// the hull (see `hullPoints`), testing every face for each point is quick; a hard
/// limit on faces means no input can make it run on.
struct ConvexHull {
    private(set) var points: [SIMD3<Float>] = []
    /// Triangles with outward winding.
    private(set) var faces: [(Int, Int, Int)] = []

    init(points input: [SIMD3<Float>]) {
        let unique = Self.spread(input)
        guard unique.count >= 4, let start = Self.tetrahedron(unique) else { return }
        points = unique
        let (a, b, c, d) = start
        // Orient the first four faces outward from the tetrahedron's centre.
        let centre = (points[a] + points[b] + points[c] + points[d]) / 4
        for face in [(a, b, c), (a, b, d), (a, c, d), (b, c, d)] {
            faces.append(outward(face, from: centre))
        }
        let epsilon = max(Self.size(of: unique) * 1e-4, 1e-5)
        for i in points.indices where ![a, b, c, d].contains(i) {
            guard faces.count < 4_000 else {
                faces = []
                return
            }
            let p = points[i]
            let visible = faces.indices.filter { distance(of: p, from: faces[$0]) > epsilon }
            guard !visible.isEmpty else { continue }
            // The horizon: edges of visible faces whose neighbour across isn't visible.
            var edges = Set<[Int]>()
            for f in visible {
                let (x, y, z) = faces[f]
                for edge in [[x, y], [y, z], [z, x]] {
                    if edges.contains([edge[1], edge[0]]) { edges.remove([edge[1], edge[0]]) } else { edges.insert(edge) }
                }
            }
            let gone = Set(visible)
            faces = faces.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
            for edge in edges { faces.append((edge[0], edge[1], i)) }
        }
    }

    /// Facing directions with the most hull area behind them.
    func biggestDirections(_ count: Int) -> [SIMD3<Float>] {
        AutoOrient.biggestDirections(count, of: faces.compactMap { face in
            let cross = simd_cross(points[face.1] - points[face.0], points[face.2] - points[face.0])
            let length = simd_length(cross)
            return length > 0 ? (cross / length, length / 2) : nil
        })
    }

    /// Hull area lying within `height` of the plate: how wide a base the model stands on.
    func area(within height: Float, of minZ: Float, along up: SIMD3<Float>) -> Float {
        var total: Float = 0
        for face in faces {
            let a = points[face.0], b = points[face.1], c = points[face.2]
            if max(simd_dot(a, up), simd_dot(b, up), simd_dot(c, up)) < minZ + height - 1e-6 {
                total += simd_length(simd_cross(b - a, c - a)) / 2
            }
        }
        return total
    }

    private func distance(of p: SIMD3<Float>, from face: (Int, Int, Int)) -> Float {
        let a = points[face.0]
        let normal = simd_cross(points[face.1] - a, points[face.2] - a)
        let length = simd_length(normal)
        return length > 0 ? simd_dot(p - a, normal / length) : 0
    }

    private func outward(_ face: (Int, Int, Int), from centre: SIMD3<Float>) -> (Int, Int, Int) {
        distance(of: centre, from: face) > 0 ? (face.0, face.2, face.1) : face
    }

    /// Drops near-duplicate points (several directions often find the same corner).
    private static func spread(_ points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        let grid = max(size(of: points) * 1e-4, 1e-5)
        struct Cell: Hashable { let x: Int32, y: Int32, z: Int32 }
        var seen = Set<Cell>()
        return points.filter { p in
            guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { return false }
            return seen.insert(Cell(x: Int32(clamping: Int((p.x / grid).rounded())), y: Int32(clamping: Int((p.y / grid).rounded())), z: Int32(clamping: Int((p.z / grid).rounded())))).inserted
        }
    }

    private static func size(of points: [SIMD3<Float>]) -> Float {
        guard var lo = points.first else { return 1 }
        var hi = lo
        for p in points { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        return max(simd_length(hi - lo), 1e-6)
    }

    /// Four points that don't lie in one plane, far apart, to start from.
    private static func tetrahedron(_ p: [SIMD3<Float>]) -> (Int, Int, Int, Int)? {
        var a = 0, b = 0
        for i in p.indices {
            if p[i].x < p[a].x { a = i }
            if p[i].x > p[b].x { b = i }
        }
        if a == b { return nil }
        let line = simd_normalize(p[b] - p[a])
        var c = -1, far: Float = 0
        for i in p.indices {
            let offset = p[i] - p[a]
            let d = simd_length(offset - line * simd_dot(offset, line))
            if d > far { far = d; c = i }
        }
        guard c >= 0, far > 1e-6 else { return nil }
        let normal = simd_normalize(simd_cross(p[b] - p[a], p[c] - p[a]))
        var d = -1
        far = 0
        for i in p.indices {
            let h = abs(simd_dot(p[i] - p[a], normal))
            if h > far { far = h; d = i }
        }
        guard d >= 0, far > 1e-6 else { return nil }
        return (a, b, c, d)
    }
}

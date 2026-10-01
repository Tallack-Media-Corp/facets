import simd
@testable import MeshKit

/// Quadric edge-collapse simplification (Garland & Heckbert). Used only to draw the
/// wireframe icon, where a few hundred even triangles read better than clustering's
/// slivers. Collapses the cheapest edge until `target` triangles remain, refusing any
/// collapse that would flip a neighbouring triangle.
enum MeshSimplifier {
    private struct Quadric {
        var m = [Double](repeating: 0, count: 10)

        init() {}

        init(plane n: SIMD3<Double>, d: Double) {
            let a = n.x, b = n.y, c = n.z
            m = [a * a, a * b, a * c, a * d, b * b, b * c, b * d, c * c, c * d, d * d]
        }

        static func + (l: Quadric, r: Quadric) -> Quadric {
            var q = Quadric()
            for i in 0..<10 { q.m[i] = l.m[i] + r.m[i] }
            return q
        }

        func error(_ v: SIMD3<Double>) -> Double {
            let x = v.x, y = v.y, z = v.z
            return m[0] * x * x + 2 * m[1] * x * y + 2 * m[2] * x * z + 2 * m[3] * x
                + m[4] * y * y + 2 * m[5] * y * z + 2 * m[6] * y
                + m[7] * z * z + 2 * m[8] * z + m[9]
        }
    }

    private struct Candidate: Comparable {
        let cost: Double
        let u: Int, v: Int
        let stamp: Int
        static func < (l: Candidate, r: Candidate) -> Bool { l.cost < r.cost }
    }

    /// A binary min-heap; Swift has none built in.
    private struct Heap {
        var items: [Candidate] = []
        mutating func push(_ c: Candidate) {
            items.append(c)
            var i = items.count - 1
            while i > 0 {
                let p = (i - 1) / 2
                if items[i] < items[p] { items.swapAt(i, p); i = p } else { break }
            }
        }
        mutating func pop() -> Candidate? {
            guard !items.isEmpty else { return nil }
            items.swapAt(0, items.count - 1)
            let top = items.removeLast()
            var i = 0
            while true {
                let l = 2 * i + 1, r = l + 1
                var m = i
                if l < items.count, items[l] < items[m] { m = l }
                if r < items.count, items[r] < items[m] { m = r }
                if m == i { break }
                items.swapAt(i, m)
                i = m
            }
            return top
        }
    }

    static func simplify(_ geometry: MeshGeometry, target: Int) -> MeshGeometry {
        // Weld the triangle soup so neighbouring triangles share vertices.
        let p = geometry.positions
        var weld: [SIMD3<Float>: Int] = [:]
        var verts: [SIMD3<Double>] = []
        var faces: [SIMD3<Int>] = []
        let corners = geometry.indices.map { $0.map(Int.init) } ?? Array(0..<(p.count / 3))
        var index: [Int] = []
        for c in corners {
            let v = SIMD3(p[c * 3], p[c * 3 + 1], p[c * 3 + 2])
            if let i = weld[v] { index.append(i) } else {
                weld[v] = verts.count
                index.append(verts.count)
                verts.append(SIMD3<Double>(v))
            }
        }
        var t = 0
        while t + 2 < index.count {
            let f = SIMD3(index[t], index[t + 1], index[t + 2])
            if f.x != f.y, f.y != f.z, f.x != f.z { faces.append(f) }
            t += 3
        }

        var alive = [Bool](repeating: true, count: faces.count)
        var vertexAlive = [Bool](repeating: true, count: verts.count)
        var stamp = [Int](repeating: 0, count: verts.count)
        var vertexFaces = [[Int]](repeating: [], count: verts.count)
        var quadrics = [Quadric](repeating: Quadric(), count: verts.count)
        for (fi, f) in faces.enumerated() {
            for k in 0..<3 { vertexFaces[f[k]].append(fi) }
            let n = simd_cross(verts[f.y] - verts[f.x], verts[f.z] - verts[f.x])
            let len = simd_length(n)
            guard len > 1e-12 else { continue }
            let unit = n / len
            let q = Quadric(plane: unit, d: -simd_dot(unit, verts[f.x]))
            for k in 0..<3 { quadrics[f[k]] = quadrics[f[k]] + q }
        }

        func best(_ u: Int, _ v: Int) -> (Double, SIMD3<Double>) {
            let q = quadrics[u] + quadrics[v]
            let options = [verts[u], verts[v], (verts[u] + verts[v]) / 2]
            var result = (Double.infinity, options[0])
            for o in options {
                let e = q.error(o)
                if e < result.0 { result = (e, o) }
            }
            return result
        }

        var heap = Heap()
        func pushEdges(of u: Int) {
            var neighbours = Set<Int>()
            for fi in vertexFaces[u] where alive[fi] {
                for k in 0..<3 where faces[fi][k] != u { neighbours.insert(faces[fi][k]) }
            }
            for v in neighbours {
                heap.push(Candidate(cost: best(u, v).0, u: u, v: v, stamp: stamp[u] &+ stamp[v]))
            }
        }
        for u in 0..<verts.count { pushEdges(of: u) }

        var remaining = faces.count
        while remaining > target, let c = heap.pop() {
            guard vertexAlive[c.u], vertexAlive[c.v], c.stamp == stamp[c.u] &+ stamp[c.v] else { continue }
            let (_, position) = best(c.u, c.v)
            // Refuse a collapse that would turn a surviving neighbour over.
            var flips = false
            for w in [c.u, c.v] {
                for fi in vertexFaces[w] where alive[fi] {
                    let f = faces[fi]
                    if (0..<3).contains(where: { f[$0] == c.u }) && (0..<3).contains(where: { f[$0] == c.v }) { continue }
                    let a = verts[f.x], b = verts[f.y], cc = verts[f.z]
                    let before = simd_cross(b - a, cc - a)
                    let moved = (0..<3).map { f[$0] == w ? position : verts[f[$0]] }
                    let after = simd_cross(moved[1] - moved[0], moved[2] - moved[0])
                    if simd_dot(before, after) <= 0 { flips = true; break }
                }
                if flips { break }
            }
            if flips { continue }

            verts[c.u] = position
            quadrics[c.u] = quadrics[c.u] + quadrics[c.v]
            vertexAlive[c.v] = false
            for fi in vertexFaces[c.v] where alive[fi] {
                var f = faces[fi]
                if (0..<3).contains(where: { f[$0] == c.u }) {
                    alive[fi] = false
                    remaining -= 1
                    continue
                }
                for k in 0..<3 where f[k] == c.v { f[k] = c.u }
                faces[fi] = f
                vertexFaces[c.u].append(fi)
            }
            vertexFaces[c.u].removeAll { !alive[$0] }
            stamp[c.u] &+= 1
            pushEdges(of: c.u)
        }

        // Compact what's left.
        var newIndex = [Int](repeating: -1, count: verts.count)
        var positions: [Float] = []
        var indices: [UInt32] = []
        for (fi, f) in faces.enumerated() where alive[fi] {
            for k in 0..<3 {
                let v = f[k]
                if newIndex[v] < 0 {
                    newIndex[v] = positions.count / 3
                    positions += [Float(verts[v].x), Float(verts[v].y), Float(verts[v].z)]
                }
                indices.append(UInt32(newIndex[v]))
            }
        }
        return MeshGeometry(positions: positions, indices: indices)
    }
}

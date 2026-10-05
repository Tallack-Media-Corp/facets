import Foundation
import simd

/// Multi-material painting as Bambu Studio and Orca Slicer (`paint_color`) and
/// PrusaSlicer (`slic3rpe:mmu_segmentation`) save it on each 3MF triangle.
///
/// The value is the slicer's triangle-subdivision tree, as hex. Read from the last
/// character to the first, each character is one 4-bit code:
/// - low 2 bits 0: a leaf, painted with filament `code >> 2` (0 is the object's own);
///   when that is 3, the next code plus 3 is the filament;
/// - low 2 bits 1–3: the triangle is split on that many sides into 2–4 children,
///   `code >> 2` names the vertex the split is arranged around, and the children
///   follow depth first, last child first.
/// The split matches the slicers' `TriangleSelector::perform_split`, so the painted
/// regions come out where they were painted.
enum TrianglePaint {
    /// The mesh split by filament: each painted state's triangles as their own
    /// geometry. State 0 is unpainted, the object's own filament. Nil when nothing
    /// decodes, so the caller keeps the mesh as it was.
    static func split(_ geometry: MeshGeometry, paint: [Int: String]) -> [Int: MeshGeometry]? {
        guard !paint.isEmpty, let indices = geometry.indices else { return nil }
        let p = geometry.positions
        let vertexCount = p.count / 3
        // Per state: its own vertices, and where each original vertex landed in them
        // (UInt32.max for not yet), so whole triangles keep sharing vertices.
        // The map is made on first use: a state painted only in subdivided pieces
        // never needs one.
        var groups: [Int: (positions: [Float], indices: [UInt32], remap: [UInt32])] = [:]

        func whole(_ state: Int, _ a: UInt32, _ b: UInt32, _ c: UInt32) {
            var group = groups.removeValue(forKey: state) ?? ([], [], [])
            if group.remap.isEmpty { group.remap = [UInt32](repeating: .max, count: vertexCount) }
            for v in [a, b, c] {
                let mapped = group.remap[Int(v)]
                if mapped != .max {
                    group.indices.append(mapped)
                } else {
                    let mapped = UInt32(group.positions.count / 3)
                    let i = Int(v) * 3
                    group.positions.append(contentsOf: [p[i], p[i + 1], p[i + 2]])
                    group.remap[Int(v)] = mapped
                    group.indices.append(mapped)
                }
            }
            groups[state] = group
        }

        func piece(_ state: Int, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
            var group = groups.removeValue(forKey: state) ?? ([], [], [])
            let base = UInt32(group.positions.count / 3)
            for v in [a, b, c] { group.positions.append(contentsOf: [v.x, v.y, v.z]) }
            group.indices.append(contentsOf: [base, base + 1, base + 2])
            groups[state] = group
        }

        func vertex(_ v: UInt32) -> SIMD3<Float> {
            let i = Int(v) * 3
            return SIMD3(p[i], p[i + 1], p[i + 2])
        }

        var decoded = false
        let count = indices.count / 3
        for t in 0..<count {
            let a = indices[t * 3], b = indices[t * 3 + 1], c = indices[t * 3 + 2]
            guard let code = paint[t], let codes = Self.codes(code) else {
                whole(0, a, b, c)
                continue
            }
            // A plain leaf (the common case: the whole triangle one colour) keeps its
            // shared vertices.
            if codes.count == 1, codes[0] & 0b11 == 0, codes[0] >> 2 != 3 {
                whole(codes[0] >> 2, a, b, c)
                decoded = true
                continue
            }
            var pieces: [(Int, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []
            var position = 0
            if decode(codes, &position, vertex(a), vertex(b), vertex(c), depth: 0, into: &pieces) {
                for (state, x, y, z) in pieces { piece(state, x, y, z) }
                decoded = true
            } else {
                whole(0, a, b, c)
            }
        }
        guard decoded else { return nil }
        return groups.mapValues { MeshGeometry(positions: $0.positions, indices: $0.indices) }
    }

    /// The 4-bit codes in reading order: the string's characters, last first.
    static func codes(_ string: String) -> [Int]? {
        var codes: [Int] = []
        codes.reserveCapacity(string.utf8.count)
        for byte in string.utf8.reversed() {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): codes.append(Int(byte - UInt8(ascii: "0")))
            case UInt8(ascii: "A")...UInt8(ascii: "F"): codes.append(Int(byte - UInt8(ascii: "A")) + 10)
            case UInt8(ascii: "a")...UInt8(ascii: "f"): codes.append(Int(byte - UInt8(ascii: "a")) + 10)
            default: return nil
            }
        }
        return codes.isEmpty ? nil : codes
    }

    /// One node of the tree, and everything below it. False if the codes run out
    /// or nest implausibly deep (a damaged file), so the triangle is drawn whole.
    static func decode(_ codes: [Int], _ position: inout Int,
                       _ v0: SIMD3<Float>, _ v1: SIMD3<Float>, _ v2: SIMD3<Float>,
                       depth: Int, into pieces: inout [(Int, SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)]) -> Bool {
        guard depth < 24, position < codes.count else { return false }
        let code = codes[position]
        position += 1
        let sides = code & 0b11
        if sides == 0 {
            var state = code >> 2
            if state == 3 {
                guard position < codes.count else { return false }
                state = codes[position] + 3
                position += 1
            }
            pieces.append((state, v0, v1, v2))
            return true
        }
        // Rotate so the split is arranged around vertex `special`.
        let special = (code >> 2) % 3
        let v = [v0, v1, v2]
        let r0 = v[special], r1 = v[(special + 1) % 3], r2 = v[(special + 2) % 3]
        func mid(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> { (a + b) * 0.5 }
        let children: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)]
        switch sides {
        case 1:
            let m12 = mid(r1, r2)
            children = [(r0, r1, m12), (m12, r2, r0)]
        case 2:
            let m01 = mid(r0, r1), m02 = mid(r0, r2)
            children = [(r0, m01, m02), (m01, r1, m02), (r1, r2, m02)]
        default:
            let m01 = mid(r0, r1), m12 = mid(r1, r2), m20 = mid(r2, r0)
            children = [(r0, m01, m20), (m01, r1, m12), (m12, r2, m20), (m01, m12, m20)]
        }
        // Saved last child first.
        for child in children.reversed() {
            guard decode(codes, &position, child.0, child.1, child.2, depth: depth + 1, into: &pieces) else { return false }
        }
        return true
    }
}

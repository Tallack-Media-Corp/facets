import Foundation

/// Reads Wavefront OBJ geometry: vertices and faces, split into parts by `o` (or,
/// failing that, `g`) names. Polygons are fanned into triangles. Materials, normals
/// and texture coordinates are ignored; units are taken as millimetres, like STL.
public enum OBJReader {
    public static func read(_ data: Data, name: String = "Model") throws -> Model3D {
        guard !data.isEmpty else { throw ModelError.emptyFile }
        let groups = data.withUnsafeBytes { parse($0) }
        var parts: [ModelPart] = []
        var objects: [ModelObject] = []
        for group in groups where !group.indices.isEmpty {
            let id = objects.count
            let partName = group.name ?? (groups.count == 1 ? name : "Object \(id + 1)")
            let geometry = MeshGeometry(positions: group.positions, indices: group.indices)
            parts.append(ModelPart(id: id, name: partName, geometry: geometry, objectID: id))
            objects.append(ModelObject(id: id, name: partName))
        }
        guard !parts.isEmpty else { throw ModelError.noGeometry }
        return Model3D(format: .obj, parts: parts, objects: objects)
    }

    private struct Group {
        var name: String?
        var positions: [Float] = []
        var indices: [UInt32] = []
        /// File vertex index to this group's vertex index.
        var remap: [Int: UInt32] = [:]
    }

    private static func parse(_ p: UnsafeRawBufferPointer) -> [Group] {
        var vertices: [Float] = []
        var groups = [Group()]
        var usesObjectNames = false
        var polygon: [Int] = []
        let end = p.count
        var i = 0

        func lineEnd(from start: Int) -> Int {
            var j = start
            while j < end, p[j] != 0x0A, p[j] != 0x0D { j += 1 }
            return j
        }
        func rest(_ start: Int, _ stop: Int) -> String? {
            var a = start
            while a < stop, ByteScan.isSpace(p[a]) { a += 1 }
            var b = stop
            while b > a, ByteScan.isSpace(p[b - 1]) { b -= 1 }
            return a < b ? ByteScan.string(p, a..<b) : nil
        }
        func startGroup(_ name: String?) {
            if groups[groups.count - 1].indices.isEmpty {
                groups[groups.count - 1].name = name
            } else {
                groups.append(Group(name: name))
            }
        }

        while i < end {
            while i < end, ByteScan.isSpace(p[i]) { i += 1 }
            guard i < end else { break }
            let stop = lineEnd(from: i)
            let c = p[i]
            let next: UInt8 = i + 1 < stop ? p[i + 1] : 0x20
            if c == UInt8(ascii: "v"), ByteScan.isSpace(next) {
                var j = i + 1
                if let x = ByteScan.parseFloat(p, &j, end: stop),
                   let y = ByteScan.parseFloat(p, &j, end: stop),
                   let z = ByteScan.parseFloat(p, &j, end: stop) {
                    vertices.append(contentsOf: [x, y, z])
                } else {
                    vertices.append(contentsOf: [0, 0, 0])
                }
            } else if c == UInt8(ascii: "f"), ByteScan.isSpace(next) {
                polygon.removeAll(keepingCapacity: true)
                let count = vertices.count / 3
                var j = i + 1
                while j < stop {
                    while j < stop, ByteScan.isSpace(p[j]) { j += 1 }
                    guard j < stop else { break }
                    // "12", "12/4", "12//7" or "12/4/7": the first number is the vertex.
                    var k = j
                    var negative = false
                    if p[k] == UInt8(ascii: "-") { negative = true; k += 1 }
                    var value = 0
                    var digits = 0
                    while k < stop, p[k] >= 0x30, p[k] <= 0x39 {
                        // Past 10 digits it's no index this file has; stop before it overflows.
                        if digits < 10 { value = value * 10 + Int(p[k] - 0x30) } else { value = Int.max / 2 }
                        digits += 1
                        k += 1
                    }
                    while k < stop, !ByteScan.isSpace(p[k]) { k += 1 }
                    j = k
                    guard digits > 0 else { continue }
                    let index = negative ? count - value : value - 1
                    if index >= 0, index < count { polygon.append(index) }
                }
                guard polygon.count >= 3 else { i = stop; continue }
                var group = groups.removeLast()
                func local(_ index: Int) -> UInt32 {
                    if let existing = group.remap[index] { return existing }
                    let new = UInt32(group.positions.count / 3)
                    group.positions.append(contentsOf: vertices[(index * 3)..<(index * 3 + 3)])
                    group.remap[index] = new
                    return new
                }
                let first = local(polygon[0])
                for t in 1..<(polygon.count - 1) {
                    group.indices.append(contentsOf: [first, local(polygon[t]), local(polygon[t + 1])])
                }
                groups.append(group)
            } else if c == UInt8(ascii: "o"), ByteScan.isSpace(next) {
                usesObjectNames = true
                startGroup(rest(i + 1, stop))
            } else if c == UInt8(ascii: "g"), ByteScan.isSpace(next), !usesObjectNames {
                startGroup(rest(i + 1, stop))
            }
            i = stop
        }
        return groups
    }
}

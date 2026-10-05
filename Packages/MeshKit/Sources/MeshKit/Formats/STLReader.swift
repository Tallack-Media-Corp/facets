import Foundation

/// Reads binary and ASCII STL. Coordinates are taken as millimetres, which is what
/// every slicer assumes.
public enum STLReader {
    public static func read(_ data: Data, name: String = "Model") throws -> Model3D {
        guard !data.isEmpty else { throw ModelError.emptyFile }
        let (positions, isASCII) = try data.withUnsafeBytes { raw -> ([Float], Bool) in
            if isBinary(raw) {
                return (try readBinary(raw), false)
            }
            return (try readASCII(raw), true)
        }
        guard !positions.isEmpty else { throw ModelError.noGeometry }
        let geometry = MeshGeometry(positions: positions)
        let part = ModelPart(id: 0, name: name, geometry: geometry)
        return Model3D(
            format: isASCII ? .asciiSTL : .stl,
            parts: [part],
            objects: [ModelObject(id: 0, name: name)]
        )
    }

    /// Binary unless the size disagrees with the triangle count and the text reads
    /// like ASCII. Many binary files start with "solid" in the header, so the prefix
    /// alone proves nothing.
    static func isBinary(_ raw: UnsafeRawBufferPointer) -> Bool {
        guard raw.count >= 84 else { return false }
        let count = Int(raw.loadUnaligned(fromByteOffset: 80, as: UInt32.self).littleEndian)
        let expected = 84 + count * 50
        if expected == raw.count { return true }
        let looksASCII = startsWithSolid(raw) && containsFacet(raw)
        if looksASCII { return false }
        // Some exporters pad the end; accept a file at least as long as promised.
        return count > 0 && expected <= raw.count
    }

    private static func startsWithSolid(_ raw: UnsafeRawBufferPointer) -> Bool {
        var i = 0
        while i < raw.count, ByteScan.isSpace(raw[i]) { i += 1 }
        return i + 5 <= raw.count && ByteScan.equals(raw, i..<(i + 5), "solid")
    }

    private static func containsFacet(_ raw: UnsafeRawBufferPointer) -> Bool {
        let window = min(raw.count, 4096)
        let needle = Array("facet".utf8)
        guard window >= needle.count else { return false }
        for i in 0...(window - needle.count) {
            var match = true
            for k in 0..<needle.count where raw[i + k] != needle[k] {
                match = false
                break
            }
            if match { return true }
        }
        return false
    }

    private static func readBinary(_ raw: UnsafeRawBufferPointer) throws -> [Float] {
        let declared = Int(raw.loadUnaligned(fromByteOffset: 80, as: UInt32.self).littleEndian)
        let count = min(declared, (raw.count - 84) / 50)
        guard count > 0 else { throw ModelError.noGeometry }
        var positions: [Float] = []
        positions.reserveCapacity(count * 9)
        var triangle = [Float](repeating: 0, count: 9)
        for t in 0..<count {
            // Skip the 12-byte normal; it's recomputed from the triangle.
            let base = 84 + t * 50 + 12
            var finite = true
            for k in 0..<9 {
                let value = Float(bitPattern: raw.loadUnaligned(fromByteOffset: base + k * 4, as: UInt32.self).littleEndian)
                if !value.isFinite { finite = false }
                triangle[k] = value
            }
            if finite { positions.append(contentsOf: triangle) }
        }
        return positions
    }

    private static func readASCII(_ raw: UnsafeRawBufferPointer) throws -> [Float] {
        var positions: [Float] = []
        positions.reserveCapacity(raw.count / 25)
        let end = raw.count
        let v = UInt8(ascii: "v")
        var i = 0
        // Every "vertex x y z" line adds a point; the facet structure around it is
        // redundant and often malformed, so it isn't checked.
        while i + 6 < end {
            if raw[i] == v, ByteScan.equals(raw, i..<(i + 6), "vertex"), i == 0 || ByteScan.isSpace(raw[i - 1]) {
                i += 6
                // "nan", "-nan(ind)" or "1.#QNAN" from some exporters: keep the vertex as
                // NaN so its triangle is dropped (MeshGeometry.sanitized), not the file.
                let x = ByteScan.parseFloat(raw, &i, end: end)
                let y = x == nil ? nil : ByteScan.parseFloat(raw, &i, end: end)
                let z = y == nil ? nil : ByteScan.parseFloat(raw, &i, end: end)
                if let x, let y, let z {
                    positions.append(x)
                    positions.append(y)
                    positions.append(z)
                } else {
                    positions.append(contentsOf: [Float.nan, .nan, .nan])
                    while i < end, raw[i] != UInt8(ascii: "\n") { i += 1 }
                }
            } else {
                i += 1
            }
        }
        // A file cut short leaves a partial triangle; drop it.
        let whole = positions.count - positions.count % 9
        if whole != positions.count { positions.removeLast(positions.count - whole) }
        return positions
    }
}

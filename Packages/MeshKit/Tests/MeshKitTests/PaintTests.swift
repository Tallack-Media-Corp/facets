import Foundation
import Testing
import simd
@testable import MeshKit

/// Multi-material painting (paint_color / mmu_segmentation) decoding.
struct PaintTests {
    private let triangle = MeshGeometry(positions: [0, 0, 0, 4, 0, 0, 0, 4, 0], indices: [0, 1, 2])

    private func area(_ g: MeshGeometry) -> Float {
        var total: Float = 0
        let p = g.positions, idx = g.indices ?? []
        var t = 0
        while t + 2 < idx.count {
            func v(_ i: UInt32) -> SIMD3<Float> { SIMD3(p[Int(i) * 3], p[Int(i) * 3 + 1], p[Int(i) * 3 + 2]) }
            total += simd_length(simd_cross(v(idx[t + 1]) - v(idx[t]), v(idx[t + 2]) - v(idx[t]))) / 2
            t += 3
        }
        return total
    }

    @Test func wholeTrianglePainted() throws {
        // "8": one code, 0b1000: a leaf in filament 2.
        let split = try #require(TrianglePaint.split(triangle, paint: [0: "8"]))
        #expect(Array(split.keys) == [2])
        #expect(split[2]?.triangleCount == 1)
    }

    @Test func extendedFilamentNumber() throws {
        // Read last character first: "C" (leaf, state 3 means "next code + 3"), then 2: filament 5.
        let split = try #require(TrianglePaint.split(triangle, paint: [0: "2C"]))
        #expect(Array(split.keys) == [5])
    }

    @Test func fourWaySplitKeepsTheArea() throws {
        // "3" splits on all three sides into four; the children, last first, are
        // filament 1, 0, 2, 1 (codes 4, 0, 8, 4 read from the end).
        let split = try #require(TrianglePaint.split(triangle, paint: [0: "48043"]))
        let total = split.values.reduce(0) { $0 + area($1) }
        #expect(abs(total - 8) < 1e-4)
        #expect(split[1]?.triangleCount == 2)
        #expect(split[2]?.triangleCount == 1)
        #expect(split[0]?.triangleCount == 1)
        // The middle triangle is the first child read (saved last).
        #expect(abs(area(try #require(split[1])) - 4) < 1e-4)
    }

    @Test func damagedCodesLeaveTheTriangleWhole() {
        // A split with no children following.
        #expect(TrianglePaint.split(triangle, paint: [0: "3"]) == nil)
        #expect(TrianglePaint.split(triangle, paint: [0: "zz"]) == nil)
    }
}

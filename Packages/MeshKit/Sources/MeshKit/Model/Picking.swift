import Foundation
import simd

/// A point where a ray met a model's surface, in world space (millimetres).
public struct SurfaceHit: Sendable, Equatable {
    public let point: SIMD3<Float>
    /// The face's normal, pointing back toward where the ray came from.
    public let normal: SIMD3<Float>
    /// The corners of the face that was hit, for snapping to a vertex.
    public let corners: [SIMD3<Float>]
    /// Distance along the ray.
    public let distance: Float
    public let partID: Int
}

extension ModelPart {
    /// The nearest face a ray crosses, if any. Brute force over the part's
    /// triangles after a bounding-box check: a tap is one ray, so even a million
    /// triangles is a few milliseconds.
    public func hit(origin: SIMD3<Float>, direction: SIMD3<Float>) -> SurfaceHit? {
        guard Self.crosses(bounds, origin: origin, direction: direction) else { return nil }
        let inverse = transform.inverse
        let localOrigin = (inverse * SIMD4(origin, 1)).xyz
        let localDirection = (inverse * SIMD4(direction, 0)).xyz

        var bestT = Float.infinity
        var best: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)?
        geometry.positions.withUnsafeBufferPointer { p in
            func vertex(_ i: Int) -> SIMD3<Float> { SIMD3(p[i * 3], p[i * 3 + 1], p[i * 3 + 2]) }
            func test(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
                // Möller–Trumbore, both faces: printed parts' winding can't be trusted.
                let e1 = b - a, e2 = c - a
                let h = simd_cross(localDirection, e2)
                let det = simd_dot(e1, h)
                guard abs(det) > 1e-12 else { return }
                let f = 1 / det
                let s = localOrigin - a
                let u = f * simd_dot(s, h)
                guard u >= 0, u <= 1 else { return }
                let q = simd_cross(s, e1)
                let v = f * simd_dot(localDirection, q)
                guard v >= 0, u + v <= 1 else { return }
                let t = f * simd_dot(e2, q)
                if t > 1e-6, t < bestT {
                    bestT = t
                    best = (a, b, c)
                }
            }
            let count = p.count / 3
            if let indices = geometry.indices {
                indices.withUnsafeBufferPointer { idx in
                    var i = 0
                    while i + 2 < idx.count {
                        let a = Int(idx[i]), b = Int(idx[i + 1]), c = Int(idx[i + 2])
                        if a < count, b < count, c < count { test(vertex(a), vertex(b), vertex(c)) }
                        i += 3
                    }
                }
            } else {
                var i = 0
                while i + 2 < count {
                    test(vertex(i), vertex(i + 1), vertex(i + 2))
                    i += 3
                }
            }
        }
        guard let (a, b, c) = best else { return nil }
        let world = { (v: SIMD3<Float>) in (self.transform * SIMD4(v, 1)).xyz }
        let corners = [world(a), world(b), world(c)]
        let point = world(localOrigin + localDirection * bestT)
        var normal = simd_cross(corners[1] - corners[0], corners[2] - corners[0])
        let length = simd_length(normal)
        normal = length > 0 ? normal / length : SIMD3(0, 0, 1)
        if simd_dot(normal, direction) > 0 { normal = -normal }
        return SurfaceHit(point: point, normal: normal, corners: corners, distance: simd_distance(origin, point), partID: id)
    }

    /// Slab test: does the ray pass through the box at all?
    static func crosses(_ box: Bounds, origin: SIMD3<Float>, direction: SIMD3<Float>) -> Bool {
        guard !box.isEmpty else { return false }
        var near = -Float.infinity, far = Float.infinity
        for axis in 0..<3 {
            let o = origin[axis], d = direction[axis]
            if abs(d) < 1e-12 {
                if o < box.min[axis] || o > box.max[axis] { return false }
                continue
            }
            var t1 = (box.min[axis] - o) / d
            var t2 = (box.max[axis] - o) / d
            if t1 > t2 { swap(&t1, &t2) }
            near = max(near, t1)
            far = min(far, t2)
            if near > far { return false }
        }
        return far >= 0
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

/// The rotation that turns `normal` to face straight down (−Z), so the face it
/// belongs to rests on the bed.
public func layFlatRotation(for normal: SIMD3<Float>) -> simd_float3x3 {
    let from = simd_normalize(normal)
    let to = SIMD3<Float>(0, 0, -1)
    let d = simd_dot(from, to)
    if d > 0.9999 { return matrix_identity_float3x3 }
    if d < -0.9999 {
        // Facing straight up: half a turn about X.
        return simd_float3x3(simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0)))
    }
    return simd_float3x3(simd_quatf(from: from, to: to))
}

/// A quarter turn about one of the bed's axes.
public func quarterTurn(about axis: SIMD3<Float>, clockwise: Bool = false) -> simd_float3x3 {
    simd_float3x3(simd_quatf(angle: clockwise ? -.pi / 2 : .pi / 2, axis: simd_normalize(axis)))
}

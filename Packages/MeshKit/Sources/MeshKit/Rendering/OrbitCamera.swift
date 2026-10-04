import Foundation
import simd

/// A turntable camera around a target point, with Z up as printers have it.
public struct OrbitCamera: Sendable, Equatable {
    public var target: SIMD3<Float> = .zero
    /// Angle around Z, radians. -π/2 looks from the front (−Y) toward the back.
    public var yaw: Float = -.pi / 2 + .pi / 6
    /// Elevation above the XY plane, radians.
    public var pitch: Float = .pi / 7
    public var distance: Float = 100
    /// Vertical field of view, radians.
    public var fieldOfView: Float = 30 * .pi / 180

    public init() {}

    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case isometric, front, back, left, right, top, bottom

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .isometric: "Isometric"
            case .front: "Front"
            case .back: "Back"
            case .left: "Left"
            case .right: "Right"
            case .top: "Top"
            case .bottom: "Bottom"
            }
        }

        var angles: (yaw: Float, pitch: Float) {
            switch self {
            case .isometric: (-.pi / 2 + .pi / 6, .pi / 7)
            case .front: (-.pi / 2, 0)
            case .back: (.pi / 2, 0)
            case .left: (.pi, 0)
            case .right: (0, 0)
            case .top: (-.pi / 2, Self.maxPitch)
            case .bottom: (-.pi / 2, -Self.maxPitch)
            }
        }

        static let maxPitch: Float = .pi / 2 - 0.001
    }

    public var eye: SIMD3<Float> {
        let c = cos(pitch)
        return target + distance * SIMD3(c * cos(yaw), c * sin(yaw), sin(pitch))
    }

    /// The camera's right and up directions in world space, for panning.
    /// The camera's right and up directions in world space, for panning.
    ///
    /// Right comes straight from the yaw rather than from crossing the view direction
    /// with world up: looking straight down or up those are parallel, and a fallback
    /// up would lock the view square whichever way the model had been turned.
    public var basis: (right: SIMD3<Float>, up: SIMD3<Float>) {
        let forward = simd_normalize(target - eye)
        let right = SIMD3<Float>(-sin(yaw), cos(yaw), 0)
        let up = simd_cross(right, forward)
        return (right, up)
    }

    public var viewMatrix: simd_float4x4 {
        let eye = eye
        let f = simd_normalize(target - eye)
        let (s, u) = basis
        return simd_float4x4(
            SIMD4(s.x, u.x, -f.x, 0),
            SIMD4(s.y, u.y, -f.y, 0),
            SIMD4(s.z, u.z, -f.z, 0),
            SIMD4(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        )
    }

    /// Perspective with Metal's 0…1 depth. Near and far follow the scene so depth
    /// precision holds from a 5 mm clip to a 1 m print bed.
    public func projectionMatrix(aspect: Float, sceneRadius: Float) -> simd_float4x4 {
        let radius = max(sceneRadius, 0.001)
        let near = max(distance - radius * 3, distance * 0.01, radius * 0.0005)
        let far = distance + radius * 4
        let ys = 1 / tan(fieldOfView / 2)
        let xs = ys / max(aspect, 0.0001)
        let zs = far / (near - far)
        return simd_float4x4(
            SIMD4(xs, 0, 0, 0),
            SIMD4(0, ys, 0, 0),
            SIMD4(0, 0, zs, -1),
            SIMD4(0, 0, zs * near, 0)
        )
    }

    /// Points at the box and backs off until its bounding sphere fits the view.
    public mutating func fit(_ bounds: Bounds, aspect: Float, margin: Float = 1.12) {
        guard !bounds.isEmpty else { return }
        target = bounds.center
        let radius = max(bounds.radius, 0.01)
        let vertical = fieldOfView
        let horizontal = 2 * atan(tan(fieldOfView / 2) * max(aspect, 0.0001))
        distance = radius / sin(min(vertical, horizontal) / 2) * margin
    }

    /// Frames the box itself rather than its bounding sphere, so a thumbnail fills its
    /// square. Perspective makes this nonlinear; a few passes converge.
    /// With `recenter` off the target stays on the model's centre, so orbiting doesn't
    /// wobble; only the distance changes.
    /// `including` adds points that must stay in view too, such as a bed's corners.
    public mutating func fitTightly(_ parts: [ModelPart], aspect: Float, fill: Float = 0.9, recenter: Bool = true, including extra: [SIMD3<Float>] = []) {
        var bounds = parts.reduce(Bounds.empty) { $0.union($1.bounds) }
        guard !bounds.isEmpty else { return }
        for point in extra { bounds.add(point) }
        fit(bounds, aspect: aspect, margin: 1)
        // A sample of the real vertices: a round part's box corners stick far out of
        // its silhouette.
        let total = parts.reduce(0) { $0 + $1.geometry.vertexCount }
        let stride = max(1, total / 20_000)
        var corners: [SIMD3<Float>] = extra
        corners.reserveCapacity(total / stride + 1 + extra.count)
        for part in parts {
            part.geometry.positions.withUnsafeBufferPointer { p in
                var i = 0
                while i < p.count / 3 {
                    let v = part.transform * SIMD4(p[i * 3], p[i * 3 + 1], p[i * 3 + 2], 1)
                    corners.append(SIMD3(v.x, v.y, v.z))
                    i += stride
                }
            }
        }
        for _ in 0..<6 {
            let viewProjection = projectionMatrix(aspect: aspect, sceneRadius: bounds.radius) * viewMatrix
            var minP = SIMD2<Float>(repeating: .infinity), maxP = SIMD2<Float>(repeating: -.infinity)
            for corner in corners {
                let p = viewProjection * SIMD4(corner, 1)
                guard p.w > 0 else { return }
                let ndc = SIMD2(p.x, p.y) / p.w
                minP = simd_min(minP, ndc)
                maxP = simd_max(maxP, ndc)
            }
            let extent: Float
            if recenter {
                let center = (minP + maxP) / 2
                extent = max((maxP.x - minP.x) / 2, (maxP.y - minP.y) / 2)
                let (right, up) = basis
                let halfHeight = tan(fieldOfView / 2) * distance
                target += right * center.x * halfHeight * aspect + up * center.y * halfHeight
            } else {
                extent = max(-minP.x, maxP.x, -minP.y, maxP.y)
            }
            guard extent > 0.0001 else { return }
            distance *= extent / fill
        }
    }

    public mutating func apply(_ preset: Preset) {
        (yaw, pitch) = preset.angles
    }

    public mutating func orbit(dx: Float, dy: Float) {
        yaw -= dx
        pitch = min(max(pitch + dy, -Preset.maxPitch), Preset.maxPitch)
    }

    public mutating func pan(dx: Float, dy: Float) {
        let (right, up) = basis
        target += (-right * dx + up * dy) * distance
    }

    public mutating func zoom(by factor: Float, sceneRadius: Float) {
        let radius = max(sceneRadius, 0.01)
        distance = min(max(distance / factor, radius * 0.05), radius * 40)
    }

    /// Eases toward another camera; yaw takes the short way round.
    public func interpolated(to other: OrbitCamera, _ t: Float) -> OrbitCamera {
        var result = self
        var dyaw = (other.yaw - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if dyaw > .pi { dyaw -= 2 * .pi }
        if dyaw < -.pi { dyaw += 2 * .pi }
        result.yaw = yaw + dyaw * t
        result.pitch = pitch + (other.pitch - pitch) * t
        result.distance = distance * pow(other.distance / max(distance, 0.0001), t)
        result.target = target + (other.target - target) * t
        return result
    }
}

import Foundation
import Testing
import simd
@testable import MeshKit

/// Auto Orient (the Bambu Studio / Orca Slicer method) on shapes with a known answer.
struct AutoOrientTests {
    /// A box from its corners, as 12 triangles wound outward.
    private func box(_ size: SIMD3<Float>) -> MeshGeometry {
        let (x, y, z) = (size.x, size.y, size.z)
        let v: [SIMD3<Float>] = [[0, 0, 0], [x, 0, 0], [x, y, 0], [0, y, 0], [0, 0, z], [x, 0, z], [x, y, z], [0, y, z]]
        let faces: [[Int]] = [[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7], [0, 1, 5], [0, 5, 4], [1, 2, 6], [1, 6, 5], [2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7]]
        return MeshGeometry(positions: v.flatMap { [$0.x, $0.y, $0.z] }, indices: faces.flatMap { $0.map(UInt32.init) })
    }

    /// A square pyramid, base on z = 0 and apex above.
    private func pyramid() -> MeshGeometry {
        let v: [SIMD3<Float>] = [[0, 0, 0], [20, 0, 0], [20, 20, 0], [0, 20, 0], [10, 10, 30]]
        let faces: [[Int]] = [[0, 2, 1], [0, 3, 2], [0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4]]
        return MeshGeometry(positions: v.flatMap { [$0.x, $0.y, $0.z] }, indices: faces.flatMap { $0.map(UInt32.init) })
    }

    private func model(_ geometry: MeshGeometry, turned rotation: simd_quatf) -> Model3D {
        var transform = simd_float4x4(rotation)
        transform.columns.3 = SIMD4(5, 5, 5, 1)
        return Model3D(format: .stl, parts: [ModelPart(id: 0, name: "Test", geometry: geometry, transform: transform)], objects: [ModelObject(id: 0, name: "Test")])
    }

    @Test func standingPlateLiesOnItsBroadFace() throws {
        // A 60 × 40 × 2 mm plate stood up on its long edge.
        let m = model(box(SIMD3(60, 40, 2)), turned: simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0)))
        let down = try #require(AutoOrient.downDirection(for: m, plateID: nil, hidden: []))
        // Its broad face's normal is ±Y in the world after that turn.
        #expect(abs(down.y) > 0.99)
    }

    @Test func pyramidOnItsTipTurnsOntoItsBase() throws {
        let m = model(pyramid(), turned: simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0)))
        let down = try #require(AutoOrient.downDirection(for: m, plateID: nil, hidden: []))
        // Upside down, the base faces up: it should be turned to face down.
        #expect(down.z > 0.99)
    }

    @Test func aGoodOrientationIsLeftAlone() {
        let m = model(pyramid(), turned: simd_quatf(angle: 0, axis: SIMD3(0, 0, 1)))
        #expect(AutoOrient.downDirection(for: m, plateID: nil, hidden: []) == nil)
    }

    @Test func aSecondAutoLeavesItWhereTheFirstPutIt() throws {
        let m = model(box(SIMD3(60, 40, 2)), turned: simd_quatf(angle: 1.1, axis: simd_normalize(SIMD3(1, 0.4, 0.2))))
        let down = try #require(AutoOrient.downDirection(for: m, plateID: nil, hidden: []))
        let turned = m.reoriented(by: layFlatRotation(for: down), plateID: nil, hidden: [])
        #expect(AutoOrient.downDirection(for: turned, plateID: nil, hidden: []) == nil)
        #expect(turned.bounds.size.z < 2.01)
    }

    @Test func nothingVisibleIsNothingToDo() {
        let m = model(pyramid(), turned: simd_quatf(angle: 0, axis: SIMD3(0, 0, 1)))
        #expect(AutoOrient.downDirection(for: m, plateID: nil, hidden: [0]) == nil)
    }
}

/// MESHKIT_ORIENT_FILE=<path>: times the hull and the scoring on a real model.
private func say(_ items: Any...) {
    FileHandle.standardError.write((items.map { "\($0)" }.joined(separator: " ") + "\n").data(using: .utf8)!)
}

struct AutoOrientTiming {
    @Test func timesARealModel() throws {
        guard let path = ProcessInfo.processInfo.environment["MESHKIT_ORIENT_FILE"] else { return }
        let model = try ModelLoader.load(URL(fileURLWithPath: path))
        say("ORIENT loaded", model.triangleCount, "triangles")
        let parts = model.visibleParts(plateID: model.plates.first?.id, hidden: [])
        var t = Date()
        let faces = AutoOrient.Faces(parts)
        let sample = faces.hullPoints(directions: 256)
        say("ORIENT sample", sample.count, "points in", Date().timeIntervalSince(t))
        t = Date()
        let hull = ConvexHull(points: sample)
        say("ORIENT hull", hull.faces.count, "faces in", Date().timeIntervalSince(t))
        t = Date()
        _ = faces.biggestDirections(10)
        say("ORIENT directions in", Date().timeIntervalSince(t))
        t = Date()
        _ = AutoOrient.score(up: SIMD3(0, 0, 1), faces: faces, hull: hull)
        say("ORIENT one score in", Date().timeIntervalSince(t), "for", faces.count, "triangles")
        let down = AutoOrient.downDirection(for: model, plateID: model.plates.first?.id, hidden: [])
        if let down {
            let turned = model.reoriented(by: layFlatRotation(for: down), plateID: model.plates.first?.id, hidden: [])
            say("ORIENT again", AutoOrient.downDirection(for: turned, plateID: turned.plates.first?.id, hidden: []).map { "\($0)" } ?? "nil (already best)")
        }
        for (label, d) in [("as is", SIMD3<Float>(0, 0, -1))] + (down.map { [("chosen", $0)] } ?? []) {
            let r = AutoOrient.terms(up: -d, faces: faces, hull: hull)
            say("ORIENT", label, d, "cost", r.cost, "bottom", r.bottom, "overhang", r.overhang, "lowAngle", r.lowAngle, "hull", r.bottomHull)
        }
    }
}

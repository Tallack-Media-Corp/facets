import Foundation
import Testing
import simd
@testable import MeshKit

// MARK: - OBJ

@Suite struct OBJTests {
    @Test func readsQuadsNegativeIndicesAndObjects() throws {
        let text = """
        # a unit square as a quad, then a triangle using relative indices
        o Square
        v 0 0 0
        v 10 0 0
        v 10 10 0
        v 0 10 0
        f 1/1/1 2/2/1 3/3/1 4/4/1
        o Tri
        v 0 0 5
        v 5 0 5
        v 0 5 5
        f -3 -2 -1
        """
        let model = try ModelLoader.load(Data(text.utf8), name: "File", fileExtension: "obj")
        #expect(model.format == .obj)
        #expect(model.objects.map(\.name) == ["Square", "Tri"])
        #expect(model.parts[0].geometry.triangleCount == 2)
        #expect(model.parts[0].geometry.vertexCount == 4)
        #expect(model.parts[1].geometry.triangleCount == 1)
        #expect(model.bounds.max == SIMD3(10, 10, 5))
    }

    @Test func singleUnnamedObjectTakesTheFileName() throws {
        let text = "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n"
        let model = try ModelLoader.load(Data(text.utf8), name: "Bracket", fileExtension: "obj")
        #expect(model.objects.map(\.name) == ["Bracket"])
    }

    @Test func noFacesFails() {
        #expect(throws: ModelError.self) { try ModelLoader.load(Data("v 0 0 0\n".utf8), name: "x", fileExtension: "obj") }
    }
}

// MARK: - Slicer estimates

@Suite struct SliceEstimateTests {
    private let model3D = """
    <?xml version="1.0"?>
    <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
     <resources><object id="1" type="model">\(cubeMeshXML())</object></resources>
     <build><item objectid="1"/></build>
    </model>
    """

    private let sliceInfo = """
    <?xml version="1.0" encoding="UTF-8"?>
    <config>
      <plate>
        <metadata key="index" value="1"/>
        <metadata key="prediction" value="2915"/>
        <metadata key="weight" value="6.45"/>
        <metadata key="support_used" value="false"/>
        <object identify_id="1" name="Roller" skipped="false" />
        <filament id="1" type="PLA" color="#00AE42" used_m="2.13" used_g="6.45" />
      </plate>
      <plate>
        <metadata key="index" value="2"/>
        <metadata key="prediction" value="1890"/>
        <metadata key="weight" value="3.33"/>
        <metadata key="support_used" value="true"/>
        <filament id="1" type="PLA" color="#00AE42" used_m="1.10" used_g="3.33" />
        <filament id="2" type="PETG" color="#FFFFFF" used_m="0.50" used_g="1.00" />
      </plate>
      <plate>
        <metadata key="index" value="3"/>
      </plate>
    </config>
    """

    @Test func readsEachSlicedPlate() throws {
        let model = try ModelLoader.load(zip([("_rels/.rels", rels), ("3D/3dmodel.model", model3D), ("Metadata/slice_info.config", sliceInfo)]), name: "File")
        #expect(model.estimates.count == 2, "plate 3 was never sliced")
        let first = try #require(model.estimate(plateID: 1))
        #expect(first.seconds == 2915)
        #expect(first.grams == 6.45)
        #expect(first.filaments == [.init(type: "PLA", colorHex: "#00AE42", meters: 2.13, grams: 6.45)])
        #expect(!first.usesSupports)
        #expect(model.estimate(plateID: 2)?.usesSupports == true)
    }

    @Test func allPlatesAddUp() throws {
        let estimates = [
            SliceEstimate(plate: 1, seconds: 100, grams: 2, filaments: [.init(type: "PLA", colorHex: "#00AE42", meters: 1, grams: 2)]),
            SliceEstimate(plate: 2, seconds: 50, grams: 3, filaments: [.init(type: "PLA", colorHex: "#00AE42", meters: 0.5, grams: 1), .init(type: "PETG", colorHex: "#FFFFFF", meters: 1, grams: 2)]),
        ]
        let total = try #require(SliceEstimate.combined(estimates))
        #expect(total.seconds == 150)
        #expect(total.grams == 5)
        #expect(total.filaments.count == 2)
        #expect(total.filaments[0].grams == 3)
        #expect(total.meters == 2.5)
    }

    @Test func unslicedProjectsHaveNone() throws {
        let model = try ModelLoader.load(zip([("_rels/.rels", rels), ("3D/3dmodel.model", model3D)]), name: "File")
        #expect(model.estimates.isEmpty)
        #expect(model.estimate(plateID: nil) == nil)
    }
}

// MARK: - Picking and orientation

@Suite struct PickingTests {
    private func cube() throws -> Model3D {
        try ModelLoader.load(binarySTL(cubeTriangles.map { $0.map { $0 * 10 } }), name: "Cube")
    }

    @Test func rayHitsTheNearFace() throws {
        let model = try cube()
        let hit = try #require(model.hit(origin: [5, -50, 5], direction: [0, 1, 0], plateID: nil, hidden: []))
        #expect(abs(hit.point.y) < 0.001)
        #expect(abs(hit.distance - 50) < 0.001)
        #expect(simd_distance(hit.normal, SIMD3(0, -1, 0)) < 0.001, "normal faces the ray")
        #expect(hit.corners.count == 3)
    }

    @Test func rayThatMissesFindsNothing() throws {
        let model = try cube()
        #expect(model.hit(origin: [50, -50, 5], direction: [0, 1, 0], plateID: nil, hidden: []) == nil)
        #expect(model.hit(origin: [5, -50, 5], direction: [0, 1, 0], plateID: nil, hidden: [0]) == nil, "hidden parts can't be picked")
    }

    @Test func hitsMovedParts() throws {
        var t = matrix_identity_float4x4
        t.columns.3 = SIMD4(100, 0, 0, 1)
        let geometry = MeshGeometry(positions: cubeTriangles.flatMap { $0.flatMap { [$0.x, $0.y, $0.z] } })
        let model = Model3D(format: .stl, parts: [ModelPart(id: 0, name: "c", geometry: geometry, transform: t)], objects: [])
        let hit = try #require(model.hit(origin: [100.5, 0.5, 50], direction: [0, 0, -1], plateID: nil, hidden: []))
        #expect(abs(hit.point.z - 1) < 0.001)
    }

    @Test func layingFlatPutsTheFaceDownOnTheBed() throws {
        // A 10 × 20 × 30 box, sitting at z 5 to start.
        let box = cubeTriangles.flatMap { $0.flatMap { [$0.x * 10, $0.y * 20, $0.z * 30 + 5] } }
        let model = Model3D(format: .stl, parts: [ModelPart(id: 0, name: "b", geometry: MeshGeometry(positions: box))], objects: [])
        // Lay it on its +X face: the 20 × 30 side.
        let flat = model.reoriented(by: layFlatRotation(for: [1, 0, 0]), plateID: nil, hidden: [])
        let size = flat.bounds.size
        #expect(abs(size.z - 10) < 0.001, "now 10 tall, was \(size)")
        #expect(abs(flat.bounds.min.z - 5) < 0.001, "rests where the model's base was")
        #expect(flat.sourceID == model.sourceID)
        #expect(flat.id != model.id)
        // A quarter turn about Z swaps width and depth.
        let turned = flat.reoriented(by: quarterTurn(about: [0, 0, 1]), plateID: nil, hidden: [])
        #expect(abs(turned.bounds.size.x - flat.bounds.size.y) < 0.001)
    }

    @Test func layFlatHandlesStraightUpAndDown() {
        #expect(simd_distance(layFlatRotation(for: [0, 0, -1]) * SIMD3(0, 0, -1), SIMD3(0, 0, -1)) < 0.001)
        #expect(simd_distance(layFlatRotation(for: [0, 0, 1]) * SIMD3(0, 0, 1), SIMD3(0, 0, -1)) < 0.001)
    }
}

// MARK: - Shape-based print estimate

@Suite struct PrintEstimateTests {
    @Test func matchesTheCalibration() throws {
        // Medicine Drawer plate 1, as measured for calibration; Bambu Studio said
        // 118.65 g and 13605 s (3 h 47 min).
        var surface = SurfaceStats()
        surface.side = 63211.824
        surface.up = 27360.168
        surface.down = 27360.113
        let estimate = try #require(PrintEstimate(volume: 196681.55, surface: surface, height: 45.54792, parts: 1, density: 1.24))
        #expect(abs(estimate.grams - 123.65) < 0.1)
        #expect(abs(estimate.seconds - 13473) < 5)
    }

    @Test func thinPartsAreAllShell() throws {
        // A 1 mm thick, 100 × 100 mm plate: walls and skins would be more than the
        // solid, so it prints solid and weighs (nearly) its volume.
        let box = cubeTriangles.flatMap { $0.flatMap { [$0.x * 100, $0.y * 100, $0.z * 1] } }
        let model = Model3D(format: .stl, parts: [ModelPart(id: 0, name: "p", geometry: MeshGeometry(positions: box))], objects: [])
        let estimate = try #require(model.shapeEstimate(plateID: nil, hidden: [], density: 1.24))
        let solid: Float = 10_000 * 1.24 / 1000
        #expect(estimate.grams <= solid && estimate.grams > solid * 0.8)
    }

    @Test func chunkyPartsAreMostlyInfill() throws {
        // A 60 mm cube: far lighter than solid.
        let box = cubeTriangles.flatMap { $0.flatMap { [$0.x * 60, $0.y * 60, $0.z * 60] } }
        let model = Model3D(format: .stl, parts: [ModelPart(id: 0, name: "c", geometry: MeshGeometry(positions: box))], objects: [])
        let estimate = try #require(model.shapeEstimate(plateID: nil, hidden: [], density: 1.24))
        let solid: Float = 216_000 * 1.24 / 1000
        #expect(estimate.grams < solid * 0.4)
    }

    @Test func surfaceSplitsByFacing() {
        // A 10 × 20 × 30 box: sides 2·(10·30 + 20·30) = 1800, top and bottom 200 each.
        let box = cubeTriangles.flatMap { $0.flatMap { [$0.x * 10, $0.y * 20, $0.z * 30] } }
        let s = MeshGeometry(positions: box).surface
        #expect(abs(s.side - 1800) < 0.01)
        #expect(abs(s.up - 200) < 0.01)
        #expect(abs(s.down - 200) < 0.01)
    }
}

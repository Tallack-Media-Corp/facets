import Foundation
import Testing
@testable import MeshKit

/// Damaged and deliberately hostile files (Hostile/): each one once crashed the
/// reader, the print estimate or Quick Look. Each must now load safely or fail
/// with an error, quickly.
struct HostileFileTests {
    private func url(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Hostile"))
    }

    @Test(arguments: ["bigidx.obj", "fanout.3mf", "huge.stl", "inf.stl", "meta_trunc.3mf", "nan.stl", "naninput.stl",
                      "pred_big.3mf", "pred_nan.3mf", "tet_1e20.stl", "tet_1e39.stl", "zip64neg.3mf"])
    func loadsOrFailsCleanly(_ name: String) throws {
        let start = Date()
        if let model = try? ModelLoader.load(try url(name)) {
            // Whatever loads has a finite size and a sane (or no) estimate.
            let bounds = model.bounds(of: model.parts)
            #expect(bounds.min.x.isFinite && bounds.max.z.isFinite)
            if let estimate = model.shapeEstimate(plateID: nil, hidden: [], density: 1.24) {
                #expect(estimate.seconds >= 0 && estimate.grams.isFinite)
            }
            #expect(model.estimates.allSatisfy { ($0.seconds ?? 0) >= 0 })
        }
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func damagedCoordinatesDropOnlyTheirTriangles() throws {
        // One good triangle and one at z = 1e39.
        let model = try ModelLoader.load(try url("tet_1e39.stl"))
        #expect(model.triangleCount >= 1)
        #expect(model.bounds(of: model.parts).size.z < 1e6)
    }

    @Test func componentFanOutIsBounded() throws {
        let model = try ModelLoader.load(try url("fanout.3mf"))
        #expect(model.parts.count <= 100_000)
    }

    @Test func zip64OffsetNearIntMaxFailsCleanly() {
        // A ZIP64 locator pointing at Int.max, behind a classic record asking for ZIP64.
        func le(_ v: UInt64, _ n: Int) -> Data { Data((0..<n).map { UInt8(truncatingIfNeeded: v >> (8 * UInt64($0))) }) }
        var data = le(0x0706_4B50, 4) + le(0, 4) + le(0x7FFF_FFFF_FFFF_FFFF, 8) + le(1, 4)
        data += le(0x0605_4B50, 4) + le(0, 4) + le(0xFFFF, 2) + le(0xFFFF, 2) + le(0, 4) + le(0xFFFF_FFFF, 4) + le(0, 2)
        #expect(throws: (any Error).self) { try ZipArchive(data: data) }
    }

    @Test func negativeColourIndexIsIgnored() throws {
        let model3D = """
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
         <resources>
          <basematerials id="5"><base displaycolor="#FF0000"/></basematerials>
          <object id="1" type="model" pid="5" pindex="-1">\(cubeMeshXML())</object>
         </resources>
         <build><item objectid="1"/></build>
        </model>
        """
        let model = try ModelLoader.load(zip([("_rels/.rels", rels), ("3D/3dmodel.model", model3D)]), name: "File")
        #expect(model.parts.count == 1)
    }

    @Test func smallMeshAfterBigOneStaysSmall() throws {
        let big = (0..<30_000).map { "<vertex x=\"\($0)\" y=\"0\" z=\"0\"/>" }.joined()
        let model3D = """
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
         <resources>
          <object id="1" type="model"><mesh><vertices>\(big)</vertices><triangles><triangle v1="0" v2="1" v3="2"/></triangles></mesh></object>
          <object id="2" type="model">\(cubeMeshXML())</object>
         </resources>
         <build><item objectid="1"/><item objectid="2"/></build>
        </model>
        """
        let model = try ModelLoader.load(zip([("_rels/.rels", rels), ("3D/3dmodel.model", model3D)]), name: "File")
        let cube = try #require(model.parts.first { $0.geometry.triangleCount == 12 })
        #expect(cube.geometry.positions.capacity < 1_000)
        #expect((cube.geometry.indices?.capacity ?? 0) < 1_000)
    }

    @Test func ampersandFloodIsQuick() {
        let start = Date()
        let text = String(repeating: "&", count: 200_000)
        #expect(text.xmlUnescaped == text)
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test func truncatedBinarySTLKeepsWhatItHas() throws {
        let model = try ModelLoader.load(binarySTL(cubeTriangles).dropLast(50), name: "Cube")
        #expect(model.triangleCount == 11)
    }

    @Test func objPartsAreCapped() throws {
        let text = "v 0 0 0\nv 1 0 0\nv 0 1 0\n" + String(repeating: "o a\nf 1 2 3\n", count: 20_000)
        let model = try ModelLoader.load(Data(text.utf8), name: "Many", fileExtension: "obj")
        #expect(model.parts.count <= 10_000)
        #expect(model.triangleCount == 20_000)
    }
}

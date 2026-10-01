import Compression
import Foundation
import Testing
import simd
@testable import MeshKit

// MARK: - Fixtures

/// A unit cube as 12 outward-facing triangles.
private let cubeTriangles: [[SIMD3<Float>]] = {
    let v = (0..<8).map { i in SIMD3<Float>(Float(i & 1), Float((i >> 1) & 1), Float((i >> 2) & 1)) }
    let faces = [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
    return faces.flatMap { f in [[v[f[0]], v[f[1]], v[f[2]]], [v[f[0]], v[f[2]], v[f[3]]]] }
}()

private func binarySTL(_ triangles: [[SIMD3<Float>]], header: String = "binary") -> Data {
    var data = Data(header.utf8.prefix(80))
    data.append(Data(count: 80 - data.count))
    var count = UInt32(triangles.count).littleEndian
    data.append(Data(bytes: &count, count: 4))
    for triangle in triangles {
        var floats: [Float] = [0, 0, 0] + triangle.flatMap { [$0.x, $0.y, $0.z] }
        data.append(Data(bytes: &floats, count: 48))
        data.append(Data(count: 2))
    }
    return data
}

private func asciiSTL(_ triangles: [[SIMD3<Float>]]) -> Data {
    var text = "solid cube\n"
    for triangle in triangles {
        text += "  facet normal 0 0 0\n    outer loop\n"
        for p in triangle { text += "      vertex \(p.x) \(p.y) \(p.z)\n" }
        text += "    endloop\n  endfacet\n"
    }
    text += "endsolid cube\n"
    return Data(text.utf8)
}

/// Cube mesh XML for a 3MF object.
private func cubeMeshXML() -> String {
    var vertices: [SIMD3<Float>] = []
    var indices: [Int] = []
    for triangle in cubeTriangles {
        for p in triangle {
            if let i = vertices.firstIndex(of: p) { indices.append(i) } else { vertices.append(p); indices.append(vertices.count - 1) }
        }
    }
    let v = vertices.map { "<vertex x=\"\($0.x)\" y=\"\($0.y)\" z=\"\($0.z)\"/>" }.joined()
    let t = stride(from: 0, to: indices.count, by: 3).map { "<triangle v1=\"\(indices[$0])\" v2=\"\(indices[$0 + 1])\" v3=\"\(indices[$0 + 2])\"/>" }.joined()
    return "<mesh><vertices>\(v)</vertices><triangles>\(t)</triangles></mesh>"
}

/// A ZIP with each entry deflated (or stored), enough for the reader.
private func zip(_ entries: [(String, String)], deflate: Bool = true) -> Data {
    var out = Data()
    var central = Data()
    func le16(_ v: Int) -> Data { var x = UInt16(v).littleEndian; return Data(bytes: &x, count: 2) }
    func le32(_ v: Int) -> Data { var x = UInt32(v).littleEndian; return Data(bytes: &x, count: 4) }
    for (name, text) in entries {
        let raw = Data(text.utf8)
        var payload = raw
        var method = 0
        if deflate {
            var buffer = [UInt8](repeating: 0, count: raw.count + 1024)
            let n = raw.withUnsafeBytes { src in
                compression_encode_buffer(&buffer, buffer.count, src.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
            }
            payload = Data(buffer[0..<n])
            method = 8
        }
        let offset = out.count
        let nameData = Data(name.utf8)
        out += le32(0x0403_4B50) + le16(20) + le16(0) + le16(method) + le16(0) + le16(0) + le32(0)
        out += le32(payload.count) + le32(raw.count) + le16(nameData.count) + le16(0) + nameData + payload
        central += le32(0x0201_4B50) + le16(20) + le16(20) + le16(0) + le16(method) + le16(0) + le16(0) + le32(0)
        central += le32(payload.count) + le32(raw.count) + le16(nameData.count) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + nameData
    }
    let centralOffset = out.count
    out += central
    out += le32(0x0605_4B50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count) + le32(central.count) + le32(centralOffset) + le16(0)
    return out
}

private let rels = """
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
 <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
</Relationships>
"""

// MARK: - STL

@Suite struct STLTests {
    @Test func readsBinary() throws {
        let model = try ModelLoader.load(binarySTL(cubeTriangles), name: "Cube")
        #expect(model.format == .stl)
        #expect(model.triangleCount == 12)
        #expect(model.bounds.size == SIMD3(1, 1, 1))
        #expect(abs(model.volume - 1) < 0.0001)
        #expect(model.objects.first?.name == "Cube")
    }

    @Test func binaryWithSolidHeaderIsStillBinary() throws {
        // Many exporters start the binary header with "solid".
        let model = try ModelLoader.load(binarySTL(cubeTriangles, header: "solid exported"), name: "Cube")
        #expect(model.format == .stl)
        #expect(model.triangleCount == 12)
    }

    @Test func readsASCII() throws {
        let model = try ModelLoader.load(asciiSTL(cubeTriangles), name: "Cube")
        #expect(model.format == .asciiSTL)
        #expect(model.triangleCount == 12)
        #expect(abs(model.volume - 1) < 0.0001)
    }

    @Test func readsExponentsAndSigns() throws {
        let text = "solid t\nfacet normal 0 0 1\nouter loop\nvertex -1.5e+01 0 0\nvertex 1.5E1 0 0\nvertex 0 +2.0e-0 -0\nendloop\nendfacet\nendsolid t\n"
        let model = try ModelLoader.load(Data(text.utf8), name: "T")
        #expect(model.bounds.min.x == -15)
        #expect(model.bounds.max.x == 15)
        #expect(model.bounds.max.y == 2)
    }

    @Test func emptyFileFails() {
        #expect(throws: ModelError.emptyFile) { try ModelLoader.load(Data(), name: "E") }
    }

    @Test func textWithoutTrianglesFails() {
        #expect(throws: ModelError.noGeometry) { try ModelLoader.load(Data("solid nothing\nendsolid\n".utf8), name: "E") }
    }
}

// MARK: - 3MF

@Suite struct ThreeMFTests {
    @Test func readsSingleObject() throws {
        let model3D = """
        <?xml version="1.0"?>
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
         <metadata name="Title">Test &amp; Cube</metadata>
         <resources><object id="1" name="Cube" type="model">\(cubeMeshXML())</object></resources>
         <build><item objectid="1" transform="1 0 0 0 1 0 0 0 1 10 20 30"/></build>
        </model>
        """
        for deflate in [true, false] {
            let data = zip([("_rels/.rels", rels), ("3D/3dmodel.model", model3D)], deflate: deflate)
            let model = try ModelLoader.load(data, name: "File")
            #expect(model.format == .threeMF)
            #expect(model.triangleCount == 12)
            #expect(model.title == "Test & Cube")
            #expect(model.objects.map(\.name) == ["Cube"])
            #expect(model.bounds.min == SIMD3(10, 20, 30))
            #expect(abs(model.volume - 1) < 0.0001)
        }
    }

    @Test func appliesUnitsScaleAndSharesGeometry() throws {
        let model3D = """
        <model unit="centimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
         <resources><object id="1" type="model">\(cubeMeshXML())</object></resources>
         <build>
          <item objectid="1"/>
          <item objectid="1" transform="2 0 0 0 2 0 0 0 2 5 0 0"/>
         </build>
        </model>
        """
        let model = try ModelLoader.load(zip([("_rels/.rels", rels), ("3D/3dmodel.model", model3D)]), name: "File")
        #expect(model.parts.count == 2)
        #expect(model.uniqueGeometryCount == 1)
        // 1 cm cube, then a 2× copy offset 5 cm.
        #expect(model.parts[0].bounds.size == SIMD3(10, 10, 10))
        #expect(model.parts[1].bounds.min.x == 50)
        #expect(model.parts[1].bounds.size.x == 20)
        #expect(abs(model.volume - (1000 + 8000)) < 0.1)
    }

    @Test func followsProductionComponentsAndBambuSettings() throws {
        // How Bambu Studio and Orca write projects: geometry in separate model parts,
        // names, filament colours, modifiers and plates in Metadata/.
        let root = """
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02" xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06">
         <resources>
          <object id="2" type="model"><components>
           <component p:path="/3D/Objects/object_1.model" objectid="1" transform="1 0 0 0 1 0 0 0 1 0 0 0"/>
           <component p:path="/3D/Objects/object_1.model" objectid="3" transform="1 0 0 0 1 0 0 0 1 0 0 5"/>
          </components></object>
          <object id="4" type="model"><components>
           <component p:path="/3D/Objects/object_1.model" objectid="1"/>
          </components></object>
         </resources>
         <build>
          <item objectid="2" transform="1 0 0 0 1 0 0 0 1 100 100 0"/>
          <item objectid="4" transform="1 0 0 0 1 0 0 0 1 400 100 0"/>
         </build>
        </model>
        """
        let objects = """
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
         <resources>
          <object id="1" type="model">\(cubeMeshXML())</object>
          <object id="3" type="model">\(cubeMeshXML())</object>
         </resources>
         <build/>
        </model>
        """
        let settings = """
        <config>
          <object id="2">
            <metadata key="name" value="Bracket"/>
            <metadata key="extruder" value="2"/>
            <part id="1" subtype="normal_part"><metadata key="name" value="Body"/></part>
            <part id="3" subtype="modifier_part"><metadata key="name" value="Infill modifier"/></part>
          </object>
          <object id="4">
            <metadata key="name" value="Clip"/>
            <part id="1" subtype="normal_part"><metadata key="extruder" value="1"/></part>
          </object>
          <plate>
            <metadata key="plater_id" value="1"/>
            <metadata key="plater_name" value="Brackets"/>
            <model_instance><metadata key="object_id" value="2"/></model_instance>
          </plate>
          <plate>
            <metadata key="plater_id" value="2"/>
            <model_instance><metadata key="object_id" value="4"/></model_instance>
          </plate>
        </config>
        """
        let project = ##"{"filament_colour": ["#FF0000", "#0000FF"]}"##
        let data = zip([
            ("_rels/.rels", rels),
            ("3D/3dmodel.model", root),
            ("3D/Objects/object_1.model", objects),
            ("Metadata/model_settings.config", settings),
            ("Metadata/project_settings.config", project),
        ])
        let model = try ModelLoader.load(data, name: "Project")

        // The modifier part isn't drawn.
        #expect(model.parts.count == 2)
        #expect(model.objects.map(\.name) == ["Bracket", "Clip"])
        #expect(model.parts[0].bounds.min == SIMD3(100, 100, 0))
        // Extruder 2 is blue, extruder 1 red (linear light).
        #expect(model.parts[0].color.map { $0.z > 0.9 && $0.x < 0.1 } == true)
        #expect(model.parts[1].color.map { $0.x > 0.9 && $0.z < 0.1 } == true)

        #expect(model.plates.map(\.id) == [1, 2])
        #expect(model.plates[0].title == "Plate 1: Brackets")
        #expect(model.parts(on: model.plates[1]).map(\.objectID) == [1])
        #expect(model.visibleParts(plateID: 1, hidden: [0]).isEmpty)
    }

    @Test func readsBaseMaterialColours() throws {
        let model3D = """
        <model unit="millimeter" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
         <resources>
          <basematerials id="5"><base name="Black" displaycolor="#000000"/><base name="White" displaycolor="#FFFFFFFF"/></basematerials>
          <object id="1" type="model" pid="5" pindex="1">\(cubeMeshXML())</object>
         </resources>
         <build><item objectid="1"/></build>
        </model>
        """
        let model = try ModelLoader.load(zip([("_rels/.rels", rels), ("3D/3dmodel.model", model3D)]), name: "File")
        #expect(model.parts[0].color == SIMD4(1, 1, 1, 1))
    }

    @Test func dropsOutOfRangeTriangles() throws {
        let model3D = """
        <model xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
         <resources><object id="1"><mesh>
          <vertices><vertex x="0" y="0" z="0"/><vertex x="1" y="0" z="0"/><vertex x="0" y="1" z="0"/></vertices>
          <triangles><triangle v1="0" v2="1" v3="2"/><triangle v1="0" v2="1" v3="99"/></triangles>
         </mesh></object></resources>
         <build><item objectid="1"/></build>
        </model>
        """
        let model = try ModelLoader.load(zip([("3D/3dmodel.model", model3D)]), name: "File")
        #expect(model.triangleCount == 1)
    }

    @Test func notAZipFails() {
        #expect(throws: ModelError.self) { try ModelLoader.load(Data("not a zip".utf8), name: "x", fileExtension: "3mf") }
    }

    @Test func findsThumbnail() throws {
        let packageRels = """
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
         <Relationship Target="/Metadata/thumb.png" Id="t" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/thumbnail"/>
        </Relationships>
        """
        let archive = try ZipArchive(data: zip([("_rels/.rels", packageRels), ("Metadata/thumb.png", "PNGDATA")]))
        #expect(ThreeMFReader.thumbnailData(in: archive) == Data("PNGDATA".utf8))
    }
}

// MARK: - Camera

@Suite struct CameraTests {
    @Test func fitKeepsModelInView() throws {
        let model = try ModelLoader.load(binarySTL(cubeTriangles), name: "Cube")
        var camera = OrbitCamera()
        camera.fitTightly(model.parts, aspect: 0.5, fill: 0.8)
        let viewProjection = camera.projectionMatrix(aspect: 0.5, sceneRadius: 1) * camera.viewMatrix
        for triangle in cubeTriangles {
            for p in triangle {
                let clip = viewProjection * SIMD4(p, 1)
                let ndc = SIMD2(clip.x, clip.y) / clip.w
                #expect(abs(ndc.x) <= 0.81 && abs(ndc.y) <= 0.81)
            }
        }
    }

    @Test func presetsLookFromTheRightSide() {
        var camera = OrbitCamera()
        camera.distance = 10
        camera.apply(.front)
        #expect(camera.eye.y < -9.9)
        camera.apply(.top)
        #expect(camera.eye.z > 9.9)
    }
}

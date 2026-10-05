import Foundation
import simd

/// Reads 3MF packages: the core spec's meshes, components and build items, the
/// production extension's per-object model parts (how Bambu Studio, Orca and
/// PrusaSlicer split large projects), base material and colour group colours, and
/// Bambu/Orca plates and filament colours from their `Metadata/` configs.
public enum ThreeMFReader {
    public static func read(url: URL) throws -> Model3D {
        try read(ZipArchive(url: url), name: url.deletingPathExtension().lastPathComponent)
    }

    public static func read(_ archive: ZipArchive, name: String = "Model") throws -> Model3D {
        var reader = Reader(archive: archive)
        return try reader.read(fallbackName: name)
    }

    /// The picture the package carries, if any: the thumbnail relationship first, then
    /// the places slicers put one.
    public static func thumbnailData(in archive: ZipArchive) -> Data? {
        if let rels = try? archive.data(for: "_rels/.rels") {
            for rel in relationships(rels) where rel.type.hasSuffix("/metadata/thumbnail") {
                if let data = try? archive.data(for: rel.target) { return data }
            }
        }
        for path in ["Metadata/plate_1.png", "Metadata/thumbnail.png", "Metadata/top_1.png"] {
            if let data = try? archive.data(for: path) { return data }
        }
        return nil
    }

    public static func thumbnailData(at url: URL) -> Data? {
        guard let archive = try? ZipArchive(url: url) else { return nil }
        return thumbnailData(in: archive)
    }

    struct Relationship {
        let type: String
        let target: String
    }

    static func relationships(_ data: Data) -> [Relationship] {
        data.withUnsafeBytes { raw in
            var scanner = XMLScanner(raw)
            var result: [Relationship] = []
            while let event = scanner.next() {
                if case .start = event, scanner.isElement("Relationship"),
                   let type = scanner.string("Type"), let target = scanner.string("Target") {
                    result.append(Relationship(type: type, target: target))
                }
            }
            return result
        }
    }
}

// MARK: - Model parts

private struct ComponentRef {
    let path: String?
    let objectID: Int
    let transform: simd_float4x4
}

private struct ObjectDef {
    let id: Int
    var name: String?
    var geometry: MeshGeometry?
    var components: [ComponentRef] = []
    var pid: Int?
    var pindex: Int?
    /// Multi-material painting by triangle index (see TrianglePaint).
    var paint: [Int: String] = [:]
}

private struct BuildItem {
    let objectID: Int
    let transform: simd_float4x4
    let path: String?
}

private struct ModelFile {
    var objects: [Int: ObjectDef] = [:]
    var build: [BuildItem] = []
    var metadata: [String: String] = [:]
    /// Base material and colour group colours by resource id.
    var colors: [Int: [SIMD4<Float>]] = [:]
}

/// Bambu Studio / Orca per-object settings from `Metadata/model_settings.config`.
private struct SlicerObject {
    var name: String?
    var extruder: Int?
    var parts: [Int: SlicerPart] = [:]
}

private struct SlicerPart {
    var name: String?
    var extruder: Int?
    var subtype: String?
}

private struct SlicerPlate {
    var id: Int?
    var name: String?
    var objectIDs: [Int] = []
}

private struct Reader {
    let archive: ZipArchive
    var files: [String: ModelFile] = [:]

    init(archive: ZipArchive) {
        self.archive = archive
    }

    mutating func read(fallbackName: String) throws -> Model3D {
        let rootPath = rootModelPath()
        let root = try modelFile(rootPath)
        let (slicerObjects, plates) = slicerSettings()
        let filamentColors = filamentColours()

        var parts: [ModelPart] = []
        var objects: [ModelObject] = []
        for (index, item) in root.build.enumerated() {
            let itemPath = item.path.map(ZipArchive.normalize) ?? rootPath
            guard let file = files[itemPath] ?? (try? modelFile(itemPath)), let object = file.objects[item.objectID] else { continue }
            let settings = slicerObjects[item.objectID]
            let objectName = settings?.name ?? object.name ?? (root.build.count == 1 ? fallbackName : "Object \(index + 1)")

            var leaves: [(ObjectDef, simd_float4x4, String)] = []
            flatten(object, path: itemPath, transform: item.transform, depth: 0, into: &leaves)
            var added = false
            for (leaf, transform, leafPath) in leaves {
                guard let geometry = leaf.geometry, geometry.triangleCount > 0 else { continue }
                let partSettings = settings?.parts[leaf.id]
                // Modifiers, negative volumes and support blockers shape the slice,
                // not the print; don't draw them.
                if let subtype = partSettings?.subtype, subtype != "normal_part" { continue }

                var color: SIMD4<Float>?
                if let extruder = partSettings?.extruder ?? settings?.extruder, extruder >= 1, extruder <= filamentColors.count {
                    color = filamentColors[extruder - 1]
                } else if let pid = leaf.pid ?? object.pid {
                    let pindex = leaf.pid != nil ? (leaf.pindex ?? 0) : (object.pindex ?? 0)
                    let file = files[leafPath]
                    if let group = file?.colors[pid] ?? root.colors[pid], pindex < group.count {
                        color = group[pindex]
                    }
                } else if filamentColors.count == 1 {
                    color = filamentColors[0]
                }

                var name = objectName
                if leaves.count > 1 {
                    name = partSettings?.name ?? leaf.name ?? "\(objectName) part \(parts.count + 1)"
                }
                // Painted in several filaments: one part per filament, so each draws
                // in its own colour. Unpainted triangles keep the object's.
                if !leaf.paint.isEmpty, let painted = TrianglePaint.split(geometry, paint: leaf.paint) {
                    for state in painted.keys.sorted() {
                        guard let piece = painted[state], piece.triangleCount > 0 else { continue }
                        let pieceColor = state == 0 ? color : Self.filamentColor(state, in: filamentColors)
                        parts.append(ModelPart(id: parts.count, name: name, geometry: piece, transform: transform, color: pieceColor, objectID: index, isPaint: state != 0))
                    }
                } else {
                    parts.append(ModelPart(id: parts.count, name: name, geometry: geometry, transform: transform, color: color, objectID: index))
                }
                added = true
            }
            if added {
                objects.append(ModelObject(id: index, name: objectName))
            }
        }

        // Some writers put objects in resources but leave the build empty.
        if parts.isEmpty, root.build.isEmpty {
            for (index, object) in root.objects.values.sorted(by: { $0.id < $1.id }).enumerated() {
                guard let geometry = object.geometry, geometry.triangleCount > 0 else { continue }
                let name = object.name ?? "Object \(index + 1)"
                parts.append(ModelPart(id: parts.count, name: name, geometry: geometry, objectID: index))
                objects.append(ModelObject(id: index, name: name))
            }
        }
        guard !parts.isEmpty else { throw ModelError.noGeometry }

        // Plates list 3MF object ids; parts know their build item.
        var modelPlates: [Plate] = []
        for (n, plate) in plates.enumerated() {
            let ids = Set(plate.objectIDs)
            let items = Set(root.build.indices.filter { ids.contains(root.build[$0].objectID) })
            guard !items.isEmpty else { continue }
            modelPlates.append(Plate(id: plate.id ?? n + 1, name: plate.name, objectIDs: items))
        }

        return Model3D(
            format: .threeMF,
            parts: parts,
            objects: objects,
            plates: modelPlates.count > 1 ? modelPlates : [],
            title: root.metadata["Title"].flatMap { $0.isEmpty ? nil : $0 },
            application: root.metadata["Application"],
            slicerBed: slicerBed(plateCount: plates.count),
            estimates: sliceEstimates()
        )
    }

    private mutating func flatten(_ object: ObjectDef, path: String, transform: simd_float4x4, depth: Int, into leaves: inout [(ObjectDef, simd_float4x4, String)]) {
        guard depth < 16 else { return }
        if object.geometry != nil {
            leaves.append((object, transform, path))
        }
        for component in object.components {
            let componentPath = component.path.map(ZipArchive.normalize) ?? path
            guard let file = files[componentPath] ?? (try? modelFile(componentPath)),
                  let child = file.objects[component.objectID] else { continue }
            flatten(child, path: componentPath, transform: transform * component.transform, depth: depth + 1, into: &leaves)
        }
    }

    private func rootModelPath() -> String {
        if let rels = try? archive.data(for: "_rels/.rels") {
            for rel in ThreeMFReader.relationships(rels) where rel.type.hasSuffix("/3dmodel") {
                return ZipArchive.normalize(rel.target)
            }
        }
        if archive.contains("3D/3dmodel.model") { return "3D/3dmodel.model" }
        return archive.paths.first { $0.lowercased().hasSuffix(".model") } ?? "3D/3dmodel.model"
    }

    private mutating func modelFile(_ path: String) throws -> ModelFile {
        let key = ZipArchive.normalize(path)
        if let cached = files[key] { return cached }
        let data = try archive.data(for: key)
        let file = try data.withUnsafeBytes { try Self.parseModel($0) }
        files[key] = file
        return file
    }

    private static func parseModel(_ raw: UnsafeRawBufferPointer) throws -> ModelFile {
        var file = ModelFile()
        var scanner = XMLScanner(raw)
        var scale: Float = 1
        var current: ObjectDef?
        var colorGroup: Int?
        var positions: [Float] = []
        var indices: [UInt32] = []
        var paint: [Int: String] = [:]
        var inBuild = false
        var depth = 0

        while let event = scanner.next() {
            switch event {
            case .start:
                if !scanner.element.isSelfClosing { depth += 1 }
                if scanner.isElement("vertex") {
                    let x = scanner.float("x") ?? 0, y = scanner.float("y") ?? 0, z = scanner.float("z") ?? 0
                    positions.append(x * scale)
                    positions.append(y * scale)
                    positions.append(z * scale)
                } else if scanner.isElement("triangle") {
                    if let a = scanner.int("v1"), let b = scanner.int("v2"), let c = scanner.int("v3"), a >= 0, b >= 0, c >= 0 {
                        indices.append(UInt32(truncatingIfNeeded: a))
                        indices.append(UInt32(truncatingIfNeeded: b))
                        indices.append(UInt32(truncatingIfNeeded: c))
                        if let code = scanner.string("paint_color") ?? scanner.string("mmu_segmentation"), !code.isEmpty {
                            paint[indices.count / 3 - 1] = code
                        }
                    }
                } else if scanner.isElement("object") {
                    current = ObjectDef(id: scanner.int("id") ?? -1, name: scanner.string("name"), pid: scanner.int("pid"), pindex: scanner.int("pindex"))
                    if scanner.element.isSelfClosing, let object = current {
                        file.objects[object.id] = object
                        current = nil
                    }
                } else if scanner.isElement("mesh") {
                    positions.removeAll(keepingCapacity: true)
                    indices.removeAll(keepingCapacity: true)
                    paint.removeAll()
                } else if scanner.isElement("component") {
                    if let id = scanner.int("objectid") {
                        current?.components.append(ComponentRef(path: scanner.string("path"), objectID: id, transform: transform(scanner, scale: scale)))
                    }
                } else if scanner.isElement("item"), inBuild {
                    if let id = scanner.int("objectid") {
                        file.build.append(BuildItem(objectID: id, transform: transform(scanner, scale: scale), path: scanner.string("path")))
                    }
                } else if scanner.isElement("build") {
                    inBuild = !scanner.element.isSelfClosing
                } else if scanner.isElement("basematerials") || scanner.isElement("colorgroup") {
                    colorGroup = scanner.int("id")
                    if let colorGroup { file.colors[colorGroup] = [] }
                } else if scanner.isElement("base") {
                    if let colorGroup { file.colors[colorGroup]?.append(scanner.string("displaycolor").flatMap(parseColor) ?? SIMD4(0.8, 0.8, 0.8, 1)) }
                } else if scanner.isElement("color") {
                    if let colorGroup { file.colors[colorGroup]?.append(scanner.string("color").flatMap(parseColor) ?? SIMD4(0.8, 0.8, 0.8, 1)) }
                } else if scanner.isElement("model") {
                    scale = unitScale(scanner.string("unit"))
                } else if scanner.isElement("metadata"), depth == 2 {
                    // Only the model's own metadata; objects carry their own too.
                    if let name = scanner.string("name"), !scanner.element.isSelfClosing {
                        file.metadata[name] = scanner.text()
                    }
                }
            case .end(let name):
                depth -= 1
                if scanner.isName(name, "mesh") {
                    let vertexCount = UInt32(positions.count / 3)
                    var valid = indices
                    if indices.contains(where: { $0 >= vertexCount }) {
                        // Out-of-range triangles would read past the GPU buffer.
                        valid = []
                        valid.reserveCapacity(indices.count)
                        var t = 0
                        while t + 2 < indices.count {
                            if indices[t] < vertexCount, indices[t + 1] < vertexCount, indices[t + 2] < vertexCount {
                                valid.append(contentsOf: indices[t...(t + 2)])
                            }
                            t += 3
                        }
                    }
                    current?.geometry = MeshGeometry(positions: positions, indices: valid)
                    // Dropping bad triangles renumbers the rest; painting would land
                    // on the wrong ones, so it's left off.
                    current?.paint = valid.count == indices.count ? paint : [:]
                } else if scanner.isName(name, "object") {
                    if let object = current { file.objects[object.id] = object }
                    current = nil
                } else if scanner.isName(name, "build") {
                    inBuild = false
                } else if scanner.isName(name, "basematerials") || scanner.isName(name, "colorgroup") {
                    colorGroup = nil
                }
            }
        }
        return file
    }

    /// 3MF writes 4×3 row-vector matrices: "m00 m01 m02 m10 m11 m12 m20 m21 m22 m30 m31 m32".
    /// As a column-vector simd matrix, each triple is a column.
    private static func transform(_ scanner: XMLScanner, scale: Float) -> simd_float4x4 {
        guard let range = scanner.attribute("transform") else { return matrix_identity_float4x4 }
        var values: [Float] = []
        values.reserveCapacity(12)
        var i = range.lowerBound
        while values.count < 12, let v = ByteScan.parseFloat(scanner.bytes, &i, end: range.upperBound) {
            values.append(v)
        }
        guard values.count == 12 else { return matrix_identity_float4x4 }
        return simd_float4x4(
            SIMD4(values[0], values[1], values[2], 0),
            SIMD4(values[3], values[4], values[5], 0),
            SIMD4(values[6], values[7], values[8], 0),
            SIMD4(values[9] * scale, values[10] * scale, values[11] * scale, 1)
        )
    }

    private static func unitScale(_ unit: String?) -> Float {
        switch unit?.lowercased() {
        case "micron": 0.001
        case "centimeter": 10
        case "inch": 25.4
        case "foot": 304.8
        case "meter": 1000
        default: 1
        }
    }

    // MARK: Slicer metadata

    private func slicerSettings() -> ([Int: SlicerObject], [SlicerPlate]) {
        guard let data = try? archive.data(for: "Metadata/model_settings.config") else { return ([:], []) }
        return data.withUnsafeBytes { raw in
            var scanner = XMLScanner(raw)
            var objects: [Int: SlicerObject] = [:]
            var plates: [SlicerPlate] = []
            var objectID: Int?
            var partID: Int?
            var plate: SlicerPlate?
            var inInstance = false

            while let event = scanner.next() {
                switch event {
                case .start:
                    if scanner.isElement("object"), plate == nil {
                        objectID = scanner.int("id")
                        if let objectID { objects[objectID] = SlicerObject() }
                    } else if scanner.isElement("part"), let objectID {
                        partID = scanner.int("id")
                        if let partID {
                            objects[objectID]?.parts[partID] = SlicerPart(subtype: scanner.string("subtype"))
                        }
                        if scanner.element.isSelfClosing { partID = nil }
                    } else if scanner.isElement("plate") {
                        plate = SlicerPlate()
                    } else if scanner.isElement("model_instance") {
                        inInstance = true
                    } else if scanner.isElement("metadata"), let key = scanner.string("key") {
                        let value = scanner.string("value")
                        if var current = plate {
                            if inInstance {
                                if key == "object_id", let id = value.flatMap({ Int($0) }) { current.objectIDs.append(id) }
                            } else if key == "plater_id" {
                                current.id = value.flatMap { Int($0) }
                            } else if key == "plater_name" {
                                current.name = value
                            }
                            plate = current
                        } else if let objectID {
                            if let partID {
                                if key == "name" { objects[objectID]?.parts[partID]?.name = value }
                                if key == "extruder" { objects[objectID]?.parts[partID]?.extruder = value.flatMap { Int($0) } }
                            } else {
                                if key == "name" { objects[objectID]?.name = value }
                                if key == "extruder" { objects[objectID]?.extruder = value.flatMap { Int($0) } }
                            }
                        }
                    }
                case .end(let name):
                    if scanner.isName(name, "part") {
                        partID = nil
                    } else if scanner.isName(name, "object") {
                        objectID = nil
                    } else if scanner.isName(name, "model_instance") {
                        inInstance = false
                    } else if scanner.isName(name, "plate") {
                        if let plate { plates.append(plate) }
                        plate = nil
                    }
                }
            }
            return (objects, plates)
        }
    }

    /// The bed the project was arranged on. Bambu Studio and Orca store it as a
    /// `printable_area` polygon in project settings; PrusaSlicer as `bed_shape` in its
    /// config.
    private func slicerBed(plateCount: Int) -> SlicerBed? {
        func box(_ points: [String]) -> SIMD2<Float>? {
            let xy = points.compactMap { point -> SIMD2<Float>? in
                let parts = point.split(separator: "x").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
                return parts.count == 2 ? SIMD2(parts[0], parts[1]) : nil
            }
            guard xy.count >= 3 else { return nil }
            let lo = xy.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }
            let hi = xy.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
            let size = hi - lo
            return size.x > 0 && size.y > 0 ? size : nil
        }
        if let data = try? archive.data(for: "Metadata/project_settings.config"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let area = json["printable_area"] as? [String], let size = box(area) {
            let height = (json["printable_height"] as? String).flatMap(Float.init) ?? (json["printable_height"] as? NSNumber)?.floatValue
            return SlicerBed(width: size.x, depth: size.y, height: height, printer: json["printer_model"] as? String, plateCount: plateCount)
        }
        if let data = try? archive.data(for: "Metadata/Slic3r_PE.config"),
           let text = String(data: data, encoding: .utf8),
           let line = text.split(separator: "\n").first(where: { $0.contains("bed_shape =") }),
           let value = line.split(separator: "=").last,
           let size = box(value.split(separator: ",").map(String.init)) {
            return SlicerBed(width: size.x, depth: size.y, printer: nil, plateCount: 1)
        }
        return nil
    }

    /// Time and filament per plate from the slicer's last slice, saved by Bambu Studio
    /// and Orca in `Metadata/slice_info.config`. A project saved unsliced has none.
    private func sliceEstimates() -> [SliceEstimate] {
        guard let data = try? archive.data(for: "Metadata/slice_info.config") else { return [] }
        return data.withUnsafeBytes { raw in
            var scanner = XMLScanner(raw)
            var estimates: [SliceEstimate] = []
            var plate: (index: Int?, seconds: Int?, grams: Float?, supports: Bool, filaments: [SliceEstimate.Filament])?
            while let event = scanner.next() {
                switch event {
                case .start:
                    if scanner.isElement("plate") {
                        plate = (nil, nil, nil, false, [])
                    } else if scanner.isElement("metadata"), plate != nil, let key = scanner.string("key") {
                        let value = scanner.string("value")
                        switch key {
                        case "index": plate?.index = value.flatMap { Int($0) }
                        case "prediction": plate?.seconds = value.flatMap { Double($0) }.map { Int($0) }
                        case "weight": plate?.grams = value.flatMap { Float($0) }
                        case "support_used": plate?.supports = value == "true"
                        default: break
                        }
                    } else if scanner.isElement("filament"), plate != nil {
                        plate?.filaments.append(SliceEstimate.Filament(
                            type: scanner.string("type"),
                            colorHex: scanner.string("color"),
                            meters: scanner.string("used_m").flatMap { Float($0) },
                            grams: scanner.string("used_g").flatMap { Float($0) }
                        ))
                    }
                case .end(let name):
                    if scanner.isName(name, "plate"), let current = plate {
                        // A plate the slicer listed but never sliced has no prediction.
                        if current.seconds != nil || current.grams != nil {
                            estimates.append(SliceEstimate(plate: current.index ?? estimates.count + 1, seconds: current.seconds, grams: current.grams, filaments: current.filaments, usesSupports: current.supports))
                        }
                        plate = nil
                    }
                }
            }
            return estimates
        }
    }

    /// Filament colours, indexed by extruder: Bambu Studio / Orca project settings,
    /// or PrusaSlicer's config (`; extruder_colour = #…;#…`, else filament_colour).
    private func filamentColours() -> [SIMD4<Float>] {
        if let data = try? archive.data(for: "Metadata/project_settings.config"),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let colours = json["filament_colour"] as? [String] {
            return colours.map { parseColor($0) ?? SIMD4(0.8, 0.8, 0.8, 1) }
        }
        guard let data = try? archive.data(for: "Metadata/Slic3r_PE.config"), let text = String(data: data, encoding: .utf8) else { return [] }
        func values(_ key: String) -> [String]? {
            guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("; \(key) = ") }) else { return nil }
            let list = line.dropFirst(key.count + 5).split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            return list.contains(where: { !$0.isEmpty }) ? list : nil
        }
        let extruders = values("extruder_colour"), filaments = values("filament_colour")
        let count = max(extruders?.count ?? 0, filaments?.count ?? 0)
        return (0..<count).map { i in
            let hex = extruders.flatMap { i < $0.count && !$0[i].isEmpty ? $0[i] : nil } ?? filaments.flatMap { i < $0.count ? $0[i] : nil }
            return hex.flatMap(parseColor) ?? SIMD4(0.8, 0.8, 0.8, 1)
        }
    }

    /// A painted filament's colour; one the project doesn't list gets a distinct
    /// stand-in, so the painting still shows.
    static func filamentColor(_ filament: Int, in colours: [SIMD4<Float>]) -> SIMD4<Float>? {
        if filament >= 1, filament <= colours.count { return colours[filament - 1] }
        let standIns = ["#F2782E", "#F2F2EE", "#2F3033", "#D8352F", "#2F6FD8", "#2FA65A", "#F4C534", "#8A4FD8"]
        return parseColor(standIns[(max(filament, 1) - 1) % standIns.count])
    }
}

/// "#RRGGBB" or "#RRGGBBAA" (sRGB) to linear RGBA.
func parseColor(_ string: String) -> SIMD4<Float>? {
    var hex = string.trimmingCharacters(in: .whitespaces)
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 6 || hex.count == 8, let value = UInt32(hex, radix: 16) else { return nil }
    let r, g, b, a: UInt32
    if hex.count == 8 {
        (r, g, b, a) = ((value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF)
    } else {
        (r, g, b, a) = ((value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF, 0xFF)
    }
    func linear(_ c: UInt32) -> Float {
        let s = Float(c) / 255
        return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
    // Clear filament is stored with alpha 0; draw it as a solid so it's visible.
    return SIMD4(linear(r), linear(g), linear(b), a == 0 ? 1 : Float(a) / 255)
}

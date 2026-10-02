import Foundation
import Testing
@testable import MeshKit

/// For calibrating print estimates (docs/print-estimates.md): writes one CSV row per
/// sliced plate in every 3MF in `MESHKIT_CALIBRATE` (a folder) to
/// `MESHKIT_CALIBRATE_OUT`, with the shape features, the project's slicer settings,
/// and what the slicer predicted. Does nothing unless both are set.
@Suite struct CalibrationDump {
    @Test func dumpSlicedPlates() throws {
        let env = ProcessInfo.processInfo.environment
        guard let folder = env["MESHKIT_CALIBRATE"], let out = env["MESHKIT_CALIBRATE_OUT"] else { return }
        let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "3mf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var rows = ["file,plate,volume,side,up,down,height,parts,tris,grams,seconds,filaments,supports,layer,infill,walls,top,bottom,linewidth,printer,density,pattern,material,overhang,support"]
        for url in urls {
            guard let model = try? ModelLoader.load(url), !model.estimates.isEmpty,
                  let archive = try? ZipArchive(data: Data(contentsOf: url, options: .alwaysMapped)) else { continue }
            let settings = (try? archive.data(for: "Metadata/project_settings.config"))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            func value(_ key: String) -> String {
                if let s = settings[key] as? String { return s }
                if let a = settings[key] as? [String], let first = a.first { return first }
                if let n = settings[key] as? NSNumber { return n.stringValue }
                return ""
            }
            for estimate in model.estimates {
                let parts = model.plates.isEmpty ? model.parts : model.visibleParts(plateID: estimate.plate, hidden: [])
                guard !parts.isEmpty, let seconds = estimate.seconds, let grams = estimate.grams else { continue }
                let surface = parts.reduce(SurfaceStats()) { $0 + $1.surface }
                let volume = abs(parts.reduce(0) { $0 + $1.volume })
                let bounds = model.bounds(of: parts)
                let tris = parts.reduce(0) { $0 + $1.geometry.triangleCount }
                let fields: [String] = [
                    url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: ",", with: " "),
                    "\(estimate.plate)", "\(volume)", "\(surface.side)", "\(surface.up)", "\(surface.down)",
                    "\(bounds.size.z)", "\(parts.count)", "\(tris)", "\(grams)", "\(seconds)",
                    "\(estimate.filaments.count)", estimate.usesSupports ? "1" : "0",
                    value("layer_height"), value("sparse_infill_density").replacingOccurrences(of: "%", with: ""),
                    value("wall_loops"), value("top_shell_layers"), value("bottom_shell_layers"),
                    value("inner_wall_line_width").isEmpty ? value("line_width") : value("inner_wall_line_width"),
                    value("printer_model").replacingOccurrences(of: ",", with: " "),
                    value("filament_density"), value("sparse_infill_pattern"),
                    value("filament_type"),
                    "\(surface.overhang)", "\(surface.supportVolume(bedZ: bounds.min.z))",
                ]
                rows.append(fields.joined(separator: ","))
            }
        }
        try rows.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
        print("wrote \(rows.count - 1) plates to \(out)")
    }
}

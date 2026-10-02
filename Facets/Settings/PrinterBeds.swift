import MeshKit
import Foundation

/// A printer's bed footprint, for the viewer's build-plate outline.
struct PrinterBed: Identifiable, Hashable {
    let id: String
    let make: String
    let name: String
    /// Printable area in millimetres.
    let width: Float
    let depth: Float
    let height: Float

    var title: String { id == Self.customID ? "custom bed" : "\(make) \(name)" }

    /// Bambu Lab sizes, heights included, are the `printable_area` and
    /// `printable_height` those printers write into their own project files. The others
    /// are each maker's published build volume (product pages, checked October 2026);
    /// the Voron is its official Klipper config's axis limits for the 350 build.
    static let presets: [PrinterBed] = [
        .init(id: "bambu-a1mini", make: "Bambu Lab", name: "A1 mini", width: 180, depth: 180, height: 180),
        .init(id: "bambu-a1", make: "Bambu Lab", name: "A1", width: 256, depth: 256, height: 256),
        .init(id: "bambu-p1p", make: "Bambu Lab", name: "P1P", width: 256, depth: 256, height: 250),
        .init(id: "bambu-p1s", make: "Bambu Lab", name: "P1S", width: 256, depth: 256, height: 250),
        .init(id: "bambu-p2s", make: "Bambu Lab", name: "P2S", width: 256, depth: 256, height: 256),
        .init(id: "bambu-x1c", make: "Bambu Lab", name: "X1C", width: 256, depth: 256, height: 250),
        .init(id: "bambu-h2s", make: "Bambu Lab", name: "H2S", width: 340, depth: 320, height: 340),
        .init(id: "bambu-h2d", make: "Bambu Lab", name: "H2D", width: 350, depth: 320, height: 325),
        .init(id: "prusa-mini", make: "Prusa", name: "MINI+", width: 180, depth: 180, height: 180),
        .init(id: "prusa-mk4s", make: "Prusa", name: "MK4S", width: 250, depth: 210, height: 220),
        .init(id: "prusa-coreone", make: "Prusa", name: "Core One", width: 250, depth: 220, height: 270),
        .init(id: "prusa-xl", make: "Prusa", name: "XL", width: 360, depth: 360, height: 360),
        .init(id: "creality-ender3v3", make: "Creality", name: "Ender-3 V3", width: 220, depth: 220, height: 250),
        .init(id: "creality-k1", make: "Creality", name: "K1", width: 220, depth: 220, height: 250),
        .init(id: "creality-k2plus", make: "Creality", name: "K2 Plus", width: 350, depth: 350, height: 350),
        .init(id: "elegoo-n4pro", make: "Elegoo", name: "Neptune 4 Pro", width: 225, depth: 225, height: 265),
        .init(id: "voron-24-350", make: "Voron", name: "2.4 (350)", width: 350, depth: 350, height: 310),
    ]

    /// Presets grouped by make, in list order.
    static var byMake: [(make: String, beds: [PrinterBed])] {
        var groups: [(String, [PrinterBed])] = []
        for bed in presets {
            if let i = groups.firstIndex(where: { $0.0 == bed.make }) { groups[i].1.append(bed) } else { groups.append((bed.make, [bed])) }
        }
        return groups.map { (make: $0.0, beds: $0.1) }
    }

    static let customID = "custom"
}

extension PrinterBed {
    /// Which calibrated speed profile the print estimate uses for this printer
    /// (docs/print-estimates.md). Custom beds assume a Bambu-class printer.
    var machine: PrintEstimate.Machine {
        switch id {
        case "bambu-a1mini", "bambu-a1": .bambuBedSlinger
        case _ where id.hasPrefix("bambu-"): .bambuCoreXY
        case "creality-k1", "creality-k2plus", "voron-24-350", "prusa-coreone", "prusa-xl": .coreXY
        case "creality-ender3v3", "elegoo-n4pro", "prusa-mk4s", "prusa-mini": .bedSlinger
        default: .bambuCoreXY
        }
    }
}

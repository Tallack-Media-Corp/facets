import Foundation

/// A printer's bed footprint, for the viewer's build-plate outline.
struct PrinterBed: Identifiable, Hashable {
    let id: String
    let make: String
    let name: String
    /// Millimetres.
    let width: Float
    let depth: Float

    var title: String { id == Self.customID ? "custom bed" : "\(make) \(name)" }

    /// Sizes are the printable area. Bambu Lab values match the `printable_area`
    /// those printers write into their own project files; check the others against
    /// each maker's published spec before a release (docs/briefs/build-plate-outline.md).
    static let presets: [PrinterBed] = [
        .init(id: "bambu-a1mini", make: "Bambu Lab", name: "A1 mini", width: 180, depth: 180),
        .init(id: "bambu-a1", make: "Bambu Lab", name: "A1", width: 256, depth: 256),
        .init(id: "bambu-p1s", make: "Bambu Lab", name: "P1S", width: 256, depth: 256),
        .init(id: "bambu-p2s", make: "Bambu Lab", name: "P2S", width: 256, depth: 256),
        .init(id: "bambu-x1c", make: "Bambu Lab", name: "X1C", width: 256, depth: 256),
        .init(id: "bambu-h2d", make: "Bambu Lab", name: "H2D", width: 350, depth: 320),
        .init(id: "prusa-mini", make: "Prusa", name: "MINI+", width: 180, depth: 180),
        .init(id: "prusa-mk4s", make: "Prusa", name: "MK4S", width: 250, depth: 210),
        .init(id: "prusa-coreone", make: "Prusa", name: "Core One", width: 250, depth: 220),
        .init(id: "prusa-xl", make: "Prusa", name: "XL", width: 360, depth: 360),
        .init(id: "creality-ender3v3", make: "Creality", name: "Ender-3 V3", width: 220, depth: 220),
        .init(id: "creality-k1", make: "Creality", name: "K1", width: 220, depth: 220),
        .init(id: "creality-k2plus", make: "Creality", name: "K2 Plus", width: 350, depth: 350),
        .init(id: "elegoo-n4pro", make: "Elegoo", name: "Neptune 4 Pro", width: 225, depth: 225),
        .init(id: "voron-24-350", make: "Voron", name: "2.4 (350)", width: 350, depth: 350),
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

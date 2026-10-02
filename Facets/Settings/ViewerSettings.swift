import MeshKit
import Observation
import SwiftUI

/// Filament for weight estimates on models a slicer hasn't sliced.
enum FilamentMaterial: String, CaseIterable, Identifiable {
    case pla, petg, abs, asa, tpu, nylon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pla: "PLA"
        case .petg: "PETG"
        case .abs: "ABS"
        case .asa: "ASA"
        case .tpu: "TPU"
        case .nylon: "Nylon"
        }
    }

    /// Grams per cubic centimetre, typical of each maker's spec sheets.
    var density: Float {
        switch self {
        case .pla: 1.24
        case .petg: 1.27
        case .abs: 1.04
        case .asa: 1.07
        case .tpu: 1.21
        case .nylon: 1.14
        }
    }
}

enum MeasurementUnits: String, CaseIterable, Identifiable {
    case millimetres, inches

    var id: String { rawValue }
    var symbol: String { self == .millimetres ? "mm" : "in" }
    var title: String { self == .millimetres ? "Millimetres" : "Inches" }
}

/// A preset model colour, named the way filament is.
struct ModelColorPreset: Identifiable, Hashable {
    let name: String
    let hex: String
    var id: String { hex }

    static let all: [ModelColorPreset] = [
        .init(name: "Orange", hex: Palette.filamentOrange),
        .init(name: "White", hex: "#F2F2EE"),
        .init(name: "Grey", hex: "#8E9196"),
        .init(name: "Black", hex: "#2F3033"),
        .init(name: "Red", hex: "#D8352F"),
        .init(name: "Yellow", hex: "#F4C534"),
        .init(name: "Green", hex: "#2FA65A"),
        .init(name: "Blue", hex: "#2F6FD8"),
        .init(name: "Purple", hex: "#8A4FD8"),
    ]
}

/// How models look, kept in UserDefaults.
@MainActor
@Observable
final class ViewerSettings {
    private let defaults = UserDefaults.standard

    var colorHex: String {
        didSet { defaults.set(colorHex, forKey: "viewer.color") }
    }

    var usesFileColors: Bool {
        didSet { defaults.set(usesFileColors, forKey: "viewer.fileColors") }
    }

    var showsGrid: Bool {
        didSet { defaults.set(showsGrid, forKey: "viewer.grid") }
    }

    /// The filament the shape-based print estimate assumes.
    var material: FilamentMaterial {
        didSet { defaults.set(material.rawValue, forKey: "viewer.material") }
    }

    /// Off for anyone who just wants the dimensions: no printer line, outline or menu.
    var checksFit: Bool {
        didSet { defaults.set(checksFit, forKey: "viewer.checksFit") }
    }

    /// The bed the viewer measures against: the chosen printer, while fit checks are on.
    var fitBed: PrinterBed? { checksFit ? bed : nil }

    var units: MeasurementUnits {
        didSet { defaults.set(units.rawValue, forKey: "viewer.units") }
    }

    /// The printer bed drawn in the viewer: a preset id, "custom", or nil for none.
    var bedID: String? {
        didSet {
            defaults.set(bedID, forKey: "viewer.bed")
            if let bedID {
                recentBedIDs = Array(([bedID] + recentBedIDs.filter { $0 != bedID }).prefix(4))
            }
        }
    }

    /// Printers chosen lately, newest first, so someone with a few printers can
    /// switch between them from the viewer without the full list.
    private(set) var recentBedIDs: [String] {
        didSet { defaults.set(recentBedIDs, forKey: "viewer.bed.recents") }
    }

    var recentBeds: [PrinterBed] { recentBedIDs.compactMap(bed(withID:)) }

    /// The custom bed, in millimetres.
    var customBedWidth: Float {
        didSet { defaults.set(customBedWidth, forKey: "viewer.bed.width") }
    }

    var customBedDepth: Float {
        didSet { defaults.set(customBedDepth, forKey: "viewer.bed.depth") }
    }

    var customBedHeight: Float {
        didSet { defaults.set(customBedHeight, forKey: "viewer.bed.height") }
    }

    var bed: PrinterBed? { bedID.flatMap(bed(withID:)) }

    private func bed(withID bedID: String) -> PrinterBed? {
        if bedID == PrinterBed.customID {
            guard customBedWidth > 0, customBedDepth > 0 else { return nil }
            return PrinterBed(id: PrinterBed.customID, make: "Custom", name: "bed", width: customBedWidth, depth: customBedDepth, height: customBedHeight)
        }
        return PrinterBed.presets.first { $0.id == bedID }
    }

    init() {
        let saved = defaults.string(forKey: "viewer.color")
        // The Orange preset was #F2802E before the design system settled on one orange.
        colorHex = (saved == nil || saved == "#F2802E") ? Palette.filamentOrange : saved!
        usesFileColors = defaults.object(forKey: "viewer.fileColors") as? Bool ?? true
        showsGrid = defaults.object(forKey: "viewer.grid") as? Bool ?? true
        checksFit = defaults.object(forKey: "viewer.checksFit") as? Bool ?? true
        material = FilamentMaterial(rawValue: defaults.string(forKey: "viewer.material") ?? "") ?? .pla
        let savedBed = defaults.string(forKey: "viewer.bed")
        bedID = savedBed
        recentBedIDs = defaults.stringArray(forKey: "viewer.bed.recents") ?? savedBed.map { [$0] } ?? []
        customBedWidth = defaults.object(forKey: "viewer.bed.width") as? Float ?? 256
        customBedDepth = defaults.object(forKey: "viewer.bed.depth") as? Float ?? 256
        customBedHeight = defaults.object(forKey: "viewer.bed.height") as? Float ?? 256
        units = MeasurementUnits(rawValue: defaults.string(forKey: "viewer.units") ?? "")
            ?? (Locale.current.measurementSystem == .us ? .inches : .millimetres)
    }

    var color: Color {
        get { Color(hex: colorHex) ?? .orange }
        set { colorHex = newValue.hexString }
    }

    /// The starting appearance for a viewer or thumbnail.
    var appearance: RenderAppearance {
        var appearance = RenderAppearance(baseColor: Color(hex: colorHex)?.linearRGBA ?? RenderAppearance.defaultColor)
        appearance.usesFileColors = usesFileColors
        appearance.showsGrid = showsGrid
        return appearance
    }
}

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    var hexString: String {
        let resolved = resolve(in: EnvironmentValues())
        func byte(_ c: Float) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(resolved.red), byte(resolved.green), byte(resolved.blue))
    }

    /// Linear-light RGBA, which is what the renderer works in.
    var linearRGBA: SIMD4<Float> {
        let resolved = resolve(in: EnvironmentValues())
        return SIMD4(resolved.linearRed, resolved.linearGreen, resolved.linearBlue, 1)
    }
}

import MeshKit
import Foundation

// MeshKit names things in English for its own use and tests; what the app shows comes
// from here, so the names are translated with the rest of the app.

extension OrbitCamera.Preset {
    var localizedTitle: String {
        switch self {
        case .isometric: String(localized: "Isometric", comment: "Preset view")
        case .front: String(localized: "Front", comment: "Preset view")
        case .back: String(localized: "Back", comment: "Preset view")
        case .left: String(localized: "Left", comment: "Preset view")
        case .right: String(localized: "Right", comment: "Preset view")
        case .top: String(localized: "Top", comment: "Preset view")
        case .bottom: String(localized: "Bottom", comment: "Preset view")
        }
    }
}

extension UnitGuess {
    var localizedTitle: String {
        switch self {
        case .metres: String(localized: "Metres")
        case .centimetres: String(localized: "Centimetres")
        case .inches: String(localized: "Inches")
        }
    }

    /// VoiceOver, when a model opens suspiciously small: one whole sentence per unit,
    /// since languages put the unit name in different cases.
    var smallModelAnnouncement: String {
        switch self {
        case .metres: String(localized: "This model is very small. It may be in metres. Options are below the size.")
        case .centimetres: String(localized: "This model is very small. It may be in centimetres. Options are below the size.")
        case .inches: String(localized: "This model is very small. It may be in inches. Options are below the size.")
        }
    }
}

extension Plate {
    var localizedTitle: String {
        if let name, !name.isEmpty { return String(localized: "Plate \(id): \(name)", comment: "A slicer project's plate: its number, then its name") }
        return String(localized: "Plate \(id)", comment: "A slicer project's plate, by number")
    }
}

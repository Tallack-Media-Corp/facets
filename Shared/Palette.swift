import SwiftUI
#if os(iOS)
import UIKit
typealias PlatformColor = UIColor
#else
import AppKit
typealias PlatformColor = NSColor
#endif

/// The design system's colours (DESIGN.md), shared by the app and the Quick Look
/// preview so a model is staged the same way wherever it's shown.
enum Palette {
    /// Filament Orange: the app tint and the default model colour.
    static let filamentOrange = "#F2782E"

    /// The viewer's backdrop, top to floor. Near black in dark mode, so the model is
    /// what's lit.
    static let stage = stage(pureBlack: false)
    /// The same sweep in miniature behind thumbnails and tiles.
    static let tile = tile(pureBlack: false)

    /// With Pure Black on (for OLED screens), dark mode's floor goes to true black.
    static func stage(pureBlack: Bool) -> (top: PlatformColor, floor: PlatformColor) {
        pureBlack
            ? (PlatformColor(light: 0xF6F7F9, dark: 0x101113), PlatformColor(light: 0xD9DCE1, dark: 0x000000))
            : (PlatformColor(light: 0xF6F7F9, dark: 0x1B1C20), PlatformColor(light: 0xD9DCE1, dark: 0x08090A))
    }

    static func tile(pureBlack: Bool) -> (top: PlatformColor, floor: PlatformColor) {
        pureBlack
            ? (PlatformColor(light: 0xF7F8FA, dark: 0x16171A), PlatformColor(light: 0xE4E7EB, dark: 0x000000))
            : (PlatformColor(light: 0xF7F8FA, dark: 0x232428), PlatformColor(light: 0xE4E7EB, dark: 0x131417))
    }
}

extension PlatformColor {
    /// A colour that follows light and dark appearance.
    convenience init(light: UInt32, dark: UInt32) {
        func component(_ rgb: UInt32, _ shift: UInt32) -> CGFloat { CGFloat((rgb >> shift) & 0xFF) / 255 }
        #if os(iOS)
        self.init { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: component(rgb, 16), green: component(rgb, 8), blue: component(rgb, 0), alpha: 1)
        }
        #else
        self.init(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: component(rgb, 16), green: component(rgb, 8), blue: component(rgb, 0), alpha: 1)
        }
        #endif
    }
}

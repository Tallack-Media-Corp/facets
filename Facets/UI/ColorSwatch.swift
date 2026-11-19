import SwiftUI

/// A colour as a circle with a faint edge, so white and black read on any
/// background: a filament or object beside its name, the colour presets in Settings.
struct ColorSwatch: View {
    let color: Color
    var size = Size.swatchSmall

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(.quaternary, lineWidth: Stroke.hairline))
            .frame(width: size, height: size)
    }
}

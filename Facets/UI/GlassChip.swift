import SwiftUI

extension View {
    /// A chip floating over the content: padded by a `ChipPadding` token on a glass
    /// capsule. The gesture hint and toasts.
    func glassChip(_ padding: EdgeInsets) -> some View {
        self.padding(padding).glassChip()
    }

    /// The chip's glass alone, for a control: its label carries the padding (so the
    /// whole chip takes the tap) and this goes on the control, interactive. A rounded
    /// rectangle instead of a capsule with `cornerRadius` (the two-line readout).
    @ViewBuilder
    func glassChip(interactive: Bool = false, cornerRadius: CGFloat? = nil) -> some View {
        let glass: Glass = interactive ? .regular.interactive() : .regular
        if let cornerRadius {
            glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
        } else {
            glassEffect(glass, in: .capsule)
        }
    }
}

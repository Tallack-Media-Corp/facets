import SwiftUI

extension View {
    /// A card of regular glass floating over the content: a tool panel, a tip, the
    /// unit card (all 24pt corners, at most 440pt wide), or the loading panel (20pt,
    /// as wide as its words). `margin` keeps it off the screen's sides; nil is the
    /// system's standard margin.
    func glassCard(padding: EdgeInsets = EdgeInsets(), cornerRadius: CGFloat = Radius.panel, maxWidth: CGFloat? = Size.cardMaxWidth, margin: CGFloat? = nil) -> some View {
        self.padding(padding)
            .frame(maxWidth: maxWidth)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            .padding(.horizontal, margin)
    }

    /// A sheet's Done: a checkmark at the confirming end of its bar, while `shown`.
    func doneButton(shown: Bool = true, action: @escaping () -> Void) -> some View {
        toolbar {
            if shown {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: Symbol.done, action: action)
                }
            }
        }
    }
}

/// The close button in a floating card's corner. A tool panel's is a full-size glyph
/// in ink; a tip's is small and quiet, since most people should read the tip rather
/// than dismiss it. Both take a 44pt tap, without pushing their neighbours away.
struct CardCloseButton: View {
    enum Style {
        /// A tool panel's header: 44pt, reaching into the card's padding.
        case panel
        /// A tip: drawn at 30pt, hit at 44pt.
        case tip
    }

    var style = Style.panel
    /// What VoiceOver calls it ("Close Measure", "Close Tip").
    let label: Text
    let action: () -> Void

    var body: some View {
        switch style {
        case .panel:
            Button("Close", systemImage: Symbol.close, action: action)
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: Size.minTapTarget, height: Size.minTapTarget)
                .contentShape(.rect)
                .padding(.vertical, -Spacing.md)
                .padding(.trailing, -Spacing.roomy)
                .accessibilityLabel(label)
        case .tip:
            Button(action: action) {
                Image(systemName: Symbol.close)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: Size.minTapTarget, height: Size.minTapTarget)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // Laid out at its drawn size, so the card's text doesn't move.
            .padding(-(Size.minTapTarget - Size.smallCloseButton) / 2)
            .accessibilityLabel(label)
        }
    }
}

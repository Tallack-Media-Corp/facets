import SwiftUI

// Facets' design tokens, from DESIGN.md's front matter: every size, radius, spacing,
// padding and timing a screen uses comes from here, so one job looks the same
// everywhere. A value between the documented steps keeps its own name (and a line
// saying where it's used) rather than being snapped to the scale.

/// Space between and around things: DESIGN.md's steps, then the in-between values
/// screens were tuned with.
enum Spacing {
    static let hair: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24

    /// A choice's figure under its name (the unit card's buttons).
    static let stacked: CGFloat = 1
    /// A list row's title to its caption.
    static let rowText: CGFloat = 3
    /// A chip's glyph to its words; a short label over its control; a footer's lines.
    static let snug: CGFloat = 6
    /// Between the parts of a floating card; a swatch to its name; the sidebar foot's sides.
    static let roomy: CGFloat = 10
    /// Above an empty library's message, so it sits in the middle of the screen.
    static let emptyStateTop: CGFloat = 80
}

/// Corner radii.
enum Radius {
    /// A list row's picture.
    static let rowThumb: CGFloat = 10
    /// Library cards, folder tiles, cloud tiles.
    static let tile: CGFloat = 14
    /// The loading panel.
    static let overlay: CGFloat = 20
    /// The dashed drag-and-drop outline.
    static let dropTarget: CGFloat = 24
    /// Floating cards: tool panels, tips, the unit card.
    static let panel: CGFloat = 24
    /// The size readout, a rounded rectangle while it has two lines.
    static let readout: CGFloat = 16
    /// A selected card's outline on the Mac, 3pt outside its tile.
    static let selectionOutline: CGFloat = 16
    /// The tint wash behind a selected card's name on the Mac.
    static let selectionWash: CGFloat = 4
}

/// Fixed sizes and size limits.
enum Size {
    /// The smallest thing a finger or pointer should have to hit.
    static let minTapTarget: CGFloat = 44
    /// A Mac sheet holding a list or form (`sheetSize()`): a Mac sheet takes its
    /// content's ideal size, which for a list is almost nothing or everything.
    static let macSheetWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (420, 480, 640)
    static let macSheetHeight: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (360, 540, 720)
    /// A list row's picture at the default text size; it grows with the text up to the max.
    static let rowThumbnail: CGFloat = 52
    static let rowThumbnailMax: CGFloat = 88
    /// Library grid cards, as the adaptive grid fits them.
    static let gridCardMin: CGFloat = 150
    static let gridCardMax: CGFloat = 220
    /// Floating cards (tool panels, tips, the unit card) on a wide screen.
    static let cardMaxWidth: CGFloat = 440
    /// An empty state's message.
    static let emptyStateTextMaxWidth: CGFloat = 480
    /// My Models | Browse.
    static let segmentedMaxWidth: CGFloat = 320
    /// Panels docked at the side when height is short (iPhone in landscape).
    static let dockedToolPanel: CGFloat = 340
    static let dockedUnitCard: CGFloat = 360
    /// The Info inspector beside the model on iPad and Mac.
    static let inspectorMin: CGFloat = 320
    static let inspectorIdeal: CGFloat = 360
    static let inspectorMax: CGFloat = 440
    /// A library card's context-menu preview.
    static let contextPreview: CGFloat = 300
    /// Colour swatches: the presets in Settings, and a filament or object beside its name.
    static let swatch: CGFloat = 36
    static let swatchSmall: CGFloat = 18
    /// Settings' swatch grid columns (at least `minTapTarget`).
    static let swatchColumnMax: CGFloat = 52
    /// An app icon choice's picture.
    static let iconPreview: CGFloat = 64
    /// A tip's glyph column.
    static let tipGlyphWidth: CGFloat = 28
    /// A tip's close button as drawn (its hit area is `minTapTarget`).
    static let smallCloseButton: CGFloat = 30
    /// The glyph row above a tool button's title.
    static let toolGlyphHeight: CGFloat = 22
    /// The Settings gear at the foot of the Mac's sidebar.
    static let sidebarButton: CGFloat = 24
    /// The printer glyph beside the readout's caption, before Dynamic Type scales it.
    static let readoutGlyph: CGFloat = 14
    /// How far a toast sits above iPhone's tab bar, and above the viewer's bottom
    /// toolbar on iPhone and iPad (measured against the bars on iOS 26).
    static let toastOverTabBar: CGFloat = 88
    static let toastOverToolbar: CGFloat = 80
}

/// Line widths.
enum Stroke {
    /// A swatch's edge, so white and black read on any background.
    static let hairline: CGFloat = 1
    /// Settings' ring round the chosen colour.
    static let swatchSelection: CGFloat = 2.5
    /// A selected card's outline on the Mac, and the drop target's dashes.
    static let outline: CGFloat = 3
    static let dropTargetDash: [CGFloat] = [10, 6]
}

/// The padding inside a glass chip, by kind (DESIGN.md: readout 6 by 12, plate
/// picker 8 by 14, toast and gesture hint 10 by 16).
enum ChipPadding {
    static let readout = EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
    static let plate = EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
    static let toast = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
    /// A toast with a button: the button's own 44pt height sets it, and its side is closer.
    static let toastWithAction = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 12)
}

/// The padding inside a floating card.
enum CardPadding {
    static let toolPanel = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    /// Tips pad themselves (FacetsTipStyle), so the size chip's popover has it too.
    static let tip: CGFloat = 16
    /// The unit card.
    static let unitCard = EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
    /// The loading panel.
    static let loading = EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20)
}

/// Animations and how long things stay. Movement goes through `animation(_:reduceMotion:)`
/// and `transition(_:reduceMotion:)`, so Reduce Motion is honoured everywhere.
enum Motion {
    /// Most changes: a toast coming or going, the library's tip card, Save to Library's tick.
    static let standard = Animation.snappy
    /// A tool panel or the unit card coming and going.
    static let panel = Animation.snappy(duration: 0.25)
    /// The gesture hint fading in, and out on its own.
    static let hintIn = Animation.easeOut(duration: 0.3)
    static let hintOut = Animation.easeIn(duration: 0.3)
    /// The gesture hint leaving at the first touch, a little quicker.
    static let hintDismissed = Animation.easeIn(duration: 0.25)
    /// Words changing in place (Lay Flat's hint line). A fade, so it stays under Reduce Motion.
    static let crossfade = Animation.easeInOut(duration: 0.2)

    /// The gesture hint waits for the model to appear, then stays this long.
    static let hintDelay = Duration.seconds(0.6)
    static let hintShown = Duration.seconds(6)
    /// A toast; one with a button stays longer so there's time to reach it.
    static let toastShown = Duration.seconds(3)
    static let toastWithActionShown = Duration.seconds(6)
    /// Lay Flat's "Already the best way up to print."
    static let alreadyBestShown = Duration.seconds(2.5)

    /// The animation, or none with Reduce Motion on.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// A transition that moves, or a plain fade with Reduce Motion on.
    static func transition(_ moving: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : moving
    }
}

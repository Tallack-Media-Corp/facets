---
name: Facets
description: A small, fast STL and 3MF viewer for iPhone and iPad, staged like a part on a clean print bed.
colors:
  filament-orange: "#F2782E"
  stage-light-top: "#F6F7F9"
  stage-light-bottom: "#D9DCE1"
  stage-dark-top: "#1B1C20"
  stage-dark-bottom: "#08090A"
  tile-light-top: "#F7F8FA"
  tile-light-bottom: "#E4E7EB"
  tile-dark-top: "#232428"
  tile-dark-bottom: "#131417"
  grid-ink-light: "rgba(69, 74, 84, 0.50)"
  grid-ink-dark: "rgba(231, 235, 243, 0.07)"
  icon-cream-top: "#FFF7EF"
  icon-cream-bottom: "#F6DCC6"
  icon-charcoal-top: "#2A2C31"
  icon-charcoal-bottom: "#0C0D10"
  icon-navy-top: "#222C45"
  icon-navy-bottom: "#0B1020"
typography:
  large-title:
    fontFamily: "SF Pro, system-ui"
    fontSize: "34pt"
    fontWeight: 700
  headline:
    fontFamily: "SF Pro, system-ui"
    fontSize: "17pt"
    fontWeight: 600
  card-title:
    fontFamily: "SF Pro, system-ui"
    fontSize: "15pt"
    fontWeight: 500
  chip-label:
    fontFamily: "SF Pro, system-ui"
    fontSize: "15pt"
    fontWeight: 600
  readout:
    fontFamily: "SF Pro, system-ui"
    fontSize: "13pt"
    fontWeight: 500
    fontFeature: "tnum"
  caption:
    fontFamily: "SF Pro, system-ui"
    fontSize: "12pt"
    fontWeight: 400
  caption-small:
    fontFamily: "SF Pro, system-ui"
    fontSize: "11pt"
    fontWeight: 400
rounded:
  row-thumb: "10px"
  tile: "14px"
  overlay: "20px"
  drop-target: "24px"
  capsule: "9999px"
spacing:
  hair: "2px"
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
components:
  library-card-tile:
    rounded: "{rounded.tile}"
    width: "150-220px"
  list-row-thumbnail:
    rounded: "{rounded.row-thumb}"
    size: "52px"
  readout-chip:
    typography: "{typography.readout}"
    rounded: "{rounded.capsule}"
    padding: "6px 12px"
  plate-picker-chip:
    typography: "{typography.chip-label}"
    rounded: "{rounded.capsule}"
    padding: "8px 14px"
  saved-toast:
    typography: "{typography.card-title}"
    rounded: "{rounded.capsule}"
    padding: "10px 16px"
  button-prominent:
    backgroundColor: "{colors.filament-orange}"
    rounded: "{rounded.capsule}"
  colour-swatch:
    rounded: "{rounded.capsule}"
    size: "36px"
  icon-picker-preview:
    size: "64px"
---

# Design System: Facets

## Overview

**Creative North Star: "The Print Bed"**

Every screen is a print bed. A calm, neutral stage holds one thing worth looking at, the model, in filament colour, with a millimetre grid underfoot. The interface is the printer's enclosure glass: present, clear, out of the way. Nothing competes with the part.

Facets is a native iOS tool in Operate mode, so it is quiet by design. Structure, navigation and controls are stock SwiftUI and Liquid Glass; brand lives in exactly three places: the filament orange tint, the soft studio gradient behind models, and the rendered models themselves. Density is moderate: generous grids of thumbnails in the library, inset grouped lists for settings and details, and a full-bleed stage in the viewer.

Confirmed rejections: no custom fonts, no heavy decoration (gradient washes, illustrations, ornament beyond the model itself), and no dark-only "pro CAD" look. Light and dark are equal citizens.

**Key Characteristics:**
- One brand colour, Filament Orange, used as the system tint and the default model colour.
- Neutral studio gradients stage every model, in the viewer and in every thumbnail.
- Liquid Glass is the only thing that floats; content is flat.
- San Francisco and Dynamic Type everywhere.
- Rendered models are the only imagery.

## Colors

A single warm accent over cool, quiet neutrals: the orange of a fresh spool against a grey enclosure.

### Primary
- **Filament Orange** (#F2782E): the app tint (selected tab, buttons, toggles, prominent glass buttons, selection rings, folder glyphs) and the default colour every model renders in, in the app, in Quick Look and in thumbnails. One value, everywhere.

### Neutral
- **Stage** (light #F6F7F9 to #D9DCE1, dark #1B1C20 to #08090A, top to bottom): the viewer's backdrop behind the transparent 3D canvas. Cool, desaturated, darker at the floor like a studio sweep.
- **Tile** (light #F7F8FA to #E4E7EB, dark #232428 to #131417): the same sweep in miniature behind every thumbnail, folder tile and cloud tile, so white and grey models still read.
- **Pure Black** (Settings › Viewer, off by default): in dark mode the stage runs #101113 to #000000 and tiles #16171A to #000000, for OLED screens. The dark grid is kept at 7% opacity because blending happens in linear light, where a little alpha over near-black reads bright.
- **Grid Ink** (light rgba(69, 74, 84, 0.50), dark rgba(231, 235, 243, 0.07)): the build-plate grid under a model. Minor lines at 40% of this, every fifth line at 80%. The alphas differ sevenfold because blending is in linear light, where dark ink on a pale stage reads far fainter than light ink on a dark one; at these values both stand out from their stage by about the same amount. The plate reaches 60% of the model's span past it and feathers out over its outer two thirds on an eased curve, so it dissolves rather than stops.
- **System semantics**: page backgrounds (systemGroupedBackground), text (label, secondaryLabel, tertiaryLabel) and separators come from iOS, never hex.
- **Icon fills** (cream #FFF7EF to #F6DCC6, charcoal #2A2C31 to #0C0D10, navy #222C45 to #0B1020): app icon backgrounds only. They never appear in the interface.

Filament presets (Orange, White, Grey, Black, Red, Yellow, Green, Blue, Purple) and colours read from 3MF files are content: they colour models, never interface.

### Named Rules
**The One Orange Rule.** The UI tint and the default model colour are the same Filament Orange (#F2782E). Any orange that isn't this value is drift.

**The Dash Means Doesn't Fit Rule.** A warning never relies on Filament Orange alone, because the model is often orange too. A bed outline the part doesn't fit is dashed, and the note beside it carries a warning symbol.

**The Content Is Colour Rule.** Filament colours from files and presets paint models only. Interface elements take Filament Orange or system semantics, nothing else.

## Typography

**Display Font:** San Francisco (SF Pro), via system text styles
**Body Font:** San Francisco (SF Pro), via system text styles
**Label/Mono Font:** San Francisco with tabular figures for measurements

**Character:** Entirely the system's voice. Hierarchy comes from Apple's text styles and weight, never from a brand face, so everything follows the user's reading size.

### Hierarchy
- **Large Title** (bold, 34pt at default size): top-level screens (Library, Recents, Search, Settings), collapsing inline on scroll.
- **Headline** (semibold, 17pt): row titles in lists (library list, recents, search results).
- **Card Title** (medium, 15pt, subheadline): names under library grid cards, toast text; up to two lines.
- **Chip Label** (semibold, 15pt, subheadline): the plate picker over the model.
- **Readout** (medium, 13pt, footnote, tabular figures): the dimensions chip, labelled "W 156.5 · D 176.0 · H 79.6 mm" and spoken as "156.5 millimetres wide, 176.0 deep, 79.6 high". Measurements always use tabular figures and one decimal place (176.0, not 176) so they don't jitter or mix precision.
- **Caption** (regular, 12pt): metadata lines ("STL · 217 KB · 1:59 PM"), joined with middle dots.
- **Caption Small** (regular, 11pt, caption2): secondary context such as a search hit's folder path.

### Named Rules
**The San Francisco Rule.** No custom fonts, no hard-coded point sizes: every text style is a system style that scales with Dynamic Type.

**The Tabular Measure Rule.** Any number the user compares (dimensions, volume, counts) uses monospaced digits.

## Layout

The library is an adaptive grid: columns from 150 to 220pt wide with 16pt between columns and 20pt between rows, top-aligned so cards with two-line names don't misalign their thumbnails, inside the standard 16pt side margins. Each card is a square thumbnail, 8pt, then a name and a caption line. The same content switches to a list (52pt thumbnails, 12pt gap to text) from the view options menu.

Settings, info sheets, Browse and Recents are inset grouped lists. The viewer is full-bleed: the 3D canvas ignores the safe area, chips sit at the top below the navigation bar (8pt apart, stacked and centred), and tools live in the bottom toolbar, which replaces the tab bar there.

On iPad the tab bar moves to the top and the grid simply gains columns; no separate iPad layout exists. At accessibility text sizes the library always shows rows, because two columns can't hold a name. Spacing steps are 2, 4, 8, 12, 16, 20 and 24pt.

## Elevation & Depth

Flat content, floating glass. Nothing in the interface casts a drop shadow. The only things above the content plane are system Liquid Glass: navigation and bottom toolbars, the tab bar, glass chips, the loading panel, toasts, sheets and menus. The only rendered depth is the model's own studio lighting (key, fill, sky and a little rim) and the soft gradient sweep behind it.

### Named Rules
**The Glass Over Stage Rule.** If it floats, it's system glass (`glassEffect`, glass button styles, sheets). Never hand-roll blur or add a shadow to make something feel lifted.

## Shapes

Gently rounded and consistent with iOS. Thumbnail and folder tiles use a 14pt corner, list thumbnails 10pt, the loading panel 20pt and the drag-and-drop target outline 24pt (dashed, 3pt, in Filament Orange). Floating chips and toasts are capsules. Swatches and icon-picker selection marks are circles. App icons use Icon Composer's own shape.

## Components

### Buttons
- **Shape:** system shapes: capsule glass for prominent actions, plain for toolbar and list actions.
- **Primary:** `.glassProminent` tinted Filament Orange, used sparingly (the "Import Files" call to action on an empty library).
- **Toolbar:** icon-only SF Symbols in system glass groups; related actions share a capsule (Fit + Views, Tools + Display; Save to Library + Share). Five items at most on the iPhone bar.
- **Info:** a sheet on iPhone (the model glides up above its medium detent); an inspector beside the canvas on iPad and Mac, so the canvas narrows and reframes instead of hiding under it. Shape-based estimates are rounded to what they can claim (time to 5 min, then quarter hours, then hours; grams to two significant figures); slicer figures stay exact.
- **Mac:** settings live in Facets › Settings… (⌘,), not a sidebar tab, and File › Open… (⌘O) opens any model in a window of its own. A click on the canvas waits out the double-click interval before it measures, so a double-click only fits. The library behaves like the Finder: a click selects (outline round the picture, the name highlighted in the tint), Command- and Shift-click extend, a double-click or Return opens, Space shows Quick Look, Command-Delete deletes, and models drag out to the Finder or a slicer. Browse locations are sidebar items under Locations, added with "Add Location…" at the sidebar's foot, instead of the Library | Browse switch. The Finder gets Facets' Quick Look preview and thumbnails for 3MF; for STL the Mac's own built-in previewer takes precedence over any app's. The Mac preview has no Stage: the model and grid sit on the Quick Look panel's own translucent material, as Apple's 3D preview does, so it reads as part of the OS (Pure Black doesn't apply there).
- **Recently Deleted:** with the library in iCloud Drive, deleted models go to a hidden `.recently-deleted` folder inside it (a move within iCloud, so nothing downloads and it works offline); otherwise to the app's own storage. The list reads both.
- **Unit check:** while the unit card is up, the readout's second line says "Check the file's units" (ruler, secondary) and no bed is drawn: no verdict on a size that's probably wrong. The card sits at the bottom, above the toolbar, in thumb reach, and the model reframes above it as it does for a tool panel.
- **Bottom-bar glyphs:** Preset Views is `move.3d`; Display (wireframe, grid, printer) is `slider.horizontal.3`, a view-options glyph rather than a grid toggle, and becomes the custom `printer3d` glyph (a template SVG in the asset catalogue: frame, gantry, nozzle, a part on the bed) once a printer is chosen. SF Symbols' `printer` is a paper printer, so it isn't used.
- **Library | Browse:** the segmented control is the first thing in each root list's own content, under the large title, so it scrolls and pulls to refresh with the list rather than staying pinned above it.
- **Tool panel:** one viewer tool at a time (Measure, Lay Flat, Cross-Section), opened from the Tools menu, whose button takes the open tool's symbol and the tint. Its controls sit in a regular-glass panel (24pt corners, max 440pt wide) above the bottom toolbar, in place of the gesture hint, with a 44pt close button. Measure markers are ink on a background-coloured halo, never the accent, since the model is often Filament Orange.
- **States:** toggles in the toolbar fill with the tint when on. A completed action swaps its symbol in place (plus becomes a checkmark) rather than disappearing.
- **Switches** in lists and sheets stay system green: on iOS green means "on", and tinting them orange would make them read as brand decoration. Filament Orange drives every other interactive element.
- **Haptics:** a selection tap for plate, wireframe, grid and printer-bed changes; success or warning feedback with each toast. Nothing else buzzes.

### Chips
- **Readout chip:** Readout type on a regular glass capsule (6pt by 12pt padding); shows "W 156.5 · D 176.0 · H 79.6 mm".
- **Plate picker chip:** Chip Label type on an interactive glass capsule (8pt by 14pt), a stacked-layers glyph, the plate title and a small chevron; opens a menu.
- **Grouping:** chips sit in one `GlassEffectContainer` so neighbouring glass merges correctly.

### Cards / Containers
- **Library card:** a square tile (14pt corners) with the Tile gradient and the rendered model inset 8%; name and caption beneath, no card background behind the text.
- **Folder tile:** the same tile with a large filled folder glyph in Filament Orange at 85%.
- **Cloud tile:** the same tile with an `icloud.and.arrow.down` glyph in secondary label colour for files not yet downloaded.
- **Shadow Strategy:** none (see Elevation & Depth).

### Inputs / Fields
- System only: search fields from `.searchable`, alerts with text fields for renaming, standard pickers and toggles. No custom fields.

### Navigation
- Tab bar with Library, Recents, Settings and a search-role tab; it minimises on scroll and hides inside the viewer.
- Library and Browse are a segmented control in a `safeAreaBar` directly under the large title (max 320pt wide), so every tab keeps its large title.
- Pushes use the zoom transition from a card into the viewer; files opened from other apps present the viewer full-screen with a Close button.

### Toast
- A capsule of regular glass at the bottom edge with a filled checkmark and Card Title text ("Saved to Library as …"); slides up with a snappy spring and leaves after about 2.5 to 3 seconds.

### Model Stage (signature)
On iPhone, when the info sheet sits at its medium height, the model scales down and glides up to stay whole between the chips and the sheet.

The viewer and every thumbnail are the same object at two scales: a Stage or Tile gradient, the model lit by the studio rig in Filament Orange (or its file colours), and in the viewer a fading millimetre grid at the model's base. Thumbnails render on a transparent background and sit on the Tile gradient, framed tightly on the model's real silhouette from the isometric view. Very dark colours (black filament, the Black preset) get a little neutral grey added in the shader, about #333333 at the darkest and fading out by mid-tones, so a black part shows its faces and details instead of a silhouette; this applies in the viewer, thumbnails and Quick Look alike.

### Printer Bed Outline
- When a printer bed is chosen (Settings › Viewer › Printer Bed, or the viewer's build-plate menu), the grid shader draws its outline under the model: a solid line in Grid Ink at up to 80% when the part fits, a dashed line in Filament Orange at 95% when it doesn't. Inside the bed the plate brightens slightly; outside, the grid drops to 45% so the bed reads first.
- The readout chip gains a second line in Caption that names the side that's over: "Fits the Bambu Lab A1 as oriented", "Fits the Prusa MK4S turned 90°" (secondary, checkmark), or "Too wide for the Bambu Lab A1 by 39.9 mm", "Too tall …", "Fits …, but runs off the plate as arranged" (primary text, tint warning triangle: orange caption text on glass falls below 4.5:1, so the symbol and dashed outline carry the warning). "As oriented" is honest about the check: it's the model's bounding box as it sits, not a lay-flat search. The chip becomes a 16pt-corner rounded rectangle while it has two lines, with a chevron: tapping it opens the full printer list. With no printer chosen, the second line reads "No printer selected" (secondary, the `printer3d` glyph, sized with `@ScaledMetric` so it grows with the caption) and the chip is still the way to pick one; there is no separate prompt. Settings › Printer › Check Fit Against a Printer (on by default) turns the whole feature off: the readout is then a plain dimensions capsule, no outline is drawn, and the Display menu drops its printer section.
- The bottom bar's Display menu holds Wireframe, Build Plate Grid, then the printer (None, up to four printers used lately, Other Printer…), so someone with several printers switches with a thumb. Opened from the viewer, the printer list marks each printer "Fits" or "Too small" for the model as it's oriented. Framing includes the bed when the model doesn't fit it or covers more than half of it.
- Slicer projects keep their real plate positions; anything else centres the bed under the model. Hidden when all plates show at once.

### Viewer Overlays
- Chips and hints floating over the model stop growing at the first accessibility text size (`.dynamicTypeSize(...accessibility1)`), so they never cover the model they describe. On iPad (regular width) the chips step up one text size to sit in proportion with the larger canvas.

### Gesture Hint
- Two short beats, one per model opened: first "Drag to turn · Pinch to zoom" (hand.draw), then "Double-tap to fit the model" (hand.tap), the way back when a model is lost off-screen. Each is a regular-glass capsule above the bottom toolbar in Card Title type, fades on the first touch or after 6 seconds, and advances only once the model has been moved while it showed. Never shown with VoiceOver on; there the canvas offers custom actions instead (turn, tilt, front, top, isometric, fit). One line on the smallest iPhone; no tours or coach marks elsewhere.

### Errors
- Never the system's error sentence. Say what happened and what to do, in a heading and one or two plain sentences ("File Not Found" / "It was moved, renamed or deleted since Facets last saw it."), with the next action as a button (Try Again, Remove from Recents). Alerts for failed actions name the action ("Couldn't Rename").

### Empty States
- System `ContentUnavailableView` with an SF Symbol (`cube.transparent`, `clock`, `magnifyingglass`), a one-line title and a short practical description; at most one prominent action.

## Do's and Don'ts

### Do:
- **Do** use Filament Orange (#F2782E) as the only tint and as the default model colour in the app, Quick Look and thumbnails.
- **Do** stage every model on the Stage or Tile gradient, in both light and dark appearance.
- **Do** use system text styles with Dynamic Type, and tabular figures for measurements.
- **Do** let Liquid Glass carry anything that floats, and group related glass controls in one capsule or container.
- **Do** keep thumbnails at 14pt corners in grids and 10pt in list rows.
- **Do** swap a symbol in place to confirm an action (plus to checkmark) instead of removing the control.
- **Do** honour Reduce Motion: camera moves and inertia snap instead of animating.

### Don't:
- **Don't** introduce custom fonts or hard-coded text sizes.
- **Don't** add gradient washes, illustrations or ornament; the model is the only imagery.
- **Don't** add drop shadows or hand-made blur to cards, tiles or panels.
- **Don't** build a dark-only, CAD-style interface; light and dark are both first-class.
- **Don't** let file or preset filament colours tint interface elements.
- **Don't** use a different orange anywhere; the app tint, the asset catalog accent, the model default and MeshKit's renderer default are all #F2782E.

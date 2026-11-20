# Keeping Facets consistent

One job, one piece: every job a person sees is built once and used everywhere, so
screens and platforms can't drift apart. Checks fail the build when someone goes
around a piece, and every screen is looked at before a build goes out.

## The rules

- Build only from the pieces in DESIGN.md's [Shared pieces](../DESIGN.md#shared-pieces) table. If none fits, extend one or add a new one to the table, with a source rule that bans the hand-built form, and replace every copy in the same change.
- Every size, radius, spacing, timing and glyph comes from the tokens (`Shared/Tokens.swift`, `Facets/UI/Symbols.swift`).
- Platform and appearance differences live inside the shared piece, never in a screen.
- A bug is a pattern: search for the same mistake elsewhere, fix all of it, and add the check that would have caught it (a row below).
- Check each fix on the platform it was reported on. Never call something fixed because the code looks right.
- Never take focus on the owner's Mac to check something; capture in the background.

## Where things live

| What | Where |
|---|---|
| The design map | DESIGN.md, "Shared pieces" |
| Tokens and glyphs | `Shared/Tokens.swift`, `Facets/UI/Symbols.swift` |
| Source rules (hand-built forms fail; `// rule-ok: <reason>` opts a line out) | `FacetsTests/SourceRulesTests.swift` |
| Design-map drift (every named piece exists, every shared file is mapped) | `FacetsTests/DesignMapTests.swift` |
| Visual sweep (every screen, iPhone, iPad and Mac, light and dark, into contact sheets) | `scripts/sweep.sh`, output in `.build/sweep/` |
| Direct ways into each screen (DEBUG launch settings) | listed in `Facets/App/FacetsApp.swift` (`openFromLaunchEnvironment`) |
| Clearing a finished round (derived data, sweep captures) | `scripts/housekeeping.sh` |

## Before any build goes out

1. All tests: `xcodebuild -scheme FacetsMac -derivedDataPath .build/DerivedData test` and, after a MeshKit change, `swift test` in `Packages/MeshKit`.
2. Both builds: the `Facets` scheme for iOS and `FacetsMac`.
3. The sweep: `scripts/sweep.sh` (quit Facets on the Mac first, or run `scripts/sweep.sh iphone ipad`).
4. Look at every contact sheet in `.build/sweep/`, comparing each screen with its neighbours. Fix what they show in one batch; confirm with at most one more sweep.
5. `scripts/housekeeping.sh` once the round is done.

## Kinds of bug and their checks

| Kind of bug | Reports | Check |
|---|---|---|
| A list row built by hand (the row picture duplicated, line limits and VoiceOver differing per list) | Batch 2 review | `ThumbnailRow` / `RowThumbnail`; source rules ban the hand-built forms |
| Whole-list actions as loose toolbar pills in Mac Settings | Batch 2 review | `.listActions(shown:leading:trailing:)` |
| Untranslated titles (text built in code that skipped the catalog) | Batch 2 review | `String(localized:)` as whole sentences; MeshKit names through `localizedTitle` |
| A caption truncated beside Restore in German or Spanish | Batch 3 review | `ThumbnailRow` gives every caption two lines (three at accessibility sizes) |
| A tip showing a different glyph from its control | Batch 3 review | Tips use the control's `Symbol` constant |
| Two plate bars in Quick Look drifting (corner, font, button size) | Batch 3 review | One `PlateSteps`/`PlateStepping`, each platform only draws it |
| Quick Look limits and format checks kept twice | Batch 3 review | `QuickLookLimits`, `ModelLoader.isZip(at:)`; `SharedValuesTests` |
| Quick Look showing only the system's file card for a large 3MF on a 4 GB iPad (out of memory mid-load) | Build 19, iPad mini | `QuickLookLimits.estimatedPeak` against the memory left, `PreviewContent`'s fallback; `SharedValuesTests.quickLookEstimateCoversMeasuredPeaks` |
| A 3MF's picture decoded once per extension | Build 19 fix | `ThreeMFReader.thumbnailImage(at:)`; `SourceRulesTests.packagePicturesComeFromMeshKit` |
| Two definitions of Filament Orange, two hex-to-linear paths | Batch 3 review | `RenderAppearance.linearColor(hex:)`; `SharedValuesTests.defaultOrangeIsFilamentOrange` |
| Typed-in sizes, curves and glyph names | Batch 2 audit | `SourceRulesTests` (`sizesAreTokens`, `animationsAreTokens`, `symbolsComeFromSymbols`) |
| The design map naming pieces that no longer exist | Batch 3 | `DesignMapTests` |
| Mac sheet with no size (Move showed no folders; the printer list ran off the window, ungrouped) | Batch 3 sweep | `.sheetSize()`; `SourceRulesTests.sheetsAreSized`; the Mac sweep |
| Dragging a library card onto a folder imported a copy into the folder on screen ("Kako 2", "Kako 3"…) | Build 20, Mac | `FileLibrary.dropMoves`: library files dropped anywhere move, never import; folder cards and rows take drops; `.dropHighlight`; `FileLibraryTests.dropsOfLibraryFilesMoveOnlyWhereTheyCan`, `SourceRulesTests.dropOutlinesComeFromDropHighlight` |
| Turned from portrait to landscape, the iPhone viewer kept the portrait zoom (model fit to height, much smaller); the iPad inspector refit late with an out-and-back pulse, and in portrait lay over the model without moving it | Build 21, iPhone and iPad | `ModelCanvasView.keepZoom`: a new canvas shape keeps the zoom relative to a fit; `trailingObscured` moves the model clear of an overlaid inspector; `CanvasFramingTests.newShapeKeepsTheFit` |
| Turning the device or opening Info, the model shrank for a moment before gliding to its new size: the first frame drew the old zoom at the new height, and a glide begun during the inspector's layout lost its first frames | Build 22, iPad and iPhone | `ModelCanvasView.keepZoom` starts from the same size on screen; glides start their clock at the first frame; `CanvasFramingTests.newShapeGlidesFromTheSameSizeOnScreen`; checked frame by frame in simulator recordings |
| A subfolder opened with its title small, as if scrolled, and the "Move to …" chip then sat over the first cards | Build 23, iPad (also in 1.2) | `FolderView.content` shows no scroll view until the folder is listed: an empty scroll view on the first frame made the bar collapse its large title; checked in the iPad simulator |
| Dragging a card inside a folder outlined the whole page, though dropping it there does nothing | Build 23, iPad | `.tracksLocalDrag(_:)`: on iOS 27 a drag that began in Facets doesn't outline the page (iOS 26 can't tell, so it still does); checked with a simulator drag |
| A smooth-scrolling mouse wheel or a Magic Mouse panned the Mac viewer instead of zooming | Build 21, Mac | `ModelCanvasView.scrollWheel`: only a scroll that starts with fingers on the trackpad (counted from its touches; a Magic Mouse sends none) pans; everything else zooms, whatever its deltas; `CanvasFramingTests.wheelAndMagicMouseZoomTrackpadPans` |
| A folder's count never updating when a file arrived inside it from outside the app (the Finder, iCloud from another device): only the open folder was watched | Build 20 review | `FolderWatcher.subfolders(of:onChange:)`; a folder that can't be listed shows "Folder", not "0 items"; `FileLibraryTests.subfolderCountsFollowFilesArrivingInside` |
| Library cards couldn't be dragged on iPhone and iPad (no moving onto a folder, no dragging a model out to Files or a slicer) | Owner, after build 20 | `.libraryDraggable(_:)` on every card and row, `LibraryDragItem` carrying the file and its URL; `SourceRulesTests.dragSourcesComeFromLibraryDraggable`. Open: on iOS a drag begun on a list row landed nowhere in the app, so iOS list rows don't drag yet (Move… there) |

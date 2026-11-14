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
| Two definitions of Filament Orange, two hex-to-linear paths | Batch 3 review | `RenderAppearance.linearColor(hex:)`; `SharedValuesTests.defaultOrangeIsFilamentOrange` |
| Typed-in sizes, curves and glyph names | Batch 2 audit | `SourceRulesTests` (`sizesAreTokens`, `animationsAreTokens`, `symbolsComeFromSymbols`) |
| The design map naming pieces that no longer exist | Batch 3 | `DesignMapTests` |
| Mac sheet with no size (Move showed no folders; the printer list ran off the window, ungrouped) | Batch 3 sweep | `.sheetSize()`; `SourceRulesTests.sheetsAreSized`; the Mac sweep |

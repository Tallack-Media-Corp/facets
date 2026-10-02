# Print estimates without a slicer

A 3MF saved after slicing in Bambu Studio or Orca carries the slicer's own time and filament per plate (`Metadata/slice_info.config`), and Facets shows those. Everything else (STL, OBJ, unsliced 3MF) gets an estimate from the model's shape, in `PrintEstimate` (MeshKit).

## Why not "percent of solid"

Printed parts aren't solid, but they aren't a fixed fraction of solid either. A slicer lays down:

- **walls** round the sides (2 or 3 lines, about 0.9 mm),
- **solid skins** on what faces up and down (about 1 mm and 0.6 mm),
- **sparse infill** (usually 15%) in whatever is left.

A thin-walled bracket is nearly all wall and prints close to solid; a chunky block is mostly infill and prints far lighter. So the estimate splits each model the same way, from its own surface.

## The model

From the triangles, in the same pass that computes the volume:

- **side** = Σ area × √(1 − n_z²): per layer, the perimeter length, so walls = side × walls × line width;
- **up / down** = Σ area × n_z for faces pointing up or down: the footprint of the skins, × layers × layer height;
- shell = walls + skins, capped at the solid volume (a thin part is all shell);
- infill = (solid − shell) × 15%.

Weight is shell and infill times the filament's density. Time follows the extrusion paths (volume ÷ line width ÷ layer height), walls and skins at one rate and infill at another, with:

- a **minimum time per layer** (slicers slow small layers so they can cool),
- a cost per **piece per layer** (travel, retraction, seam),
- a fixed **start-up** (heating and the printer's own calibration).

Assumed settings: 0.2 mm layers, two 0.45 mm walls, 5 top and 3 bottom layers, 15% infill, 1.75 mm filament. It doesn't model supports.

## Calibration

Two rounds, both cross-validated by leaving each model out in turn (a model's plates, or its slices on several printers, would otherwise flatter each other).

**Round 1:** 34 plates from 10 projects sliced by Bambu Studio for X1C, P1S, P1P and A1 printers, with whatever settings each project used.

**Round 2:** 259 more plates: real projects sliced by Orca Slicer's command line with its stock 0.20 mm profiles for a Bambu Lab X1C and A1, a Creality K1 and an Ender-3 V3 (2 walls, 15% infill, 5 top and 3 bottom layers; the Ender's profile uses 3 walls and 3 top layers). The batch was stopped early because Orca's command line crashed on many of the projects; the 259 are the usable plates from the slices that completed. A Prusa MK4S profile wouldn't slice from the command line, so Prusa printers borrow the closest kind (below).

### Weight

Median absolute error against the slicer, no supports:

| Data | Solid | Best fixed fraction | Shape model (shipped constants) |
|---|---|---|---|
| Bambu Studio projects (own settings) | 83% | 24% | 9% |
| Orca, X1C | | 38% | 9% |
| Orca, A1 | | 42% | 7% |
| Orca, K1 | | 37% | 8% |
| Orca, Ender-3 V3 | | 38% | 7% |

The mass factors (0.78 × shell, 1.30 × infill) were chosen to keep the worst of those five as low as possible (9.2%). Slicers don't quite fill a shell, and lay infill denser than its nominal percentage, solid where it's narrow. With supports (28 plates) the error is 12%; a support-volume term from overhangs didn't improve it, so supports aren't modelled.

### Time

Time depends on the printer, so each kind has its own speeds. Median absolute error:

| Printer kind (fitted on) | Volume only | Shape model |
|---|---|---|
| Bambu CoreXY (X1C) | 34% | 14% |
| Bambu bed-slinger (A1) | 36% | 14% |
| Other fast CoreXY (K1) | 49% | 19% |
| Other bed-slingers (Ender-3 V3) | 42% | 23% |
| One model for every printer | | 21% |

Orca's estimates leave out most of a Bambu printer's start-up (its calibration routine), which Bambu Studio's include. Bambu users compare against Bambu Studio, so the Bambu kinds take their path speeds from the Orca slices and their start-up from the Bambu Studio projects (600 s CoreXY, 360 s A1): 6.5% median on those projects' typical-settings plates.

The app picks the kind from the printer chosen in Facets: A1 and A1 mini are Bambu bed-slingers, other Bambu printers Bambu CoreXY; K1, K2 Plus, Voron 2.4, Prusa Core One and XL are fast CoreXY; Ender-3 V3, Neptune 4 Pro, Prusa MK4S and MINI+ are bed-slingers. With no printer (or a custom bed) it assumes a Bambu CoreXY.

## Recalibrating

1. `MESHKIT_CALIBRATE=<folder of sliced 3MFs> MESHKIT_CALIBRATE_OUT=plates.csv swift test -c release -Xswiftc -enable-testing --filter CalibrationDump` (in `Packages/MeshKit`) writes one row per sliced plate: shape features, the project's settings, and the slicer's figures.
2. `python3 tools/estimates/fit.py plates.csv` (round 1) or `python3 tools/estimates/fit2.py bambu.csv x1c=orca_x1c.csv a1=…` (round 2) compares the methods and prints fitted constants.
3. To slice your own set with Orca's command line, `tools/estimates/flatten_orca_profile.py` turns a system profile's `inherits` chain into the single file `--load-settings` needs. Expect Orca to crash on some projects; run small batches.
4. Copy the constants into `PrintEstimate`, and update the `matchesTheCalibration` test.

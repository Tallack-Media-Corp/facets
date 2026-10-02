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

The constants were fitted to 34 plates from 10 projects sliced by Bambu Studio for X1C, P1S, P1P and A1 printers, cross-validated by leaving each project out in turn (plates from one project share settings, so they'd flatter each other). Median absolute error:

| Method | Weight | Time |
|---|---|---|
| Solid (volume × density) | 83% | — |
| Best single fraction of solid (0.47) | 28% | — |
| Volume only (+ start-up) | — | 25% |
| **Shape model, assumed defaults** | **17%** | **17%** |
| Shape model, the project's real settings | 17% | 11% |

Within 20% of the slicer: 22 of 34 plates for weight (against 11 for the best fixed fraction), 19 of 34 for time. The worst misses are plates sliced with settings the app can't know about (100% infill, 0.08 mm layers, 5% infill) and a 27-piece plate with supports. Published no-slice estimators quote about ±30%.

Fitted constants: walls and skins print at about 103 mm/s of path and infill at about 110 mm/s; each piece costs about 1 s per layer; layers take at least 12 s; start-up is about 15½ minutes. The mass factors (0.87 for shell, 0.81 for infill) absorb how slicers overlap lines and leave gaps.

The time constants describe Bambu-class printers. Slower printers will take longer than the estimate says.

## Recalibrating

1. `MESHKIT_CALIBRATE=<folder of sliced 3MFs> MESHKIT_CALIBRATE_OUT=plates.csv swift test -c release -Xswiftc -enable-testing --filter CalibrationDump` (in `Packages/MeshKit`) writes one row per sliced plate: shape features, the project's settings, and the slicer's figures.
2. `python3 tools/estimates/fit.py plates.csv` compares the methods and prints the fitted constants.
3. Copy the constants into `PrintEstimate`, and update the `matchesTheCalibration` test.

More plates, and plates from other printers (Prusa, Creality), would tighten the numbers and allow per-printer speeds.

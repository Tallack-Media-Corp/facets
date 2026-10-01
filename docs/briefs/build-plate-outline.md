# Brief: build-plate outline

Confirmed with Brennan, 1 October 2026 (Impeccable shape). Build after the adapt and onboard passes.

1. **Job.** A hobbyist who has just opened a model on their phone wants to know at a glance whether it fits their printer, instead of comparing "W 156.5 · D 176.0 · H 79.6 mm" against their bed in their head.
2. **Outcome.** The viewer draws the user's bed as an outline on the grid, with its width and depth labelled at one corner. If the part's footprint is bigger than the bed, the outline turns Filament Orange and the size chip adds "Too big for A1 by 12 mm". A warning, never a block.
3. **Bed choice.** Settings › Viewer gains "Printer bed": None (default), presets grouped by make, and Custom (width × depth, in the chosen units). The viewer's grid button becomes a menu (Grid on/off plus the bed list) so another printer can be tried without leaving the model.
   - Bambu Lab: A1 mini 180×180; A1, P1S, P2S, X1C 256×256; H2D 325×320.
   - Prusa: MINI+ 180×180; MK4S 250×210; Core One 250×220; XL 360×360.
   - Creality and others: Ender-3 V3 220×220; K1 220×220; K2 Plus 350×350; Elegoo Neptune 4 Pro 225×225; Voron 2.4 350×350.
   - **These sizes are from memory: verify each against the manufacturer's published spec before shipping.**
4. **Placement.** STLs and plain 3MFs are centred on the bed. Bambu Studio and Orca projects keep their real plate positions, so the outline matches the slicer, one plate at a time.
5. **Fit.** Footprint only (X and Y). Height is shown but not judged. With "All Plates" selected the outline hides, because several plates can't share one bed.
6. **States.** No bed (today's grid, unchanged); fits; too big; custom bed; all plates; light and dark; VoiceOver announces "Fits on the Bambu A1 bed" or "Too big for the Bambu A1 by 12 millimetres".
7. **Constraints and open decisions.** Drawn by MeshKit's grid shader in 3D, not as a 2D overlay. Each Bambu plate's origin must be derived from real multi-plate files (plates are laid out side by side; don't assume a stride). Custom sizes follow the inches/millimetres setting.

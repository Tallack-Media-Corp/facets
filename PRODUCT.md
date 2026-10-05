# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Hobbyist 3D printer owners (Bambu Lab, Prusa, Orca Slicer users) on the go. They reach for Facets away from their computer: a model they just downloaded from MakerWorld, Printables or Thingiverse, or one a friend sent in Messages or Mail, and they want to see what it is, how big it is and whether it's worth printing before they get back to the slicer.

## Product Purpose

Facets is a free viewer for STL, 3MF and OBJ files on iPhone and iPad. It opens a model from anywhere on the device, shows it in 3D with its real size, and keeps a library of models worth keeping. Success is that looking at a 3D printing file on an iPhone feels as immediate as looking at a photo: tap it anywhere, and it's there.

## Positioning

- **Free, open source, private.** MIT licence, public repository (github.com/Tallack-Media-Corp/facets), no accounts, no network connections of its own (the library syncs through the user's iCloud Drive), nothing collected.
- **Fast and lightweight.** No dependencies; its own readers and Metal renderer open multi-million-triangle 3MF projects in about a second.
- **Lives inside iOS.** The library is a real folder in Files, files open in place from other apps, Quick Look shows a live 3D preview, and Files shows rendered thumbnails.
- **Understands slicer projects.** Bambu Studio and Orca 3MF plates, filament colours, multi-part objects and hidden modifiers, not just raw meshes.

## Operating Context

- Files arrive from Safari downloads, Messages, Mail, AirDrop, iCloud Drive and storage apps in Files; the share sheet and "Open in Facets" hand them over, in place where iOS allows.
- Users browse their own library (On My iPhone › Facets) or folders they add under Browse (security-scoped bookmarks; iOS only shows an app what the user picks).
- Viewing happens in short sessions, one-handed on a phone or on an iPad, often to decide whether to print. Printing itself happens in the slicer, or through a companion such as Culm for Bambuddy.

## Capabilities and Constraints

- Formats: binary and ASCII STL; 3MF (core, production extension, base materials and colour groups, multi-material painting from Bambu Studio, Orca and PrusaSlicer, Bambu/Orca metadata and slice estimates); OBJ. Units shown in millimetres or inches.
- Viewer: orbit, pan, pinch, twist, double-tap to fit, preset views, wireframe, build-plate grid, printer bed fit check, dimensions, volume, triangle count, per-object visibility, plate picker; tools to measure, lay flat and cut a cross-section; slicer print estimates.
- Library: folders, import, rename, duplicate, move, delete, drag and drop on iPad, search, recents; Browse for folders outside the library with Save to Library.
- iPhone and iPad, iOS 26 and later, SwiftUI and Swift 6; Quick Look preview and thumbnail extensions have tight memory limits on device.
- Copy is in English only for now, using Canadian spelling (colour, licence).

## Brand Commitments

- Name: **Facets**. App Store listing name planned as "Facets: STL & 3MF Viewer"; home screen name "Facets".
- Publisher: Tallack Media Corp.
- Liquid Glass interface throughout, native SwiftUI, following Apple's platform conventions. The design reference is Tallack Media's own Culm for Bambuddy app.
- App icon: a render of the public-domain (CC0) #3DBenchy model, credited in About. "Benchy" must not appear in the app name, subtitle or App Store keywords.
- Nothing tied to a developer account goes in the repository (signing stays in the git-ignored Config/Local.xcconfig).

## Evidence on Hand

- A working app and package with readers tested against about 80 real STL and 3MF files.
- Measured: a 3.9-million-triangle Bambu project parses in under a second on a Mac (optimised build).
- No users, reviews, ratings, press or download numbers exist yet; never invent them.

## Product Principles

1. **Opening a file is the product.** Every path into a model (Files, Messages, share sheet, Browse) should land in the viewer with as little in between as possible.
2. **Private by construction.** No feature may need a network connection, an account or data leaving the device.
3. **Small and quick beats complete.** Add capability only when it keeps launches, loads and the binary lean; Facets views, it doesn't slice, print or sell.
4. **Belong to iOS.** Prefer system affordances (Files, Quick Look, share sheet, standard navigation and controls) over custom ones.
5. **Speak printer.** Sizes on a build plate, plates, filament colours: present models the way the person will print them.

## Out of Scope

- Accounts, cloud sync or uploading files anywhere.
- Slicing, printing or controlling printers.
- Paid tiers, purchases or ads.
- Browsing MakerWorld, Printables or other model catalogues in the app.

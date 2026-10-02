# Facets

A small, fast viewer for 3D printing files on iPhone and iPad. Open STL, 3MF and OBJ models from anywhere, keep a library of them, and preview them in 3D right in the Files app.

Free and open source (MIT). No accounts, no network access, no tracking.

## Features

- **Viewer**: orbit, pan, pinch and twist; double tap to fit; front, back, side, top, bottom and isometric views; wireframe; a millimetre build-plate grid; size readout in mm or inches.
- **Fit check**: pick your printer (Bambu Lab, Prusa, Creality, Elegoo, Voron or a custom bed) and the viewer outlines its bed under the model and says whether it fits, turned if need be. It can be turned off for dimensions only.
- **Tools**: measure between two points (snapping to corners), lay a model flat on any face or turn it a quarter at a time, and cut a cross-section to see walls and cavities.
- **Print estimates**: a project saved sliced from Bambu Studio or Orca shows the slicer's print time and filament per plate; anything else shows its weight if printed solid.
- **3MF projects**: Bambu Studio and Orca plates (pick one or show all), filament colours, multi-part objects, modifiers hidden, per-object visibility, and 3MF base material colours.
- **Library**: a folder of models with rendered thumbnails, subfolders, import, rename, duplicate, move, delete, drag and drop on iPad, and search across every folder.
- **Browse**: next to Library, add any folder from iCloud Drive, On My iPhone or a storage app in Files and look through it without importing. Folders are kept as security-scoped bookmarks (iOS only lets an app see what the user picks), iCloud files that aren't downloaded yet show a cloud and download when opened, and a plus beside Share saves a copy to the library.
- **Recents**: models opened from other apps are remembered with security-scoped bookmarks, so they reopen without picking them again.
- **iOS integration**:
  - STL, 3MF and OBJ open in Facets from Files, Mail, Messages, Safari downloads and share sheets, in place where possible.
  - The Facets library is a real folder in the Files app (On My iPhone › Facets).
  - A Quick Look extension shows a live, rotatable 3D preview wherever the system previews files.
  - A thumbnail extension draws STL, 3MF and OBJ thumbnails in Files.
  - Library models show up in Spotlight, and Shortcuts can open a model or get its dimensions.
  - Keyboard commands on iPad for views, tools, the grid and info.
- Liquid Glass throughout, light and dark.

## Requirements

- Xcode 27 or later (iOS 26 SDK), [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- iOS / iPadOS 26 or later

## Building

The Xcode project is generated and isn't committed.

```bash
brew install xcodegen
xcodegen generate
open Facets.xcodeproj
```

That builds and runs on the simulator with no further setup. To run on a device, copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` and set your team and a bundle id of your own. `Local.xcconfig` is git-ignored, so account details never reach the repository.

`scripts/run-sim.sh [simulator] [file]` builds, installs and launches on a simulator; the optional file (a path below the app's Documents folder) opens straight into the viewer in debug builds.

## Layout

| Path | What |
|---|---|
| `Facets/` | The app: library, recents, search, viewer, settings |
| `FacetsPreview/` | Quick Look preview extension (interactive 3D) |
| `FacetsThumbnail/` | Quick Look thumbnail extension |
| `Packages/MeshKit/` | File readers and the Metal renderer, shared by the app and both extensions |
| `Config/` | Build settings; `Local.xcconfig` (yours, ignored) holds signing |
| `project.yml` | XcodeGen spec |

### MeshKit

- `STLReader`: binary and ASCII, decided by size rather than the "solid" prefix (many binary files start with it).
- `ZipArchive`: a minimal reader (stored and deflate, ZIP64) on Apple's Compression framework, so there are no dependencies.
- `XMLScanner`: an allocation-free tokenizer. 3MF models can hold millions of `<vertex>` elements; this reads a 3.9-million-triangle Bambu project in under a second on a Mac.
- `ThreeMFReader`: core spec meshes, components and build items, the production extension's per-object model files, base materials and colour groups, and Bambu Studio / Orca `Metadata/` (plates, object names, filament colours, part types).
- `SceneRenderer`, `ModelCanvasView`, `ModelSnapshotter`: a small Metal renderer. Positions are the only vertex data; flat normals come from screen-space derivatives, which gives the faceted look of a printed part and halves memory. The view draws only when something changes. Shaders compile from source at runtime, so the package needs no Metal build step.

## Tests

```bash
cd Packages/MeshKit && swift test
```

The readers are tested against synthetic fixtures. Two opt-in checks read real files, which stay outside the repository:

```bash
# Parse every STL/3MF in a folder and print timings
MESHKIT_SAMPLES=~/Downloads swift test --filter RealFilesTests
# Render files to PNGs for a look
MESHKIT_SNAPSHOT_FILES=/path/a.stl:/path/b.3mf MESHKIT_SNAPSHOT_OUT=/tmp/snaps swift test --filter SnapshotTests
```

### Icons

The app icon and its alternates (Settings › App Icon) are Icon Composer documents in `Facets/Resources/Icons`, built by `python3 tools/icons/build_icons.py`, which also renders the picker previews. The Benchy artwork in `tools/icons/art` is rendered by MeshKit from the public domain (CC0) [#3DBenchy](https://www.3dbenchy.com) model by Creative Tools. The script's docstring has the command to redraw it; the STL itself isn't kept here.

## File types

STL uses the system's `public.standard-tesselated-geometry-format`. 3MF has no system type, so Facets imports `com.bambulab.3mf`, the identifier Bambu Studio declares and other 3MF apps on Apple platforms share. Both are imported rather than exported: Facets opens these files but doesn't claim to own them.

## TestFlight

Maintainers only: this needs the team and bundle id in `Config/Local.xcconfig`. Bump `CURRENT_PROJECT_VERSION` in `project.yml` first; App Store Connect rejects a build number it has already seen.

```bash
xcodegen generate
xcodebuild -project Facets.xcodeproj -scheme Facets -configuration Release -destination 'generic/platform=iOS' \
  -archivePath .build/archive/Facets.xcarchive -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath .build/archive/Facets.xcarchive \
  -exportOptionsPlist docs/ExportOptions.plist -exportPath .build/archive/export -allowProvisioningUpdates
xcrun altool --upload-app -f .build/archive/export/Facets.ipa -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

The export step is what registers the app's and extensions' bundle ids: with no entitlements the archive signs with the team's wildcard profile. The key is an App Store Connect API key at `~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8`.

## Licence

MIT. See [LICENSE](LICENSE).

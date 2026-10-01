# Facet

A small, fast viewer for 3D printing files on iPhone and iPad. Open STL and 3MF models from anywhere, keep a library of them, and preview them in 3D right in the Files app.

Free and open source (MIT). No accounts, no network access, no tracking.

## Features

- **Viewer**: orbit, pan, pinch and twist; double tap to fit; front, back, side, top, bottom and isometric views; wireframe; a millimetre build-plate grid; size readout in mm or inches.
- **3MF projects**: Bambu Studio and Orca plates (pick one or show all), filament colours, multi-part objects, modifiers hidden, per-object visibility, and 3MF base material colours.
- **Library**: a folder of models with rendered thumbnails, subfolders, import, rename, duplicate, move, delete, drag and drop on iPad, and search across every folder.
- **Recents**: models opened from other apps are remembered with security-scoped bookmarks, so they reopen without picking them again.
- **iOS integration**:
  - STL and 3MF open in Facet from Files, Mail, Messages, Safari downloads and share sheets, in place where possible.
  - Facet's library is a real folder in the Files app (On My iPhone › Facet).
  - A Quick Look extension shows a live, rotatable 3D preview wherever the system previews files.
  - A thumbnail extension draws STL and 3MF thumbnails in Files.
- Liquid Glass throughout, light and dark.

## Requirements

- Xcode 27 or later (iOS 26 SDK), [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- iOS / iPadOS 26 or later

## Building

The Xcode project is generated and isn't committed.

```bash
brew install xcodegen
xcodegen generate
open Facet.xcodeproj
```

That builds and runs on the simulator with no further setup. To run on a device, copy `Config/Local.example.xcconfig` to `Config/Local.xcconfig` and set your team and a bundle id of your own. `Local.xcconfig` is git-ignored, so account details never reach the repository.

`scripts/run-sim.sh [simulator] [file]` builds, installs and launches on a simulator; the optional file (a path below the app's Documents folder) opens straight into the viewer in debug builds.

## Layout

| Path | What |
|---|---|
| `Facet/` | The app: library, recents, search, viewer, settings |
| `FacetPreview/` | Quick Look preview extension (interactive 3D) |
| `FacetThumbnail/` | Quick Look thumbnail extension |
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

The app icon is drawn by the renderer too: `FACET_ICON_OUT=<AppIcon.appiconset path> swift test --filter IconTests`.

## File types

STL uses the system's `public.standard-tesselated-geometry-format`. 3MF has no system type, so Facet imports `com.bambulab.3mf`, the identifier Bambu Studio declares and other 3MF apps on Apple platforms share. Both are imported rather than exported: Facet opens these files but doesn't claim to own them.

## Licence

MIT. See [LICENSE](LICENSE).

#!/usr/bin/env python3
"""Build Facets' app icons as Icon Composer documents (.icon), one per design.

    python3 tools/icons/build_icons.py            # write the .icon bundles and picker previews
    python3 tools/icons/build_icons.py --preview DIR  # also render every appearance to PNGs in DIR

Each design is one or two flat layers on a 1024-point canvas over a gradient fill.
Icon Composer (and Xcode, from the same document) adds the Liquid Glass and derives
the dark, tinted and clear appearances; the dark background is set here.

The Benchy artwork in tools/icons/art comes from the public-domain (CC0) 3DBenchy
model by Creative Tools, rendered by MeshKit itself:

    cd Packages/MeshKit
    FACETS_BENCHY_STL=/path/to/3DBenchy.stl FACETS_ICON_ART_OUT=../../tools/icons/art \\
      swift test -Xswiftc -O --filter IconArtTests

The STL isn't kept in this repository; download it from 3dbenchy.com.
"""
import json
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).parent
ROOT = HERE.parents[1]
ART = HERE / "art"
OUT = ROOT / "Facets/Resources/Icons"
PREVIEWS = ROOT / "Facets/Resources/Assets.xcassets"
ICTOOL = "/Applications/Icon Composer.app/Contents/Executables/ictool"


def rgb(hex_colour: str) -> str:
    h = hex_colour.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"


CREAM = [rgb("#FFF7EF"), rgb("#F6DCC6")]
CHARCOAL = [rgb("#2A2C31"), rgb("#0C0D10")]
NAVY = [rgb("#222C45"), rgb("#0B1020")]


def svg(body: str) -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{body}</svg>\n'


def mesh_svg() -> str:
    """The wireframe mesh concept: the front half of an icosahedron."""
    faces = [
        ("512,212 392,452 632,452", "#FBB97A", 0.55), ("512,212 252,362 392,452", "#FBB97A", 0.4),
        ("512,212 632,452 772,362", "#F59A4A", 0.4), ("252,362 252,662 392,452", "#F59A4A", 0.35),
        ("772,362 632,452 772,662", "#E57A2A", 0.4), ("392,452 252,662 512,660", "#F59A4A", 0.3),
        ("632,452 512,660 772,662", "#E57A2A", 0.35), ("392,452 512,660 632,452", "#FBB97A", 0.25),
        ("252,662 512,812 512,660", "#E57A2A", 0.3), ("512,660 512,812 772,662", "#B85A1A", 0.35),
    ]
    body = "".join(f'<polygon points="{p}" fill="{c}" fill-opacity="{o}"/>' for p, c, o in faces)
    edges = ("M512 212 L772 362 L772 662 L512 812 L252 662 L252 362 Z M392 452 L632 452 L512 660 Z "
             "M392 452 L512 212 M392 452 L252 362 M392 452 L252 662 M632 452 L512 212 M632 452 L772 362 "
             "M632 452 L772 662 M512 660 L252 662 M512 660 L512 812 M512 660 L772 662")
    body += f'<path d="{edges}" fill="none" stroke="#E8742A" stroke-width="16" stroke-linejoin="round" stroke-linecap="round"/>'
    for x, y in [(512, 212), (772, 362), (772, 662), (512, 812), (252, 662), (252, 362), (392, 452), (632, 452), (512, 660)]:
        body += f'<circle cx="{x}" cy="{y}" r="22" fill="#E8742A"/>'
    return svg(body)


# name: (title, layer file name, layer source, light fill, dark fill)
DESIGNS = {
    "AppIcon": ("Benchy", "benchy.png", ART / "benchy.png", CREAM, CHARCOAL),
    "AppIcon-Mesh": ("Mesh", "mesh.svg", mesh_svg, CREAM, NAVY),
}


def icon_json(layer: str, light: list, dark: list) -> dict:
    return {
        "fill-specializations": [
            {"value": {"linear-gradient": light}},
            {"appearance": "dark", "value": {"linear-gradient": dark}},
        ],
        "groups": [{
            "layers": [{"image-name": layer, "name": pathlib.Path(layer).stem}],
            "shadow": {"kind": "neutral", "opacity": 0.5},
            "translucency": {"enabled": False, "value": 0},
        }],
        "supported-platforms": {"squares": "shared"},
    }


def write_picker_previews() -> None:
    """Light and dark previews for the in-app icon picker, as image sets."""
    for name in DESIGNS:
        imageset = PREVIEWS / f"IconPreview-{name}.imageset"
        shutil.rmtree(imageset, ignore_errors=True)
        imageset.mkdir(parents=True)
        images = []
        for appearance, suffix in (("Light", ""), ("Dark", "-dark")):
            file = f"{name}{suffix}.png"
            subprocess.run([ICTOOL, str(OUT / f"{name}.icon"), "--export-preview", "iOS", appearance, "80", "80", "3", str(imageset / file)],
                           check=True, capture_output=True)
            entry = {"filename": file, "idiom": "universal", "scale": "3x"}
            if suffix:
                entry["appearances"] = [{"appearance": "luminosity", "value": "dark"}]
            images.append(entry)
        (imageset / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    print("wrote picker previews")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (_, layer, source, light, dark) in DESIGNS.items():
        bundle = OUT / f"{name}.icon"
        shutil.rmtree(bundle, ignore_errors=True)
        (bundle / "Assets").mkdir(parents=True)
        if callable(source):
            (bundle / "Assets" / layer).write_text(source())
        else:
            shutil.copy(source, bundle / "Assets" / layer)
        (bundle / "icon.json").write_text(json.dumps(icon_json(layer, light, dark), indent=2) + "\n")
        print("wrote", bundle.relative_to(ROOT))
    write_picker_previews()
    if "--preview" in sys.argv:
        i = sys.argv.index("--preview")
        preview_dir = pathlib.Path(sys.argv[i + 1]) if len(sys.argv) > i + 1 else OUT
        preview_dir.mkdir(parents=True, exist_ok=True)
        for name in DESIGNS:
            for appearance in ("Light", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark"):
                target = preview_dir / f"{name}-{appearance}.png"
                subprocess.run([ICTOOL, str(OUT / f"{name}.icon"), "--export-preview", "iOS", appearance, "256", "256", "1", str(target)],
                               check=True, capture_output=True)
        print("previews in", preview_dir)


if __name__ == "__main__":
    main()

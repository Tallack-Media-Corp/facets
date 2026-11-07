"""Builds the sample files for App Review (and anyone trying Facets) as one ZIP.

Everything comes from Facets' own bundled sample, #3DBenchy by Creative Tools
(3DBenchy.com, public domain, CC0), or is generated here, so the set can be
published freely:

    python3 tools/samples/build_review_samples.py Facets/Resources/Samples/3DBenchy.3mf <out.zip>

Each file shows something App Review asked to see working:
- STL, 3MF and OBJ files, one of each;
- a two-colour 3MF (file colours);
- a Bambu Studio-style project with two named plates, several objects and the
  slicer's own print time and filament per plate (the plate picker, object list
  and slicer estimates in Info);
- a plate standing on its edge (Lay Flat › Auto turns it flat);
- a model saved in metres (Facets offers to fix the units);
- a subfolder, for browsing a folder with Add Location… / Browse.
"""
import math, re, struct, sys, zipfile

SRC, OUT = sys.argv[1], sys.argv[2]
ROOT = "Facets sample files/"


# MARK: Reading the bundled Benchy

def benchy_parts():
    """The bundled sample's two parts as lists of triangles, in millimetres."""
    with zipfile.ZipFile(SRC) as z:
        model = z.read("3D/3dmodel.model").decode()
    parts = []
    for obj in re.finditer(r'<object id="(\d+)" type="model"><mesh>(.*?)</mesh></object>', model, re.S):
        verts = [tuple(float(v) for v in m) for m in re.findall(r'<vertex x="([^"]+)" y="([^"]+)" z="([^"]+)"/>', obj.group(2))]
        tris = [(verts[int(a)], verts[int(b)], verts[int(c)]) for a, b, c in re.findall(r'<triangle v1="(\d+)" v2="(\d+)" v3="(\d+)"/>', obj.group(2))]
        parts.append(tris)
    return parts


def grounded(tris):
    """Centred on the origin and standing on z = 0."""
    xs = [v[0] for t in tris for v in t]; ys = [v[1] for t in tris for v in t]; zs = [v[2] for t in tris for v in t]
    cx, cy, cz = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, min(zs)
    return [tuple((v[0] - cx, v[1] - cy, v[2] - cz) for v in t) for t in tris]


# MARK: Shapes

def box(sx, sy, sz):
    """A box from the origin, as 12 outward-facing triangles."""
    p = [(0, 0, 0), (sx, 0, 0), (sx, sy, 0), (0, sy, 0), (0, 0, sz), (sx, 0, sz), (sx, sy, sz), (0, sy, sz)]
    f = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4), (1, 2, 6), (1, 6, 5), (2, 3, 7), (2, 7, 6), (3, 0, 4), (3, 4, 7)]
    return [tuple(p[i] for i in tri) for tri in f]


def turned_x(tris, degrees):
    """Turned about the X axis, then stood back on z = 0."""
    a = math.radians(degrees); c, s = math.cos(a), math.sin(a)
    out = [tuple((x, y * c - z * s, y * s + z * c) for x, y, z in t) for t in tris]
    low = min(v[2] for t in out for v in t)
    return [tuple((x, y, z - low) for x, y, z in t) for t in out]


def scaled(tris, k):
    return [tuple(tuple(c * k for c in v) for v in t) for t in tris]


# MARK: Writers

def stl(tris, name):
    out = bytearray(name.encode()[:80].ljust(80, b"\0")) + struct.pack("<I", len(tris))
    for a, b, c in tris:
        u = [b[i] - a[i] for i in range(3)]; w = [c[i] - a[i] for i in range(3)]
        n = (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])
        l = math.sqrt(sum(x * x for x in n)) or 1
        out += struct.pack("<12fH", *(x / l for x in n), *a, *b, *c, 0)
    return bytes(out)


def obj(tris, name):
    index, verts, faces = {}, [], []
    for t in tris:
        ids = []
        for v in t:
            key = tuple(round(x, 4) for x in v)
            if key not in index:
                index[key] = len(verts) + 1
                verts.append(key)
            ids.append(index[key])
        faces.append(ids)
    lines = [f"# {name}, made for Facets' sample files", f"o {name}"]
    lines += [f"v {x:g} {y:g} {z:g}" for x, y, z in verts]
    lines += [f"f {a} {b} {c}" for a, b, c in faces]
    return ("\n".join(lines) + "\n").encode()


def mesh_xml(tris):
    index, verts, out = {}, [], []
    for t in tris:
        ids = []
        for v in t:
            key = tuple(round(x, 4) for x in v)
            if key not in index:
                index[key] = len(verts)
                verts.append(key)
            ids.append(index[key])
        if len(set(ids)) == 3:
            out.append(ids)
    v = "".join(f'<vertex x="{x:g}" y="{y:g}" z="{z:g}"/>' for x, y, z in verts)
    t = "".join(f'<triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in out)
    return f"<mesh><vertices>{v}</vertices><triangles>{t}</triangles></mesh>"


TYPES = """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/><Default Extension="config" ContentType="text/xml"/></Types>"""
RELS = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/></Relationships>"""


def two_plate_project(hull, details):
    """A Bambu Studio-style project: plate 1 holds the two-colour Benchy, plate 2 a
    calibration cube and a small tray; the slicer's figures for each plate."""
    # Grounded together, so the deck stays on the hull.
    both = grounded(hull + details)
    hull_g, details_g = both[:len(hull)], both[len(hull):]
    cube = box(20, 20, 20)
    tray = box(70, 40, 4)
    model = f"""<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
<metadata name="Title">Two-plate project</metadata>
<metadata name="Designer">3DBenchy by Creative Tools (3DBenchy.com), CC0; cube and tray made for Facets</metadata>
<metadata name="Application">BambuStudio-02.03.00.70</metadata>
<resources>
<object id="1" type="model">{mesh_xml(hull_g)}</object>
<object id="2" type="model">{mesh_xml(details_g)}</object>
<object id="3" type="model"><components><component objectid="1"/><component objectid="2"/></components></object>
<object id="4" type="model">{mesh_xml(cube)}</object>
<object id="5" type="model">{mesh_xml(tray)}</object>
</resources>
<build>
<item objectid="3" transform="1 0 0 0 1 0 0 0 1 128 128 0"/>
<item objectid="4" transform="1 0 0 0 1 0 0 0 1 376 118 0"/>
<item objectid="5" transform="1 0 0 0 1 0 0 0 1 346 158 0"/>
</build>
</model>"""
    settings = """<?xml version="1.0" encoding="UTF-8"?>
<config>
  <object id="3">
    <metadata key="name" value="3DBenchy"/>
    <metadata key="extruder" value="1"/>
    <part id="1" subtype="normal_part"><metadata key="name" value="Hull"/><metadata key="extruder" value="1"/></part>
    <part id="2" subtype="normal_part"><metadata key="name" value="Deck and trim"/><metadata key="extruder" value="2"/></part>
  </object>
  <object id="4"><metadata key="name" value="Calibration cube"/><metadata key="extruder" value="2"/></object>
  <object id="5"><metadata key="name" value="Tray"/><metadata key="extruder" value="1"/></object>
  <plate>
    <metadata key="plater_id" value="1"/>
    <metadata key="plater_name" value="Benchy"/>
    <model_instance><metadata key="object_id" value="3"/><metadata key="instance_id" value="0"/></model_instance>
  </plate>
  <plate>
    <metadata key="plater_id" value="2"/>
    <metadata key="plater_name" value="Cube and tray"/>
    <model_instance><metadata key="object_id" value="4"/><metadata key="instance_id" value="0"/></model_instance>
    <model_instance><metadata key="object_id" value="5"/><metadata key="instance_id" value="0"/></model_instance>
  </plate>
</config>"""
    # Plausible figures for these models on a Bambu Lab printer, for the
    # "from the slicer" estimate in Info.
    slice_info = """<?xml version="1.0" encoding="UTF-8"?>
<config>
  <header><header_item key="X-BBL-Client-Type" value="slicer"/></header>
  <plate>
    <metadata key="index" value="1"/>
    <metadata key="prediction" value="3480"/>
    <metadata key="weight" value="14.62"/>
    <metadata key="support_used" value="false"/>
    <filament id="1" type="PLA" color="#F2782E" used_m="3.71" used_g="11.06"/>
    <filament id="2" type="PLA" color="#F2F2EE" used_m="1.19" used_g="3.56"/>
  </plate>
  <plate>
    <metadata key="index" value="2"/>
    <metadata key="prediction" value="2310"/>
    <metadata key="weight" value="13.95"/>
    <metadata key="support_used" value="false"/>
    <filament id="1" type="PLA" color="#F2782E" used_m="2.67" used_g="7.95"/>
    <filament id="2" type="PLA" color="#F2F2EE" used_m="2.01" used_g="6.00"/>
  </plate>
</config>"""
    project = '{"filament_colour": ["#F2782E", "#F2F2EE"], "filament_type": ["PLA", "PLA"], "printable_area": ["0x0", "256x0", "256x256", "0x256"]}'
    return zipped({"3D/3dmodel.model": model, "Metadata/model_settings.config": settings,
                   "Metadata/slice_info.config": slice_info, "Metadata/project_settings.config": project})


def zipped(files):
    import io
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        z.writestr("[Content_Types].xml", TYPES)
        z.writestr("_rels/.rels", RELS)
        for name, data in files.items():
            z.writestr(name, data)
    return buffer.getvalue()


README = """Facets sample files
===================

Sample STL, 3MF and OBJ files for trying every part of Facets. Open any of them
in Facets (on a Mac: double-click, File > Open, or drag into the window; on
iPhone and iPad: tap in the Files app and choose Facets, or the + button in
Facets' library). To browse without importing, add this folder with
Add Location... in the Mac sidebar, or Library > Browse on iPhone and iPad.

3DBenchy.stl              A plain STL. Turn, zoom, Fit, preset views, Measure,
                          Cross-Section, the printer fit check (click the size).
3DBenchy two-colour.3mf   A 3MF with two filament colours.
Calibration cube.obj      An OBJ file (a 20 mm cube).
Two-plate project.3mf     A Bambu Studio-style project: choose Plate 1 or Plate 2
                          (or all plates) from the menu, see its objects in Info
                          (each can be hidden), and the slicer's print time and
                          filament for each plate in Info > Print Estimate.
Standing plate.stl        A flat plate standing on its edge. Tools > Lay Flat >
                          Auto lays it flat; or click a face to rest it on.
Benchy saved in metres.stl  Saved in metres, so it opens 1000 times too small:
                          Facets offers Metres or Inches under the size.
More models/              A subfolder, for browsing folders.

3DBenchy is by Creative Tools (3DBenchy.com), public domain (CC0). The cube,
tray and plate were made for Facets. All of these files may be shared freely.
"""


def main():
    hull, details = benchy_parts()
    benchy = grounded(hull + details)
    plate = turned_x(box(60, 40, 3), 90)
    files = {
        "README.txt": README.encode(),
        "3DBenchy.stl": stl(benchy, "3DBenchy by Creative Tools, CC0"),
        "3DBenchy two-colour.3mf": open(SRC, "rb").read(),
        "Calibration cube.obj": obj(box(20, 20, 20), "Calibration cube"),
        "Two-plate project.3mf": two_plate_project(hull, details),
        "Standing plate.stl": stl(plate, "Standing plate, made for Facets"),
        "Benchy saved in metres.stl": stl(scaled(benchy, 0.001), "3DBenchy in metres, CC0"),
        "More models/Calibration cube.stl": stl(box(20, 20, 20), "Calibration cube"),
        "More models/Tray.obj": obj(box(70, 40, 4), "Tray"),
    }
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in files.items():
            z.writestr(ROOT + name, data)
    for name, data in files.items():
        print(f"{len(data):>9,}  {name}")


main()

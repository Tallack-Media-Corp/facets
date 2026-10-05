"""Builds Facets' bundled sample: a two-colour #3DBenchy as a Bambu Studio-style 3MF.

#3DBenchy is by Creative Tools (3DBenchy.com), released into the public domain (CC0).
The dual-print STLs come from github.com/CreativeTools/3DBenchy (Multi-part):

    python3 tools/samples/build_benchy_sample.py <hull+box.stl> <gunwale+deck.stl> Facets/Resources/Samples/3DBenchy.3mf

The hull, cargo box, bridge walls and chimney print in Filament Orange; gunwale,
deck, name plate, wheel, frames, roof
and chimney top in white. The STLs themselves aren't kept in the repository.
"""
import struct, sys, zipfile

def read_stl(path):
    data = open(path, "rb").read()
    tris = []
    if data[:5] == b"solid" and b"facet" in data[:400]:
        verts = [tuple(float(v) for v in line.split()[1:4]) for line in data.decode("ascii", "replace").splitlines() if line.strip().startswith("vertex")]
        tris = [verts[i:i + 3] for i in range(0, len(verts) - 2, 3)]
    else:
        count = struct.unpack("<I", data[80:84])[0]
        for i in range(count):
            o = 84 + i * 50 + 12
            v = struct.unpack("<9f", data[o:o + 36])
            tris.append([v[0:3], v[3:6], v[6:9]])
    return tris

def mesh_xml(tris):
    index, verts, out = {}, [], []
    for t in tris:
        ids = []
        for v in t:
            key = tuple(round(c, 4) for c in v)
            if key not in index:
                index[key] = len(verts)
                verts.append(key)
            ids.append(index[key])
        if len(set(ids)) == 3:
            out.append(ids)
    v = "".join(f'<vertex x="{x:g}" y="{y:g}" z="{z:g}"/>' for x, y, z in verts)
    t = "".join(f'<triangle v1="{a}" v2="{b}" v3="{c}"/>' for a, b, c in out)
    return f"<mesh><vertices>{v}</vertices><triangles>{t}</triangles></mesh>", verts

hull, details = read_stl(sys.argv[1]), read_stl(sys.argv[2])
hull_xml, hv = mesh_xml(hull)
detail_xml, dv = mesh_xml(details)
allv = hv + dv
cx = (min(v[0] for v in allv) + max(v[0] for v in allv)) / 2
cy = (min(v[1] for v in allv) + max(v[1] for v in allv)) / 2
cz = min(v[2] for v in allv)
# Centred on a 256 mm plate, standing on it.
place = f"1 0 0 0 1 0 0 0 1 {128 - cx:g} {128 - cy:g} {-cz:g}"

model = f"""<?xml version="1.0" encoding="UTF-8"?>
<model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
<metadata name="Title">3DBenchy</metadata>
<metadata name="Designer">Creative Tools (3DBenchy.com)</metadata>
<metadata name="License">CC0 1.0 Universal (public domain)</metadata>
<metadata name="Application">Facets sample</metadata>
<resources>
<object id="1" type="model">{hull_xml}</object>
<object id="2" type="model">{detail_xml}</object>
<object id="3" type="model"><components><component objectid="1"/><component objectid="2"/></components></object>
</resources>
<build><item objectid="3" transform="{place}"/></build>
</model>"""

settings = """<?xml version="1.0" encoding="UTF-8"?>
<config>
  <object id="3">
    <metadata key="name" value="3DBenchy"/>
    <metadata key="extruder" value="1"/>
    <part id="1" subtype="normal_part">
      <metadata key="name" value="Hull, box, bridge walls and chimney"/>
      <metadata key="extruder" value="1"/>
    </part>
    <part id="2" subtype="normal_part">
      <metadata key="name" value="Deck, gunwale, roof and trim"/>
      <metadata key="extruder" value="2"/>
    </part>
  </object>
</config>"""

project = '{"filament_colour": ["#F2782E", "#F2F2EE"], "filament_type": ["PLA", "PLA"]}'
types = """<?xml version="1.0" encoding="UTF-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/><Default Extension="config" ContentType="text/xml"/></Types>"""
rels = """<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/></Relationships>"""

with zipfile.ZipFile(sys.argv[3], "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    z.writestr("[Content_Types].xml", types)
    z.writestr("_rels/.rels", rels)
    z.writestr("3D/3dmodel.model", model)
    z.writestr("Metadata/model_settings.config", settings)
    z.writestr("Metadata/project_settings.config", project)
print(len(hull), "+", len(details), "triangles")

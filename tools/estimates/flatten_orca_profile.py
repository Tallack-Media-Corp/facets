"""Resolve an Orca system profile's `inherits` chain into one flat JSON."""
import json, os, sys, glob
ROOT = "/Applications/OrcaSlicer.app/Contents/Resources/profiles"
index = {}  # (vendor, name) -> path
for path in glob.glob(f"{ROOT}/*/*/*.json") + glob.glob(f"{ROOT}/*/*/*/*.json"):
    try:
        data = json.load(open(path))
    except Exception:
        continue
    if isinstance(data, dict) and "name" in data:
        vendor = os.path.relpath(path, ROOT).split(os.sep)[0]
        index.setdefault((vendor, data["name"]), path)

def find(name, vendor=None):
    if vendor and (vendor, name) in index: return index[(vendor, name)], vendor
    for (v, n), path in index.items():
        if n == name: return path, v
    raise KeyError(name)

def resolve(name, seen=(), vendor=None):
    path, vendor = find(name, vendor)
    data = json.load(open(path))
    parent = data.get("inherits")
    if parent and parent not in seen:
        merged = resolve(parent, seen + (name,), vendor)
        merged.update({k: v for k, v in data.items() if k != "inherits"})
        return merged
    return data

def flatten(name, out):
    data = resolve(name)
    data.pop("inherits", None)
    data["name"] = name
    data["from"] = "system"
    data.setdefault("version", "2.0.0.0")
    json.dump(data, open(out, "w"), indent=1)

if __name__ == "__main__":
    kind_name_out = sys.argv[1:]
    for i in range(0, len(kind_name_out), 2):
        flatten(kind_name_out[i], kind_name_out[i + 1])
        print("ok", kind_name_out[i])

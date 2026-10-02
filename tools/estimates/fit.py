"""Calibrate a shape-based print estimate against real Bambu Studio slices.

Leave-one-project-out cross-validation: plates from one file share settings, so
each project is predicted by a fit on the others. Plain Python, no numpy."""
import csv, math, sys, statistics as st

rows = list(csv.DictReader(open(sys.argv[1])))
for r in rows:
    for k in ("volume", "side", "up", "down", "height", "grams", "seconds", "layer", "infill", "walls", "top", "bottom", "linewidth", "density"):
        r[k] = float(r[k]) if r[k] else 0.0

DEFAULT = dict(layer=0.2, infill=15, walls=2, top=5, bottom=3, linewidth=0.45)

def shell_infill(r, s):
    """mm³ of wall+skin and of infill, for settings s."""
    wall = r["side"] * s["walls"] * s["linewidth"]
    skin = r["up"] * s["top"] * s["layer"] + r["down"] * s["bottom"] * s["layer"]
    shell = min(r["volume"], wall + skin)
    infill = max(r["volume"] - shell, 0) * s["infill"] / 100
    return shell, infill

def actual(r):
    return {k: r[k] for k in DEFAULT}

def solve(X, y):
    """Least squares by normal equations (small, well-scaled problems)."""
    n = len(X[0])
    A = [[sum(x[i] * x[j] for x in X) for j in range(n)] for i in range(n)]
    b = [sum(x[i] * t for x, t in zip(X, y)) for i in range(n)]
    for c in range(n):  # Gaussian elimination with partial pivoting
        p = max(range(c, n), key=lambda i: abs(A[i][c]))
        A[c], A[p], b[c], b[p] = A[p], A[c], b[p], b[c]
        for i in range(c + 1, n):
            f = A[i][c] / A[c][c]
            for j in range(c, n): A[i][j] -= f * A[c][j]
            b[i] -= f * b[c]
    w = [0.0] * n
    for i in reversed(range(n)):
        w[i] = (b[i] - sum(A[i][j] * w[j] for j in range(i + 1, n))) / A[i][i]
    return w

def cross_validate(features, target, rel=True):
    """Leave one project out; fit relative error (divide by target) if rel."""
    files = sorted({r["file"] for r in rows})
    errors = []
    for f in files:
        train = [r for r in rows if r["file"] != f]
        test = [r for r in rows if r["file"] == f]
        X = [features(r) for r in train]
        y = [target(r) for r in train]
        if rel:  # weight by 1/target so small and large plates count alike
            X = [[v / t for v in x] for x, t in zip(X, y)]
            y = [1.0] * len(y)
        w = solve(X, y)
        for r in test:
            pred = sum(a * b for a, b in zip(w, features(r)))
            errors.append((pred - target(r)) / target(r))
    return errors, solve([[v / target(r) for v in features(r)] for r in rows], [1.0] * len(rows))

def report(name, errors, weights=None):
    a = [abs(e) for e in errors]
    print(f"  {name:<44} median {st.median(a)*100:5.1f}%  mean {st.mean(a)*100:5.1f}%  within 20%: {sum(x <= .2 for x in a)}/{len(a)}  worst {max(a)*100:5.0f}%"
          + (f"   w={['%.4g' % x for x in weights]}" if weights else ""))

grams = lambda r: r["grams"]
g = lambda r: r["density"] / 1000  # g per mm³

print(f"{len(rows)} plates from {len({r['file'] for r in rows})} projects\n")
print("WEIGHT")
report("solid (volume × density)", [(r["volume"] * g(r) - r["grams"]) / r["grams"] for r in rows])
e, w = cross_validate(lambda r: [r["volume"] * g(r)], grams); report("best fixed fraction of solid", e, w)
e, w = cross_validate(lambda r: [x * g(r) for x in shell_infill(r, actual(r))], grams); report("shell + infill, project's own settings", e, w)
e, w = cross_validate(lambda r: [x * g(r) for x in shell_infill(r, DEFAULT)], grams); report("shell + infill, assumed defaults", e, w)
typical = [r for r in rows if r["infill"] <= 20 and r["layer"] >= 0.16]
print(f"  (typical settings only, {len(typical)} plates:)")
saved = rows
rows = typical
e, w = cross_validate(lambda r: [r["volume"] * g(r)], grams); report("  best fixed fraction of solid", e, w)
e, w = cross_validate(lambda r: [x * g(r) for x in shell_infill(r, DEFAULT)], grams); report("  shell + infill, assumed defaults", e, w)
rows = saved

print("\nTIME")
secs = lambda r: r["seconds"]
def tfeat(s_of):
    def f(r):
        s = s_of(r)
        shell, infill = shell_infill(r, s)
        layers = r["height"] / s["layer"]
        return [shell, infill, layers, 1.0]
    return f
e, w = cross_validate(lambda r: [r["volume"], 1.0], secs); report("volume only (+ start-up)", e, w)
e, w = cross_validate(tfeat(actual), secs); report("shell, infill, layers, start-up: own settings", e, w)
e, w = cross_validate(tfeat(lambda r: DEFAULT), secs); report("shell, infill, layers, start-up: defaults", e, w)
rows = typical
print(f"  (typical settings only, {len(typical)} plates:)")
e, w = cross_validate(lambda r: [r["volume"], 1.0], secs)
rows = saved; report("  volume only (+ start-up)", e, w)
e, w = cross_validate(tfeat(lambda r: DEFAULT), secs); report("  shell, infill, layers, start-up: defaults", e, w)

print("\nTIME, path-based with a cooling floor")
for r in rows: r["parts"] = float(r["parts"])
for r in typical: r["parts"] = float(r["parts"]) if isinstance(r["parts"], str) else r["parts"]

def paths(r, s):
    """mm of extrusion path: walls, skins, infill; and layer count."""
    lw, lh = s["linewidth"], s["layer"]
    wall_vol = r["side"] * s["walls"] * lw
    skin_vol = r["up"] * s["top"] * lh + r["down"] * s["bottom"] * lh
    shell = wall_vol + skin_vol
    if shell > r["volume"]:  # thin part: scale both down to fit the solid
        k = r["volume"] / shell
        wall_vol, skin_vol = wall_vol * k, skin_vol * k
    infill_vol = max(r["volume"] - wall_vol - skin_vol, 0) * s["infill"] / 100
    per = lw * lh
    return wall_vol / per, skin_vol / per, infill_vol / per, r["height"] / lh

def fit_floor(train, s_of, tmin):
    """T = max(work, tmin·layers) + c·layers·parts + d, work = a·wall + b·skin + e·infill.
    Alternates: decide which plates sit on the floor, refit, repeat."""
    floored = set()
    w = [0.05, 0.02, 0.0, 600.0]
    for _ in range(12):
        X, y = [], []
        for idx, r in enumerate(train):
            wall, skin, infill, layers = paths(r, s_of(r))
            if idx in floored:
                X.append([0, 0, layers * r["parts"], 1.0]); y.append(r["seconds"] - tmin * layers)
            else:
                X.append([wall + skin, infill, layers * r["parts"], 1.0]); y.append(r["seconds"])
        Xn = [[v / r["seconds"] for v in x] for x, r in zip(X, train)]
        yn = [t / r["seconds"] for t, r in zip(y, train)]
        w = solve(Xn, yn)
        new = set()
        for idx, r in enumerate(train):
            wall, skin, infill, layers = paths(r, s_of(r))
            if w[0] * (wall + skin) + w[1] * infill < tmin * layers: new.add(idx)
        if new == floored: break
        floored = new
    return w

def predict_floor(r, w, s_of, tmin):
    wall, skin, infill, layers = paths(r, s_of(r))
    work = w[0] * (wall + skin) + w[1] * infill
    return max(work, tmin * layers) + w[2] * layers * r["parts"] + w[3]

def cv_floor(data, s_of, tmin):
    errs = []
    for f in sorted({r["file"] for r in data}):
        train = [r for r in data if r["file"] != f]
        w = fit_floor(train, s_of, tmin)
        errs += [(predict_floor(r, w, s_of, tmin) - r["seconds"]) / r["seconds"] for r in data if r["file"] == f]
    return errs, fit_floor(data, s_of, tmin)

for name, data in (("all", rows), ("typical", typical)):
    for settings_name, s_of in (("own", actual), ("defaults", lambda r: DEFAULT)):
        for tmin in (0, 3, 5, 8, 12):
            e, w = cv_floor(data, s_of, tmin)
            report(f"{name}/{settings_name} floor {tmin}s", e, w)

print("\nPer plate, defaults, floor 5s (cross-validated):")
e, w = cv_floor(rows, lambda r: DEFAULT, 5)
for r, x in sorted(zip(rows, e), key=lambda t: -abs(t[1]))[:10]:
    print(f"  {x*100:+6.0f}%  {r['file'][:34]:<34} p{r['plate']:<3} {r['seconds']/60:6.0f} min  layer {r['layer']} infill {r['infill']:.0f}% parts {r['parts']:.0f} {r['printer']}")

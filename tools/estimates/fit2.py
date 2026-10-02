"""Round 2: Bambu Studio plates plus Orca slices on four printers.
Usage: fit2.py bambu.csv x1c=orca_x1c.csv a1=orca_a1.csv ..."""
import csv, statistics as st, sys

NUM = ("volume", "side", "up", "down", "height", "parts", "grams", "seconds", "layer", "infill",
       "walls", "top", "bottom", "linewidth", "density", "overhang", "support", "supports", "filaments")
def load(path, source):
    out = []
    for r in csv.DictReader(open(path)):
        for k in NUM:
            r[k] = float(r[k]) if r.get(k) not in (None, "") else 0.0
        r["source"] = source
        r["key"] = f"{source}:{r['file']}"
        if r["grams"] > 0.5 and r["seconds"] > 60 and r["volume"] > 10:
            out.append(r)
    return out

rows = load(sys.argv[1], "bambu")
for arg in sys.argv[2:]:
    name, path = arg.split("=")
    rows += load(path, name)

DEFAULT = dict(layer=0.2, infill=15, walls=2, top=5, bottom=3, linewidth=0.45)

def solve(X, y):
    n = len(X[0])
    A = [[sum(x[i] * x[j] for x in X) for j in range(n)] for i in range(n)]
    b = [sum(x[i] * t for x, t in zip(X, y)) for i in range(n)]
    for i in range(n): A[i][i] += 1e-9 * (A[i][i] + 1)
    for c in range(n):
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

def parts_of(r, s):
    lw, lh = s["linewidth"], s["layer"]
    wall = r["side"] * s["walls"] * lw
    skin = r["up"] * s["top"] * lh + r["down"] * s["bottom"] * lh
    if wall + skin > r["volume"]:
        k = r["volume"] / (wall + skin); wall *= k; skin *= k
    infill = max(r["volume"] - wall - skin, 0) * s["infill"] / 100
    return wall, skin, infill

def cv(data, feats, target, group="file"):
    """Leave one model out (all its plates), relative least squares."""
    errs = []
    for g in sorted({r[group] for r in data}):
        train = [r for r in data if r[group] != g]
        w = solve([[v / target(r) for v in feats(r)] for r in train], [1.0] * len(train))
        errs += [(sum(a * b for a, b in zip(w, feats(r))) - target(r)) / target(r) for r in data if r[group] == g]
    w = solve([[v / target(r) for v in feats(r)] for r in data], [1.0] * len(data))
    return errs, w

def report(name, errs, w=None):
    a = sorted(abs(e) for e in errs)
    q = lambda p: a[min(int(p * len(a)), len(a) - 1)]
    print(f"  {name:<40} n={len(a):<4} median {q(.5)*100:5.1f}%  p80 {q(.8)*100:5.1f}%  within 20%: {sum(x <= .2 for x in a)*100/len(a):3.0f}%"
          + (f"  w={['%.4g' % x for x in w]}" if w else ""))

g = lambda r: r["density"] / 1000
grams = lambda r: r["grams"]
secs = lambda r: r["seconds"]
nosup = [r for r in rows if r["supports"] == 0]
print(f"{len(rows)} plates ({len(nosup)} without supports); by source:",
      {s: sum(r["source"] == s for r in rows) for s in sorted({r['source'] for r in rows})}, "\n")

print("WEIGHT (assumed defaults), no supports")
for src in ["all"] + sorted({r["source"] for r in rows}):
    data = [r for r in nosup if src == "all" or r["source"] == src]
    if len(data) < 10: continue
    e, _ = cv(data, lambda r: [r["volume"] * g(r)], grams, "key"); report(f"{src}: best fixed fraction", e)
    e, w = cv(data, lambda r: [(a + b) * g(r) for a, b in [parts_of(r, DEFAULT)[:2]]] + [parts_of(r, DEFAULT)[2] * g(r)], grams, "key")
    report(f"{src}: shell + infill", e, w)
print("  using the round-1 constants (0.875 shell, 0.808 infill) unchanged:")
for src in sorted({r["source"] for r in rows}):
    data = [r for r in nosup if r["source"] == src]
    e = []
    for r in data:
        a, b, c = parts_of(r, DEFAULT)
        e.append(((a + b) * 0.875 + c * 0.808) * g(r) / r["grams"] - 1)
    report(f"{src}: round-1 model", e)

sup = [r for r in rows if r["supports"] == 1]
print(f"\nSUPPORTS ({len(sup)} plates with supports)")
if len(sup) >= 8:
    e, w = cv(sup, lambda r: [(sum(parts_of(r, DEFAULT)[:2])) * g(r), parts_of(r, DEFAULT)[2] * g(r)], grams, "key"); report("without support term", e, w)
    e, w = cv(sup, lambda r: [(sum(parts_of(r, DEFAULT)[:2])) * g(r), parts_of(r, DEFAULT)[2] * g(r), r["support"] * g(r)], grams, "key"); report("with support volume term", e, w)

print("\nTIME per printer (assumed defaults, cooling floor 12 s, no supports)")
def paths(r, s):
    wall, skin, infill = parts_of(r, s)
    per = s["linewidth"] * s["layer"]
    return (wall + skin) / per, infill / per, r["height"] / s["layer"]

def fit_floor(train, tmin):
    floored, w = set(), None
    for _ in range(12):
        X, y = [], []
        for i, r in enumerate(train):
            shell, infill, layers = paths(r, DEFAULT)
            if i in floored: X.append([0, 0, layers * r["parts"], 1.0]); y.append(r["seconds"] - tmin * layers)
            else: X.append([shell, infill, layers * r["parts"], 1.0]); y.append(r["seconds"])
        w = solve([[v / r["seconds"] for v in x] for x, r in zip(X, train)], [t / r["seconds"] for t, r in zip(y, train)])
        new = {i for i, r in enumerate(train) if w[0] * paths(r, DEFAULT)[0] + w[1] * paths(r, DEFAULT)[1] < tmin * paths(r, DEFAULT)[2]}
        if new == floored: break
        floored = new
    return w

def predict(r, w, tmin):
    shell, infill, layers = paths(r, DEFAULT)
    return max(w[0] * shell + w[1] * infill, tmin * layers) + w[2] * layers * r["parts"] + w[3]

def cv_time(data, tmin):
    errs = []
    for f in sorted({r["key"] for r in data}):
        w = fit_floor([r for r in data if r["key"] != f], tmin)
        errs += [(predict(r, w, tmin) - r["seconds"]) / r["seconds"] for r in data if r["key"] == f]
    return errs, fit_floor(data, tmin)

for src in sorted({r["source"] for r in rows}):
    data = [r for r in nosup if r["source"] == src]
    if len(data) < 10: continue
    e, _ = cv(data, lambda r: [r["volume"], 1.0], secs, "key"); report(f"{src}: volume only", e)
    for tmin in (8, 12):
        e, w = cv_time(data, tmin); report(f"{src}: path model, floor {tmin}s", e, w)

print("\nTIME pooled across printers (one model for everyone)")
e, w = cv_time(nosup, 12); report("all: path model, floor 12s", e, w)

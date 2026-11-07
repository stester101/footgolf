#!/usr/bin/env python3
"""One-off migration used for the owner's hole-length ranges (docs/DECISIONS.md): shortens the
hand-authored Starter Links holes (hole_01..03) to the new nominal yardages.

Every feature is re-expressed as (distance along the line of play, lateral offset) on the old centreline
(tee -> fairway points -> pin) and placed at the same lateral offset on the uniformly scaled centreline,
with distance-along remapped by gen_forest_holes.smap (tee and green surrounds keep their metres, only the
middle of the hole shrinks). Sizes (fairway width, green/bunker radii, tree spacing) are kept; water radii
along the line of play are shrunk like the middle of the hole (>= 50 %). Terrain bounds are recomputed.

It reads the hole's CURRENT yardage as the design length and skips holes already at the target yardage,
so re-running it is a no-op. Usage: python3 tools/data/rescale_starter_holes.py
"""
import json, math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_forest_holes import smap, middle_scale, YD  # noqa: E402

NEW_YARDS = {"hole_01": 75, "hole_02": 160, "hole_03": 260}
PAD = 75


class Line:
    def __init__(self, pts):
        self.pts = pts
        self.cum = [0.0]
        for a, b in zip(pts, pts[1:]):
            self.cum.append(self.cum[-1] + math.dist(a, b))
        self.total = self.cum[-1]

    def project(self, p):
        """(s, t): distance along (extrapolated before/after the ends) and signed lateral offset."""
        best = None
        n = len(self.pts) - 1
        for i in range(n):
            a, b = self.pts[i], self.pts[i + 1]
            dx, dz = b[0] - a[0], b[1] - a[1]
            L = math.hypot(dx, dz)
            u = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dz) / (L * L)
            if i > 0:
                u = max(u, 0.0)
            if i < n - 1:
                u = min(u, 1.0)
            q = (a[0] + dx * u, a[1] + dz * u)
            dist = math.dist(p, q)
            if best is None or dist < best[0]:
                t = ((p[0] - a[0]) * -dz + (p[1] - a[1]) * dx) / L
                best = (dist, self.cum[i] + u * L, t)
        return best[1], best[2]

    def at(self, s, t=0.0):
        n = len(self.pts) - 1
        i = 0
        while i < n - 1 and s > self.cum[i + 1]:
            i += 1
        a, b = self.pts[i], self.pts[i + 1]
        L = self.cum[i + 1] - self.cum[i]
        u = (s - self.cum[i]) / L
        dx, dz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        return (a[0] + dx * u * L - dz * t, a[1] + dz * u * L + dx * t)

    def dir_at(self, s):
        a = self.at(s - 0.5)
        b = self.at(s + 0.5)
        n = math.dist(a, b)
        return ((b[0] - a[0]) / n, (b[1] - a[1]) / n)


def r1(v):
    return round(v, 1)


def rescale(d, new_yards):
    tee = tuple(d["tee"])
    pts = [tee]
    for f in d["fairway"]:
        pts += [tuple(q) for q in f["points"]]
    pts.append(tuple(d["pin"]))
    old = Line(pts)
    k = new_yards / float(d["yards"])
    new = Line([(tee[0] + (x - tee[0]) * k, tee[1] + (z - tee[1]) * k) for x, z in pts])
    L0, L1 = old.total, new.total
    along_k = max(0.5, middle_scale(L0, L1))

    def m(p):
        s, t = old.project(p)
        q = new.at(smap(s, L0, L1), t)
        return [r1(q[0]), r1(q[1])]

    d["yards"] = new_yards
    d["pin"] = m(d["pin"])
    for f in d["fairway"]:
        # fairway points sit on the centreline: scale uniformly (keeps the shape and the nominal length)
        f["points"] = [[r1(tee[0] + (x - tee[0]) * k), r1(tee[1] + (z - tee[1]) * k)] for x, z in f["points"]]
    for key in ("greens", "bunkers", "tee_boxes"):
        for e in d.get(key, []):
            if key != "tee_boxes":
                e["center"] = m(e["center"])
    for w in d.get("water", []):
        s, _ = old.project(w["center"])
        ax = math.radians(w.get("rot_deg", 0.0))
        lx = (math.cos(ax), -math.sin(ax))     # ellipse local x axis in world (x, z)
        dx, dz = old.dir_at(s)
        i = 0 if abs(lx[0] * dx + lx[1] * dz) > 0.707 else 1   # radius lying along the line of play
        w["radii"][i] = r1(max(3.5, w["radii"][i] * along_k))
        w["center"] = m(w["center"])
    for tr in d.get("trees", []):
        tr["pos"] = m(tr["pos"])
    lines = []
    for ln in d.get("tree_lines", []):
        a, b = ln["from"], ln["to"]
        n = max(1, int(math.dist(a, b) / 20.0))
        for j in range(n):
            pa = (a[0] + (b[0] - a[0]) * j / n, a[1] + (b[1] - a[1]) * j / n)
            pb = (a[0] + (b[0] - a[0]) * (j + 1) / n, a[1] + (b[1] - a[1]) * (j + 1) / n)
            seg = dict(ln)
            seg["from"], seg["to"] = m(pa), m(pb)
            seg["seed"] = ln["seed"] * 100 + j
            if math.dist(seg["from"], seg["to"]) >= 4.0:
                lines.append(seg)
    d["tree_lines"] = lines
    for c in d.get("tree_clusters", []):
        c["center"] = m(c["center"])
    for b in d["terrain"].get("bumps", []):
        b["center"] = m(b["center"])
    d["relief_points"] = [m(p) for p in d.get("relief_points", [])]
    # rendered terrain: every feature + PAD metres (the outer 25 m of it is the only OOB)
    xs, zs = [], []

    def add(c, r):
        xs.extend([c[0] - r, c[0] + r])
        zs.extend([c[1] - r, c[1] + r])
    for t in d["tee_boxes"]:
        add(t["center"], max(t["size"]) / 2)
    for g in d["greens"]:
        add(g["center"], max(g["radii"]))
    for f in d["fairway"]:
        for q in f["points"]:
            add(q, f["width"] / 2)
    for key in ("bunkers", "water"):
        for e in d.get(key, []):
            add(e["center"], max(e["radii"]))
    d["bounds"] = [int(min(xs) - PAD), int(min(zs) - PAD), int(max(xs) + PAD), int(max(zs) + PAD)]
    return d


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "..", "..", "data", "holes")
    for hid, y in NEW_YARDS.items():
        p = os.path.join(out, hid + ".json")
        d = json.load(open(p))
        if int(d["yards"]) == y:
            print(hid, "already", y, "yd")
            continue
        d = rescale(d, y)
        with open(p, "w") as f:
            f.write(json.dumps(d, indent=1))
        print(hid, d["name"], y, "yd", "pin", d["pin"], "bounds", d["bounds"])

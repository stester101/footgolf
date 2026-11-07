#!/usr/bin/env python3
"""Authoring tool for the "Pinewood Ridge" forest/mountainside holes (hole_04 .. hole_09).

Writes data/holes/hole_0N.json. The JSON files are the source of truth for the game; this script only
makes authoring consistent: centreline control points are smoothed (Chaikin), scaled so the centreline
equals the nominal yardage, and features are placed in (fraction-along-hole, lateral-metres) coords.
Deterministic (seeded). Re-run:  python3 tools/data/gen_forest_holes.py
"""
import json, math, random, os

YD = 0.9144


def chaikin(pts, it=1):
    for _ in range(it):
        out = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            out.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            out.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        out.append(pts[-1])
        pts = out
    return pts


def length(pts):
    return sum(math.dist(a, b) for a, b in zip(pts, pts[1:]))


class Path:
    def __init__(self, ctrl, yards):
        pts = chaikin(ctrl, 1)
        k = yards * YD / length(pts)
        self.pts = [(x * k, z * k) for x, z in pts]
        self.cum = [0.0]
        for a, b in zip(self.pts, self.pts[1:]):
            self.cum.append(self.cum[-1] + math.dist(a, b))
        self.total = self.cum[-1]

    def at(self, f, t=0.0):
        """Point at fraction f (may be <0 or >1 to extend), lateral offset t (metres, + = (-dz, dx) side)."""
        s = f * self.total
        if s <= 0:
            i, u = 0, s / math.dist(self.pts[0], self.pts[1])
        elif s >= self.total:
            i = len(self.pts) - 2
            u = 1.0 + (s - self.total) / math.dist(self.pts[-2], self.pts[-1])
        else:
            i = max(j for j in range(len(self.cum) - 1) if self.cum[j] <= s)
            u = (s - self.cum[i]) / (self.cum[i + 1] - self.cum[i])
        a, b = self.pts[i], self.pts[i + 1]
        d = (b[0] - a[0], b[1] - a[1])
        n = math.hypot(*d)
        dx, dz = d[0] / n, d[1] / n
        return (a[0] + d[0] * u - dz * t, a[1] + d[1] * u + dx * t)

    def dir_at(self, f):
        a = self.at(max(0.0, f - 0.01))
        b = self.at(min(1.0, f + 0.01))
        n = math.dist(a, b)
        return ((b[0] - a[0]) / n, (b[1] - a[1]) / n)


def rot_for_axis(ax, az):
    """Ellipse/box rot_deg so the local x axis points along world (ax, az)."""
    return round(math.degrees(math.atan2(-az, ax)), 1)


def r1(v):
    return round(v, 1)


def build(spec):
    rng = random.Random(spec["seed"])
    P = Path(spec["ctrl"], spec["yards"])
    hw = spec["fw_width"] / 2.0
    wl = spec.get("side_a", 50.0)   # boundary offset on the + side
    wr = spec.get("side_b", 50.0)   # boundary offset on the - side
    d = {"id": spec["id"], "name": spec["name"], "par": spec["par"], "yards": spec["yards"]}
    tee = P.at(0.0)
    green_c = P.at(1.0)
    d["tee"] = [0, 0]
    po = spec.get("pin_offset", (2.0, 3.0))
    d["pin"] = [r1(green_c[0] + po[0]), r1(green_c[1] + po[1])]
    d["theme"] = {"conifer": spec.get("conifer", 0.78)}
    d["tee_boxes"] = [{"center": [0, 0], "size": [8, 11], "rot_deg": 0}]
    d["fairway"] = [{"points": [[r1(x), r1(z)] for x, z in P.pts], "width": spec["fw_width"]}]
    gr = spec.get("green", (13, 11))
    d["greens"] = [{"center": [r1(green_c[0]), r1(green_c[1])], "radii": list(gr), "rot_deg": round(rng.uniform(-30, 30), 1),
                    "tilt": [round(rng.uniform(-0.02, 0.02), 3), round(rng.uniform(-0.02, 0.02), 3)]}]
    bunkers = []
    for (f, t, ra, rb, depth) in spec.get("bunkers", []):
        c = P.at(f, t)
        dx, dz = P.dir_at(f)
        bunkers.append({"center": [r1(c[0]), r1(c[1])], "radii": [ra, rb], "rot_deg": rot_for_axis(-dz, dx), "depth": depth})
    d["bunkers"] = bunkers
    water = []
    for w in spec.get("water", []):
        c = P.at(w["f"], w.get("t", 0.0))
        dx, dz = P.dir_at(w["f"])
        axis = (-dz, dx) if w.get("across", True) else (dx, dz)
        water.append({"center": [r1(c[0]), r1(c[1])], "radii": w["radii"], "rot_deg": rot_for_axis(*axis)})
    d["water"] = water
    # ---- boundary (OOB) polygon offset from the centreline
    N = max(12, int(P.total / 14))
    left, right = [], []
    for i in range(-2, N + 3):
        f = min(max(i / N, -0.06), 1.06)
        wa = wl * (1.0 + 0.12 * math.sin(f * 9.0))
        wb = wr * (1.0 + 0.12 * math.sin(f * 7.0 + 1.3))
        left.append(P.at(f, wa))
        right.append(P.at(f, -wb))
    poly = left + right[::-1]
    d["boundary"] = [[r1(x), r1(z)] for x, z in poly]
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    m = 80
    d["bounds"] = [int(min(xs) - m), int(min(zs) - m), int(max(xs) + m), int(max(zs) + m)]
    # ---- terrain: elevation plane + fairway undulation + feature mounds + mountain hills outside
    bumps = []
    for _ in range(int(P.total / 16)):
        f = rng.uniform(0.04, 0.96)
        t = rng.uniform(-hw - 12, hw + 12)
        c = P.at(f, t)
        h = rng.uniform(0.7, 1.4) * rng.choice([-1, 1]) * spec.get("undulation", 1.0)
        bumps.append({"center": [r1(c[0]), r1(c[1])], "radius": r1(rng.uniform(24, 34)), "height": round(h, 2)})
    for (f, t, rad, h) in spec.get("mounds", []):
        c = P.at(f, t)
        bumps.append({"center": [r1(c[0]), r1(c[1])], "radius": rad, "height": h})
    ring = [P.at(i / 80.0) for i in range(-4, 85)]
    placed = 0
    tries = 0
    while placed < spec.get("hills", 16) and tries < 400:
        tries += 1
        f = rng.uniform(-0.05, 1.05)
        side = rng.choice([1, -1])
        off = (wl if side > 0 else wr) + rng.uniform(25, 70)
        c = P.at(f, side * off)
        rad = rng.uniform(55, 110)
        # keep every hill clear of ALL stretches of the hole (bends bring other fairway sections close)
        if min(math.dist(c, q) for q in ring) < 1.3 * rad + hw + 10:
            continue
        h = rng.uniform(7, 22) * spec.get("hill_scale", 1.0)
        if side in spec.get("valley_sides", []):
            h = -h * 0.8
        bumps.append({"center": [r1(c[0]), r1(c[1])], "radius": r1(rad), "height": round(h, 1)})
        placed += 1
    d["terrain"] = {"base": spec["base"], "plane": [0, spec["slope"]], "bumps": bumps}
    # ---- trees: rows both sides, plus clusters. Dense, mostly conifers (theme).
    lines = []
    seed = spec["seed"] * 10
    for i in range(len(P.pts) - 1):
        f0 = P.cum[i] / P.total
        f1 = P.cum[i + 1] / P.total
        for side in (1, -1):
            for row, off in enumerate(spec.get("tree_rows", [9, 21, 35, 52, 72])):
                t = side * (hw + off)
                a = P.at(f0, t)
                b = P.at(f1, t)
                seed += 1
                lines.append({"from": [r1(a[0]), r1(a[1])], "to": [r1(b[0]), r1(b[1])],
                              "spacing": round(rng.uniform(7.5, 10.5), 1), "jitter": 3.5, "seed": seed})
    d["tree_lines"] = lines
    clusters = []
    for _ in range(spec.get("clusters", 10)):
        f = rng.uniform(0.05, 0.95)
        side = rng.choice([1, -1])
        c = P.at(f, side * (hw + rng.uniform(14, 40)))
        clusters.append({"center": [r1(c[0]), r1(c[1])], "radius": r1(rng.uniform(10, 20)), "count": rng.randint(6, 14), "seed": seed + len(clusters) + 100})
    d["tree_clusters"] = clusters
    d["wind"] = {"speed": spec["wind"][0], "bearing": spec["wind"][1]}
    d["relief_points"] = [[r1(P.at(f)[0]), r1(P.at(f)[1])] for f in (0.25, 0.5, 0.75)]
    d["camera"] = {"overhead_padding": 1.1}
    return d


HOLES = [
    dict(id="hole_04", name="Switchback", par=4, yards=380, seed=4, base=12, slope=0.055, fw_width=28,
         ctrl=[(0, 0), (0, 70), (-30, 140), (-45, 215), (-15, 280), (30, 325), (46, 350)],
         bunkers=[(0.42, 20, 5, 9, 0.7), (0.62, -19, 4, 7.5, 0.7), (0.97, 13, 4, 6, 0.65), (0.99, -12, 4.5, 5.5, 0.65), (0.93, -14, 5, 3.6, 0.6)],
         mounds=[(0.55, 35, 28, 2.4), (0.8, -32, 26, 2.6)], wind=(2.5, 40)),
    dict(id="hole_05", name="Ravine Drop", par=3, yards=195, seed=5, base=26, slope=-0.085, fw_width=26,
         ctrl=[(0, 0), (0, 60), (6, 125), (10, 178)], side_a=44, side_b=44,
         water=[dict(f=0.5, t=6, radii=[24, 13], across=True)],
         bunkers=[(0.94, 10, 4.5, 6, 0.7), (0.97, -11, 4, 5.5, 0.7), (1.03, 2, 6, 3.4, 0.6)],
         mounds=[(0.8, 28, 22, 2.2)], wind=(1.5, 200), green=(12, 10), pin_offset=(-1.0, 2.0)),
    dict(id="hole_06", name="Timber Line", par=5, yards=540, seed=6, base=18, slope=0.018, fw_width=24,
         ctrl=[(0, 0), (0, 80), (40, 155), (72, 235), (55, 325), (-8, 395), (-32, 455), (-22, 525)],
         side_a=40, side_b=40, conifer=0.9, clusters=18, tree_rows=[8, 18, 30, 44, 60, 80],
         bunkers=[(0.3, 18, 4, 8, 0.7), (0.58, -16, 4.5, 7, 0.7), (0.96, -12, 4, 6, 0.65)],
         mounds=[(0.4, -30, 24, 2.4)], wind=(2.0, 120), undulation=1.2),
    dict(id="hole_07", name="Cascade Creek", par=4, yards=335, seed=7, base=14, slope=-0.032, fw_width=27,
         ctrl=[(0, 0), (0, 90), (24, 165), (42, 235), (36, 305)],
         water=[dict(f=0.52, t=0, radii=[42, 6.5], across=True), dict(f=0.96, t=-26, radii=[13, 9], across=True)],
         bunkers=[(0.3, -17, 4, 9, 0.7), (0.78, 16, 4.5, 7, 0.7), (0.98, 12, 4, 5.5, 0.65)],
         mounds=[(0.7, -34, 26, 2.2)], wind=(3.0, 250), green=(12, 12)),
    dict(id="hole_08", name="The Bowl", par=3, yards=160, seed=8, base=16, slope=-0.012, fw_width=24,
         ctrl=[(0, 0), (5, 50), (0, 100), (-8, 146)], side_a=46, side_b=46, conifer=0.7,
         bunkers=[(0.95, 12, 5, 6, 0.8), (0.97, -13, 5, 6.5, 0.8), (1.13, 0, 8, 3.5, 0.7), (0.88, 8, 4, 4.5, 0.7)],
         mounds=[(1.0, 0, 52, -3.0), (0.78, 30, 22, 2.8), (0.78, -30, 22, 2.8), (1.12, 20, 22, 2.8), (1.12, -22, 22, 2.8), (0.95, 36, 20, 2.5)],
         wind=(1.0, 20), green=(14, 12)),
    dict(id="hole_09", name="Summit", par=5, yards=575, seed=9, base=20, slope=0.05, fw_width=26,
         ctrl=[(0, 0), (0, 100), (-30, 195), (-42, 295), (0, 380), (42, 450), (30, 526)],
         side_a=28, side_b=48, valley_sides=[1], hill_scale=1.2,
         bunkers=[(0.35, -20, 4.5, 9, 0.7), (0.6, 18, 5, 8, 0.7), (0.94, -13, 5, 6, 0.75), (0.97, 14, 4.5, 5.5, 0.75), (1.04, -3, 8, 3.5, 0.7)],
         mounds=[(0.5, -34, 26, 2.6), (0.82, 30, 24, 2.4)], wind=(4.0, 160), green=(14, 11), pin_offset=(1.0, 3.0)),
]


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "..", "..", "data", "holes")
    for spec in HOLES:
        d = build(spec)
        with open(os.path.join(out, spec["id"] + ".json"), "w") as f:
            json.dump(d, f, indent=1)
        print(spec["id"], spec["name"], "trees(lines)", len(d["tree_lines"]), "bounds", d["bounds"])

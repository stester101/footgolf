#!/usr/bin/env python3
"""Authoring tool for the generated themed courses:
  Pinewood Ridge  (hole_04 .. hole_09) forest / mountainside, dense conifers, big hills
  Coastal Links   (hole_10 .. hole_13) open links: dunes, pot bunkers, a burn, few trees, strong wind
  Lakeside        (hole_14 .. hole_17) parkland: water carries and lakes, deciduous trees, gentle hills

Writes data/holes/hole_NN.json. The JSON files are the source of truth for the game; this script only
makes authoring consistent: centreline control points are smoothed (Chaikin), scaled so the centreline
equals the nominal yardage, and features are placed in (fraction-along-hole, lateral-metres) coords.
Deterministic (seeded). Re-run:  python3 tools/data/gen_forest_holes.py
There is no per-hole OOB line: the game treats the whole rendered terrain (`bounds`) minus a 25 m edge band
as in play (docs/DECISIONS.md, "Make all visible course playable").
Hole lengths follow the owner's ranges (par 3 50-100, par 4 100-200, par 5 200-300 yd). `design_yards` is the
original layout length the feature fractions were authored for; features are remapped (smap) so tee and green
surrounds keep their metres. No length simulations are run here.
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


TEE_ZONE_M = 15.0     # features this close to the tee keep their distance from it
GREEN_ZONE_M = 35.0   # features this close to the green keep their distance from it


def middle_scale(L0, L1):
    return (L1 - GREEN_ZONE_M - TEE_ZONE_M) / (L0 - GREEN_ZONE_M - TEE_ZONE_M)


def smap(s, L0, L1):
    """Map distance-along-hole s (metres) on a hole designed at length L0 to a hole of length L1:
    the tee and green surrounds move rigidly, only the middle of the hole is compressed/stretched."""
    if abs(L1 - L0) < 1e-6 or s <= TEE_ZONE_M:
        return s
    if s >= L0 - GREEN_ZONE_M:
        return s - (L0 - L1)
    return TEE_ZONE_M + (s - TEE_ZONE_M) * middle_scale(L0, L1)


def rot_for_axis(ax, az):
    """Ellipse/box rot_deg so the local x axis points along world (ax, az)."""
    return round(math.degrees(math.atan2(-az, ax)), 1)


def r1(v):
    return round(v, 1)


def build(spec):
    rng = random.Random(spec["seed"])
    P = Path(spec["ctrl"], spec["yards"])
    # Features are authored as fractions of the DESIGN length (the original longer layout); remap them so
    # green/tee surrounds keep their metres and only the middle of the hole shrinks to the new length.
    L0 = spec.get("design_yards", spec["yards"]) * YD
    L1 = P.total
    ff = lambda f: smap(f * L0, L0, L1) / L1
    along_k = max(0.5, middle_scale(L0, L1)) if L0 > L1 else 1.0
    hw = spec["fw_width"] / 2.0
    wl = spec.get("side_a", 50.0)   # boundary offset on the + side
    wr = spec.get("side_b", 50.0)   # boundary offset on the - side
    d = {"id": spec["id"], "name": spec["name"], "par": spec["par"], "yards": spec["yards"]}
    tee = P.at(0.0)
    green_c = P.at(1.0)
    d["tee"] = [0, 0]
    po = spec.get("pin_offset", (2.0, 3.0))
    d["pin"] = [r1(green_c[0] + po[0]), r1(green_c[1] + po[1])]
    d["theme"] = {"conifer": spec.get("conifer", 0.78), "style": spec.get("style", "forest")}
    d["tee_boxes"] = [{"center": [0, 0], "size": [8, 11], "rot_deg": 0}]
    d["fairway"] = [{"points": [[r1(x), r1(z)] for x, z in P.pts], "width": spec["fw_width"]}]
    gr = spec.get("green", (13, 11))
    d["greens"] = [{"center": [r1(green_c[0]), r1(green_c[1])], "radii": list(gr), "rot_deg": round(rng.uniform(-30, 30), 1),
                    "tilt": [round(rng.uniform(-0.02, 0.02), 3), round(rng.uniform(-0.02, 0.02), 3)]}]
    bunkers = []
    for (f, t, ra, rb, depth) in spec.get("bunkers", []):
        f = ff(f)
        c = P.at(f, t)
        dx, dz = P.dir_at(f)
        bunkers.append({"center": [r1(c[0]), r1(c[1])], "radii": [ra, rb], "rot_deg": rot_for_axis(-dz, dx), "depth": depth})
    d["bunkers"] = bunkers
    water = []
    for w in spec.get("water", []):
        wf = ff(w["f"])
        c = P.at(wf, w.get("t", 0.0))
        dx, dz = P.dir_at(wf)
        axis = (-dz, dx) if w.get("across", True) else (dx, dz)
        radii = list(w["radii"])
        k = 1 if w.get("across", True) else 0   # index of the along-the-hole radius
        if along_k < 1.0:
            radii[k] = r1(max(3.5, radii[k] * along_k))
        water.append({"center": [r1(c[0]), r1(c[1])], "radii": radii, "rot_deg": rot_for_axis(*axis)})
    d["water"] = water
    # ---- rendered terrain extent. There is no per-hole OOB line any more: the game treats everything
    # inside `bounds` minus a 25 m edge band as in play ("Make all visible course playable").
    # The corridor below (side_a/side_b off the centreline) only sizes the map and places the hills.
    N = max(12, int(P.total / 14))
    poly = []
    for i in range(-2, N + 3):
        f = min(max(i / N, -0.06), 1.06)
        poly.append(P.at(f, wl * (1.0 + 0.12 * math.sin(f * 9.0))))
        poly.append(P.at(f, -wr * (1.0 + 0.12 * math.sin(f * 7.0 + 1.3))))
    xs = [p[0] for p in poly]
    zs = [p[1] for p in poly]
    m = spec.get("map_margin", 80)
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
        c = P.at(ff(f), t)
        bumps.append({"center": [r1(c[0]), r1(c[1])], "radius": rad, "height": h})
    ring = [P.at(i / 80.0) for i in range(-4, 85)]
    placed = 0
    tries = 0
    hill_off = spec.get("hill_off", (25, 70))
    hill_rad = spec.get("hill_rad", (55, 110))
    hill_h = spec.get("hill_h", (7, 22))
    while placed < spec.get("hills", 16) and tries < 400:
        tries += 1
        f = rng.uniform(-0.05, 1.05)
        side = rng.choice([1, -1])
        off = (wl if side > 0 else wr) + rng.uniform(*hill_off)
        c = P.at(f, side * off)
        rad = rng.uniform(*hill_rad)
        # keep every hill clear of ALL stretches of the hole (bends bring other fairway sections close)
        if min(math.dist(c, q) for q in ring) < 1.3 * rad + hw + 10:
            continue
        h = rng.uniform(*hill_h) * spec.get("hill_scale", 1.0)
        if side in spec.get("valley_sides", []):
            h = -h * 0.8
        bumps.append({"center": [r1(c[0]), r1(c[1])], "radius": r1(rad), "height": round(h, 1)})
        placed += 1
    # ---- links dunes: many medium humps in the rough, each >= 2 sigma clear of every fairway stretch
    placed = 0
    tries = 0
    while placed < spec.get("dunes", 0) and tries < 600:
        tries += 1
        f = rng.uniform(-0.04, 1.04)
        rad = rng.uniform(14, 26)
        c = P.at(f, rng.choice([1, -1]) * (hw + rad + rng.uniform(4, 45)))
        if min(math.dist(c, q) for q in ring) < hw + rad + 4 or math.dist(c, green_c) < rad + 26:
            continue
        bumps.append({"center": [r1(c[0]), r1(c[1])], "radius": r1(rad), "height": round(rng.uniform(1.6, 4.2), 2)})
        placed += 1
    d["terrain"] = {"base": spec["base"], "plane": [0, spec["slope"]], "bumps": bumps}
    # ---- trees: rows both sides, plus clusters. Dense, mostly conifers (theme).
    lines = []
    seed = spec["seed"] * 10
    spacing = spec.get("tree_spacing", (7.5, 10.5))
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
                              "spacing": round(rng.uniform(*spacing), 1), "jitter": spec.get("tree_jitter", 3.5), "seed": seed})
    d["tree_lines"] = lines
    clusters = []
    for _ in range(spec.get("clusters", 10)):
        f = rng.uniform(0.05, 0.95)
        side = rng.choice([1, -1])
        c = P.at(f, side * (hw + rng.uniform(*spec.get("cluster_off", (14, 40)))))
        clusters.append({"center": [r1(c[0]), r1(c[1])], "radius": r1(rng.uniform(10, 20)), "count": rng.randint(*spec.get("cluster_count", (6, 14))), "seed": seed + len(clusters) + 100})
    d["tree_clusters"] = clusters
    d["wind"] = {"speed": spec["wind"][0], "bearing": spec["wind"][1]}
    d["relief_points"] = [[r1(P.at(f)[0]), r1(P.at(f)[1])] for f in (0.25, 0.5, 0.75)]
    d["camera"] = {"overhead_padding": 1.1}
    return d


RIDGE = [
    dict(id="hole_04", name="Switchback", par=4, yards=170, design_yards=380, seed=4, base=12, slope=0.055, fw_width=28,
         ctrl=[(0, 0), (0, 70), (-30, 140), (-45, 215), (-15, 280), (30, 325), (46, 350)],
         bunkers=[(0.42, 20, 5, 9, 0.7), (0.62, -19, 4, 7.5, 0.7), (0.97, 13, 4, 6, 0.65), (0.99, -12, 4.5, 5.5, 0.65), (0.93, -14, 5, 3.6, 0.6)],
         mounds=[(0.55, 35, 28, 2.4), (0.8, -32, 26, 2.6)], wind=(2.5, 40)),
    dict(id="hole_05", name="Ravine Drop", par=3, yards=90, design_yards=195, seed=5, base=26, slope=-0.085, fw_width=26,
         ctrl=[(0, 0), (0, 60), (6, 125), (10, 178)], side_a=44, side_b=44,
         water=[dict(f=0.5, t=6, radii=[24, 13], across=True)],
         bunkers=[(0.94, 10, 4.5, 6, 0.7), (0.97, -11, 4, 5.5, 0.7), (1.03, 2, 6, 3.4, 0.6)],
         mounds=[(0.8, 28, 22, 2.2)], wind=(1.5, 200), green=(12, 10), pin_offset=(-1.0, 2.0)),
    dict(id="hole_06", name="Timber Line", par=5, yards=270, design_yards=540, seed=6, base=18, slope=0.018, fw_width=24,
         ctrl=[(0, 0), (0, 80), (40, 155), (72, 235), (55, 325), (-8, 395), (-32, 455), (-22, 525)],
         side_a=40, side_b=40, conifer=0.9, clusters=18, tree_rows=[8, 18, 30, 44, 60, 80],
         bunkers=[(0.3, 18, 4, 8, 0.7), (0.58, -16, 4.5, 7, 0.7), (0.96, -12, 4, 6, 0.65)],
         mounds=[(0.4, -30, 24, 2.4)], wind=(2.0, 120), undulation=1.2),
    dict(id="hole_07", name="Cascade Creek", par=4, yards=150, design_yards=335, seed=7, base=14, slope=-0.032, fw_width=27,
         ctrl=[(0, 0), (0, 90), (24, 165), (42, 235), (36, 305)],
         water=[dict(f=0.52, t=0, radii=[42, 6.5], across=True), dict(f=0.96, t=-26, radii=[13, 9], across=True)],
         bunkers=[(0.3, -17, 4, 9, 0.7), (0.78, 16, 4.5, 7, 0.7), (0.98, 12, 4, 5.5, 0.65)],
         mounds=[(0.7, -34, 26, 2.2)], wind=(3.0, 250), green=(12, 12)),
    dict(id="hole_08", name="The Bowl", par=3, yards=70, design_yards=160, seed=8, base=16, slope=-0.012, fw_width=24,
         ctrl=[(0, 0), (5, 50), (0, 100), (-8, 146)], side_a=46, side_b=46, conifer=0.7,
         bunkers=[(0.95, 12, 5, 6, 0.8), (0.97, -13, 5, 6.5, 0.8), (1.13, 0, 8, 3.5, 0.7), (0.88, 8, 4, 4.5, 0.7)],
         mounds=[(1.0, 0, 52, -3.0), (0.78, 30, 22, 2.8), (0.78, -30, 22, 2.8), (1.12, 20, 22, 2.8), (1.12, -22, 22, 2.8), (0.95, 36, 20, 2.5)],
         wind=(1.0, 20), green=(14, 12)),
    dict(id="hole_09", name="Summit", par=5, yards=290, design_yards=575, seed=9, base=20, slope=0.05, fw_width=26,
         ctrl=[(0, 0), (0, 100), (-30, 195), (-42, 295), (0, 380), (42, 450), (30, 526)],
         side_a=28, side_b=48, valley_sides=[1], hill_scale=1.2,
         bunkers=[(0.35, -20, 4.5, 9, 0.7), (0.6, 18, 5, 8, 0.7), (0.94, -13, 5, 6, 0.75), (0.97, 14, 4.5, 5.5, 0.75), (1.04, -3, 8, 3.5, 0.7)],
         mounds=[(0.5, -34, 26, 2.6), (0.82, 30, 24, 2.4)], wind=(4.0, 160), green=(14, 11), pin_offset=(1.0, 3.0)),
]

# Open seaside links: low and windy, rolling dune humps, deep pot bunkers (some in the fairway), a burn,
# a handful of wind-bent trees (few rows, wide spacing), broad greens.
LINKS = dict(style="links", conifer=0.35, base=4, slope=0.004, side_a=58, side_b=58,
             tree_rows=[34, 62], tree_spacing=(24, 38), tree_jitter=6.0, clusters=3, cluster_off=(30, 55),
             cluster_count=(3, 5), hills=10, hill_off=(30, 80), hill_rad=(40, 75), hill_h=(3, 8), dunes=26,
             undulation=1.3)

COASTAL = [
    dict(LINKS, id="hole_10", name="Sea Breeze", par=4, yards=175, design_yards=395, seed=10, fw_width=32,
         ctrl=[(0, 0), (0, 110), (10, 200), (34, 280), (52, 350)],
         bunkers=[(0.38, -6, 2.8, 3.0, 1.0), (0.55, 19, 3.2, 3.4, 1.0), (0.62, -17, 3.0, 3.2, 1.0),
                  (0.95, 13, 2.8, 3.0, 1.0), (0.97, -12, 3.0, 3.2, 1.0), (1.05, 6, 2.6, 2.8, 0.9)],
         mounds=[(0.45, 34, 20, 3.0), (0.86, -34, 22, 3.2)], wind=(5.5, 250), green=(15, 13), pin_offset=(-2.0, 3.0)),
    dict(LINKS, id="hole_11", name="Pot Luck", par=3, yards=80, design_yards=170, seed=11, fw_width=28,
         ctrl=[(0, 0), (-4, 60), (-8, 115), (-6, 155)],
         bunkers=[(0.88, 0, 3.0, 3.2, 1.05), (0.93, 13, 2.8, 3.0, 1.0), (0.95, -13, 3.0, 3.0, 1.0),
                  (1.06, 9, 2.8, 2.8, 1.0), (1.07, -8, 2.8, 3.0, 1.0)],
         mounds=[(0.72, 30, 18, 2.6), (0.72, -30, 18, 2.6)], wind=(6.5, 300), green=(14, 12), pin_offset=(1.5, 2.0)),
    dict(LINKS, id="hole_12", name="The Dunes", par=5, yards=275, design_yards=555, seed=12, fw_width=30,
         ctrl=[(0, 0), (0, 100), (-28, 190), (-40, 290), (-12, 380), (24, 450), (30, 515)],
         bunkers=[(0.28, 17, 3.0, 3.4, 1.0), (0.46, -5, 2.8, 3.0, 1.0), (0.5, 7, 2.8, 3.0, 1.0),
                  (0.7, -18, 3.2, 3.4, 1.0), (0.84, 6, 3.0, 3.0, 1.0), (0.96, -13, 3.0, 3.2, 1.0), (0.97, 13, 2.8, 3.0, 1.0)],
         mounds=[(0.6, 34, 22, 3.4), (0.36, -34, 22, 3.0)], wind=(6.0, 200), green=(15, 12), pin_offset=(1.0, 3.0)),
    dict(LINKS, id="hole_13", name="Lighthouse Burn", par=4, yards=155, design_yards=350, seed=13, fw_width=30,
         ctrl=[(0, 0), (0, 90), (-14, 180), (-34, 250), (-46, 315)],
         water=[dict(f=0.74, t=0, radii=[44, 4.5], across=True)],
         bunkers=[(0.4, 16, 3.0, 3.2, 1.0), (0.52, -14, 2.8, 3.2, 1.0), (0.96, 12, 3.0, 3.0, 1.0), (0.98, -12, 2.8, 3.0, 1.0)],
         mounds=[(0.6, -36, 20, 3.0)], wind=(7.0, 160), green=(14, 12)),
]

# Parkland lakes: water carries off the tee and into greens, broad-leaved trees, gentle slopes, light wind.
PARK = dict(style="lakeside", conifer=0.15, base=6, slope=0.006, side_a=54, side_b=54,
            tree_rows=[10, 24, 40, 58], tree_spacing=(8.5, 12.5), clusters=12, hills=12, hill_off=(30, 75),
            hill_rad=(55, 95), hill_h=(4, 11), undulation=0.7)

LAKESIDE = [
    dict(PARK, id="hole_14", name="Lily Pad", par=4, yards=165, design_yards=365, seed=14, fw_width=30,
         ctrl=[(0, 0), (0, 120), (-12, 220), (-30, 300), (-36, 330)],
         water=[dict(f=0.44, t=4, radii=[40, 15], across=True), dict(f=0.9, t=-34, radii=[26, 10], across=False)],
         bunkers=[(0.66, 18, 4.5, 8, 0.7), (0.97, 13, 4, 6, 0.65)],
         mounds=[(0.7, -34, 24, 1.8)], wind=(1.5, 70), green=(13, 12), pin_offset=(1.0, 2.0)),
    dict(PARK, id="hole_15", name="Water Carry", par=3, yards=85, design_yards=165, seed=15, fw_width=26,
         ctrl=[(0, 0), (2, 60), (8, 110), (10, 150)],
         water=[dict(f=0.6, t=0, radii=[32, 24], across=True)],
         bunkers=[(1.06, 4, 6, 3.4, 0.6), (0.96, 13, 4, 5, 0.65)],
         mounds=[(0.95, -30, 20, 1.8)], wind=(2.0, 110), green=(13, 11), pin_offset=(-1.0, 2.0)),
    dict(PARK, id="hole_16", name="Two Lakes", par=5, yards=250, design_yards=525, seed=16, fw_width=28,
         ctrl=[(0, 0), (0, 110), (30, 210), (48, 300), (40, 390), (16, 480)],
         water=[dict(f=0.33, t=-6, radii=[42, 15], across=True), dict(f=0.66, t=36, radii=[48, 12], across=False),
                dict(f=0.91, t=0, radii=[34, 5.5], across=True)],
         bunkers=[(0.52, -18, 4.5, 8, 0.7), (0.97, -12, 4, 6, 0.65), (0.98, 13, 4, 5.5, 0.65)],
         wind=(2.5, 300), green=(13, 12)),
    dict(PARK, id="hole_17", name="Boathouse", par=4, yards=185, design_yards=405, seed=17, fw_width=30,
         ctrl=[(0, 0), (0, 120), (14, 230), (24, 310), (20, 370)],
         water=[dict(f=0.5, t=-38, radii=[110, 17], across=False), dict(f=0.98, t=26, radii=[11, 8], across=True)],
         bunkers=[(0.36, 18, 4.5, 8, 0.7), (0.72, 18, 4, 7, 0.7), (0.95, -13, 4, 6, 0.65)],
         mounds=[(0.55, 36, 26, 2.0)], wind=(1.8, 20), green=(13, 12), pin_offset=(-1.5, 2.5)),
]

HOLES = RIDGE + COASTAL + LAKESIDE


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "..", "..", "data", "holes")
    for spec in HOLES:
        d = build(spec)
        with open(os.path.join(out, spec["id"] + ".json"), "w") as f:
            json.dump(d, f, indent=1)
        print(spec["id"], spec["name"], "trees(lines)", len(d["tree_lines"]), "bounds", d["bounds"])

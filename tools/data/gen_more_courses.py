#!/usr/bin/env python3
"""Authoring tool for four more themed courses, built on gen_forest_holes.build():

  ALPINE   Alpine Peaks   (hole_33 .. hole_38, 6) high mountain: big elevation changes up and down the slope,
                          dense conifers, a glacial tarn par 3, a meltwater creek, valleys on one side.
  OASIS    Oasis Dunes    (hole_39 .. hole_44, 6) desert oasis: sand dunes, broad waste bunkers, palm-like
                          deciduous clusters around ponds, strong wind. (Canyon Mesa is dry rock; this is wet sand.)
  ISLANDS  Archipelago    (hole_45 .. hole_50, 6) island-hopping: sea-level holes with water carries, an island
                          green, a causeway between two water lines, light trees, sea wind.
  STADIUM  Stadium Park   (hole_51 .. hole_59, 9) manicured stadium parkland: flat, spectator banks (mounds) lining
                          the holes, ornamental tree rows, big bunkered greens, an amphitheatre finish.

Writes data/holes/hole_NN.json (JSON stays the source of truth) and registers the courses in data/courses.json
(before "full9"; Full 9 and Grand Tour are unchanged, docs/DECISIONS.md 2026-11-08).
Hole lengths follow the owner's DEFAULT (yellow tee) ranges: par 3 50-100, par 4 100-200, par 5 200-300 yd.
Relief points are moved off water/bunkers (back along the centreline) so automatic relief always lands dry.
Re-run:  python3 tools/data/gen_more_courses.py
"""
import json, math, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_forest_holes as G
import tee_pin_options
from gen_new_courses import front, back

RELIEF_CLEAR_M = 4.0

# ---------------------------------------------------------------- Alpine Peaks
ALP = dict(style="alpine", conifer=0.95, base=70, side_a=46, side_b=46,
           tree_rows=[11, 22, 34, 48, 64], tree_spacing=(7.0, 10.0), clusters=16, cluster_off=(12, 34),
           cluster_count=(7, 13), hills=16, hill_off=(20, 70), hill_rad=(50, 100), hill_h=(14, 32),
           undulation=1.4, green=(14, 12))

ALPINE = [
    dict(ALP, id="hole_33", name="Glacier Gate", par=4, yards=150, seed=133, slope=0.025, fw_width=28,
         ctrl=[(0, 0), (0, 80), (10, 150), (24, 215)],
         bunkers=[(0.55, -17, 4.5, 8, 0.7), (front(150, 22), 11, 5, 4, 0.8)],
         mounds=[(0.7, 32, 24, 2.6)], wind=(3.0, 200), tilt=(0.01, -0.015), pin_offset=(0.5, 1.5)),
    dict(ALP, id="hole_34", name="The Tarn", par=3, yards=75, seed=134, slope=-0.075, fw_width=26,
         ctrl=[(0, 0), (0, 40), (3, 80), (2, 120)], side_a=42, side_b=42,
         water=[dict(f=0.58, t=-4, radii=[26, 10], across=True)],
         bunkers=[(front(75, 16), 13, 4.5, 4, 0.8), (back(75, 20), -2, 7, 3.0, 0.6)],
         mounds=[(0.9, -28, 20, 2.4)], wind=(2.0, 90), pin_offset=(0.5, 1.5)),
    dict(ALP, id="hole_35", name="Chairlift", par=5, yards=260, seed=135, slope=0.06, fw_width=28,
         ctrl=[(0, 0), (0, 90), (35, 165), (60, 240), (30, 320), (-15, 380), (-30, 440)], valley_sides=[1],
         bunkers=[(0.38, -18, 4.5, 8, 0.7), (0.66, 18, 4.5, 8, 0.7), (front(260, 22), -12, 5, 4, 0.8)],
         mounds=[(0.5, -34, 26, 2.6)], wind=(3.5, 300), green=(15, 12), tilt=(0.015, -0.03), pin_offset=(1.0, 2.0)),
    dict(ALP, id="hole_36", name="Edelweiss", par=3, yards=88, seed=136, slope=-0.04, fw_width=26,
         ctrl=[(0, 0), (-3, 50), (-6, 100), (-4, 150)], side_a=44, side_b=44,
         bunkers=[(front(88, 17), -12, 5, 4, 0.8), (front(88, 17), 12, 5, 4, 0.8), (back(88, 20), 0, 8, 3.0, 0.6)],
         mounds=[(0.85, 30, 20, 2.4)], wind=(2.5, 30), pin_offset=(-0.5, 1.5)),
    dict(ALP, id="hole_37", name="Avalanche Chute", par=4, yards=190, seed=137, slope=-0.045, fw_width=25,
         ctrl=[(0, 0), (0, 90), (-12, 170), (-30, 250), (-26, 320)], side_a=34, side_b=50, valley_sides=[1],
         bunkers=[(0.48, 16, 4, 8, 0.7), (front(190, 21), -11, 5, 4, 0.8), (front(190, 21), 11, 5, 4, 0.8)],
         mounds=[(0.75, -32, 24, 2.4)], wind=(4.0, 160), tilt=(-0.01, 0.03), pin_offset=(0.5, 2.0)),
    dict(ALP, id="hole_38", name="Summit Hut", par=5, yards=225, seed=138, slope=0.045, fw_width=28,
         ctrl=[(0, 0), (0, 90), (-25, 170), (-30, 250), (0, 320), (20, 370)],
         water=[dict(f=front(225, 34), t=0, radii=[40, 4.0], across=True)],
         bunkers=[(0.42, 18, 4.5, 8, 0.7), (front(225, 14), -20, 5, 4.5, 0.8), (back(225, 21), 0, 8, 3.0, 0.6)],
         mounds=[(0.6, -32, 24, 2.4)], wind=(3.0, 60), green=(15, 13), tilt=(0.02, -0.025), pin_offset=(1.0, 2.0)),
]

# ---------------------------------------------------------------- Oasis Dunes
OAS = dict(style="oasis", conifer=0.05, base=30, slope=0.008, side_a=58, side_b=58,
           tree_rows=[40], tree_spacing=(22, 34), tree_jitter=6.0, clusters=10, cluster_off=(16, 40),
           cluster_count=(4, 8), hills=10, hill_off=(30, 80), hill_rad=(40, 80), hill_h=(6, 16), dunes=30,
           undulation=1.3, green=(15, 12))

OASIS = [
    dict(OAS, id="hole_39", name="Mirage", par=4, yards=160, seed=139, fw_width=28,
         ctrl=[(0, 0), (0, 80), (-10, 160), (-30, 230)],
         water=[dict(f=0.6, t=-32, radii=[30, 12], across=False)],
         bunkers=[(0.4, 24, 9, 18, 0.45), (front(160, 21), 11, 5, 4, 0.8)],
         wind=(5.0, 240), pin_offset=(0.5, 2.0)),
    dict(OAS, id="hole_40", name="Palm Springs", par=3, yards=70, seed=140, fw_width=24,
         ctrl=[(0, 0), (0, 40), (2, 80), (4, 110)], side_a=46, side_b=46,
         water=[dict(f=front(70, 14), t=24, radii=[10, 12], across=True)],
         bunkers=[(front(70, 17), -13, 5, 4, 0.8), (back(70, 20), 0, 8, 3.0, 0.6)],
         wind=(4.5, 300), green=(14, 12), pin_offset=(-0.5, 1.5)),
    dict(OAS, id="hole_41", name="Caravan Trail", par=5, yards=285, seed=141, fw_width=28, slope=-0.02,
         ctrl=[(0, 0), (0, 100), (30, 200), (40, 300), (10, 390), (-20, 460)],
         water=[dict(f=0.62, t=34, radii=[34, 12], across=False)],
         bunkers=[(0.3, -24, 10, 22, 0.45), (0.5, 24, 9, 18, 0.45), (0.8, -23, 9, 16, 0.45), (front(285, 22), 12, 5, 4, 0.8)],
         wind=(5.5, 100), pin_offset=(1.0, 2.5)),
    dict(OAS, id="hole_42", name="Sandstorm", par=4, yards=120, seed=142, fw_width=28,
         ctrl=[(0, 0), (0, 60), (6, 120), (4, 170)],
         bunkers=[(0.5, 0, 22, 6, 0.45), (front(120, 20), -11, 5, 4, 0.8), (front(120, 20), 11, 5, 4, 0.8)],
         wind=(7.0, 270), pin_offset=(0.5, 1.5)),
    dict(OAS, id="hole_43", name="Date Grove", par=4, yards=185, seed=143, fw_width=28, slope=0.02,
         ctrl=[(0, 0), (0, 90), (20, 170), (45, 250), (50, 320)], clusters=20, cluster_off=(14, 30),
         water=[dict(f=front(185, 30), t=-30, radii=[14, 10], across=True)],
         bunkers=[(0.45, -22, 9, 16, 0.45), (front(185, 21), 11, 5, 4, 0.8)],
         wind=(4.0, 30), pin_offset=(-1.0, 2.0)),
    dict(OAS, id="hole_44", name="Twin Wells", par=5, yards=245, seed=144, fw_width=28,
         ctrl=[(0, 0), (0, 90), (-25, 170), (-35, 260), (-10, 340), (10, 400)],
         water=[dict(f=0.36, t=0, radii=[40, 9], across=True), dict(f=front(245, 32), t=0, radii=[36, 5.0], across=True)],
         bunkers=[(0.6, 24, 9, 18, 0.45), (front(245, 14), -20, 5, 4.5, 0.8), (back(245, 21), 0, 8, 3.0, 0.6)],
         wind=(5.0, 180), green=(16, 13), pin_offset=(0.5, 2.0)),
]

# ---------------------------------------------------------------- Archipelago
ISL = dict(style="island", conifer=0.2, base=2, slope=0.002, side_a=56, side_b=56,
           tree_rows=[30, 56], tree_spacing=(18, 28), tree_jitter=5.0, clusters=6, cluster_off=(22, 46),
           cluster_count=(3, 6), hills=8, hill_off=(30, 80), hill_rad=(40, 70), hill_h=(3, 7), dunes=10,
           undulation=0.8, green=(15, 13))

ISLANDS = [
    dict(ISL, id="hole_45", name="Ferry Crossing", par=4, yards=140, seed=145, fw_width=30,
         ctrl=[(0, 0), (0, 70), (8, 140), (20, 200)],
         water=[dict(f=0.45, t=0, radii=[60, 11], across=True)],
         bunkers=[(front(140, 20), -11, 5, 4, 0.8), (front(140, 20), 11, 5, 4, 0.8)],
         wind=(4.5, 90), pin_offset=(0.5, 2.0)),
    dict(ISL, id="hole_46", name="Island Green", par=3, yards=85, seed=146, fw_width=24,
         ctrl=[(0, 0), (0, 50), (0, 100), (0, 140)], side_a=48, side_b=48, green=(14, 12),
         water=[dict(f=front(85, 26), t=0, radii=[40, 9], across=True),
                dict(f=back(85, 24), t=0, radii=[40, 7], across=True),
                dict(f=1.0, t=26, radii=[7, 18], across=True), dict(f=1.0, t=-26, radii=[7, 18], across=True)],
         wind=(3.5, 200), tilt=(0.01, -0.02), pin_offset=(0.0, 1.0)),
    dict(ISL, id="hole_47", name="Causeway", par=5, yards=270, seed=147, fw_width=26,
         ctrl=[(0, 0), (0, 100), (10, 200), (30, 300), (30, 420)],
         water=[dict(f=0.5, t=30, radii=[70, 9], across=False), dict(f=0.5, t=-30, radii=[70, 9], across=False),
                dict(f=0.82, t=0, radii=[40, 7], across=True)],
         bunkers=[(front(270, 21), -11, 5, 4, 0.8), (front(270, 21), 11, 5, 4, 0.8)],
         wind=(5.0, 135), pin_offset=(1.0, 2.0)),
    dict(ISL, id="hole_48", name="Lagoon", par=4, yards=180, seed=148, fw_width=30,
         ctrl=[(0, 0), (0, 90), (25, 160), (70, 210), (120, 230)],
         water=[dict(f=0.55, t=42, radii=[34, 22], across=True)],
         bunkers=[(0.45, -20, 4.5, 8, 0.7), (front(180, 21), 11, 5, 4, 0.8)],
         wind=(4.0, 20), pin_offset=(-0.5, 2.0)),
    dict(ISL, id="hole_49", name="The Reef", par=3, yards=60, seed=149, fw_width=24,
         ctrl=[(0, 0), (0, 40), (-2, 80), (-3, 100)], side_a=44, side_b=44,
         water=[dict(f=0.58, t=0, radii=[34, 6], across=True)],
         bunkers=[(front(60, 16), 12, 4.5, 3.5, 0.8), (back(60, 19), -3, 7, 3.0, 0.6)],
         wind=(5.0, 250), green=(13, 11), pin_offset=(0.5, 1.0)),
    dict(ISL, id="hole_50", name="Lighthouse Isle", par=5, yards=235, seed=150, fw_width=28,
         ctrl=[(0, 0), (0, 90), (-20, 180), (-20, 270), (10, 360)],
         water=[dict(f=0.3, t=0, radii=[50, 9], across=True), dict(f=0.7, t=0, radii=[50, 8], across=True),
                dict(f=0.95, t=-36, radii=[12, 18], across=True)],
         bunkers=[(front(235, 20), 12, 5, 4, 0.8), (back(235, 21), 0, 8, 3.0, 0.6)],
         wind=(6.0, 300), pin_offset=(0.5, 2.0)),
]

# ---------------------------------------------------------------- Stadium Park
STA = dict(style="stadium", conifer=0.1, base=8, slope=0.0, side_a=54, side_b=54,
           tree_rows=[14, 34], tree_spacing=(10, 13), tree_jitter=1.0, clusters=4, cluster_off=(30, 50),
           cluster_count=(3, 5), hills=8, hill_off=(30, 75), hill_rad=(55, 90), hill_h=(4, 9),
           undulation=0.5, green=(17, 14))


def banks(fs, off=26, rad=16, h=3.2):
    """Spectator banks: a mound either side of the fairway at each fraction."""
    out = []
    for f in fs:
        out += [(f, off, rad, h), (f, -off, rad, h)]
    return out


GB = lambda y: [(front(y, 18), -12, 6, 4, 0.8), (front(y, 18), 12, 6, 4, 0.8)]   # front greenside pair

STADIUM = [
    dict(STA, id="hole_51", name="Kick Off", par=4, yards=150, seed=151, fw_width=32,
         ctrl=[(0, 0), (0, 100), (0, 200)], bunkers=[(0.55, 18, 4.5, 8, 0.7)] + GB(150),
         mounds=banks([0.3, 0.6]), wind=(1.5, 80), pin_offset=(0.5, 2.0)),
    dict(STA, id="hole_52", name="Penalty Spot", par=3, yards=64, seed=152, fw_width=26,
         ctrl=[(0, 0), (0, 40), (0, 80)], side_a=44, side_b=44, green=(16, 13),
         bunkers=GB(64) + [(back(64, 20), 0, 8, 3.0, 0.6)], mounds=banks([0.5], off=24), wind=(1.0, 200),
         pin_offset=(0.0, 1.0)),
    dict(STA, id="hole_53", name="Wing Play", par=5, yards=280, seed=153, fw_width=30,
         ctrl=[(0, 0), (0, 120), (30, 230), (70, 330), (80, 440)],
         bunkers=[(0.35, -18, 4.5, 9, 0.7), (0.6, 18, 4.5, 9, 0.7)] + GB(280),
         mounds=banks([0.2, 0.45, 0.7]), wind=(2.0, 300), pin_offset=(1.0, 2.0)),
    dict(STA, id="hole_54", name="Half Time", par=3, yards=86, seed=154, fw_width=26,
         ctrl=[(0, 0), (2, 50), (6, 100), (8, 140)], side_a=46, side_b=46,
         bunkers=GB(86) + [(back(86, 21), 0, 9, 3.0, 0.6)], mounds=banks([0.45], off=24), wind=(1.5, 30),
         pin_offset=(-0.5, 1.5)),
    dict(STA, id="hole_55", name="Counter Attack", par=4, yards=175, seed=155, fw_width=30,
         ctrl=[(0, 0), (0, 90), (-20, 170), (-40, 260)],
         water=[dict(f=0.62, t=-36, radii=[60, 11], across=False)],
         bunkers=[(0.5, 18, 4.5, 8, 0.7)] + GB(175), mounds=banks([0.3], off=28), wind=(2.0, 120),
         pin_offset=(0.5, 2.0)),
    dict(STA, id="hole_56", name="Dugout", par=4, yards=115, seed=156, fw_width=30,
         ctrl=[(0, 0), (0, 70), (-14, 130), (-30, 170)],
         bunkers=[(0.45, 0, 6, 4, 0.9)] + GB(115), mounds=banks([0.3, 0.6], off=26), wind=(1.5, 260),
         pin_offset=(0.5, 1.5)),
    dict(STA, id="hole_57", name="Extra Time", par=5, yards=215, seed=157, fw_width=30,
         ctrl=[(0, 0), (0, 100), (20, 190), (40, 280), (40, 340)],
         water=[dict(f=front(215, 32), t=0, radii=[44, 7], across=True)],
         bunkers=[(0.4, -18, 4.5, 8, 0.7), (front(215, 14), -20, 5, 4.5, 0.8), (front(215, 14), 20, 5, 4.5, 0.8)],
         mounds=banks([0.25, 0.55]), wind=(2.0, 45), pin_offset=(0.5, 2.0)),
    dict(STA, id="hole_58", name="Corner Flag", par=3, yards=78, seed=158, fw_width=26,
         ctrl=[(0, 0), (0, 50), (12, 95), (24, 120)], side_a=46, side_b=46,
         bunkers=GB(78) + [(back(78, 20), 0, 8, 3.0, 0.6)], mounds=banks([0.4], off=24), wind=(1.5, 300),
         pin_offset=(0.5, 1.5)),
    dict(STA, id="hole_59", name="Final Whistle", par=4, yards=185, seed=159, fw_width=32,
         ctrl=[(0, 0), (0, 100), (10, 200), (10, 290)],
         bunkers=[(0.45, 18, 4.5, 9, 0.7), (0.6, -18, 4.5, 9, 0.7)] + GB(185),
         mounds=banks([0.25, 0.5, 0.72]) + [(back(185, 40), 0, 24, 4.0), (1.0, 40, 20, 3.6), (1.0, -40, 20, 3.6)],
         wind=(1.5, 180), green=(18, 15), pin_offset=(0.5, 2.0)),
]

COURSES = [
    {"id": "alpine", "name": "Alpine Peaks", "blurb": "6 mountain holes, steep climbs and drops, a glacial tarn", "specs": ALPINE},
    {"id": "oasis", "name": "Oasis Dunes", "blurb": "6 desert-oasis holes, dunes, ponds, strong wind", "specs": OASIS},
    {"id": "islands", "name": "Archipelago", "blurb": "6 island holes, sea carries and an island green", "specs": ISLANDS},
    {"id": "stadium", "name": "Stadium Park", "blurb": "9 flat stadium holes, spectator banks, big greens", "specs": STADIUM},
]


def _hazards(d):
    return list(d.get("water", [])) + list(d.get("bunkers", []))


def fix_relief(d):
    """Move each relief point back along the centreline until it is clear of water and bunkers."""
    pts = [tuple(p) for p in d["fairway"][0]["points"]]
    dense = []
    for a, b in zip(pts, pts[1:]):
        for i in range(20):
            u = i / 20.0
            dense.append((a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u))
    out = []
    for rp in d["relief_points"]:
        k = min(range(len(dense)), key=lambda i: math.dist(dense[i], rp))
        while k > 0 and any(tee_pin_options.ell_signed_dist(h, *dense[k]) < RELIEF_CLEAR_M for h in _hazards(d)):
            k -= 1
        p = [round(dense[k][0], 1), round(dense[k][1], 1)]
        if p not in out:
            out.append(p)
    d["relief_points"] = out
    return d


def register(root):
    """Adds/replaces the courses in data/courses.json (text insert before "full9", keeps the file's formatting)."""
    path = os.path.join(root, "data", "courses.json")
    text = open(path).read()
    have = {c["id"] for c in json.loads(text)["courses"]}
    for c in COURSES:
        holes = ", ".join(json.dumps(s["id"]) for s in c["specs"])
        entry = ('    {\n      "id": %s,\n      "name": %s,\n      "blurb": %s,\n      "holes": [%s]\n    },\n'
                 % (json.dumps(c["id"]), json.dumps(c["name"]), json.dumps(c["blurb"]), holes))
        if c["id"] in have:
            pat = re.compile(r'    \{\n      "id": "%s",.*?\n    \},?\n' % re.escape(c["id"]), re.S)
            text = pat.sub(lambda m: entry, text, count=1)
        else:
            marker = '    {\n      "id": "full9"'
            text = text.replace(marker, entry + marker, 1)
    json.loads(text)
    open(path, "w").write(text)


if __name__ == "__main__":
    root = os.path.join(HERE, "..", "..")
    for c in COURSES:
        for spec in c["specs"]:
            d = fix_relief(tee_pin_options.augment(G.build(spec)))
            with open(os.path.join(root, "data", "holes", spec["id"] + ".json"), "w") as f:
                json.dump(d, f, indent=1)
            print(c["id"], d["id"], d["name"], "par", d["par"], d["yards"], "yd, green overlap",
                  tee_pin_options.bunker_green_overlap(d), "pins", len(d["pin_options"]), "relief", len(d["relief_points"]))
    register(root)

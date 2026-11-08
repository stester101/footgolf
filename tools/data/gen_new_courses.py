#!/usr/bin/env python3
"""Authoring tool for two more themed courses, built on gen_forest_holes.build():

  JIZZY_NASH_NASH  (hole_18 .. hole_26, 9 holes) Augusta-inspired parkland: rolling pine / dogwood / magnolia
                   style tree rows (deciduous + conifer mix), white-sand bunkers (the normal bunker surface),
                   elevation, big sloping greens with front bunkers, a water-carry par 3 and a creek-fronted
                   green. Inspired only: no real hole layouts, names or trademarks are copied.
  CANYON_MESA      (hole_27 .. hole_32, 6 holes) desert: mesas, big waste bunkers, a dry wash, wind, few trees.

Writes data/holes/hole_NN.json (JSON stays the source of truth) and registers both courses in
data/courses.json. The course NAME lives in one constant per course below (rename there and re-run), and in
courses.json "name".  Re-run:  python3 tools/data/gen_new_courses.py
Hole lengths follow the owner's DEFAULT (yellow tee) ranges: par 3 50-100, par 4 100-200, par 5 200-300 yd.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_forest_holes as G
import tee_pin_options

YD = G.YD
JIZZY_NAME = "Jizzy Nash Nash"   # owner-chosen name; single place to rename (plus courses.json "name")
JIZZY_ID = "jizzy"
MESA_NAME = "Canyon Mesa"
MESA_ID = "mesa"


def front(yards, dist_m):
    """Fraction along a hole of `yards` that is `dist_m` metres short of the green centre."""
    return 1.0 - dist_m / (yards * YD)


def back(yards, dist_m):
    """Fraction along a hole of `yards` that is `dist_m` metres beyond the green centre."""
    return 1.0 + dist_m / (yards * YD)


# Parkland with pines, dogwood-like flowering trees and azalea-style shrub clusters (tree clusters),
# rolling hills for elevation.
MAGNOLIA = dict(style="parkland", conifer=0.45, base=34, slope=0.0, side_a=52, side_b=52,
                tree_rows=[9, 20, 34, 52], tree_spacing=(7.5, 11.0), clusters=18, cluster_off=(12, 38),
                cluster_count=(6, 12), hills=14, hill_off=(25, 70), hill_rad=(50, 100), hill_h=(6, 16),
                undulation=1.2, green=(17, 14))

JIZZY = [
    dict(MAGNOLIA, id="hole_18", name="Long Driveway", par=4, yards=185, seed=118, slope=0.035, fw_width=30,
         ctrl=[(0, 0), (0, 90), (10, 160), (30, 230), (40, 300)],
         bunkers=[(0.52, 17, 4.5, 9, 0.7), (0.64, -18, 4, 8, 0.7), (front(185, 24), -11, 6, 4, 0.8), (front(185, 24), 11, 6, 4, 0.8)],
         mounds=[(0.7, -34, 26, 2.4), (0.9, 30, 22, 2.0)], wind=(2.0, 80), tilt=(0.012, -0.03), pin_offset=(1.0, 2.0)),
    dict(MAGNOLIA, id="hole_19", name="Pecan Row", par=5, yards=270, seed=119, slope=-0.04, fw_width=30,
         ctrl=[(0, 0), (0, 80), (-25, 160), (-50, 250), (-30, 340), (10, 410), (25, 460)],
         bunkers=[(0.4, -17, 4.5, 9, 0.7), (0.66, 18, 5, 8, 0.7), (front(270, 25), -12, 6, 4, 0.8), (front(270, 25), 12, 6, 4, 0.8)],
         mounds=[(0.55, 34, 26, 2.6)], wind=(2.5, 250), green=(18, 14), tilt=(-0.02, 0.032), pin_offset=(-1.0, 2.0)),
    dict(MAGNOLIA, id="hole_20", name="Hollow Pines", par=3, yards=65, seed=120, slope=0.02, fw_width=26,
         ctrl=[(0, 0), (0, 40), (2, 80), (0, 115)], conifer=0.7, green=(15, 12), side_a=44, side_b=44,
         bunkers=[(front(65, 21), -12, 5, 3.5, 0.8), (front(65, 21), 12, 5, 3.5, 0.8)],
         mounds=[(0.9, 28, 20, 2.2)], wind=(1.5, 120), tilt=(0.02, -0.025), pin_offset=(0.5, 1.5)),
    dict(MAGNOLIA, id="hole_21", name="Creekside Carry", par=4, yards=130, seed=121, slope=-0.02, fw_width=28,
         ctrl=[(0, 0), (0, 60), (6, 120), (14, 190)],
         water=[dict(f=front(130, 27), t=0, radii=[44, 4.5], across=True)],
         bunkers=[(front(130, 12), -22, 5, 5, 0.8), (front(130, 12), 22, 5, 5, 0.8), (back(130, 21), 0, 8, 3.0, 0.6)],
         mounds=[(0.45, -32, 24, 2.0)], wind=(1.8, 170), tilt=(0.0, -0.035), pin_offset=(0.5, 2.0)),
    dict(MAGNOLIA, id="hole_22", name="Honeysuckle Bend", par=4, yards=150, seed=122, slope=0.0, fw_width=28,
         ctrl=[(0, 0), (0, 70), (-20, 140), (-70, 200), (-120, 235)],
         bunkers=[(0.5, 17, 5, 8, 0.7), (0.72, -17, 4.5, 7, 0.7), (front(150, 24), -11, 6, 4, 0.8), (front(150, 24), 11, 6, 4, 0.8)],
         mounds=[(0.6, 30, 24, 2.2)], wind=(2.2, 40), tilt=(-0.03, 0.02), pin_offset=(1.0, 2.0)),
    dict(MAGNOLIA, id="hole_23", name="Hickory Drop", par=3, yards=90, seed=123, slope=-0.07, fw_width=26,
         ctrl=[(0, 0), (0, 50), (4, 100), (0, 150)], green=(16, 13), side_a=46, side_b=46,
         water=[dict(f=0.5, t=0, radii=[30, 17], across=True)],
         bunkers=[(front(90, 14), -22, 5, 4.5, 0.8), (front(90, 14), 22, 5, 4.5, 0.8), (back(90, 21), 0, 8, 3.0, 0.6)],
         mounds=[(0.92, 30, 22, 2.0)], wind=(1.6, 200), tilt=(0.03, 0.03), pin_offset=(0.5, 1.5)),
    dict(MAGNOLIA, id="hole_24", name="Dogwood Rise", par=4, yards=170, seed=124, slope=0.06, fw_width=30,
         ctrl=[(0, 0), (0, 80), (16, 150), (30, 220), (22, 290)],
         bunkers=[(0.45, -17, 4.5, 8, 0.7), (0.68, 18, 4.5, 8, 0.7), (front(170, 24), -11, 6, 4, 0.8), (front(170, 24), 11, 6, 4, 0.8)],
         mounds=[(0.8, -30, 22, 2.4)], wind=(2.0, 20), tilt=(0.018, -0.035), pin_offset=(-1.0, 2.0)),
    dict(MAGNOLIA, id="hole_25", name="Magnolia Shade", par=5, yards=240, seed=125, slope=-0.02, fw_width=30,
         ctrl=[(0, 0), (0, 90), (30, 170), (50, 260), (30, 350), (-10, 410)], conifer=0.3,
         water=[dict(f=0.55, t=0, radii=[40, 5.0], across=True)],
         bunkers=[(0.3, 18, 4.5, 9, 0.7), (0.78, -17, 4.5, 8, 0.7), (front(240, 25), -12, 6, 4, 0.8), (front(240, 25), 12, 6, 4, 0.8)],
         mounds=[(0.4, -34, 26, 2.4)], wind=(2.4, 300), green=(18, 14), tilt=(0.02, 0.03), pin_offset=(1.0, 2.0)),
    dict(MAGNOLIA, id="hole_26", name="Homeward Hill", par=4, yards=175, seed=126, slope=0.05, fw_width=30,
         ctrl=[(0, 0), (0, 90), (-14, 170), (-28, 250), (-20, 320)],
         bunkers=[(0.5, -18, 4.5, 9, 0.7), (0.7, 17, 4.5, 8, 0.7), (front(175, 24), -11, 6, 4, 0.8), (front(175, 24), 11, 6, 4, 0.8), (1.15, 0, 9, 3.4, 0.6)],
         mounds=[(0.85, 28, 24, 2.6), (0.85, -28, 24, 2.6)], wind=(2.2, 130), green=(18, 15), tilt=(-0.025, -0.03), pin_offset=(0.5, 2.0)),
]

# Desert: high and dry, mesas, wide waste areas (large shallow bunkers), few trees, steady wind.
DESERT = dict(style="desert", conifer=0.0, base=48, slope=0.01, side_a=60, side_b=60,
              tree_rows=[44], tree_spacing=(26, 40), tree_jitter=6.0, clusters=4, cluster_off=(30, 60),
              cluster_count=(2, 4), hills=14, hill_off=(30, 90), hill_rad=(45, 90), hill_h=(10, 26), dunes=18,
              undulation=1.2)

MESA = [
    dict(DESERT, id="hole_27", name="Dry Wash", par=4, yards=140, seed=127, fw_width=26,
         ctrl=[(0, 0), (0, 70), (12, 130), (30, 190)],
         bunkers=[(0.35, 24, 9, 20, 0.45), (0.62, -23, 9, 18, 0.45), (front(140, 20), -11, 5, 3.6, 0.8), (front(140, 20), 11, 5, 3.6, 0.8)],
         mounds=[(0.5, -34, 26, 2.4)], wind=(4.5, 260), green=(14, 12), pin_offset=(1.0, 2.0)),
    dict(DESERT, id="hole_28", name="Red Rock", par=3, yards=68, seed=128, fw_width=24,
         ctrl=[(0, 0), (0, 40), (2, 80), (0, 100)], side_a=46, side_b=46,
         bunkers=[(front(68, 17), -12, 5, 4, 0.8), (front(68, 17), 12, 5, 4, 0.8), (back(68, 21), 0, 8, 3.0, 0.6)],
         mounds=[(1.0, 0, 46, -2.0)], wind=(5.0, 200), green=(13, 11), pin_offset=(0.5, 1.5)),
    dict(DESERT, id="hole_29", name="Long Mesa", par=5, yards=285, seed=129, fw_width=26, slope=-0.03,
         ctrl=[(0, 0), (0, 100), (-30, 195), (-45, 295), (-10, 385), (30, 450)],
         bunkers=[(0.3, -24, 10, 22, 0.45), (0.55, 24, 10, 20, 0.45), (0.78, -23, 9, 16, 0.45), (front(285, 22), -12, 5, 4, 0.8), (front(285, 22), 12, 5, 4, 0.8)],
         mounds=[(0.45, 34, 26, 2.8)], wind=(5.5, 120), green=(15, 12), pin_offset=(1.0, 3.0)),
    dict(DESERT, id="hole_30", name="Sidewinder", par=4, yards=190, seed=130, fw_width=26, slope=0.02,
         ctrl=[(0, 0), (0, 80), (30, 160), (-10, 240), (-40, 310), (-20, 360)],
         bunkers=[(0.3, -22, 9, 18, 0.45), (0.52, 22, 9, 18, 0.45), (0.8, -22, 9, 14, 0.45), (front(190, 21), -11, 5, 3.8, 0.8), (front(190, 21), 11, 5, 3.8, 0.8)],
         wind=(6.0, 300), green=(14, 12), pin_offset=(-1.0, 2.5)),
    dict(DESERT, id="hole_31", name="Oasis", par=3, yards=88, seed=131, fw_width=24,
         ctrl=[(0, 0), (0, 50), (4, 100), (6, 150)], side_a=46, side_b=46,
         water=[dict(f=0.6, t=-6, radii=[16, 12], across=True)],
         bunkers=[(front(88, 17), -13, 5, 4, 0.8), (front(88, 17), 14, 5, 4, 0.8), (back(88, 21), 0, 8, 3.0, 0.6)],
         wind=(3.5, 40), green=(14, 12), pin_offset=(0.5, 2.0)),
    dict(DESERT, id="hole_32", name="Canyon Home", par=5, yards=230, seed=132, fw_width=26, slope=0.04,
         ctrl=[(0, 0), (0, 90), (35, 170), (60, 250), (40, 330), (0, 380)],
         bunkers=[(0.35, 24, 10, 20, 0.45), (0.6, -23, 10, 18, 0.45), (front(230, 22), -12, 5, 4, 0.8), (front(230, 22), 12, 5, 4, 0.8), (1.12, 0, 8, 3.0, 0.6)],
         mounds=[(0.7, -34, 26, 2.4)], wind=(5.0, 80), green=(15, 12), pin_offset=(-1.0, 2.5)),
]

COURSES = [
    {"id": JIZZY_ID, "name": JIZZY_NAME, "blurb": "9 rolling pine and azalea holes, creeks, big greens",
     "holes": [h["id"] for h in JIZZY]},
    {"id": MESA_ID, "name": MESA_NAME, "blurb": "6 desert holes, waste bunkers, steady wind",
     "holes": [h["id"] for h in MESA]},
]


def register(root):
    """Adds the courses to data/courses.json (text insert before "full9", keeps the file's formatting)."""
    path = os.path.join(root, "data", "courses.json")
    text = open(path).read()
    data = json.loads(text)
    have = {c["id"] for c in data["courses"]}
    for c in COURSES:
        holes = ", ".join(json.dumps(h) for h in c["holes"])
        entry = ('    {\n      "id": %s,\n      "name": %s,\n      "blurb": %s,\n      "holes": [%s]\n    },\n'
                 % (json.dumps(c["id"]), json.dumps(c["name"]), json.dumps(c["blurb"]), holes))
        if c["id"] in have:
            # replace the existing entry in place (rename / re-run)
            pat = re.compile(r'    \{\n      "id": "%s",.*?\n    \},?\n' % re.escape(c["id"]), re.S)
            text = pat.sub(lambda m: entry, text, count=1)
        else:
            marker = '    {\n      "id": "full9"'
            text = text.replace(marker, entry + marker, 1)
    json.loads(text)
    open(path, "w").write(text)


if __name__ == "__main__":
    root = os.path.join(HERE, "..", "..")
    for spec in JIZZY + MESA:
        d = tee_pin_options.augment(G.build(spec))
        with open(os.path.join(root, "data", "holes", spec["id"] + ".json"), "w") as f:
            json.dump(d, f, indent=1)
        print(d["id"], d["name"], "par", d["par"], d["yards"], "yd, green overlap pts", tee_pin_options.bunker_green_overlap(d),
              "tees", {k: v["yards"] for k, v in d["tee_options"].items()}, "pins", [o["name"] for o in d["pin_options"]])
    register(root)

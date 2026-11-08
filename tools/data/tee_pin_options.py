#!/usr/bin/env python3
"""Adds `tee_options` (blue / yellow / red) and `pin_options` (3-4 greens positions) to hole JSON.

  python3 tools/data/tee_pin_options.py            # every data/holes/hole_*.json (idempotent)

Also imported by gen_forest_holes.py / gen_new_courses.py so regenerated holes keep their options.

tee_options: yellow = the hole's existing tee (default, the nominal `yards`), blue = back tee 12-18 % longer
(behind the yellow tee on the extension of the first fairway segment), red = forward tee 12-18 % shorter
(along the centreline). Each non-yellow tee gets its own small tee box in `tee_boxes` so the lie there is TEE.
pin_options: [{name, pos}]; index 0 is "middle" = the hole's fixed `pin`. Others lie on the green at least
PIN_EDGE_M inside its edge and clear of bunkers / water. The game picks one per hole from the round seed.
"""
import glob, json, math, os, re

YD = 0.9144
PIN_EDGE_M = 3.0      # >= 2 m from the green edge required by the owner; 3 m used for margin
HAZARD_CLEAR_M = 3.0  # pins keep this far from bunkers and water
TEE_BOX = [7, 7]


def r1(v):
    return round(v, 1)


def ell_signed_dist(e, x, z):
    """Mirror of HoleDefinition.Ellipse.signed_dist (negative inside)."""
    cx, cz = e["center"]
    a = max(0.5, e["radii"][0])
    b = max(0.5, e["radii"][1])
    rot = math.radians(e.get("rot_deg", 0.0))
    c, s = math.cos(rot), math.sin(rot)
    dx, dz = x - cx, z - cz
    lx = dx * c - dz * s
    lz = dx * s + dz * c
    r = math.sqrt((lx / a) ** 2 + (lz / b) ** 2)
    if r < 1e-6:
        return -min(a, b)
    return math.hypot(dx, dz) * (1.0 - 1.0 / r)


def _unit(v):
    n = math.hypot(*v)
    return (v[0] / n, v[1] / n)


def _num(hole_id):
    m = re.search(r"(\d+)", hole_id)
    return int(m.group(1)) if m else 0


def tee_pcts(hole_id):
    """Deterministic 12-18 % blue/red offsets, varied by hole number."""
    n = _num(hole_id)
    blue = 0.12 + 0.06 * ((n * 5) % 7) / 6.0
    red = 0.12 + 0.06 * ((n * 3 + 2) % 7) / 6.0
    return blue, red


def tee_options(d):
    yards = float(d["yards"])
    pts = [tuple(p) for p in d["fairway"][0]["points"]]
    tee = tuple(d["tee"])
    line = [tee] + [p for p in pts if math.dist(p, tee) > 0.5]
    d0 = _unit((line[1][0] - line[0][0], line[1][1] - line[0][1]))
    pb, pr = tee_pcts(d["id"])
    blue_pos = (tee[0] - d0[0] * pb * yards * YD, tee[1] - d0[1] * pb * yards * YD)
    # red: walk the centreline
    want = pr * yards * YD
    acc = 0.0
    red_pos, red_dir = line[-1], d0
    for a, b in zip(line, line[1:]):
        seg = math.dist(a, b)
        if acc + seg >= want:
            u = (want - acc) / seg
            red_pos = (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u)
            red_dir = _unit((b[0] - a[0], b[1] - a[1]))
            break
        acc += seg
    opts = {
        "blue": {"pos": [r1(blue_pos[0]), r1(blue_pos[1])], "yards": int(round(yards * (1 + pb)))},
        "yellow": {"pos": [tee[0], tee[1]], "yards": int(round(yards))},
        "red": {"pos": [r1(red_pos[0]), r1(red_pos[1])], "yards": int(round(yards * (1 - pr)))},
    }
    boxes = [b for b in d["tee_boxes"] if not b.get("option")]
    boxes.append({"center": opts["blue"]["pos"], "size": TEE_BOX, "rot_deg": r1(math.degrees(math.atan2(d0[0], d0[1]))), "option": "blue"})
    boxes.append({"center": opts["red"]["pos"], "size": TEE_BOX, "rot_deg": r1(math.degrees(math.atan2(red_dir[0], red_dir[1]))), "option": "red"})
    return opts, boxes


def pin_options(d):
    g = d["greens"][0]
    c = tuple(g["center"])
    pts = [tuple(p) for p in d["fairway"][0]["points"]]
    approach = _unit((pts[-1][0] - pts[-2][0], pts[-1][1] - pts[-2][1]))
    perp = (-approach[1], approach[0])
    default = tuple(d["pin"])
    hazards = list(d.get("bunkers", [])) + list(d.get("water", []))
    side_sign = 1 if _num(d["id"]) % 2 == 0 else -1
    cands = [("front", (-approach[0], -approach[1])), ("back", approach),
             ("left" if side_sign > 0 else "right", (perp[0] * side_sign, perp[1] * side_sign))]
    # a fourth, diagonal option
    diag = _unit((approach[0] * 0.6 - perp[0] * side_sign * 0.8, approach[1] * 0.6 - perp[1] * side_sign * 0.8))
    out = [{"name": "middle", "pos": [default[0], default[1]]}]
    for name, u in cands + [("back-" + ("right" if side_sign > 0 else "left"), diag)]:
        tmax = 0.0
        t = 0.0
        while t < 40.0:
            if ell_signed_dist(g, c[0] + u[0] * t, c[1] + u[1] * t) > -PIN_EDGE_M:
                break
            tmax = t
            t += 0.25
        t = tmax
        pos = None
        while t > 0.3 * tmax:
            p = (c[0] + u[0] * t, c[1] + u[1] * t)
            if all(ell_signed_dist(h, *p) > HAZARD_CLEAR_M for h in hazards) and math.dist(p, default) >= 3.0 \
                    and all(math.dist(p, tuple(o["pos"])) >= 3.0 for o in out):
                pos = p
                break
            t -= 0.5
        if pos is not None:
            out.append({"name": name, "pos": [r1(pos[0]), r1(pos[1])]})
        if len(out) >= 4:
            break
    return out


def augment(d):
    d["tee_options"], d["tee_boxes"] = tee_options(d)
    d["pin_options"] = pin_options(d)
    if len(d["pin_options"]) < 3:
        raise SystemExit("%s: fewer than 3 pin options" % d["id"])
    return d


def bunker_green_overlap(d):
    """Sample points of the green; returns how many lie inside a bunker or water (should be 0)."""
    g = d["greens"][0]
    cx, cz = g["center"]
    bad = 0
    for i in range(-20, 21):
        for j in range(-20, 21):
            x, z = cx + i, cz + j
            if ell_signed_dist(g, x, z) <= 0 and any(ell_signed_dist(h, x, z) <= 0 for h in list(d.get("bunkers", [])) + list(d.get("water", []))):
                bad += 1
    return bad


if __name__ == "__main__":
    root = os.path.join(os.path.dirname(__file__), "..", "..", "data", "holes")
    for path in sorted(glob.glob(os.path.join(root, "hole_*.json"))):
        d = json.load(open(path))
        augment(d)
        with open(path, "w") as f:
            json.dump(d, f, indent=1)
        print(d["id"], {k: v["yards"] for k, v in d["tee_options"].items()}, [o["name"] for o in d["pin_options"]],
              "green overlap pts", bunker_green_overlap(d))

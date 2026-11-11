class_name Grandstands
extends RefCounted
## Grandstands beside the green: placement AND solid shape. Shared by physics (BallSim), relief
## (HoleDefinition.is_safe_spot) and rendering (CourseDressing), so what you see is what the ball hits on
## every graphics quality and on every phone (deterministic, analytic terrain only, no render data).
##
## A stand is a stepped block: front hoarding, ROWS rising decks away from the green, a back wall.
## Local frame of a stand: u = along the stand, w = away from the green (w = -STAND_D/2 is the front).

const STAND_W := 15.0
const STAND_D := 6.0
const ROWS := 5
const ROW_RISE := 0.55
## Solid outline (local), including the hoarding in front and the side/back walls.
const FRONT_W := -STAND_D * 0.5 - 0.25
const BACK_W := STAND_D * 0.5 + 0.2
const HALF_U := STAND_W * 0.5 + 0.3
## Ball response: concrete/seats are hard and dead-ish.
const RESTITUTION := 0.35
const RETENTION := 0.6
## A ball that settles on the seats is nudged down the steps towards the green (it never rests up there).
const NUDGE_SPEED := 1.6
const NUDGE_UP := 1.2


## Plans up to two stands near the green the pin is on. Each: {xf: Transform2D (x = along, y = towards the
## green, origin = centre), base: lowest ground, top: highest ground, front_y, back_top, floor_y}.
static func plan(hole: HoleDefinition) -> Array:
	var out: Array = []
	if not hole.has_cup or hole.greens.is_empty():
		return out
	var g := target_green(hole)
	if g == null:
		return out
	var gc := Vector2(g.cx, g.cz)
	var play := (gc - hole.tee).normalized()
	if play == Vector2.ZERO:
		play = Vector2(0, 1)
	var rad := maxf(g.a, g.b)
	var used_angles: Array = []
	for ang_deg in [0.0, 35.0, -35.0, 70.0, -70.0, 105.0, -105.0, 140.0, -140.0]:
		if out.size() >= 2:
			break
		var ang := deg_to_rad(ang_deg)
		var clash := false
		for u in used_angles:
			if absf(ang - float(u)) < deg_to_rad(65.0):
				clash = true
		if clash:
			continue
		for extra in [14.0, 20.0, 27.0]:
			var c: Vector2 = gc + play.rotated(ang) * (rad + float(extra))
			var f: Vector2 = (gc - c).normalized()
			var xf := Transform2D(Vector2(f.y, -f.x), f, c)
			var fit := _fits(hole, xf)
			if fit.is_empty():
				continue
			var front_y: float = float(fit["max"]) + 0.25
			out.append({
				"xf": xf, "inv": xf.affine_inverse(), "base": fit["min"], "top": fit["max"],
				"floor_y": float(fit["min"]) - 0.6, "front_y": front_y,
				"back_top": front_y + ROWS * ROW_RISE + 1.6,
			})
			used_angles.append(ang)
			break
	return out


static func target_green(hole: HoleDefinition) -> HoleDefinition.Ellipse:
	var best: HoleDefinition.Ellipse = null
	var bd := INF
	for g in hole.greens:
		var e: HoleDefinition.Ellipse = g
		var d := Vector2(e.cx, e.cz).distance_to(hole.pin)
		if d < bd:
			bd = d
			best = e
	return best


## Footprint test: rough/OOB only, inside the rendered terrain, clear of trees, not too steep.
static func _fits(hole: HoleDefinition, xf: Transform2D) -> Dictionary:
	var lo := INF
	var hi := -INF
	var inner := hole.bounds.grow(-4.0)
	for ix in 7:
		for iz in 4:
			var l := Vector2(lerpf(-STAND_W * 0.5 - 1.5, STAND_W * 0.5 + 1.5, ix / 6.0), lerpf(-STAND_D * 0.5 - 1.5, STAND_D * 0.5 + 2.5, iz / 3.0))
			var w := xf * l
			if not inner.has_point(w):
				return {}
			var s := hole.surface_at(w.x, w.y)
			if s != Surface.Type.ROUGH and s != Surface.Type.OOB:
				return {}
			for ti in hole.trees_near(w.x, w.y):
				var t: Dictionary = hole.trees[ti]
				if Vector2(t["x"], t["z"]).distance_to(w) < float(t["canopy_r"]) + 1.5:
					return {}
			var h := hole.terrain_height(w.x, w.y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	if hi - lo > 2.2:
		return {}
	return {"min": lo, "max": hi}


## Top of the solid at local depth w (front hoarding, stepped decks, back wall).
static func top_at(st: Dictionary, w: float) -> float:
	var front_y: float = st["front_y"]
	if w < -STAND_D * 0.5:
		return front_y - 0.15
	if w > STAND_D * 0.5:
		return st["back_top"]
	var r := clampi(floori((w + STAND_D * 0.5) / (STAND_D / ROWS)), 0, ROWS - 1)
	return front_y + r * ROW_RISE + 0.27  # deck + bench


## Is (x, z) on or within `margin` metres of a stand's footprint.
static func covers(stands: Array, x: float, z: float, margin: float) -> bool:
	for st in stands:
		var l: Vector2 = (st["inv"] as Transform2D) * Vector2(x, z)
		if absf(l.x) <= HALF_U + margin and l.y >= FRONT_W - margin and l.y <= BACK_W + margin:
			return true
	return false


## Ball (centre p, previous centre p0, velocity v, radius r) against every stand. Returns [p, v, hit_kind]
## with hit_kind "" (no contact), "stand_top" or "stand_side".
static func collide(stands: Array, p0: Vector3, p: Vector3, v: Vector3, r: float) -> Array:
	for st in stands:
		var inv: Transform2D = st["inv"]
		var l := inv * Vector2(p.x, p.z)
		if absf(l.x) > HALF_U + r or l.y < FRONT_W - r or l.y > BACK_W + r:
			continue
		if p.y - r < float(st["floor_y"]):
			continue
		var lw := clampf(l.y, FRONT_W, BACK_W)
		var top := top_at(st, lw)
		if p.y - r >= top:
			continue
		var xf: Transform2D = st["xf"]
		var l0 := inv * Vector2(p0.x, p0.z)
		var top0 := top_at(st, clampf(l0.y, FRONT_W, BACK_W))
		var inside0 := absf(l0.x) <= HALF_U + r and l0.y >= FRONT_W - r and l0.y <= BACK_W + r
		if not inside0 or p0.y - r < top0 - 0.05:
			# came in through a side: push out through the nearest face, reflect that component
			var pens := [HALF_U + r - l.x, HALF_U + r + l.x, BACK_W + r - l.y, l.y - (FRONT_W - r)]
			var k := 0
			for i in 4:
				if pens[i] < pens[k]:
					k = i
			var nl := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)][k] as Vector2
			var lo := l + nl * (float(pens[k]) + 0.001)
			var wp := xf * lo
			var nw := (xf.basis_xform(nl)).normalized()
			var n3 := Vector3(nw.x, 0.0, nw.y)
			var vn := v.dot(n3)
			if vn < 0.0:
				v = v - n3 * (vn * (1.0 + RESTITUTION))
				v *= 0.8
			return [Vector3(wp.x, p.y, wp.y), v, "stand_side"]
		if top - (p0.y - r) > 0.15:
			# ran into the next step up (riser or back wall): bounce back towards the green
			var nf := xf.y.normalized()
			var n3 := Vector3(nf.x, 0.0, nf.y)
			var vn := v.dot(n3)
			if vn < 0.0:
				v = v - n3 * (vn * (1.0 + RESTITUTION))
				v *= 0.8
			return [Vector3(p0.x, p.y, p0.z), v, "stand_side"]
		# came down onto the seats / hoarding / wall top
		p.y = top + r
		var vh := Vector3(v.x, 0.0, v.z) * RETENTION
		var vy := -v.y * RESTITUTION if v.y < 0.0 else v.y
		if vy < NUDGE_UP:
			var f := xf.y.normalized()  # towards the green: down the steps
			vh = Vector3(f.x, 0.0, f.y) * NUDGE_SPEED
			vy = NUDGE_UP
		return [p, vh + Vector3(0.0, vy, 0.0), "stand_top"]
	return [p, v, ""]

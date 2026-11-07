class_name HoleDefinition
extends RefCounted
## Static, game-state-independent description of one hole, loaded from JSON
## (res://data/holes/*.json). Provides the authoritative analytic terrain and surface
## metadata used by BOTH the physics simulation and the terrain mesh builder, so that
## visual regions and physics lies always come from the same data.

class Ellipse:
	var cx := 0.0
	var cz := 0.0
	var a := 1.0
	var b := 1.0
	var c := 1.0
	var s := 0.0
	var data: Dictionary = {}
	var aabb := Rect2()

	func _init(d: Dictionary, margin: float) -> void:
		var center: Array = d.get("center", [0.0, 0.0])
		cx = float(center[0])
		cz = float(center[1])
		var radii: Array = d.get("radii", [1.0, 1.0])
		a = maxf(0.5, float(radii[0]))
		b = maxf(0.5, float(radii[1]))
		var rot := deg_to_rad(float(d.get("rot_deg", 0.0)))
		c = cos(rot)
		s = sin(rot)
		data = d
		var m := maxf(a, b) + margin
		aabb = Rect2(cx - m, cz - m, 2.0 * m, 2.0 * m)

	func norm_r(x: float, z: float) -> float:
		var dx := x - cx
		var dz := z - cz
		var lx := dx * c - dz * s
		var lz := dx * s + dz * c
		return sqrt((lx / a) * (lx / a) + (lz / b) * (lz / b))

	## Approximate signed distance in metres (negative inside), measured radially.
	func signed_dist(x: float, z: float) -> float:
		var r := norm_r(x, z)
		if r < 1e-6:
			return -minf(a, b)
		var dx := x - cx
		var dz := z - cz
		var dist := sqrt(dx * dx + dz * dz)
		return dist * (1.0 - 1.0 / r)

	func contains(x: float, z: float) -> bool:
		return norm_r(x, z) <= 1.0

	func point_at(angle: float) -> Vector2:
		var lx := a * cos(angle)
		var lz := b * sin(angle)
		# inverse rotation of norm_r's local frame
		return Vector2(cx + lx * c + lz * s, cz - lx * s + lz * c)


class Box:
	var cx := 0.0
	var cz := 0.0
	var hw := 1.0
	var hl := 1.0
	var c := 1.0
	var s := 0.0
	var height := 0.0
	var aabb := Rect2()

	func _init(d: Dictionary) -> void:
		var center: Array = d.get("center", [0.0, 0.0])
		cx = float(center[0])
		cz = float(center[1])
		var size: Array = d.get("size", [6.0, 8.0])
		hw = float(size[0]) * 0.5
		hl = float(size[1]) * 0.5
		var rot := deg_to_rad(float(d.get("rot_deg", 0.0)))
		c = cos(rot)
		s = sin(rot)
		var m := maxf(hw, hl) * 1.5 + 2.0
		aabb = Rect2(cx - m, cz - m, 2.0 * m, 2.0 * m)

	func signed_dist(x: float, z: float) -> float:
		var dx := x - cx
		var dz := z - cz
		var lx := absf(dx * c - dz * s)
		var lz := absf(dx * s + dz * c)
		return maxf(lx - hw, lz - hl)


const TEE_BLEND := 4.0
const GREEN_BLEND := 8.0
const FRINGE_WIDTH := 1.6
const BUNKER_INNER := 2.0
const BUNKER_LIP := 0.8
const WATER_INNER := 3.0
const WATER_OUTER := 1.0
const TREE_CELL := 16.0

var id := ""
var display_name := ""
var par := 3
var yards := 0.0
var tee := Vector2.ZERO
var pin := Vector2(0, 100)
var has_cup := true
var flat_surface := -1
## Surface outside all features (rough on real holes).
var default_surface: int = Surface.Type.ROUGH
var base_height := 0.0
var plane_a := 0.0
var plane_b := 0.0
var bumps: Array = []           # [{x,z,sigma,h,aabb}]
var tee_boxes: Array = []       # [Box]
var greens: Array = []          # [Ellipse] (+ data base/tilt)
var green_base: Array = []      # float per green
var green_tilt: Array = []      # Vector2 per green
var bunkers: Array = []         # [Ellipse]
var bunker_depth: Array = []
var waters: Array = []          # [Ellipse]
var water_level: Array = []
var fairway: Array = []         # [{p0:Vector2,p1:Vector2,hw:float}]
var fairway_aabb := Rect2()
## Out-of-bounds line: the rectangle `play_area` (rendered terrain `bounds` inset by `oob_inset`), so the
## whole visible course is in play and only the far map edge is OOB ("Make all visible course playable",
## docs/DECISIONS.md). Kept as a closed polygon for presentation (edge stakes). Legacy per-hole
## "boundary" polygons in JSON are ignored.
var boundary := PackedVector2Array()
var bounds := Rect2(-100, -50, 200, 300)
const OOB_INSET_M := 25.0
var oob_inset := OOB_INSET_M
var play_area := Rect2(-75, -25, 150, 250)
var trees: Array = []           # [{x,z,base_y,trunk_r,trunk_h,canopy_y,canopy_r,canopy_ry,kind}]
var _tree_grid: Dictionary = {}
var _spacing_grid: Dictionary = {}  # 4.5 m cells -> tree indices (placement spacing check)
var conifer_ratio := 0.5
var wind_speed := 0.0
var wind_bearing := 0.0
var relief_points: Array = []   # [Vector2]
var camera: Dictionary = {}
var source_path := ""


static func load_from_file(path: String) -> HoleDefinition:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("HoleDefinition: cannot open %s" % path)
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("HoleDefinition: invalid JSON in %s" % path)
		return null
	var h := HoleDefinition.new()
	h.source_path = path
	h._parse(parsed)
	return h


## A flat, unbounded, obstacle-free neutral reference plane at height 0.
static func make_flat(surface_type: int) -> HoleDefinition:
	var h := HoleDefinition.new()
	h.id = "flat_reference"
	h.display_name = "Neutral reference plane"
	h.flat_surface = surface_type
	h.has_cup = false
	h.pin = Vector2(1.0e6, 1.0e6)
	h.bounds = Rect2(-1000, -1000, 2000, 2000)
	h._set_play_area()
	return h


func _set_play_area() -> void:
	play_area = bounds.grow(-oob_inset)
	var r := play_area
	boundary = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


static func _v2(a) -> Vector2:
	if typeof(a) == TYPE_ARRAY and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


func _parse(d: Dictionary) -> void:
	id = String(d.get("id", "hole"))
	display_name = String(d.get("name", id))
	par = int(d.get("par", 3))
	yards = float(d.get("yards", 0.0))
	tee = _v2(d.get("tee", [0, 0]))
	pin = _v2(d.get("pin", [0, 100]))
	var t: Dictionary = d.get("terrain", {})
	base_height = float(t.get("base", 0.0))
	var plane: Array = t.get("plane", [0.0, 0.0])
	plane_a = float(plane[0])
	plane_b = float(plane[1])
	for bd in t.get("bumps", []):
		var bc := _v2(bd.get("center", [0, 0]))
		var sigma := float(bd.get("radius", 10.0)) * 0.5
		var ext := sigma * 4.6  # Gaussian tail < 3e-5 of height at the cutoff (no visible step)
		bumps.append({"x": bc.x, "z": bc.y, "sigma2": 2.0 * sigma * sigma, "h": float(bd.get("height", 0.0)),
			"aabb": Rect2(bc.x - ext, bc.y - ext, 2.0 * ext, 2.0 * ext)})
	for td in d.get("tee_boxes", []):
		tee_boxes.append(Box.new(td))
	for fd in d.get("fairway", []):
		var pts: Array = fd.get("points", [])
		var hw := float(fd.get("width", 30.0)) * 0.5
		for i in range(pts.size() - 1):
			var p0 := _v2(pts[i])
			var p1 := _v2(pts[i + 1])
			fairway.append({"p0": p0, "p1": p1, "hw": hw})
			var r := Rect2(p0, Vector2.ZERO).expand(p1).grow(hw + 1.0)
			fairway_aabb = r if fairway_aabb.size == Vector2.ZERO else fairway_aabb.merge(r)
	for gd in d.get("greens", []):
		greens.append(Ellipse.new(gd, GREEN_BLEND + 1.0))
		green_tilt.append(_v2(gd.get("tilt", [0, 0])))
	for bd2 in d.get("bunkers", []):
		bunkers.append(Ellipse.new(bd2, BUNKER_LIP + 0.5))
		bunker_depth.append(float(bd2.get("depth", 0.6)))
	for wd in d.get("water", []):
		waters.append(Ellipse.new(wd, WATER_OUTER + 0.5))
	var bb: Array = d.get("bounds", [])
	if bb.size() == 4:
		bounds = Rect2(float(bb[0]), float(bb[1]), float(bb[2]) - float(bb[0]), float(bb[3]) - float(bb[1]))
	oob_inset = clampf(float(d.get("oob_inset", OOB_INSET_M)), 0.0, minf(bounds.size.x, bounds.size.y) * 0.25)
	_set_play_area()
	conifer_ratio = clampf(float((d.get("theme", {}) as Dictionary).get("conifer", 0.5)), 0.0, 1.0)
	var w: Dictionary = d.get("wind", {})
	wind_speed = float(w.get("speed", 0.0))
	wind_bearing = float(w.get("bearing", 0.0))
	for rp in d.get("relief_points", []):
		relief_points.append(_v2(rp))
	camera = d.get("camera", {})
	_precompute_heights()
	_build_trees(d)


func _precompute_heights() -> void:
	for tb in tee_boxes:
		(tb as Box).height = raw_height((tb as Box).cx, (tb as Box).cz) + 0.15
	for i in greens.size():
		var g: Ellipse = greens[i]
		green_base.append(raw_height(g.cx, g.cz))
	for i in bunkers.size():
		pass
	# Water level sits just below the lowest shore point so that the water plane never floats.
	for i in waters.size():
		var wt: Ellipse = waters[i]
		var lowest := INF
		for k in 32:
			var p := wt.point_at(TAU * float(k) / 32.0)
			lowest = minf(lowest, _height_before_water(p.x, p.y))
		water_level.append(lowest - 0.15)


func raw_height(x: float, z: float) -> float:
	var h := base_height + plane_a * x + plane_b * z
	var pt := Vector2(x, z)
	for b in bumps:
		if (b["aabb"] as Rect2).has_point(pt):
			var dx: float = x - float(b["x"])
			var dz: float = z - float(b["z"])
			h += float(b["h"]) * exp(-(dx * dx + dz * dz) / float(b["sigma2"]))
	return h


func _height_before_water(x: float, z: float) -> float:
	var h := raw_height(x, z)
	var pt := Vector2(x, z)
	for tb in tee_boxes:
		var box: Box = tb
		if box.aabb.has_point(pt):
			var sd := box.signed_dist(x, z)
			if sd < TEE_BLEND:
				h = lerpf(h, box.height, 1.0 - smoothstep(0.0, TEE_BLEND, sd))
	for i in greens.size():
		var g: Ellipse = greens[i]
		if g.aabb.has_point(pt):
			var sd := g.signed_dist(x, z)
			if sd < GREEN_BLEND:
				var tilt: Vector2 = green_tilt[i]
				var target: float = float(green_base[i]) + tilt.x * (x - g.cx) + tilt.y * (z - g.cz) \
					+ 0.06 * sin(x * 0.31 + 1.3) * cos(z * 0.23 + 0.4)
				h = lerpf(h, target, 1.0 - smoothstep(0.0, GREEN_BLEND, sd))
	for i in bunkers.size():
		var bk: Ellipse = bunkers[i]
		if bk.aabb.has_point(pt):
			var sd := bk.signed_dist(x, z)
			if sd < BUNKER_LIP:
				h -= float(bunker_depth[i]) * (1.0 - smoothstep(-BUNKER_INNER, BUNKER_LIP, sd))
	return h


## Authoritative terrain height (ball contact surface, excluding water plane).
func terrain_height(x: float, z: float) -> float:
	if flat_surface >= 0:
		return 0.0
	var h := _height_before_water(x, z)
	if waters.is_empty():
		return h
	var pt := Vector2(x, z)
	for i in waters.size():
		var wt: Ellipse = waters[i]
		if wt.aabb.has_point(pt):
			var sd := wt.signed_dist(x, z)
			if sd < WATER_OUTER:
				var w := 1.0 - smoothstep(-WATER_INNER, WATER_OUTER, sd)
				h = lerpf(h, float(water_level[i]) - 0.9, w)
	return h


## Contact height for the ball: terrain, or the water surface where it covers terrain.
func contact_height(x: float, z: float) -> float:
	var h := terrain_height(x, z)
	for i in waters.size():
		var wt: Ellipse = waters[i]
		if wt.aabb.has_point(Vector2(x, z)) and wt.contains(x, z):
			h = maxf(h, float(water_level[i]))
	return h


func normal_at(x: float, z: float) -> Vector3:
	if flat_surface >= 0:
		return Vector3.UP
	var e := 0.15
	var hx := terrain_height(x + e, z) - terrain_height(x - e, z)
	var hz := terrain_height(x, z + e) - terrain_height(x, z - e)
	return Vector3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)).normalized()


## Everything inside the play area (the visible terrain minus the outer `oob_inset` band) is in play.
func in_bounds(x: float, z: float) -> bool:
	return x >= play_area.position.x and x <= play_area.end.x and z >= play_area.position.y and z <= play_area.end.y


func fairway_distance(x: float, z: float) -> float:
	var best := INF
	var p := Vector2(x, z)
	for seg in fairway:
		var p0: Vector2 = seg["p0"]
		var p1: Vector2 = seg["p1"]
		var q := Geometry2D.get_closest_point_to_segment(p, p0, p1)
		best = minf(best, p.distance_to(q) - float(seg["hw"]))
	return best


## Lie classification at a horizontal point. Priority: OOB > water > bunker > green > fringe > tee > fairway > rough.
func surface_at(x: float, z: float) -> int:
	if flat_surface >= 0:
		return flat_surface
	if not in_bounds(x, z):
		return Surface.Type.OOB
	var pt := Vector2(x, z)
	for wt in waters:
		if (wt as Ellipse).aabb.has_point(pt) and (wt as Ellipse).contains(x, z):
			return Surface.Type.WATER
	for bk in bunkers:
		if (bk as Ellipse).aabb.has_point(pt) and (bk as Ellipse).contains(x, z):
			return Surface.Type.BUNKER
	for g in greens:
		var ge: Ellipse = g
		if ge.aabb.has_point(pt):
			var sd := ge.signed_dist(x, z)
			if sd <= 0.0:
				return Surface.Type.GREEN
			if sd <= FRINGE_WIDTH:
				return Surface.Type.FRINGE
	for tb in tee_boxes:
		if (tb as Box).signed_dist(x, z) <= 0.0:
			return Surface.Type.TEE
	if fairway_aabb.has_point(pt) and fairway_distance(x, z) <= 0.0:
		return Surface.Type.FAIRWAY
	return default_surface


func tee_position(radius: float) -> Vector3:
	return Vector3(tee.x, terrain_height(tee.x, tee.y) + radius, tee.y)


func cup_position() -> Vector3:
	return Vector3(pin.x, terrain_height(pin.x, pin.y), pin.y)


# ---------------------------------------------------------------- trees

func _build_trees(d: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	for td in d.get("trees", []):
		_add_tree(_v2(td.get("pos", [0, 0])), float(td.get("height", 12.0)), rng, false)
	for line in d.get("tree_lines", []):
		rng.seed = int(line.get("seed", 1))
		var a := _v2(line.get("from", [0, 0]))
		var b := _v2(line.get("to", [0, 0]))
		var spacing := maxf(3.0, float(line.get("spacing", 10.0)))
		var jitter := float(line.get("jitter", 2.0))
		var n := int(a.distance_to(b) / spacing)
		for i in n + 1:
			var p := a.lerp(b, float(i) / maxf(1.0, float(n)))
			p += Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
			_add_tree(p, rng.randf_range(9.0, 16.0), rng, true)
	for cl in d.get("tree_clusters", []):
		rng.seed = int(cl.get("seed", 1))
		var c := _v2(cl.get("center", [0, 0]))
		var r := float(cl.get("radius", 20.0))
		for i in int(cl.get("count", 10)):
			var ang := rng.randf() * TAU
			var rad := sqrt(rng.randf()) * r
			_add_tree(c + Vector2(cos(ang), sin(ang)) * rad, rng.randf_range(9.0, 17.0), rng, true)
	for i in trees.size():
		var tr: Dictionary = trees[i]
		var key := Vector2i(floori(float(tr["x"]) / TREE_CELL), floori(float(tr["z"]) / TREE_CELL))
		if not _tree_grid.has(key):
			_tree_grid[key] = []
		(_tree_grid[key] as Array).append(i)


func _add_tree(p: Vector2, height: float, rng: RandomNumberGenerator, filter: bool) -> void:
	if filter:
		for off in [Vector2.ZERO, Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)]:
			var s := surface_at(p.x + off.x, p.y + off.y)
			if s != Surface.Type.ROUGH and s != Surface.Type.OOB:
				return
		var ck := Vector2i(floori(p.x / 4.5), floori(p.y / 4.5))
		for ix in range(ck.x - 1, ck.x + 2):
			for iz in range(ck.y - 1, ck.y + 2):
				for ti in _spacing_grid.get(Vector2i(ix, iz), []):
					var other: Dictionary = trees[ti]
					if Vector2(float(other["x"]), float(other["z"])).distance_to(p) < 4.5:
						return
		if p.distance_to(tee) < 12.0 or p.distance_to(pin) < 18.0:
			return
	var base_y := terrain_height(p.x, p.y)
	var canopy_r := height * rng.randf_range(0.24, 0.3)
	trees.append({
		"x": p.x, "z": p.y, "base_y": base_y,
		"trunk_r": rng.randf_range(0.22, 0.38),
		"trunk_h": height * 0.55,
		"canopy_y": base_y + height * 0.64,
		"canopy_r": canopy_r,
		"canopy_ry": canopy_r * 1.05,
		"height": height,
		"kind": 1 if (rng.randi() % 100) < int(conifer_ratio * 100.0) else 0,
	})
	var sk := Vector2i(floori(p.x / 4.5), floori(p.y / 4.5))
	if not _spacing_grid.has(sk):
		_spacing_grid[sk] = []
	(_spacing_grid[sk] as Array).append(trees.size() - 1)


## Indices of trees whose collision proxies could touch a ball at (x, z).
func trees_near(x: float, z: float) -> Array:
	if trees.is_empty():
		return []
	var cx := floori(x / TREE_CELL)
	var cz := floori(z / TREE_CELL)
	var out: Array = []
	for ix in range(cx - 1, cx + 2):
		for iz in range(cz - 1, cz + 2):
			var key := Vector2i(ix, iz)
			if _tree_grid.has(key):
				out.append_array(_tree_grid[key])
	return out


## Is (x,z) a safe resting place: in bounds, dry, clear of tree trunks, with a margin.
func is_safe_spot(x: float, z: float, margin: float) -> bool:
	var offsets := [Vector2.ZERO]
	for k in 8:
		offsets.append(Vector2(cos(TAU * k / 8.0), sin(TAU * k / 8.0)) * margin)
	for off in offsets:
		var s := surface_at(x + off.x, z + off.y)
		if s == Surface.Type.OOB or s == Surface.Type.WATER:
			return false
	for idx in trees_near(x, z):
		var tr: Dictionary = trees[idx]
		var dx := x - float(tr["x"])
		var dz := z - float(tr["z"])
		if sqrt(dx * dx + dz * dz) < float(tr["trunk_r"]) + 0.6:
			return false
	var h := terrain_height(x, z)
	return is_finite(h)


## Horizontal length of the nominal line of play (tee -> fairway spine -> pin), metres.
func nominal_length_m() -> float:
	return Units.yards_to_m(yards)

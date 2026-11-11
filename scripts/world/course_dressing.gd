class_name CourseDressing
extends RefCounted
## Visual-only course dressing (no physics, never read by gameplay):
##  - High graphics: up to two small grandstands near the green with seated spectators and
##    FICTIONAL sponsor boards on the front hoarding. Placed only on rough/out-of-bounds ground,
##    clear of trees, water, sand and the putting surface; their footprint is baked into the terrain
##    AO map (see TerrainBuilder.bake_ao) so they sit on the ground.
##  - Every quality: yardage plates (flush in the fairway centre line) and short marker posts at the
##    fairway edge, at 50 / 100 / 150 / 200 yd to the middle of the green.
## Deterministic per hole (seeded from the hole id).

## Fictional brands only (never real companies).
const SPONSORS := [
	["FERNBANK HARDWARE", Color(0.10, 0.30, 0.18), Color(0.96, 0.92, 0.70)],
	["GULLWING CAFE", Color(0.92, 0.92, 0.88), Color(0.12, 0.30, 0.55)],
	["TARN VALLEY DAIRY", Color(0.20, 0.45, 0.80), Color(1.0, 1.0, 1.0)],
	["NORTHSPIRE TELECOM", Color(0.12, 0.12, 0.16), Color(0.40, 0.90, 0.95)],
	["AURELIAN AIRWAYS", Color(0.55, 0.10, 0.14), Color(1.0, 0.86, 0.45)],
	["BRAMBLETON BAKES", Color(0.95, 0.80, 0.30), Color(0.30, 0.15, 0.08)],
	["QUILLFEATHER TEA", Color(0.24, 0.16, 0.36), Color(0.95, 0.95, 0.95)],
	["WRENHOLLOW WATER", Color(0.85, 0.95, 1.0), Color(0.05, 0.35, 0.60)],
]
const SHIRTS := [
	Color(0.85, 0.12, 0.12), Color(0.12, 0.30, 0.75), Color(0.95, 0.95, 0.95), Color(0.98, 0.80, 0.15),
	Color(0.15, 0.55, 0.25), Color(0.10, 0.10, 0.12), Color(0.55, 0.20, 0.55), Color(0.95, 0.50, 0.15),
	Color(0.45, 0.70, 0.90), Color(0.85, 0.85, 0.80),
]
## Yardage plates: yards -> colour (blue 200, white 150, red 100, yellow 50).
const YARDAGES := [[200, Color(0.15, 0.35, 0.85)], [150, Color(0.96, 0.96, 0.96)], [100, Color(0.85, 0.12, 0.10)], [50, Color(0.98, 0.82, 0.10)]]

const STAND_W := 15.0
const STAND_D := 6.0
const ROWS := 5
const ROW_RISE := 0.55

var hole: HoleDefinition
var terrain: TerrainBuilder
## Planned stands: [{xf: Transform2D (x = along the stand, y = towards the green), base: float, top: float}]
var stands: Array = []
## Footprints for TerrainBuilder.bake_ao.
var ao_blobs: Array = []


func _init(p_hole: HoleDefinition, p_terrain: TerrainBuilder = null) -> void:
	hole = p_hole
	terrain = p_terrain


func _h(x: float, z: float) -> float:
	return terrain.mesh_height_at(x, z) if terrain != null else hole.terrain_height(x, z)


static func target_green(p_hole: HoleDefinition) -> HoleDefinition.Ellipse:
	var best: HoleDefinition.Ellipse = null
	var bd := INF
	for g in p_hole.greens:
		var e: HoleDefinition.Ellipse = g
		var d := Vector2(e.cx, e.cz).distance_to(p_hole.pin)
		if d < bd:
			bd = d
			best = e
	return best


## Chooses grandstand spots (call once the terrain heights exist).
func plan() -> void:
	stands.clear()
	ao_blobs.clear()
	var g := target_green(hole)
	if g == null:
		return
	var gc := Vector2(g.cx, g.cz)
	var play := (gc - hole.tee).normalized()
	if play == Vector2.ZERO:
		play = Vector2(0, 1)
	var rad := maxf(g.a, g.b)
	var used_angles: Array = []
	for ang_deg in [0.0, 35.0, -35.0, 70.0, -70.0, 105.0, -105.0, 140.0, -140.0]:
		if stands.size() >= 2:
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
			var fit := _fits(xf)
			if fit.is_empty():
				continue
			stands.append({"xf": xf, "base": fit["min"], "top": fit["max"]})
			ao_blobs.append({"xf": xf, "half": Vector2(STAND_W * 0.5, STAND_D * 0.5), "amt": 0.38})
			used_angles.append(ang)
			break


## Footprint test: rough/OOB only, inside the rendered terrain, clear of trees, not too steep.
func _fits(xf: Transform2D) -> Dictionary:
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
			var h := _h(w.x, w.y)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	if hi - lo > 2.2:
		return {}
	return {"min": lo, "max": hi}


# ------------------------------------------------------------------ geometry helpers

class _Mesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var i := PackedInt32Array()

	## Axis-aligned (in `b`) box centred at `o` with half extents `he`.
	func box(o: Vector3, b: Basis, he: Vector3, col: Color, head: float = 0.0) -> void:
		var faces := [
			[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
			[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
			[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
		]
		for f in faces:
			var nn: Vector3 = f[0]
			var a: Vector3 = f[1]
			var bb: Vector3 = f[2]
			var shade := 1.0 if nn.y > 0.5 else (0.62 if nn.y < -0.5 else 0.85)
			var k := v.size()
			for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var lp: Vector3 = (nn + a * s.y + bb * s.x) * he
				v.append(o + b * lp)
				n.append((b * nn).normalized())
				c.append(Color(col.r * shade, col.g * shade, col.b * shade))
				uv.append(Vector2(0.0, head))
			i.append_array(PackedInt32Array([k, k + 2, k + 1, k, k + 3, k + 2]))

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_INDEX] = i
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static var _person: ArrayMesh


## Seated spectator, ~1.05 m tall, facing -Z (white body; head vertices have UV.y = 1).
static func person_mesh() -> ArrayMesh:
	if _person != null:
		return _person
	var m := _Mesh.new()
	m.box(Vector3(0, 0.36, 0), Basis(), Vector3(0.21, 0.30, 0.13), Color.WHITE)
	m.box(Vector3(0, 0.79, -0.01), Basis(), Vector3(0.10, 0.12, 0.10), Color.WHITE, 1.0)
	m.box(Vector3(0, 0.06, -0.18), Basis(), Vector3(0.19, 0.07, 0.16), Color(0.55, 0.55, 0.6))
	_person = m.commit()
	return _person


static func _vc_material(rough: float = 0.85) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = rough
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


# ------------------------------------------------------------------ build

func build(view: Node3D) -> void:
	if stands.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(hole.id + "stands")
	var m := _Mesh.new()
	var crowd_x: Array[Transform3D] = []
	var crowd_c: Array[Color] = []
	var sponsor_i := rng.randi() % SPONSORS.size()
	var seat_col: Color = [Color(0.16, 0.30, 0.55), Color(0.55, 0.12, 0.14), Color(0.18, 0.42, 0.26)][rng.randi() % 3]
	var frame := Color(0.32, 0.34, 0.36)
	var board_mesh := _Mesh.new()
	for st in stands:
		var xf: Transform2D = st["xf"]
		var base: float = st["base"]
		var top: float = st["top"]
		var f := Vector3(xf.y.x, 0, xf.y.y)  # towards the green
		var side := Vector3(xf.x.x, 0, xf.x.y)
		# local basis: x along the stand, z = -f (the stand's back), y up
		var b := Basis(-side, Vector3.UP, -f)
		var o := Vector3(xf.origin.x, 0, xf.origin.y)
		var floor_y := base - 0.6
		var front_y := top + 0.25  # first deck clears the highest ground under the stand
		var row_d := STAND_D / ROWS
		for r in ROWS:
			var deck_y := front_y + r * ROW_RISE
			var lz := -STAND_D * 0.5 + (r + 0.5) * row_d  # +z local = away from the green
			var center := o + b * Vector3(0, 0, lz)
			# riser block from the ground to the deck (reads as the stepped concrete tier)
			var hgt := deck_y - floor_y
			m.box(center + Vector3(0, floor_y + hgt * 0.5, 0), b, Vector3(STAND_W * 0.5, hgt * 0.5, row_d * 0.5), frame.lerp(Color(0.5, 0.5, 0.5), 0.3 * (r % 2)))
			# bench seats
			m.box(center + b * Vector3(0, 0, 0.12) + Vector3(0, deck_y + 0.22, 0), b, Vector3(STAND_W * 0.5 - 0.2, 0.05, 0.22), seat_col)
			m.box(center + b * Vector3(0, 0, 0.36) + Vector3(0, deck_y + 0.45, 0), b, Vector3(STAND_W * 0.5 - 0.2, 0.2, 0.03), seat_col * 0.85)
			# spectators along the bench, ~75 % full
			var n := int(STAND_W / 0.62)
			for k in n:
				if rng.randf() > 0.75:
					continue
				var lx := -STAND_W * 0.5 + 0.5 + k * ((STAND_W - 1.0) / float(n - 1)) + rng.randf_range(-0.08, 0.08)
				var p := o + b * Vector3(lx, 0, lz + 0.05) + Vector3(0, deck_y + 0.22, 0)
				var yaw := Basis(Vector3.UP, rng.randf_range(-0.25, 0.25))
				crowd_x.append(Transform3D(b * yaw * Basis.from_scale(Vector3.ONE * rng.randf_range(0.92, 1.08)), p))
				crowd_c.append((SHIRTS[rng.randi() % SHIRTS.size()] as Color) * rng.randf_range(0.85, 1.05))
		var back_top := front_y + ROWS * ROW_RISE + 1.6
		# side walls and back wall
		for sgn in [-1.0, 1.0]:
			var wc := o + b * Vector3(sgn * (STAND_W * 0.5 + 0.1), 0, 0)
			m.box(wc + Vector3(0, (floor_y + back_top) * 0.5, 0), b, Vector3(0.1, (back_top - floor_y) * 0.5, STAND_D * 0.5 + 0.1), frame * 0.9)
		var bc := o + b * Vector3(0, 0, STAND_D * 0.5 + 0.1)
		m.box(bc + Vector3(0, (floor_y + back_top) * 0.5, 0), b, Vector3(STAND_W * 0.5 + 0.2, (back_top - floor_y) * 0.5, 0.1), frame * 0.8)
		# roof: slab over the back half on two front posts
		var roof_y := back_top + 0.15
		m.box(o + b * Vector3(0, 0, STAND_D * 0.1) + Vector3(0, roof_y, 0), b, Vector3(STAND_W * 0.5 + 0.4, 0.08, STAND_D * 0.42), Color(0.86, 0.87, 0.88))
		for sgn in [-1.0, 1.0]:
			var pc := o + b * Vector3(sgn * (STAND_W * 0.5 - 0.1), 0, -STAND_D * 0.28)
			var ph := roof_y - (front_y + 1.2)
			m.box(pc + Vector3(0, front_y + 1.2 + ph * 0.5, 0), b, Vector3(0.06, ph * 0.5, 0.06), frame)
		# front hoarding with three sponsor boards
		var hz := -STAND_D * 0.5 - 0.15
		var hy := front_y - 0.15
		var hc := o + b * Vector3(0, 0, hz)
		m.box(hc + Vector3(0, (floor_y + hy) * 0.5, 0), b, Vector3(STAND_W * 0.5 + 0.2, (hy - floor_y) * 0.5, 0.08), frame * 0.7)
		var bw := STAND_W / 3.0
		for k in 3:
			var sp: Array = SPONSORS[(sponsor_i + k) % SPONSORS.size()]
			var bx := -STAND_W * 0.5 + bw * (k + 0.5)
			var bh := 0.85
			var by := hy - bh * 0.5 - 0.05
			var bcen := o + b * Vector3(bx, 0, hz - 0.1) + Vector3(0, by, 0)
			board_mesh.box(bcen, b, Vector3(bw * 0.5 - 0.06, bh * 0.5, 0.03), sp[1])
			var lbl := Label3D.new()
			lbl.text = sp[0]
			lbl.font_size = 64
			lbl.outline_size = 0
			lbl.modulate = sp[2]
			lbl.pixel_size = minf((bw - 0.5) / (float(String(sp[0]).length()) * 0.62 * 64.0), 0.55 / 64.0)
			lbl.double_sided = false
			lbl.shaded = false
			lbl.position = bcen + f * 0.045
			lbl.basis = Basis.looking_at(-f, Vector3.UP)
			lbl.name = "Board"
			view.add_child(lbl)
		sponsor_i += 3
	var mi := MeshInstance3D.new()
	mi.name = "Grandstands"
	mi.mesh = m.commit()
	mi.material_override = _vc_material()
	view.add_child(mi)
	var bmi := MeshInstance3D.new()
	bmi.name = "SponsorBoards"
	bmi.mesh = board_mesh.commit()
	var bmat := _vc_material(0.5)
	bmat.emission_enabled = true
	bmat.emission = Color(0.12, 0.12, 0.12)
	bmi.material_override = bmat
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.add_child(bmi)
	if not crowd_x.is_empty():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = person_mesh()
		mm.instance_count = crowd_x.size()
		for k in crowd_x.size():
			mm.set_instance_transform(k, crowd_x[k])
			mm.set_instance_color(k, crowd_c[k])
		var cmi := MultiMeshInstance3D.new()
		cmi.name = "Crowd"
		cmi.multimesh = mm
		var cmat := ShaderMaterial.new()
		cmat.shader = load("res://assets/shaders/crowd.gdshader")
		cmi.material_override = cmat
		cmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.add_child(cmi)


# ------------------------------------------------------------------ yardage markers

## Plates in the fairway centre line plus a short post at the fairway edge for each yardage that fits
## on the hole. `high` adds the painted number on the post and soft contact shadows.
static func build_yardage_markers(view: Node3D, p_hole: HoleDefinition, high: bool, tb: TerrainBuilder = null) -> void:
	var g := target_green(p_hole)
	if g == null or p_hole.fairway.is_empty():
		return
	var gc := Vector2(g.cx, g.cz)
	var h := func(x: float, z: float) -> float: return tb.mesh_height_at(x, z) if tb != null else p_hole.terrain_height(x, z)
	var plate := CylinderMesh.new()
	plate.top_radius = 0.3
	plate.bottom_radius = 0.3
	plate.height = 0.03
	plate.radial_segments = 16
	var post := CylinderMesh.new()
	post.top_radius = 0.05
	post.bottom_radius = 0.06
	post.height = 0.6
	post.radial_segments = 6
	var shadow_mesh := QuadMesh.new()
	shadow_mesh.size = Vector2(0.7, 0.7)
	shadow_mesh.orientation = PlaneMesh.FACE_Y
	var shadow_mat: ShaderMaterial = null
	if high:
		shadow_mat = ShaderMaterial.new()
		shadow_mat.shader = load("res://assets/shaders/contact_shadow.gdshader")
	var tee_dist := p_hole.tee.distance_to(gc)
	for yd in YARDAGES:
		var meters: float = float(yd[0]) * 0.9144
		if meters > tee_dist - 15.0 or meters < 20.0:
			continue
		var spot := _fairway_point_at(p_hole, gc, meters)
		if spot.is_empty():
			continue
		var p: Vector2 = spot["p"]
		var col: Color = yd[1]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.5
		var n := p_hole.normal_at(p.x, p.y)
		var tilt := Basis(Quaternion(Vector3.UP, n))
		var pm := MeshInstance3D.new()
		pm.name = "YardagePlate%d" % int(yd[0])
		pm.mesh = plate
		pm.material_override = mat
		pm.transform = Transform3D(tilt, Vector3(p.x, h.call(p.x, p.y) + 0.004, p.y))
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.add_child(pm)
		# post at the fairway edge (right of the line of play), only on rough
		var dir: Vector2 = spot["dir"]
		var right := Vector2(-dir.y, dir.x)
		for sgn in [1.0, -1.0]:
			var q: Vector2 = p + right * sgn * (float(spot["hw"]) + 1.4)
			if p_hole.surface_at(q.x, q.y) != Surface.Type.ROUGH:
				continue
			var y: float = h.call(q.x, q.y)
			var po := MeshInstance3D.new()
			po.name = "YardagePost%d" % int(yd[0])
			po.mesh = post
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = col
			pmat.roughness = 0.45
			po.material_override = pmat
			po.position = Vector3(q.x, y + 0.27, q.y)
			view.add_child(po)
			if high:
				var sh := MeshInstance3D.new()
				sh.mesh = shadow_mesh
				sh.material_override = shadow_mat
				sh.position = Vector3(q.x, y + 0.02, q.y)
				sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				view.add_child(sh)
				var lbl := Label3D.new()
				lbl.text = str(int(yd[0]))
				lbl.font_size = 48
				lbl.pixel_size = 0.004
				lbl.outline_size = 10
				lbl.modulate = Color(1, 1, 1)
				lbl.outline_modulate = Color(0.05, 0.05, 0.05)
				lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
				lbl.position = Vector3(q.x, y + 0.85, q.y)
				view.add_child(lbl)
			break


## Point on the fairway centre line whose straight distance to `gc` is `meters` (searching from the
## green back towards the tee). Returns {p, dir (unit, towards the green), hw} or {} if none.
static func _fairway_point_at(p_hole: HoleDefinition, gc: Vector2, meters: float) -> Dictionary:
	var segs := p_hole.fairway
	for si in range(segs.size() - 1, -1, -1):
		var s: Dictionary = segs[si]
		var p0: Vector2 = s["p0"]
		var p1: Vector2 = s["p1"]
		var seg_len := p0.distance_to(p1)
		if seg_len < 0.1:
			continue
		# walk p1 -> p0 (assumes segments run tee -> green; also handles reversed ones)
		var a := p1 if p1.distance_to(gc) < p0.distance_to(gc) else p0
		var bpt := p0 if a == p1 else p1
		if a.distance_to(gc) > meters or bpt.distance_to(gc) < meters:
			continue
		var steps := int(seg_len / 0.5)
		for k in steps + 1:
			var q := a.lerp(bpt, float(k) / float(maxi(steps, 1)))
			if q.distance_to(gc) >= meters:
				if p_hole.surface_at(q.x, q.y) != Surface.Type.FAIRWAY:
					return {}
				return {"p": q, "dir": (a - bpt).normalized(), "hw": float(s["hw"])}
	return {}

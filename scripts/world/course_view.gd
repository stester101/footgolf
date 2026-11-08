class_name CourseView
extends Node3D
## Visual scene for one hole, generated from its HoleDefinition (terrain, water, trees with
## matching collision proxies in the simulation, pin, cup, tee markers, OOB stakes, grass tufts).
## Building is incremental: begin_build() then build_step(budget) every frame until it returns
## true (progress in `progress`), so the next hole can be prepared behind a loading bar.
## build() does everything at once.

const GRASS_RADIUS := 9.0
const GRASS_MAX_DENSITY := 7.0  # tufts per m² in full rough

var hole: HoleDefinition
var pin_label: Label3D
var cup_radius := 0.1524
var terrain: TerrainBuilder
var progress := 0.0

var _cup_disc: MeshInstance3D
var _cup_ring: MeshInstance3D
var _pin_root: Node3D
var _terrain_mat: ShaderMaterial
var _grass: MultiMeshInstance3D
var _grass_at := Vector3.INF
var _jobs: Array = []  # [{w: float, run: Callable(deadline) -> bool, part: Callable() -> float}]
var _job_i := 0
var _tree_i := 0
var _tree_x := {}

var _terrain_shader: Shader = preload("res://assets/shaders/terrain.gdshader")
var _water_shader: Shader = preload("res://assets/shaders/water.gdshader")
var _flag_shader: Shader = preload("res://assets/shaders/flag.gdshader")
var _foliage_shader: Shader = preload("res://assets/shaders/foliage.gdshader")
var _bark_shader: Shader = preload("res://assets/shaders/bark.gdshader")
var _grass_shader: Shader = preload("res://assets/shaders/grass_blades.gdshader")

# Tree/tuft meshes are the same for every hole: build once per run.
static var _meshes := {}


func build(p_hole: HoleDefinition, p_cup_radius: float = 0.1524) -> void:
	begin_build(p_hole, p_cup_radius)
	while not build_step(1000000000):
		pass


func begin_build(p_hole: HoleDefinition, p_cup_radius: float = 0.1524) -> void:
	hole = p_hole
	cup_radius = p_cup_radius
	for c in get_children():
		c.queue_free()
	_cup_disc = null
	_cup_ring = null
	_pin_root = null
	_grass = null
	_grass_at = Vector3.INF
	pin_label = null
	progress = 0.0
	terrain = TerrainBuilder.new(hole)
	_tree_i = 0
	_tree_x = {}
	_job_i = 0
	var tb := terrain
	_jobs = [
		{"w": tb.total_work(), "run": tb.step, "part": func() -> float: return tb.done_work() / maxf(tb.total_work(), 1.0)},
		{"w": tb.total_work() * 0.12, "run": _job_terrain},
		{"w": 3000.0, "run": _job_ground_water},
		{"w": 400.0 + hole.trees.size() * 40.0, "run": _step_trees, "part": func() -> float: return float(_tree_i) / maxf(hole.trees.size(), 1.0)},
		{"w": 6000.0, "run": _job_tree_meshes},
		{"w": 1500.0, "run": _job_details},
	]


func _job_terrain(_deadline: int) -> bool:
	_build_terrain()
	return true


func _job_ground_water(_deadline: int) -> bool:
	_build_outer_ground()
	_build_water()
	return true


func _job_tree_meshes(_deadline: int) -> bool:
	_build_tree_multimeshes()
	_build_backdrop()
	return true


func _job_details(_deadline: int) -> bool:
	_build_pin()
	_build_tee_markers()
	_build_oob_stakes()
	_build_grass()
	return true


func is_built() -> bool:
	return _job_i >= _jobs.size()


## Runs build work for at most ~budget_usec; returns true once the hole is complete.
func build_step(budget_usec: int) -> bool:
	var deadline := Time.get_ticks_usec() + budget_usec
	while _job_i < _jobs.size():
		var job: Dictionary = _jobs[_job_i]
		if (job["run"] as Callable).call(deadline):
			_job_i += 1
		if Time.get_ticks_usec() > deadline:
			break
	_update_progress()
	return is_built()


func _update_progress() -> void:
	var total := 0.0
	var done := 0.0
	for i in _jobs.size():
		var w: float = _jobs[i]["w"]
		total += w
		if i < _job_i:
			done += w
		elif i == _job_i and _jobs[i].has("part"):
			done += w * clampf((_jobs[i]["part"] as Callable).call(), 0.0, 1.0)
	progress = 1.0 if is_built() else clampf(done / maxf(total, 1.0), 0.0, 0.99)


func _build_terrain() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = terrain.commit_mesh()
	_terrain_mat = ShaderMaterial.new()
	_terrain_mat.shader = _terrain_shader
	var d := (hole.pin - hole.tee).normalized()
	_terrain_mat.set_shader_parameter("stripe_dir", Vector2(-d.y, d.x))
	_terrain_mat.set_shader_parameter("surface_tex", terrain.color_texture())
	_terrain_mat.set_shader_parameter("kind_tex", terrain.kind_texture())
	_terrain_mat.set_shader_parameter("noise_tex", WorldTextures.noise_texture())
	_terrain_mat.set_shader_parameter("map_origin", hole.bounds.position)
	_terrain_mat.set_shader_parameter("map_size", Vector2(terrain.map_w, terrain.map_h) * terrain.map_mpp)
	mi.material_override = _terrain_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Ground OUTSIDE the terrain mesh only (a frame around hole.bounds), at the height the terrain
## edges blend to. Uses the turf material: its surface maps clamp to the edge pixels, so the
## rough continues seamlessly. A full plane would poke through low parts of the course.
func _build_outer_ground() -> void:
	var y := TerrainBuilder.outer_height(hole) - 0.05
	var r := hole.bounds.grow(-1.0)
	var big := 1500.0
	var rects := [
		Rect2(-big, -big, r.position.x + big, 2.0 * big),
		Rect2(r.end.x, -big, big - r.end.x, 2.0 * big),
		Rect2(r.position.x, -big, r.size.x, r.position.y + big),
		Rect2(r.position.x, r.end.y, r.size.x, big - r.end.y),
	]
	for i in rects.size():
		var rc: Rect2 = rects[i]
		var mi := MeshInstance3D.new()
		mi.name = "OuterGround%d" % i
		var pm := PlaneMesh.new()
		pm.size = rc.size
		mi.mesh = pm
		mi.position = Vector3(rc.get_center().x, y, rc.get_center().y)
		mi.material_override = _terrain_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _build_water() -> void:
	for i in hole.waters.size():
		var mi := MeshInstance3D.new()
		mi.name = "Water%d" % i
		mi.mesh = TerrainBuilder.ellipse_mesh(hole.waters[i], float(hole.water_level[i]), 64)
		var mat := ShaderMaterial.new()
		mat.shader = _water_shader
		mat.set_shader_parameter("noise_tex", WorldTextures.noise_texture())
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# ------------------------------------------------------------------ trees

func _mesh(key: String) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var m: ArrayMesh
	var mat := ShaderMaterial.new()
	mat.set_shader_parameter("noise_tex", WorldTextures.noise_texture())
	match key:
		"trunk_d":
			m = TreeMeshes.trunk(true)
			mat.shader = _bark_shader
		"trunk_c":
			m = TreeMeshes.trunk(false)
			mat.shader = _bark_shader
		"crown0", "crown1", "crown2":
			m = TreeMeshes.canopy_cluster(1000 + int(key.right(1)) * 77)
			mat.shader = _foliage_shader
		"pine0", "pine1":
			m = TreeMeshes.conifer(2000 + int(key.right(1)) * 31)
			mat.shader = _foliage_shader
		"crown_lo":
			m = TreeMeshes.canopy_cluster(3001, true)
			mat.shader = _foliage_shader
		"pine_lo":
			m = TreeMeshes.conifer(3002, true)
			mat.shader = _foliage_shader
		"tuft":
			m = TreeMeshes.grass_tuft(4242, 6)
			mat = null
	if mat != null:
		m.surface_set_material(0, mat)
	_meshes[key] = m
	return m


func _push(key: String, x: Transform3D, c: Color) -> void:
	if not _tree_x.has(key):
		_tree_x[key] = [[], []]
	(_tree_x[key][0] as Array).append(x)
	(_tree_x[key][1] as Array).append(c)


## Transforms + tints for the course trees, matching the physics proxies:
## trunk cylinder (trunk_r, up to trunk_h) and canopy ellipsoid (canopy_r, canopy_ry @ canopy_y).
func _step_trees(deadline: int) -> bool:
	var n := hole.trees.size()
	while _tree_i < n:
		var t: Dictionary = hole.trees[_tree_i]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(hole.id) ^ (_tree_i * 7919)
		var x: float = t["x"]
		var z: float = t["z"]
		var base_y: float = t["base_y"]
		var tr: float = t["trunk_r"]
		var th: float = t["trunk_h"]
		var cr: float = t["canopy_r"]
		var cry: float = t["canopy_ry"]
		var cy: float = t["canopy_y"]
		var yaw := rng.randf() * TAU
		var conif := int(t["kind"]) != 0
		var bark := Color(0.17, 0.12, 0.085) if not conif else Color(0.20, 0.11, 0.07)
		bark = bark * rng.randf_range(0.8, 1.1)
		bark.a = 1.0
		_push("trunk_c" if conif else "trunk_d", Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(tr, th + 0.15, tr)), Vector3(x, base_y - 0.15, z)), bark)
		# slight natural lean, never enough to leave the proxy
		var lean_axis := Vector3(cos(yaw), 0, sin(yaw))
		var lean := Basis(lean_axis, rng.randf_range(-0.035, 0.035))
		if conif:
			var col := Color.from_hsv(rng.randf_range(0.36, 0.43), rng.randf_range(0.48, 0.62), rng.randf_range(0.26, 0.34))
			var y0 := cy - cry * 0.95
			var b := lean * Basis(Vector3.UP, yaw).scaled(Vector3(cr, cry * 2.35, cr) * rng.randf_range(0.97, 1.03))
			_push("pine%d" % (rng.randi() % 2), Transform3D(b, Vector3(x, y0, z)), col)
		else:
			var hue := rng.randf_range(0.22, 0.31)
			if rng.randf() < 0.12:
				hue = rng.randf_range(0.15, 0.19)  # the odd olive / yellowing crown
			var col2 := Color.from_hsv(hue, rng.randf_range(0.55, 0.72), rng.randf_range(0.36, 0.48))
			var b2 := lean * Basis(Vector3.UP, yaw).scaled(Vector3(cr, cry, cr) * rng.randf_range(0.98, 1.04))
			_push("crown%d" % (rng.randi() % 3), Transform3D(b2, Vector3(x, cy, z)), col2)
		_tree_i += 1
		if _tree_i % 32 == 0 and Time.get_ticks_usec() > deadline:
			return false
	return true


func _build_tree_multimeshes() -> void:
	for key in _tree_x.keys():
		_add_multimesh("Trees_" + key, _mesh(key), _tree_x[key][0], _tree_x[key][1])


func _add_multimesh(n: String, mesh: Mesh, xforms: Array, colors: Array, shadows: bool = true) -> MultiMeshInstance3D:
	if xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


## Decorative tree belt well beyond the out-of-bounds line (visual only; any ball out there
## is already out of bounds). Low-poly crowns and pines in the hole's conifer mix fill the horizon.
func _build_backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(hole.id + "backdrop")
	var r := hole.bounds.grow(25.0)
	var outer_h := TerrainBuilder.outer_height(hole)
	var dx: Array[Transform3D] = []
	var dc: Array[Color] = []
	var px: Array[Transform3D] = []
	var pc: Array[Color] = []
	var per := r.size.x * 2.0 + r.size.y * 2.0
	var n := int(per / 7.0)
	for i in n:
		var t := float(i) / float(n) * per
		var p := Vector2.ZERO
		if t < r.size.x:
			p = Vector2(r.position.x + t, r.position.y)
		elif t < r.size.x + r.size.y:
			p = Vector2(r.end.x, r.position.y + t - r.size.x)
		elif t < r.size.x * 2.0 + r.size.y:
			p = Vector2(r.end.x - (t - r.size.x - r.size.y), r.end.y)
		else:
			p = Vector2(r.position.x, r.end.y - (t - 2.0 * r.size.x - r.size.y))
		for row in 3:
			var q := p + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5)) + (p - r.get_center()).normalized() * row * 12.0
			var hgt := rng.randf_range(11.0, 20.0)
			var yaw := Basis(Vector3.UP, rng.randf() * TAU)
			if rng.randf() < hole.conifer_ratio:
				var w := hgt * rng.randf_range(0.26, 0.32)
				px.append(Transform3D(yaw.scaled(Vector3(w, hgt * 0.92, w)), Vector3(q.x, outer_h + hgt * 0.08, q.y)))
				pc.append(Color.from_hsv(rng.randf_range(0.36, 0.43), rng.randf_range(0.45, 0.6), rng.randf_range(0.22, 0.3)))
			else:
				var cr := hgt * 0.32
				dx.append(Transform3D(yaw.scaled(Vector3(cr, cr * 1.15, cr)), Vector3(q.x, outer_h + hgt * 0.58, q.y)))
				dc.append(Color.from_hsv(rng.randf_range(0.21, 0.30), rng.randf_range(0.52, 0.7), rng.randf_range(0.30, 0.42)))
	_add_multimesh("Backdrop", _mesh("crown_lo"), dx, dc, false)
	_add_multimesh("BackdropPines", _mesh("pine_lo"), px, pc, false)


# ------------------------------------------------------------------ grass tufts near the ball

func _build_grass() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _grass_shader
	for p in ["stripe_dir", "surface_tex", "kind_tex", "noise_tex", "map_origin", "map_size"]:
		mat.set_shader_parameter(p, _terrain_mat.get_shader_parameter(p))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _mesh("tuft")
	_grass = MultiMeshInstance3D.new()
	_grass.name = "GrassTufts"
	_grass.multimesh = mm
	_grass.material_override = mat
	_grass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grass)


func set_grass_visible(on: bool) -> void:
	if _grass != null:
		_grass.visible = on


## Scatter tufts around a resting ball: dense and long in rough, short and sparse on fairway /
## tee / fringe close to the ball, none on the green, sand or water. Heights follow the rendered
## terrain surface exactly; size fades out towards the patch edge so it has no visible border.
func place_grass(center: Vector3) -> void:
	if _grass == null or terrain == null:
		return
	if center.distance_squared_to(_grass_at) < 0.01:
		return
	_grass_at = center
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(center.x * 10.0), roundi(center.z * 10.0))) ^ hash(hole.id)
	var c2 := Vector2(center.x, center.z)
	var candidates := int(PI * GRASS_RADIUS * GRASS_RADIUS * GRASS_MAX_DENSITY)
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	for i in candidates:
		var rr := GRASS_RADIUS * sqrt(rng.randf())
		var a := rng.randf() * TAU
		var p := c2 + Vector2(cos(a), sin(a)) * rr
		if rr < 0.2:
			continue  # keep the ball itself readable
		# same warped surface-map lookup as the turf shader
		var wq := WorldTextures.sample(p / 19.0)
		var fq := WorldTextures.sample(p / 7.3)
		var wp := p + Vector2(wq.r - 0.5, wq.g - 0.5) * 2.4 + Vector2(fq.r - 0.5, fq.g - 0.5) * 0.5
		var k := terrain.kind_at(wp.x, wp.y)
		var near_ball := 1.0 - smoothstep(2.0, 4.5, rr)
		var w_rough := k.b
		var w_mown := k.r * near_ball
		var dens := (w_rough * GRASS_MAX_DENSITY + w_mown * 6.0) / GRASS_MAX_DENSITY
		if rng.randf() >= dens:
			continue
		var is_rough := rng.randf() < w_rough / maxf(w_rough + w_mown, 0.001)
		var fade := 1.0 - smoothstep(GRASS_RADIUS * 0.55, GRASS_RADIUS, rr)
		var h := (rng.randf_range(0.06, 0.13) if is_rough else rng.randf_range(0.018, 0.03)) * lerpf(0.25, 1.0, fade)
		var wsc := (rng.randf_range(0.10, 0.15) if is_rough else rng.randf_range(0.07, 0.09))
		var y := terrain.mesh_height_at(p.x, p.y) - 0.004
		xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wsc, h, wsc)), Vector3(p.x, y, p.y)))
		var v := rng.randf_range(0.88, 1.08)
		cs.append(Color(v, v * rng.randf_range(0.98, 1.04), v * rng.randf_range(0.9, 1.0)))
	var mm := _grass.multimesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_color(i, cs[i])


# ------------------------------------------------------------------ pin, tee, stakes

func _build_pin() -> void:
	var cup := hole.cup_position()
	_cup_disc = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.01
	cm.radial_segments = 24
	_cup_disc.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.03, 0.03, 0.03)
	_cup_disc.material_override = cmat
	_cup_disc.position = cup + Vector3(0, 0.006, 0)
	add_child(_cup_disc)
	_cup_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.12
	tm.rings = 24
	tm.ring_segments = 4
	_cup_ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.95, 0.95, 0.95)
	_cup_ring.material_override = rmat
	_cup_ring.position = cup + Vector3(0, 0.004, 0)
	add_child(_cup_ring)
	set_cup_radius(cup_radius)
	# Pole + flag share one root so they can be scaled up together with distance.
	_pin_root = Node3D.new()
	_pin_root.name = "Pin"
	_pin_root.position = cup
	add_child(_pin_root)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.016
	pm.bottom_radius = 0.016
	pm.height = 2.3
	pm.radial_segments = 6
	pole.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.97, 0.97, 0.95)
	pmat.emission_enabled = true
	pmat.emission = Color(0.25, 0.25, 0.24)
	pole.material_override = pmat
	pole.position = Vector3(0, 1.15, 0)
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pin_root.add_child(pole)
	var flag := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.72, 0.48)
	qm.subdivide_width = 10
	qm.subdivide_depth = 2
	flag.mesh = qm
	var fmat := ShaderMaterial.new()
	fmat.shader = _flag_shader
	flag.material_override = fmat
	flag.position = Vector3(0.37, 2.04, 0)
	_pin_root.add_child(flag)
	pin_label = Label3D.new()
	pin_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pin_label.fixed_size = true
	pin_label.pixel_size = 0.0016
	pin_label.font_size = 28
	pin_label.outline_size = 8
	pin_label.no_depth_test = true
	pin_label.modulate = Color(1, 1, 1)
	pin_label.position = cup + Vector3(0, 3.0, 0)
	add_child(pin_label)


## Distance boost for the pin so it reads from the tee: true size within ~40 m, growing
## smoothly to at most 4x far away (it still looks like a normal flag at that distance).
func update_view(cam: Camera3D) -> void:
	if _pin_root == null or cam == null:
		return
	var s := 1.0
	if cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
		var d := cam.global_position.distance_to(_pin_root.global_position)
		s = clampf(d / 40.0, 1.0, 4.0)
	_pin_root.scale = Vector3.ONE * s


func set_cup_radius(r: float) -> void:
	cup_radius = r
	if _cup_disc != null:
		_cup_disc.scale = Vector3(r, 1.0, r)
	if _cup_ring != null:
		_cup_ring.scale = Vector3(r, 0.1, r)


func _build_tee_markers() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.1)  # yellow tee markers
	mat.roughness = 0.4
	var d := (hole.pin - hole.tee).normalized()
	var side := Vector2(-d.y, d.x)
	for sgn in [-1.0, 1.0]:
		var p: Vector2 = hole.tee + side * 2.6 * float(sgn) + d * 0.8
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.11
		sm.height = 0.22
		mi.mesh = sm
		mi.material_override = mat
		mi.position = Vector3(p.x, hole.terrain_height(p.x, p.y) + 0.12, p.y)
		add_child(mi)


func _build_oob_stakes() -> void:
	if hole.boundary.size() < 3:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.04
	mesh.height = 1.0
	mesh.radial_segments = 5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.96, 0.96)
	mesh.material = mat
	var xforms: Array[Transform3D] = []
	for i in hole.boundary.size():
		var a := hole.boundary[i]
		var b := hole.boundary[(i + 1) % hole.boundary.size()]
		var n := int(a.distance_to(b) / 12.0)
		for k in n:
			var p := a.lerp(b, float(k) / float(maxi(n, 1)))
			xforms.append(Transform3D(Basis(), Vector3(p.x, hole.terrain_height(p.x, p.y) + 0.5, p.y)))
	_add_multimesh("OOBStakes", mesh, xforms, [])

class_name SkyLife
extends Node3D
## Tier-2 High-graphics scenery that lives far away or high up: layered hill/ridge silhouettes,
## horizon cloud puffs (static, built once) plus occasional bird flocks and a jet with a contrail
## (spawned rarely, a handful of node moves per frame at most). Everything is presentation only,
## deterministic per hole id for its SHAPE (timing of birds/jet is random). One CourseView owns one
## SkyLife, and CourseView only creates it when HoleAtmosphere.high_quality is on.
##
## Cost: 3 ridge draws + 1 cloud MultiMesh draw (+ <= 3 small flocks and 1 jet over a hole).
## Readability: all of it sits beyond the course (>= 800 m) or high in the sky; birds only appear
## well above the horizon and never in the overhead map view.

## Smoke-test hook: place a flock and the jet straight ahead immediately, nearly stationary.
static var preview := false

const MAX_FLOCKS := 3
const RIDGE_SEGMENTS := 720

# Three colour families (near, mid, far layer) picked per hole; each is hazed further towards the
# fog colour with distance.
const PALETTES := [
	[Color(0.20, 0.36, 0.25), Color(0.30, 0.46, 0.42), Color(0.46, 0.60, 0.68)],  # green hills
	[Color(0.26, 0.37, 0.46), Color(0.36, 0.48, 0.60), Color(0.52, 0.64, 0.76)],  # blue-grey
	[Color(0.38, 0.38, 0.24), Color(0.48, 0.48, 0.38), Color(0.62, 0.66, 0.66)],  # dry olive
	[Color(0.28, 0.30, 0.44), Color(0.40, 0.42, 0.58), Color(0.58, 0.64, 0.78)],  # dusk blue
]

var hole: HoleDefinition
var _h := 0
var _atmos := {}
var _rng := RandomNumberGenerator.new()
var _flocks: Array = []  # [{node: MeshInstance3D, vel: Vector3, life: float}]
var _flocks_made := 0
var _bird_timer := 0.0
var _bird_mesh_mat: ShaderMaterial
var _jet: MeshInstance3D
var _jet_mat: ShaderMaterial
var _jet_vel := Vector3.ZERO
var _jet_life := 0.0
var _jet_total := 1.0
var _jet_timer := 0.0
var _jet_pending := false


func build(p_hole: HoleDefinition) -> void:
	hole = p_hole
	_h = absi(hole.id.hash())
	_atmos = HoleAtmosphere.for_hole(hole)
	var c := hole.bounds.get_center()
	position = Vector3(c.x, 0.0, c.y)
	_rng.seed = _h ^ 0x51F7
	_add_ridges()
	_add_clouds()
	# random (not hole-seeded) timing so repeats feel different; the shape of each is still varied
	_bird_timer = 0.5 if preview else randf_range(4.0, 12.0)
	_jet_pending = preview or ((_h >> 11) % 10) < 6
	_jet_timer = 0.8 if preview else randf_range(6.0, 25.0)


# ------------------------------------------------------------------ ridges

func _add_ridges() -> void:
	var pal: Array = PALETTES[(_h >> 3) % PALETTES.size()]
	var haze: Color = _atmos["fog"]
	var radii := [820.0, 1100.0, 1380.0]
	var hmin := [26.0, 55.0, 90.0]
	var hmax := [65.0, 150.0, 300.0]
	var haze_amt := [0.38, 0.56, 0.72]
	var base_y := TerrainBuilder.outer_height(hole) - 6.0
	var env_k := 1 + (_h >> 7) % 2
	for li in 3:
		var n := FastNoiseLite.new()
		n.seed = int(_h % 100000) + li * 131
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = 1.0
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 5
		n.fractal_gain = 0.55
		var top: float = lerpf(hmin[li], hmax[li], _rng.randf_range(0.35, 1.0))
		var rho := 1.6 + li * 0.7
		var phase := _rng.randf() * TAU
		var depth := _rng.randf_range(0.30, 0.55)  # how much valleys drop between the peaks
		var verts := PackedVector3Array()
		var uvs := PackedVector2Array()
		var idx := PackedInt32Array()
		var r: float = radii[li]
		for i in RIDGE_SEGMENTS + 1:
			var a := TAU * float(i % RIDGE_SEGMENTS) / RIDGE_SEGMENTS
			var nv := n.get_noise_2d(cos(a) * rho, sin(a) * rho) * 0.5 + 0.5
			var env := 0.65 + 0.35 * sin(a * float(env_k) + phase)  # some directions are flatter
			var hgt: float = top * (depth + (1.0 - depth) * clampf(nv * 1.35 - 0.1, 0.0, 1.0)) * env
			var x := cos(a) * r
			var z := sin(a) * r
			var u := float(i) / RIDGE_SEGMENTS
			verts.append(Vector3(x, base_y, z))
			uvs.append(Vector2(u, 0.0))
			verts.append(Vector3(x, base_y + 6.0 + hgt, z))
			uvs.append(Vector2(u, 1.0))
		for i in RIDGE_SEGMENTS:
			var b := i * 2
			idx.append_array(PackedInt32Array([b, b + 1, b + 2, b + 2, b + 1, b + 3]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/ridge.gdshader")
		mat.set_shader_parameter("col", (pal[li] as Color).lerp(haze, haze_amt[li]))
		mat.set_shader_parameter("haze", haze)
		var mi := MeshInstance3D.new()
		mi.name = "Ridge%d" % li
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16384.0  # the ring surrounds the camera; never frustum-cull it
		add_child(mi)


# ------------------------------------------------------------------ horizon cloud puffs

func _add_clouds() -> void:
	var bearing := atan2(hole.pin.x - hole.tee.x, hole.pin.y - hole.tee.y)
	var count := 7 + (_h >> 5) % 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 0.6)
	mm.mesh = q
	mm.instance_count = count
	for i in count:
		# mostly ahead (the direction the player looks), some to the sides
		var az := bearing + _rng.randf_range(-1.7, 1.7)
		var dist := _rng.randf_range(1500.0, 2250.0)
		var elev := deg_to_rad(_rng.randf_range(7.0, 18.0))
		var w := _rng.randf_range(380.0, 700.0)
		var p := Vector3(sin(az) * dist, tan(elev) * dist, cos(az) * dist)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(w, w, w)), p))
		mm.set_instance_custom_data(i, Color(_rng.randf() * 20.0, 0, 0, 0))
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/cloud_puff.gdshader")
	mat.set_shader_parameter("lit", Color.WHITE.lerp(_atmos["sun"], 0.35))
	mat.set_shader_parameter("shade", (_atmos["mid"] as Color).lerp(Color.WHITE, 0.5))
	mat.set_shader_parameter("opacity", 0.80)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "HorizonClouds"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.extra_cull_margin = 16384.0
	add_child(mmi)


# ------------------------------------------------------------------ birds and jet

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	for i in range(_flocks.size() - 1, -1, -1):
		var f: Dictionary = _flocks[i]
		(f["node"] as Node3D).global_position += (f["vel"] as Vector3) * delta
		f["life"] = float(f["life"]) - delta
		if float(f["life"]) <= 0.0:
			(f["node"] as Node).queue_free()
			_flocks.remove_at(i)
	if _flocks_made < MAX_FLOCKS:
		_bird_timer -= delta
		if _bird_timer <= 0.0:
			_bird_timer = 0.2 if preview else 3.0  # retried soon when the camera pose does not allow it
			if _spawn_flock():
				_bird_timer = randf_range(14.0, 40.0)
	if _jet != null:
		_jet.global_position += _jet_vel * delta
		_jet_life -= delta
		_jet_mat.set_shader_parameter("fade", clampf(minf(_jet_total - _jet_life, _jet_life) / 3.0, 0.0, 1.0))
		if _jet_life <= 0.0:
			_jet.queue_free()
			_jet = null
	elif _jet_pending:
		_jet_timer -= delta
		if _jet_timer <= 0.0:
			_jet_timer = 0.2 if preview else 3.0
			if _spawn_jet():
				_jet_pending = false


## Camera frame for spawning: [camera, flat forward, right], or empty when the view is not suitable
## (overhead/orthographic map, or looking steeply down).
func _view() -> Array:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return []
	var fwd := -cam.global_transform.basis.z
	if fwd.y < -0.55:
		return []
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	if flat.length() < 0.2:
		return []
	flat = flat.normalized()
	return [cam, flat, flat.cross(Vector3.UP)]


func _spawn_flock() -> bool:
	var v := _view()
	if v.is_empty():
		return false
	var cam: Camera3D = v[0]
	var flat: Vector3 = v[1]
	var right: Vector3 = v[2]
	var dir_sign := -1.0 if randf() < 0.5 else 1.0
	var dist := randf_range(95.0, 170.0)
	var elev := deg_to_rad(randf_range(9.0, 19.0))
	var speed := randf_range(7.0, 11.0)
	var start := cam.global_position + flat * dist + Vector3.UP * (dist * tan(elev))
	if preview:
		start += right * -20.0
		speed = 0.4
	else:
		start += right * (-dir_sign * dist * 0.85)
	var vel := right * (dir_sign * speed) + Vector3.UP * randf_range(-0.2, 0.5)
	var mi := MeshInstance3D.new()
	mi.name = "BirdFlock"
	mi.mesh = _flock_mesh(randi_range(4, 8))
	if _bird_mesh_mat == null:
		_bird_mesh_mat = ShaderMaterial.new()
		_bird_mesh_mat.shader = load("res://assets/shaders/bird.gdshader")
	mi.material_override = _bird_mesh_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = start
	mi.rotation.y = atan2(-vel.x, -vel.z)
	_flocks.append({"node": mi, "vel": vel, "life": 60.0 if preview else (dist * 1.9) / speed})
	_flocks_made += 1
	return true


## One mesh for a whole flock: each bird is two dihedral wing triangles plus a body triangle.
## UV.y = wing-tip weight (flap amplitude), COLOR = (phase, speed variation).
func _flock_mesh(n: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for b in n:
		var off := Vector3(rng.randf_range(-1.0, 1.0) * 2.0 + b * 0.0, rng.randf_range(-1.2, 1.2), 0.0)
		# loose V: later birds sit further behind and to alternating sides
		off.x = (float(b + 1) / 2.0) * 4.5 * (1.0 if b % 2 == 0 else -1.0) + rng.randf_range(-1.0, 1.0)
		off.z = float(b + 1) / 2.0 * 3.5 + rng.randf_range(-1.0, 1.0)
		var s := rng.randf_range(1.0, 1.5)
		var col := Color(rng.randf(), rng.randf(), 0.0)
		var tris := [
			[Vector3(0, 0, -0.30), 0.0, Vector3(-1.05, 0.10, 0.10), 1.0, Vector3(0, 0, 0.26), 0.0],
			[Vector3(0, 0, -0.30), 0.0, Vector3(0, 0, 0.26), 0.0, Vector3(1.05, 0.10, 0.10), 1.0],
			[Vector3(-0.07, 0, -0.30), 0.0, Vector3(0, 0, 0.62), 0.0, Vector3(0.07, 0, -0.30), 0.0],
		]
		for t in tris:
			for k in 3:
				verts.append(off + (t[k * 2] as Vector3) * s)
				uvs.append(Vector2(0.0, float(t[k * 2 + 1])))
				cols.append(col)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _spawn_jet() -> bool:
	var v := _view()
	if v.is_empty():
		return false
	var cam: Camera3D = v[0]
	var flat: Vector3 = v[1]
	var right: Vector3 = v[2]
	var dir_sign := -1.0 if randf() < 0.5 else 1.0
	var dist := randf_range(1750.0, 2000.0)
	var elev := deg_to_rad(randf_range(13.0, 19.0))
	var yaw := Basis(Vector3.UP, deg_to_rad(randf_range(-18.0, 18.0)))
	var centre := cam.global_position + (yaw * flat) * dist
	centre.y = cam.global_position.y + dist * tan(elev)
	var along := (yaw * right) * dir_sign
	var reach := 0.0 if preview else 1300.0
	var speed := 1.0 if preview else 70.0
	var head := centre - along * reach
	var length := 700.0
	_jet = MeshInstance3D.new()
	_jet.name = "JetContrail"
	var q := QuadMesh.new()
	q.size = Vector2(length, 17.0)
	_jet.mesh = q
	_jet_mat = ShaderMaterial.new()
	_jet_mat.shader = load("res://assets/shaders/contrail.gdshader")
	_jet_mat.set_shader_parameter("length_m", length)
	_jet_mat.set_shader_parameter("fade", 0.0)
	_jet.material_override = _jet_mat
	_jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jet.extra_cull_margin = 4000.0
	add_child(_jet)
	# quad faces the camera position at spawn; +X is the flight direction, head at the +X end
	var z := (cam.global_position - head).normalized()
	var x := (along - z * along.dot(z)).normalized()
	var y := z.cross(x).normalized()
	_jet.global_transform = Transform3D(Basis(x, y, z), head - x * (length * 0.5))
	_jet_vel = along * speed
	_jet_total = (2.0 * reach / speed) if not preview else 120.0
	_jet_total = maxf(_jet_total, 8.0)
	_jet_life = _jet_total
	return true

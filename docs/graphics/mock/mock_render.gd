extends SceneTree
## MOCKUP RENDERER (not shipped, touches no game script). Builds the REAL CourseView + the same
## sun/camera as the game, then optionally layers cheap "tier" upgrades on top, and saves a PNG.
##
##   xvfb-run -a godot --path . --rendering-method mobile --resolution 450x800 \
##     -s res://docs/graphics/mock/mock_render.gd -- --level=before|tier1|tier2|tier2_golden \
##     --hole=hole_01 --view=aim|high --out=docs/graphics/mockups/x.png
##
## Everything the tiers add is created here (sky shader, ground shader copy, billboard clouds,
## hill silhouettes, birds, contrail); the game's own scripts and shaders are untouched.

const SHADERS := "res://docs/graphics/mock/"

var level := "before"
var hole_id := "hole_01"
var view := "aim"
var out := "res://docs/graphics/mockups/out.png"
var frames := 0
var cam: Camera3D
var env: Environment
var sun: DirectionalLight3D
var course: CourseView
var hole: HoleDefinition
var center_pos := Vector3.ZERO


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			level = a.substr(8)
		elif a.begins_with("--hole="):
			hole_id = a.substr(7)
		elif a.begins_with("--view="):
			view = a.substr(7)
		elif a.begins_with("--out="):
			out = a.substr(6)
	hole = HoleDefinition.load_from_file("res://data/holes/%s.json" % hole_id)
	_build_environment()
	course = CourseView.new()
	root.add_child(course)
	course.build(hole)
	_build_camera()
	if level != "before":
		_apply_ground()
	if level.begins_with("tier2"):
		_add_hills()
		_add_billboard_clouds()
		_add_birds()
		_add_contrail()


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 6:
		var img := root.get_viewport().get_texture().get_image()
		var p := out
		if not p.is_absolute_path():
			p = ProjectSettings.globalize_path("res://" + p)
		img.save_png(p)
		print("[MOCK] saved ", p, " ", img.get_size(), " renderer=", RenderingServer.get_current_rendering_method())
		quit(0)
	return false


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	if level == "before":
		# identical to RoundController._build_environment()
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = Color(0.20, 0.42, 0.78)
		psm.sky_horizon_color = Color(0.66, 0.78, 0.90)
		psm.sky_curve = 0.12
		psm.ground_horizon_color = Color(0.45, 0.55, 0.42)
		psm.ground_bottom_color = Color(0.16, 0.24, 0.12)
		psm.sun_angle_max = 25.0
		sky.sky_material = psm
	else:
		var sm := ShaderMaterial.new()
		sm.shader = load(SHADERS + "sky_mock.gdshader")
		sm.set_shader_parameter("noise_tex", WorldTextures.noise_texture())
		if level == "tier1":
			sm.set_shader_parameter("cover", 0.55)
			sm.set_shader_parameter("wind", Vector2(0.13, 0.05))
		elif level == "tier2":
			sm.set_shader_parameter("cover", 0.42)
			sm.set_shader_parameter("wind", Vector2(0.13, 0.05))
		else: # golden hour
			sm.set_shader_parameter("cover", 0.44)
			sm.set_shader_parameter("wind", Vector2(0.13, 0.05))
			sm.set_shader_parameter("top_color", Color(0.17, 0.27, 0.55))
			sm.set_shader_parameter("mid_color", Color(0.55, 0.52, 0.66))
			sm.set_shader_parameter("horizon_color", Color(1.0, 0.74, 0.48))
			sm.set_shader_parameter("sun_color", Color(1.0, 0.62, 0.30))
			sm.set_shader_parameter("cloud_lit", Color(1.0, 0.86, 0.72))
			sm.set_shader_parameter("cloud_shade", Color(0.50, 0.46, 0.62))
			sm.set_shader_parameter("ground_color", Color(0.42, 0.40, 0.30))
		sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.ambient_light_sky_contribution = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.06
	env.fog_enabled = true
	env.fog_light_color = Color(0.74, 0.83, 0.93)
	env.fog_density = 0.00045
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.0
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_blur = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0
	sun.rotation_degrees = Vector3(-38.0, 145.0, 0.0)
	if level != "before":
		# Tier 1+: fog colour follows the sky horizon, a touch more fog for depth, slightly warmer sun.
		env.fog_light_color = Color(0.70, 0.82, 0.94)
		env.fog_density = 0.0009
		env.fog_sky_affect = 0.15
		sun.light_color = Color(1.0, 0.93, 0.80)
	if level.begins_with("tier2"):
		env.glow_enabled = true
		env.glow_intensity = 0.35
		env.glow_strength = 0.9
		env.glow_bloom = 0.04
		env.glow_hdr_threshold = 1.1
	if level == "tier2_golden":
		# Low, warm sun to the left of the view (view bearing is derived from the hole below).
		sun.rotation_degrees = Vector3(-9.0, 200.0, 0.0)
		sun.light_color = Color(1.0, 0.70, 0.42)
		sun.light_energy = 1.7
		env.fog_light_color = Color(0.98, 0.74, 0.55)
		env.fog_density = 0.0016
		env.ambient_light_energy = 0.5
		env.tonemap_exposure = 1.0
	we.environment = env
	root.add_child(we)
	root.add_child(sun)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.05
	cam.far = 3000.0
	root.add_child(cam)
	var tee3 := hole.tee_position(0.0)
	var dir := Vector3(hole.pin.x - hole.tee.x, 0.0, hole.pin.y - hole.tee.y).normalized()
	var pos: Vector3
	var look: Vector3
	if view == "aim":
		pos = tee3 - dir * 6.5 + Vector3.UP * 2.1
		look = tee3 + dir * 16.0 + Vector3.UP * 0.4
	else: # "high": ball-flight style camera, higher and looking out over the course
		pos = tee3 - dir * 11.0 + Vector3.UP * 14.0
		look = tee3 + dir * 70.0 + Vector3.UP * 4.0
	pos.y = maxf(pos.y, hole.terrain_height(pos.x, pos.z) + 1.0)
	cam.look_at_from_position(pos, look, Vector3.UP)
	center_pos = pos
	if level == "tier2_golden":
		# put the low sun roughly in front-left of the camera so the glow is visible
		var yaw := rad_to_deg(atan2(-dir.x, -dir.z)) # direction the camera looks, as sun-light yaw
		sun.rotation_degrees = Vector3(-8.0, yaw + 25.0 + 180.0, 0.0)


# ---------------------------------------------------------------- tier 1+: ground

func _apply_ground() -> void:
	var old: ShaderMaterial = course._terrain_mat
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADERS + "terrain_mock.gdshader")
	for u in old.shader.get_shader_uniform_list():
		var v = old.get_shader_parameter(u["name"])
		if v != null:
			mat.set_shader_parameter(u["name"], v)
	mat.set_shader_parameter("macro_amt", 1.0)
	if level.begins_with("tier2"):
		mat.set_shader_parameter("cloud_shadow", 0.22)
		mat.set_shader_parameter("shadow_wind", Vector2(0.12, 0.05))
	for c in course.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override == old:
			(c as MeshInstance3D).material_override = mat


# ---------------------------------------------------------------- tier 2 additions

func _outer_y() -> float:
	return TerrainBuilder.outer_height(hole)


## Layered ridge-line silhouettes (vertical walls with a noisy top edge, fogged by colour).
func _add_hills() -> void:
	var layers := [
		{"r": 620.0, "h": 70.0, "col": Color(0.20, 0.34, 0.22), "seed": 11},
		{"r": 900.0, "h": 120.0, "col": Color(0.34, 0.50, 0.50), "seed": 23},
		{"r": 1250.0, "h": 200.0, "col": Color(0.52, 0.65, 0.76), "seed": 37},
	]
	if level == "tier2_golden":
		layers[0]["col"] = Color(0.34, 0.30, 0.20)
		layers[1]["col"] = Color(0.62, 0.48, 0.44)
		layers[2]["col"] = Color(0.86, 0.66, 0.58)
	var c := hole.bounds.get_center()
	for L in layers:
		var n := FastNoiseLite.new()
		n.seed = L["seed"]
		n.frequency = 0.9
		n.fractal_octaves = 4
		var segs := 160
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var r: float = L["r"]
		var base := _outer_y() - 6.0
		for i in segs:
			var a0 := TAU * float(i) / segs
			var a1 := TAU * float(i + 1) / segs
			var h0: float = L["h"] * (0.35 + 0.65 * (n.get_noise_1d(float(i) * 0.35) * 0.5 + 0.5))
			var h1: float = L["h"] * (0.35 + 0.65 * (n.get_noise_1d(float(i + 1) * 0.35) * 0.5 + 0.5))
			var p0 := Vector3(c.x + cos(a0) * r, base, c.y + sin(a0) * r)
			var p1 := Vector3(c.x + cos(a1) * r, base, c.y + sin(a1) * r)
			var t0 := p0 + Vector3(0, h0 + 6.0, 0)
			var t1 := p1 + Vector3(0, h1 + 6.0, 0)
			for v in [[p0, 0.0], [t0, 1.0], [p1, 0.0], [p1, 0.0], [t0, 1.0], [t1, 1.0]]:
				st.set_uv(Vector2(float(i) / segs, v[1]))
				st.add_vertex(v[0])
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, fog_disabled;\nuniform vec3 col : source_color;\nuniform vec3 haze : source_color;\nvoid fragment(){ ALBEDO = mix(haze, col, smoothstep(0.0, 0.9, UV.y)); }\n"
		sm.shader = sh
		sm.set_shader_parameter("col", L["col"])
		var hz := Color(0.80, 0.88, 0.95) if level != "tier2_golden" else Color(1.0, 0.80, 0.62)
		sm.set_shader_parameter("haze", hz)
		mi.material_override = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


func _quad(w: float, h: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	return q


func _add_billboard_clouds() -> void:
	var dir := Vector3(hole.pin.x - hole.tee.x, 0.0, hole.pin.y - hole.tee.y).normalized()
	var side := dir.cross(Vector3.UP)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var golden := level == "tier2_golden"
	var cloud_shader: Shader = load(SHADERS + "cloud_billboard.gdshader")
	for i in 16:
		var dist := rng.randf_range(700.0, 1500.0)
		var lateral := rng.randf_range(-0.9, 0.9) * dist
		var alt := rng.randf_range(110.0, 330.0) + dist * 0.06
		var p := center_pos + dir * dist + side * lateral
		p.y = alt
		var mi := MeshInstance3D.new()
		var w := rng.randf_range(260.0, 520.0)
		mi.mesh = _quad(w, w * rng.randf_range(0.36, 0.5))
		var mat := ShaderMaterial.new()
		mat.shader = cloud_shader
		mat.set_shader_parameter("noise_tex", WorldTextures.noise_texture())
		mat.set_shader_parameter("seed", rng.randf())
		mat.set_shader_parameter("opacity", 0.9)
		if golden:
			mat.set_shader_parameter("lit", Color(1.0, 0.82, 0.66))
			mat.set_shader_parameter("shade", Color(0.55, 0.45, 0.58))
		mi.material_override = mat
		mi.position = p
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


func _bird_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# body-centre at origin; wings swept back; UV.y = distance from body (flap amplitude)
	var tris := [
		[Vector3(0, 0, -0.18), 0.0, Vector3(-0.9, 0, 0.12), 1.0, Vector3(0, 0, 0.14), 0.0],
		[Vector3(0, 0, -0.18), 0.0, Vector3(0, 0, 0.14), 0.0, Vector3(0.9, 0, 0.12), 1.0],
	]
	for t in tris:
		st.set_uv(Vector2(0, t[1]))
		st.add_vertex(t[0])
		st.set_uv(Vector2(0, t[3]))
		st.add_vertex(t[2])
		st.set_uv(Vector2(0, t[5]))
		st.add_vertex(t[4])
	return st.commit()


func _add_birds() -> void:
	var dir := Vector3(hole.pin.x - hole.tee.x, 0.0, hole.pin.y - hole.tee.y).normalized()
	var side := dir.cross(Vector3.UP)
	var mesh := _bird_mesh()
	var sh: Shader = load(SHADERS + "bird_mock.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var centre := center_pos + dir * 75.0 + side * 22.0 + Vector3.UP * 4.0
	if view == "aim":
		centre = center_pos + dir * 70.0 + side * 18.0 + Vector3.UP * 14.0
	for i in 9:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mi.material_override = mat
		mi.position = centre + Vector3(rng.randf_range(-14, 14), rng.randf_range(-3, 5), rng.randf_range(-12, 12)) + dir * (-i * 1.5)
		mi.rotation.y = atan2(-dir.x, -dir.z) + rng.randf_range(-0.3, 0.3) + PI * 0.5 * 0.0
		mi.scale = Vector3.ONE * rng.randf_range(0.9, 1.4)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


func _add_contrail() -> void:
	var dir := Vector3(hole.pin.x - hole.tee.x, 0.0, hole.pin.y - hole.tee.y).normalized()
	var side := dir.cross(Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.mesh = _quad(900.0, 9.0)
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADERS + "contrail.gdshader")
	mi.material_override = mat
	var p := center_pos + dir * 1400.0 + side * -250.0
	p.y = center_pos.y + 1100.0
	mi.position = p
	# Quad lies in a plane facing the camera, rotated so the trail runs diagonally across the sky.
	mi.look_at_from_position(p, center_pos, Vector3.UP)
	mi.rotate_object_local(Vector3.FORWARD, deg_to_rad(-14.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

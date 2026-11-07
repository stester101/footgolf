extends Node3D
## Round scene: owns the GameSession, builds the 3D world for each hole, routes touch input
## (drag-to-aim / overhead measuring), drives the camera and syncs the ball visual to the
## simulation every frame.

signal exit_to_menu

const AIM_DEG_PER_PX := 0.22
const AIM_GUIDE_LEN := 28.0

var session: GameSession
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var course: CourseView
var ball_mesh: MeshInstance3D
var aim_line: LineDrawer
var trail_line: LineDrawer
var measure_line: LineDrawer
var rig: CameraRig
var ui: GameUI
var dev_panel: DeveloperPanel
var _canvas: CanvasLayer
var _drag_active := false
var _drag_moved := 0.0
var _tap_place := false
var _built_hole_id := ""
var _last_aim := -1.0
var _last_ball := Vector3.INF
var open_dev_on_start := false
var course_id := "starter"
var _marker: MeshInstance3D
var _marker_pos := Vector3.INF
var _shown_cup_r := -1.0


func _ready() -> void:
	_build_environment()
	course = CourseView.new()
	add_child(course)
	ball_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 16
	sm.rings = 8
	ball_mesh.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.98, 0.98, 0.98)
	bm.roughness = 0.35
	bm.emission_enabled = true
	bm.emission = Color(0.25, 0.25, 0.25)
	ball_mesh.material_override = bm
	add_child(ball_mesh)
	aim_line = LineDrawer.new(Color.WHITE)
	add_child(aim_line)
	trail_line = LineDrawer.new(Color.WHITE)
	add_child(trail_line)
	measure_line = LineDrawer.new(Color.WHITE)
	add_child(measure_line)
	_marker = MeshInstance3D.new()
	var mk := SphereMesh.new()
	mk.radius = 1.0
	mk.height = 2.0
	mk.radial_segments = 12
	mk.rings = 6
	_marker.mesh = mk
	var mkm := StandardMaterial3D.new()
	mkm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mkm.albedo_color = Color(1.0, 0.8, 0.1)
	mkm.no_depth_test = true
	_marker.material_override = mkm
	_marker.visible = false
	add_child(_marker)
	rig = CameraRig.new()
	add_child(rig)
	session = GameSession.new(App.settings.physics, App.repo)
	App.settings.apply_to(session)
	session.hole_started.connect(_on_hole_started)
	session.shot_started.connect(func(_r: ShotRequest) -> void: _on_shot_started())
	session.state_changed.connect(_on_state_changed)
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	ui = GameUI.new()
	_canvas.add_child(ui)
	ui.setup(session)
	ui.markers.camera = rig.cam
	ui.camera_toggle_requested.connect(_toggle_camera)
	ui.aim_here_requested.connect(_aim_at_marker)
	ui.overhead_zoom_requested.connect(func(f: float) -> void:
		if f <= 0.0:
			rig.overhead_fit()
		else:
			rig.overhead_zoom(f, get_viewport().get_visible_rect().size * 0.5))
	ui.main_menu_requested.connect(func() -> void: exit_to_menu.emit())
	ui.developer_requested.connect(toggle_dev_panel)
	DisplayServer.screen_set_keep_on(true)
	session.start_round(App.load_holes(course_id))
	if open_dev_on_start:
		toggle_dev_panel()


func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.20, 0.42, 0.78)
	psm.sky_horizon_color = Color(0.66, 0.78, 0.90)
	psm.sky_curve = 0.12
	psm.ground_horizon_color = Color(0.45, 0.55, 0.42)
	psm.ground_bottom_color = Color(0.16, 0.24, 0.12)
	psm.sun_angle_max = 25.0
	sky.sky_material = psm
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
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_blur = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 160.0
	sun.rotation_degrees = Vector3(-38.0, 145.0, 0.0)
	add_child(sun)


func _on_hole_started(_i: int) -> void:
	if _built_hole_id != session.hole.id + str(session.round_state.current_index):
		course.build(session.hole, session.cfg.cup_radius)
		_built_hole_id = session.hole.id + str(session.round_state.current_index)
	rig.set_hole(session.hole)
	_set_overhead(true)
	trail_line.clear()
	measure_line.clear()
	ui.set_measure("")
	ui.close_all_overlays()
	ui.show_hole_intro()


func _on_state_changed(s: int) -> void:
	if s == ShotTypes.State.AIMING and rig.mode == CameraRig.Mode.OVERHEAD and ui.overhead and not _tap_place:
		if session.current_hole_state().strokes == 0 and session.current_hole_state().shots.is_empty():
			_set_overhead(false)
	if dev_panel != null and is_instance_valid(dev_panel):
		dev_panel._refresh_diag()


func _on_shot_started() -> void:
	_set_overhead(false)
	measure_line.clear()
	ui.set_measure("")
	rig.snap()


func _set_overhead(on: bool) -> void:
	rig.set_mode(CameraRig.Mode.OVERHEAD if on else CameraRig.Mode.BEHIND)
	ui.overhead = on
	# Depth fog adds atmosphere at ground level but would wash out the 600 m-high map view.
	world_env.environment.fog_enabled = not on
	# Perspective shadow cascades don't suit a 600 m-high orthographic map view.
	sun.shadow_enabled = not on
	if not on:
		measure_line.clear()
		ui.set_measure("")
		_marker.visible = false
		_marker_pos = Vector3.INF
		ui.set_marker_ready(false)
	ui.refresh()


func _toggle_camera() -> void:
	if session.is_ball_moving():
		return
	_set_overhead(rig.mode != CameraRig.Mode.OVERHEAD)


func toggle_dev_panel() -> void:
	if dev_panel != null and is_instance_valid(dev_panel):
		dev_panel.queue_free()
		dev_panel = null
		_tap_place = false
		return
	dev_panel = DeveloperPanel.new()
	_canvas.add_child(dev_panel)
	dev_panel.setup(session, App.settings)
	dev_panel.closed.connect(toggle_dev_panel)
	dev_panel.tap_place_toggled.connect(func(on: bool) -> void:
		_tap_place = on
		if on:
			_set_overhead(true))


func _process(delta: float) -> void:
	if session == null or session.hole == null:
		return
	session.advance(delta, App.settings.sim_speed)
	var bpos := session.ball_render_pos()
	var moving := session.is_ball_moving()
	var aim := session.aim_dir()
	rig.update_rig(delta, bpos, aim, moving)
	var cam_pos := rig.cam.global_position
	var dist := cam_pos.distance_to(bpos)
	var vis_r := clampf(dist * 0.011, 0.045, 2.2) if rig.mode == CameraRig.Mode.BEHIND else clampf(rig.cam.size * 0.006, 0.4, 4.0)
	ball_mesh.scale = Vector3.ONE * vis_r
	ball_mesh.position = bpos + Vector3.UP * (vis_r - session.cfg.ball_radius)
	ball_mesh.visible = session.state != ShotTypes.State.HOLE_COMPLETE or moving
	var fwd := -rig.cam.global_transform.basis.z
	ui.camera_yaw = deg_to_rad(Units.dir_to_bearing(fwd))
	if not is_equal_approx(_shown_cup_r, session.cfg.cup_radius):
		_shown_cup_r = session.cfg.cup_radius
		course.set_cup_radius(_shown_cup_r)
	if course.pin_label != null and course.pin_label.visible:
		course.pin_label.visible = false  # the HUD draws the pin distance label now (HudMarkers)
	_update_aim_guide(bpos)
	_update_trail(bpos, moving)


func _update_aim_guide(bpos: Vector3) -> void:
	var show := session.state == ShotTypes.State.AIMING
	aim_line.visible = show
	if not show:
		_last_aim = -1.0
		return
	var over := rig.mode == CameraRig.Mode.OVERHEAD
	var k := clampf(rig.cam.size / 70.0, 1.0, 8.0) if over else 1.0
	var key := session.aim_bearing_deg + k * 1000.0 + session.mode * 100000.0 + session.trajectory * 1000000.0
	if is_equal_approx(_last_aim, key) and _last_ball.is_equal_approx(bpos):
		return
	_last_aim = key
	_last_ball = bpos
	var d := session.aim_dir()
	var length := AIM_GUIDE_LEN * k * (1.6 if over else 1.0)
	var segs: Array = []
	var s := 1.2 * k
	var h := session.hole
	# Caps: 3D arc showing the initial launch path for the chosen trajectory (same guide length,
	# shape independent of the footballer so no stats are revealed). Goals: chevrons on the ground.
	var caps := session.mode == ShotTypes.Mode.CAPS
	var tan_a := tan(deg_to_rad(session.launch_angle_for(session.trajectory)))
	if caps:
		# thin camera-facing line (never giant chevrons near the camera)
		var pts := PackedVector3Array()
		var n := 40
		for i in n + 1:
			var x := length * float(i) / float(n)
			var p := bpos + d * x
			p.y = maxf(bpos.y + _arc_height(x, length, tan_a), h.contact_height(p.x, p.z) + 0.05)
			pts.append(p)
		var col := Color(UiKit.C_TEXT, 0.9)
		aim_line.draw_trail(pts, rig.cam.global_position, 0.0035 * (2.0 if over else 1.0), col)
		_last_aim = -1.0  # camera moves: keep the camera-facing ribbon updated
		return
	while s < length:
		var a := bpos + d * s
		var b := bpos + d * (s + 1.1 * k)
		if caps:
			a.y = bpos.y + _arc_height(s, length, tan_a)
			b.y = bpos.y + _arc_height(s + 1.1 * k, length, tan_a)
			a.y = maxf(a.y, h.contact_height(a.x, a.z) + 0.05)
			b.y = maxf(b.y, h.contact_height(b.x, b.z) + 0.05)
		else:
			a.y = h.contact_height(a.x, a.z) + 0.05
			b.y = h.contact_height(b.x, b.z) + 0.05
		segs.append([a, b])
		s += 2.2 * k
	aim_line.draw_dashes(segs, 0.55 * k, Color(UiKit.C_TEXT, 0.9) if over else Color(UiKit.C_TEXT, 0.75))


## Initial-flight arc: starts at the launch angle and flattens to half that slope at the end.
static func _arc_height(x: float, length: float, tan_a: float) -> float:
	return x * tan_a * (1.0 - x / (4.0 * length))


func _update_trail(bpos: Vector3, moving: bool) -> void:
	if not App.settings.show_trail:
		trail_line.clear()
		return
	if moving and session.sim != null:
		var pts := session.sim.trail.duplicate()
		pts.append(bpos)
		trail_line.draw_trail(pts, rig.cam.global_position, 0.0022, Color(1, 1, 1, 0.8))
	else:
		trail_line.clear()


# ------------------------------------------------------------------ input

var _touches: Dictionary = {}  # index -> position
var _pinch_dist := 0.0


func _unhandled_input(event: InputEvent) -> void:
	if ui.has_overlay():
		_touches.clear()
		return
	var overhead := rig.mode == CameraRig.Mode.OVERHEAD
	if event is InputEventMouseButton and overhead:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			rig.overhead_zoom(1.15, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			rig.overhead_zoom(1.0 / 1.15, mb.position)
	elif event is InputEventMagnifyGesture and overhead:
		var mg := event as InputEventMagnifyGesture
		rig.overhead_zoom(mg.factor, mg.position)
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() == 1:
				_drag_active = true
				_drag_moved = 0.0
			else:
				_drag_moved = 999.0  # multi-touch is never a tap
				_pinch_dist = _pinch_distance()
		else:
			if _touches.size() == 1 and _drag_active and _drag_moved < 12.0 and overhead:
				_overhead_tap(st.position)
			_touches.erase(st.index)
			if _touches.is_empty():
				_drag_active = false
			else:
				_pinch_dist = _pinch_distance()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _drag_active:
			return
		_drag_moved += absf(sd.relative.x) + absf(sd.relative.y)
		_touches[sd.index] = sd.position
		if overhead:
			if _touches.size() >= 2:
				var d := _pinch_distance()
				if _pinch_dist > 1.0 and d > 1.0:
					rig.overhead_zoom(d / _pinch_dist, _pinch_center())
				_pinch_dist = d
				rig.overhead_pan(sd.relative / float(_touches.size()))
			else:
				rig.overhead_pan(sd.relative)
		elif session.state == ShotTypes.State.AIMING and _touches.size() == 1:
			session.set_aim(session.aim_bearing_deg - sd.relative.x * AIM_DEG_PER_PX)


func _pinch_distance() -> float:
	var pts := _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1])


func _pinch_center() -> Vector2:
	var pts := _touches.values()
	if pts.size() < 2:
		return Vector2.ZERO
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5


func _overhead_tap(screen_pos: Vector2) -> void:
	var hit = rig.screen_to_ground(screen_pos)
	if hit == null:
		return
	var p: Vector3 = hit
	if _tap_place:
		var err := session.dev_place_ball(p.x, p.z)
		ui.toast("DEV: ball placed" if err == "" else "DEV: %s" % err)
		return
	_set_marker(p)


func _set_marker(p: Vector3) -> void:
	_marker_pos = p
	var b := session.ball_pos
	var d := Units.horizontal_distance(b, p)
	var a := Vector3(b.x, session.hole.contact_height(b.x, b.z) + 0.3, b.z)
	var c := Vector3(p.x, session.hole.contact_height(p.x, p.z) + 0.3, p.z)
	measure_line.draw_ribbon(PackedVector3Array([a, c]), clampf(rig.cam.size * 0.004, 0.3, 2.0), Color(UiKit.C_TEXT, 0.9))
	var bearing := Units.dir_to_bearing(p - b)
	ui.set_target(Vector3(p.x, session.hole.contact_height(p.x, p.z), p.z), d, Surface.name_of(session.hole.surface_at(p.x, p.z)), bearing)
	ui.set_marker_ready(true)


func _aim_at_marker() -> void:
	if _marker_pos == Vector3.INF:
		ui.toast("Tap the map first to pick a target point")
		return
	if session.state != ShotTypes.State.AIMING:
		return
	var dir := _marker_pos - session.ball_pos
	if Vector2(dir.x, dir.z).length() < 0.5:
		return
	session.set_aim(Units.dir_to_bearing(dir))
	ui.toast("Aim set: %d°" % int(round(session.aim_bearing_deg)))
	_set_marker(_marker_pos)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back()
	elif what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		DisplayServer.screen_set_keep_on(false)


func handle_back() -> void:
	if dev_panel != null and is_instance_valid(dev_panel):
		toggle_dev_panel()
	elif ui.has_overlay():
		if session.state == ShotTypes.State.HOLE_INTRO or session.state == ShotTypes.State.HOLE_COMPLETE or session.state == ShotTypes.State.ROUND_COMPLETE:
			ui.show_pause()
		else:
			ui.close_top_overlay()
	elif rig.mode == CameraRig.Mode.OVERHEAD:
		_set_overhead(false)
	else:
		ui.show_pause()

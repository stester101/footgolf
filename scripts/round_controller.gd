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
	ui.camera_toggle_requested.connect(_toggle_camera)
	ui.main_menu_requested.connect(func() -> void: exit_to_menu.emit())
	ui.developer_requested.connect(toggle_dev_panel)
	session.start_round(App.load_holes())
	if open_dev_on_start:
		toggle_dev_panel()


func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.26, 0.47, 0.78)
	psm.sky_horizon_color = Color(0.70, 0.80, 0.90)
	psm.ground_horizon_color = Color(0.55, 0.62, 0.55)
	psm.ground_bottom_color = Color(0.2, 0.28, 0.18)
	psm.sun_angle_max = 30.0
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.80, 0.88)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 140.0
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	add_child(sun)


func _on_hole_started(_i: int) -> void:
	if _built_hole_id != session.hole.id + str(session.round_state.current_index):
		course.build(session.hole)
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
	if not on:
		measure_line.clear()
		ui.set_measure("")
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
	if course.pin_label != null:
		course.pin_label.text = Units.fmt_distance(Units.horizontal_distance(bpos, session.hole.cup_position()))
	_update_aim_guide(bpos)
	_update_trail(bpos, moving)


func _update_aim_guide(bpos: Vector3) -> void:
	var show := session.state == ShotTypes.State.AIMING
	aim_line.visible = show
	if not show:
		_last_aim = -1.0
		return
	if is_equal_approx(_last_aim, session.aim_bearing_deg) and _last_ball.is_equal_approx(bpos):
		return
	_last_aim = session.aim_bearing_deg
	_last_ball = bpos
	var d := session.aim_dir()
	var segs: Array = []
	var s := 1.2
	var h := session.hole
	while s < AIM_GUIDE_LEN:
		var a := bpos + d * s
		var b := bpos + d * (s + 1.1)
		a.y = h.contact_height(a.x, a.z) + 0.05
		b.y = h.contact_height(b.x, b.z) + 0.05
		segs.append([a, b])
		s += 2.2
	aim_line.draw_dashes(segs, 0.55, Color(1, 1, 1, 0.75))


func _update_trail(bpos: Vector3, moving: bool) -> void:
	if not App.settings.show_trail:
		trail_line.clear()
		return
	if moving and session.sim != null:
		var pts := session.sim.trail.duplicate()
		pts.append(bpos)
		var w := clampf(rig.cam.global_position.distance_to(bpos) * 0.004, 0.04, 0.6)
		trail_line.draw_ribbon(pts, w, Color(1, 1, 1, 0.55))
	elif session.state == ShotTypes.State.AIMING:
		trail_line.clear()


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if ui.has_overlay():
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_drag_active = true
			_drag_moved = 0.0
		else:
			if _drag_active and _drag_moved < 12.0 and rig.mode == CameraRig.Mode.OVERHEAD:
				_overhead_tap(st.position)
			_drag_active = false
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if not _drag_active:
			return
		_drag_moved += absf(sd.relative.x) + absf(sd.relative.y)
		if rig.mode == CameraRig.Mode.BEHIND and session.state == ShotTypes.State.AIMING:
			session.set_aim(session.aim_bearing_deg - sd.relative.x * AIM_DEG_PER_PX)


func _overhead_tap(screen_pos: Vector2) -> void:
	var hit = rig.screen_to_ground(screen_pos)
	if hit == null:
		return
	var p: Vector3 = hit
	if _tap_place:
		var err := session.dev_place_ball(p.x, p.z)
		ui.toast("DEV: ball placed" if err == "" else "DEV: %s" % err)
		return
	var b := session.ball_pos
	var d := Units.horizontal_distance(b, p)
	var a := Vector3(b.x, session.hole.contact_height(b.x, b.z) + 0.3, b.z)
	var c := Vector3(p.x, session.hole.contact_height(p.x, p.z) + 0.3, p.z)
	measure_line.draw_ribbon(PackedVector3Array([a, c]), clampf(rig.cam.size * 0.004, 0.3, 2.0), Color(1.0, 0.8, 0.2, 0.9))
	ui.set_measure("Measured %s from ball (%s)" % [Units.fmt_yards(d), Surface.name_of(session.hole.surface_at(p.x, p.z))])


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		handle_back()


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

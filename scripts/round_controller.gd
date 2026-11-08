extends Node3D
## Round scene: owns the GameSession, builds the 3D world for each hole, routes touch input
## (drag-to-aim / overhead measuring), drives the camera and syncs the ball visual to the
## simulation every frame.

signal exit_to_menu

const AIM_DEG_PER_PX := 0.22
const AIM_GUIDE_LEN := 3.2
const TRAJ_DRAG_PX := 48.0

var session: GameSession
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var _sky_mat: ShaderMaterial  # High graphics only (null = Low: procedural sky)
var course: CourseView
var ball_mesh: MeshInstance3D
var tee_peg: MeshInstance3D
var aim_line: LineDrawer
var trail_line: LineDrawer
var measure_line: LineDrawer
var rig: CameraRig
var ui: GameUI
var dev_panel: DeveloperPanel
var _canvas: CanvasLayer
var _drag_active := false
var _traj_accum := 0.0
var _drag_moved := 0.0
var _tap_place := false
var _built_hole_id := ""
var _last_aim := -1.0
var _last_ball := Vector3.INF
## Hole-out drop: the ball rolls in from the rim with the shot's line, then falls into the cup.
const DROP_TIME := 0.9
var _drop_t := -1.0
var _drop_dir := Vector3.FORWARD
var _drop_result: ShotResult = null


static func _drop_pos(cup: Vector3, dir: Vector3, cup_r: float, t: float) -> Vector3:
	var rim := Vector3(cup.x, cup.y, cup.z) + dir * (cup_r * 1.6)
	var roll := clampf(t / 0.45, 0.0, 1.0)
	var fall := clampf((t - 0.40) / 0.50, 0.0, 1.0)
	var xz := Vector3(rim.x, 0.0, rim.z).lerp(Vector3(cup.x, 0.0, cup.z), 1.0 - (1.0 - roll) * (1.0 - roll))
	var y := lerpf(cup.y + 0.02, cup.y - 0.06, fall * fall)
	return Vector3(xz.x, y, xz.z)
var open_dev_on_start := false
var course_id := "starter"
var mulligans := 0
var players := 1
## Frozen Round Setup rules (set by Main before the scene is added).
var rules: RoundConfig
var _marker: MeshInstance3D
var _marker_pos := Vector3.INF
var _shown_cup_r := -1.0
# Next hole prepared incrementally behind the hole summary (loading bar).
const PRELOAD_BUDGET_USEC := 9000
const PRELOAD_TIMEOUT_MS := 20000
var _pending: CourseView
var _pending_key := ""
var _pending_t0 := 0


func _ready() -> void:
	HoleAtmosphere.high_quality = App.settings.graphics_quality == 1
	HoleAtmosphere.glow = HoleAtmosphere.high_quality and App.settings.graphics_glow
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
	tee_peg = MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.5
	pm.bottom_radius = 0.18
	pm.height = 1.0
	pm.radial_segments = 8
	tee_peg.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.95, 0.86, 0.62)
	pmat.roughness = 0.6
	tee_peg.material_override = pmat
	tee_peg.visible = false
	add_child(tee_peg)
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
	if App.online.started:
		var net := OnlineSession.new(PhysicsConfig.new(), App.repo)
		net.configure(App.online)
		# the host's frozen setup (RoundConfig rules, physics incl. cup, wind) is applied identically on every phone
		rules = OnlineSession.apply_setup(net, App.online.setup)
		session = net
	else:
		# Non-developer rounds get a private physics copy so the frozen cup size never edits Settings.
		var round_cfg := App.settings.physics
		if not open_dev_on_start:
			round_cfg = PhysicsConfig.new()
			round_cfg.apply_dict(App.settings.physics.to_dict())
		session = GameSession.new(round_cfg, App.repo)
		App.settings.apply_to(session)
		session.cfg = round_cfg
		session.apply_rules(rules)
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
	# after ui.setup(): the summary card exists before preloading reports progress into it
	session.hole_completed.connect(func(_hs: HoleState) -> void: _start_preload())
	DisplayServer.screen_set_keep_on(true)
	var defs := App.load_holes(course_id)
	var seed_value := -1
	if App.online.started:
		seed_value = int(App.online.setup.seed)
		for h in defs:
			h.par = int(App.online.setup.pars.get(h.id, h.par))
	else:
		App.telemetry.attach(session, course_id, String(App.course_info(course_id).get("name", course_id)))
	session.start_round(defs, seed_value, rules.pool_rule(), mulligans, players)
	for i in mini(players, MainMenu.player_names.size()):
		session.player_names[i] = String(MainMenu.player_names[i])
		session.profile_ids.append(String(MainMenu.player_profile_ids[i]))
	if App.online.started:
		for i in App.online.players.size():
			session.player_names[i] = String(App.online.players[i].name)
		_add_online_status()
	if open_dev_on_start:
		toggle_dev_panel()


func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	if HoleAtmosphere.high_quality:
		_sky_mat = ShaderMaterial.new()
		_sky_mat.shader = load("res://assets/shaders/sky.gdshader")
		_sky_mat.set_shader_parameter("noise_tex", WorldTextures.noise_texture())
		sky.sky_material = _sky_mat
	else:
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
	if HoleAtmosphere.high_quality:
		env.fog_density = 0.0007
		env.fog_sky_affect = 0.15
	if HoleAtmosphere.glow:
		# optional subtle bloom (one extra post pass): only the brightest highlights bleed a little
		env.glow_enabled = true
		env.glow_intensity = 0.35
		env.glow_strength = 0.8
		env.glow_bloom = 0.0
		env.glow_hdr_threshold = 1.15
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
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


## High graphics: per-hole sun direction/colour, sky colours and a fog tint matching the horizon.
func _apply_atmosphere(hole: HoleDefinition) -> void:
	if _sky_mat == null:
		return
	var a := HoleAtmosphere.for_hole(hole)
	var sd: Vector3 = a["sun_dir"]
	_sky_mat.set_shader_parameter("sun_dir", sd)
	_sky_mat.set_shader_parameter("top_color", a["top"])
	_sky_mat.set_shader_parameter("mid_color", a["mid"])
	_sky_mat.set_shader_parameter("horizon_color", a["horizon"])
	_sky_mat.set_shader_parameter("sun_color", a["sun"])
	_sky_mat.set_shader_parameter("cover", a["cover"])
	_sky_mat.set_shader_parameter("offset", a["offset"])
	sun.basis = Basis.looking_at(-sd, Vector3.UP)
	sun.light_color = a["light"]
	sun.light_energy = a["energy"]
	world_env.environment.fog_light_color = a["fog"]


## Visual-only wind (flag, trees, grass, cloud shadows) follows the same wind as the HUD chip.
func _apply_wind() -> void:
	if course != null and session != null and session.hole != null:
		var w := session.wind_vector()
		course.set_wind(Vector2(w.x, w.z))


func _hole_key(index: int) -> String:
	return (session.hole_defs[index] as HoleDefinition).id + str(index)


## Start building the upcoming hole in a hidden CourseView, a slice per frame (see _process).
func _start_preload() -> void:
	_cancel_preload()
	var idx := session.round_state.upcoming_index()
	if idx < 0 or idx >= session.hole_defs.size():
		ui.set_next_hole_progress(1.0)
		return
	_pending = CourseView.new()
	_pending.name = "PendingCourse"
	_pending.visible = false
	add_child(_pending)
	_pending.begin_build(session.hole_defs[idx], session.cfg.cup_radius)
	_pending_key = _hole_key(idx)
	_pending_t0 = Time.get_ticks_msec()
	ui.set_next_hole_progress(0.0)


func _cancel_preload() -> void:
	if _pending != null and is_instance_valid(_pending):
		_pending.queue_free()
	_pending = null
	_pending_key = ""


func _step_preload() -> void:
	if _pending == null or _pending.is_built():
		return
	if Time.get_ticks_msec() - _pending_t0 > PRELOAD_TIMEOUT_MS:
		# never leave the player stuck behind a greyed button: give up, build on demand instead
		push_warning("next hole preload timed out; building on demand")
		_cancel_preload()
		ui.set_next_hole_progress(1.0)
		return
	_pending.build_step(PRELOAD_BUDGET_USEC)
	ui.set_next_hole_progress(_pending.progress)


func _on_hole_started(_i: int) -> void:
	var key := session.hole.id + str(session.round_state.current_index)
	if _pending != null and _pending_key == key:
		if not _pending.is_built():
			_pending.build_step(1000000000)
		course.visible = false
		course.queue_free()
		course = _pending
		course.name = "Course"
		course.visible = true
		_pending = null
		_pending_key = ""
		_built_hole_id = key
		_shown_cup_r = -1.0
	else:
		_cancel_preload()
	if _built_hole_id != key:
		course.build(session.hole, session.cfg.cup_radius)
		_built_hole_id = key
	_apply_atmosphere(session.hole)
	_apply_wind()
	rig.set_hole(session.hole)
	_set_overhead(true)
	trail_line.clear()
	measure_line.clear()
	ui.set_measure("")
	ui.close_all_overlays()
	ui.show_hole_intro()


func _on_state_changed(s: int) -> void:
	if s == ShotTypes.State.AIMING and HoleAtmosphere.high_quality:
		_apply_wind()  # the developer panel can change the wind between shots
	if session is OnlineSession and ui != null and s in [ShotTypes.State.AIMING, ShotTypes.State.ROUND_COMPLETE]:
		ui.close_all_overlays()
	if s == ShotTypes.State.AIMING and rig.mode == CameraRig.Mode.OVERHEAD and ui.overhead and not _tap_place:
		if session.current_hole_state().strokes == 0 and session.current_hole_state().shots.is_empty():
			_set_overhead(false)
	if dev_panel != null and is_instance_valid(dev_panel):
		dev_panel._refresh_diag()


func _on_shot_started() -> void:
	_set_overhead(false)
	measure_line.clear()
	ui.set_measure("")
	if session.current_request != null and session.current_request.style == ShotTypes.Style.FLIGHT:
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
	if session is OnlineSession:
		ui.toast("Developer controls are disabled in online rounds.")
		return
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
	_step_preload()
	session.advance(delta, App.settings.sim_speed * (4.0 if ui.fast_forward else 1.0))
	var bpos := session.ball_render_pos()
	var moving := session.is_ball_moving()
	var aim := _watched_aim().get("dir", session.aim_dir()) as Vector3
	rig.update_rig(delta, bpos, aim, moving,
		moving and session.sim != null and session.sim.phase == BallSim.Phase.ROLL)
	var cam_pos := rig.cam.global_position
	var dist := cam_pos.distance_to(bpos)
	var vis_r := clampf(dist * 0.011, 0.045, 2.2) if rig.mode == CameraRig.Mode.BEHIND else clampf(rig.cam.size * 0.006, 0.4, 4.0)
	ball_mesh.scale = Vector3.ONE * vis_r
	var draw_pos := bpos
	if _drop_result == null or session.last_result != _drop_result:
		if session.last_result != null and session.last_result.holed:
			_drop_result = session.last_result
			_drop_t = 0.0
			_drop_dir = Units.bearing_to_dir(session.last_result.aim_bearing_deg)
			_cup_celebrate(session.hole.cup_position(), session.current_hole_state())
	if _drop_t >= 0.0 and _drop_t < DROP_TIME:
		draw_pos = _drop_pos(session.hole.cup_position(), _drop_dir, session.cfg.cup_radius, _drop_t)
		_drop_t += get_process_delta_time()
	# first shot of a hole (and any shot from the tee box): the ball sits on a tee peg
	var on_tee := not moving and not (_drop_t >= 0.0 and _drop_t < DROP_TIME) and session.current_lie() == Surface.Type.TEE \
			and session.state != ShotTypes.State.HOLE_COMPLETE and rig.mode == CameraRig.Mode.BEHIND
	var peg_h := vis_r * 0.9 if on_tee else 0.0
	tee_peg.visible = on_tee
	if on_tee:
		tee_peg.scale = Vector3(vis_r * 0.7, peg_h, vis_r * 0.7)
		tee_peg.position = draw_pos + Vector3.DOWN * session.cfg.ball_radius + Vector3.UP * (peg_h * 0.5)
	ball_mesh.position = draw_pos + Vector3.UP * (vis_r - session.cfg.ball_radius + peg_h)
	ball_mesh.visible = session.state != ShotTypes.State.HOLE_COMPLETE or moving
	var fwd := -rig.cam.global_transform.basis.z
	ui.camera_yaw = deg_to_rad(Units.dir_to_bearing(fwd))
	if not is_equal_approx(_shown_cup_r, session.cfg.cup_radius):
		_shown_cup_r = session.cfg.cup_radius
		course.set_cup_radius(_shown_cup_r)
	course.update_view(rig.cam)
	course.set_grass_visible(rig.mode == CameraRig.Mode.BEHIND)
	if not moving and session.state != ShotTypes.State.HOLE_COMPLETE:
		course.place_grass(session.ball_pos)
	if course.pin_label != null and course.pin_label.visible:
		course.pin_label.visible = false  # the HUD draws the pin distance label now (HudMarkers)
	_update_aim_guide(bpos)
	_update_trail(bpos, moving)


## Online spectators see the active player's live aim (cosmetic preview, never authoritative).
## Returns {} when this phone is not watching a fresh preview.
func _watched_aim() -> Dictionary:
	if session is OnlineSession:
		var p := (session as OnlineSession).watch_preview()
		if not p.is_empty():
			return {"dir": Units.bearing_to_dir(float(p.aim)), "style": int(p.style), "traj": int(p.traj)}
	return {}


func _update_aim_guide(bpos: Vector3) -> void:
	var watched := _watched_aim()
	var show := session.state == ShotTypes.State.AIMING and session.rules.show_aim_arrow
	if session is OnlineSession and (session as OnlineSession).is_spectating() and watched.is_empty():
		show = false  # no fresh preview from the active player: do not show a stale local arrow
	aim_line.visible = show
	if not show:
		return
	var over := rig.mode == CameraRig.Mode.OVERHEAD
	var k := clampf(rig.cam.size / 70.0, 1.0, 8.0) if over else 1.0
	var d: Vector3 = watched.get("dir", session.aim_dir())
	var style_now: int = watched.get("style", session.style)
	var traj_now: int = watched.get("traj", session.trajectory)
	var start := bpos + Vector3.UP * (0.06 * k)
	# smaller when putting and as the ball nears the pin
	var g := 0.5 if style_now == ShotTypes.Style.ROLL else clampf(session.distance_to_pin_m() / 40.0, 0.55, 1.0)
	var finish := bpos + d * AIM_GUIDE_LEN * g * k
	if style_now == ShotTypes.Style.FLIGHT:
		finish.y = start.y + minf(AIM_GUIDE_LEN * g * tan(deg_to_rad(session.launch_angle_for(traj_now))), AIM_GUIDE_LEN * g) * k
	else:
		finish.y = session.hole.contact_height(finish.x, finish.z) + 0.08 * k
	aim_line.draw_arrow(start, finish, rig.cam.global_position, 0.35 * g * k,
		Color(UiKit.C_TEXT, 0.45))


func _update_trail(bpos: Vector3, moving: bool) -> void:
	if not session.rules.show_trail:
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
var _mouse_drag_active := false


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
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_mouse_drag_active = (event as InputEventMouseButton).pressed
	elif event is InputEventMouseMotion and _mouse_drag_active and _touches.is_empty() \
			and not overhead and session.state == ShotTypes.State.AIMING:
		session.set_aim(session.aim_bearing_deg - (event as InputEventMouseMotion).relative.x * AIM_DEG_PER_PX)
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
				_traj_accum = 0.0
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
			# trial: drag up/down (mostly vertical movement) steps the trajectory Punch / Low / Standard / High
			if App.settings.drag_trajectory and session.style == ShotTypes.Style.FLIGHT and absf(sd.relative.y) > absf(sd.relative.x):
				_traj_accum -= sd.relative.y
				while absf(_traj_accum) >= TRAJ_DRAG_PX:
					var step := 1 if _traj_accum > 0.0 else -1
					_traj_accum -= step * TRAJ_DRAG_PX
					session.set_trajectory(clampi(session.trajectory + step, 0, 3))


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


func _add_online_status() -> void:
	var label := UiKit.label("", 17, UiKit.C_CYAN)
	label.position = Vector2(20, 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(label)
	var update := func() -> void:
		if not is_instance_valid(label): return
		if App.online.paused:
			label.text = App.online.status
		else:
			label.text = "ONLINE · %s · %s" % [App.online.code,
				"Your turn" if App.online.seat == session.turn else "Watching " + session.active_name()]
	App.online.changed.connect(update)
	session.selection_changed.connect(update)
	label.tree_exiting.connect(func() -> void:
		if App.online.changed.is_connected(update): App.online.changed.disconnect(update))
	update.call()

func _exit_tree() -> void:
	if session is OnlineSession:
		(session as OnlineSession).dispose()


## Gentle hole-out effect at the cup: a soft expanding ring plus a small burst of sparks (a few more
## for an eagle or better). Cheap CPU particles, a couple of seconds, then everything frees itself.
func _cup_celebrate(cup: Vector3, hs: HoleState) -> void:
	var big := hs.complete and (hs.score() == 1 or hs.relative_to_par() <= -2)
	var k := clampf(rig.cam.global_position.distance_to(cup) / 15.0, 1.0, 6.0) if rig.mode == CameraRig.Mode.BEHIND else clampf(rig.cam.size * 0.02, 1.0, 8.0)
	var root := Node3D.new()
	root.position = cup + Vector3.UP * 0.03
	add_child(root)
	# ring
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.92
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 6
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(1.0, 0.93, 0.6, 0.75)
	ring.material_override = rm
	ring.scale = Vector3(session.cfg.cup_radius, session.cfg.cup_radius, session.cfg.cup_radius)
	root.add_child(ring)
	var end_r := maxf(session.cfg.cup_radius * 1.5, 0.5) * k
	var tw := create_tween()
	tw.tween_property(ring, "scale", Vector3(end_r, end_r, end_r), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(rm, "albedo_color:a", 0.0, 0.9)
	# sparks
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.emitting = true
	ps.amount = 36 if big else 18
	ps.lifetime = 1.0
	ps.explosiveness = 0.9
	ps.direction = Vector3.UP
	ps.spread = 35.0
	ps.initial_velocity_min = 1.2 * sqrt(k)
	ps.initial_velocity_max = 2.8 * sqrt(k)
	ps.gravity = Vector3(0, -4.0, 0)
	ps.scale_amount_min = 0.5
	ps.scale_amount_max = 1.0
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.05) * k
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = Color(1.0, 0.9, 0.5)
	pm.vertex_color_use_as_albedo = true
	qm.material = pm
	ps.mesh = qm
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.65, 1.0))
	grad.set_color(1, Color(1.0, 0.8, 0.3, 0.0))
	ps.color_ramp = grad
	root.add_child(ps)
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if is_instance_valid(root):
			root.queue_free())

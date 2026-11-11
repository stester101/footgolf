class_name FxDirector
extends Node3D
## Presentation-only game feel for a round: watches the running BallSim (read-only) and turns its
## events into sound (Feedback.sfx -> SfxPlayer), impact particles, camera moments and outcome
## callouts. Never changes physics, scoring or consumption. Outcome callouts and crowd reactions are
## only triggered from `shot_resolved`, i.e. after the ball has stopped (stats-hidden rule).
## Must be a CHILD of the round controller so its _process runs after session.advance().

var session: GameSession
var rig: CameraRig
var sfx_player: SfxPlayer
## Optional: GameUI, so a callout gets out of the way when a full overlay (hole complete, pause) opens.
var ui: GameUI

var _sim: BallSim
var _bounces := 0
var _coll_n := 0
var _phase := -1
var _prev_vel := Vector3.ZERO
var _rim_cool := 0.0
var _pin_hit := false
var _rim_hit := false
var _callout_layer: CanvasLayer
var _mats: Dictionary = {}

## Landing surface -> sound cue / particle kind.
const LAND_CUE := {
	Surface.Type.TEE: "land_fairway", Surface.Type.FAIRWAY: "land_fairway", Surface.Type.ROUGH: "land_rough",
	Surface.Type.FRINGE: "land_green", Surface.Type.GREEN: "land_green", Surface.Type.BUNKER: "land_sand",
}


func setup(p_session: GameSession, p_rig: CameraRig, p_ui: GameUI = null) -> void:
	session = p_session
	rig = p_rig
	ui = p_ui
	sfx_player = SfxPlayer.new()
	add_child(sfx_player)
	Feedback.volume = App.settings.sfx_volume
	_callout_layer = CanvasLayer.new()
	_callout_layer.layer = 5
	add_child(_callout_layer)
	session.shot_started.connect(_on_shot_started)
	session.shot_resolved.connect(_on_shot_resolved)


func _muted() -> bool:
	return App.settings.sound_muted


func _reduced() -> bool:
	return App.settings.reduced_motion


func _sfx(cue: String, strength: float = 1.0, pitch: float = 1.0) -> void:
	Feedback.sfx(cue, _muted(), strength, pitch)


# ------------------------------------------------------------------ shot start (kick)

func _on_shot_started(req: ShotRequest) -> void:
	_watch(session.sim)
	if _sim == null:
		return
	var speed := _sim.vel.length()
	if req != null and req.style == ShotTypes.Style.ROLL:
		_sfx("putt", clampf(0.45 + speed / 12.0, 0.45, 1.0))
		return
	# three coarse bands so the sound follows the strike without reading as a precise readout
	var cue := "kick_soft" if speed < 12.0 else ("kick" if speed < 24.0 else "kick_hard")
	_sfx(cue, 1.0, randf_range(0.96, 1.04))
	if rig != null:
		rig.add_shake(0.04 if cue == "kick_soft" else (0.07 if cue == "kick" else 0.1))


func _watch(s: BallSim) -> void:
	_sim = s
	_bounces = 0
	_coll_n = 0
	_phase = s.phase if s != null else -1
	_prev_vel = s.vel if s != null else Vector3.ZERO
	_pin_hit = false
	_rim_hit = false


# ------------------------------------------------------------------ in-motion events (polled)

func _process(delta: float) -> void:
	_rim_cool = maxf(0.0, _rim_cool - delta)
	if ui != null and ui.has_overlay() and _callout_layer != null and _callout_layer.get_child_count() > 0:
		for c in _callout_layer.get_children():
			c.queue_free()
	if session == null or session.sim == null:
		return
	if session.sim != _sim:
		_watch(session.sim)
	var s := _sim
	if s.bounces > _bounces:
		var n := s.bounces - _bounces
		_bounces = s.bounces
		_on_landing(s.pos, absf(_prev_vel.y), n)
	while _coll_n < s.collisions.size():
		var c: Dictionary = s.collisions[_coll_n]
		_coll_n += 1
		_on_collision(String(c.get("type", "")), c.get("pos", s.pos))
	if s.phase != _phase:
		_phase = s.phase
		if _phase == BallSim.Phase.HAZARD and s.hazard == "WATER":
			_sfx("splash")
			_burst(s.hazard_pos, "splash", 1.0)
		elif _phase == BallSim.Phase.HOLED:
			_sfx("cup")
			if rig != null and session.hole != null:
				rig.cup_moment(session.hole.cup_position())
	_prev_vel = s.vel


func _on_landing(p: Vector3, impact_vy: float, count: int) -> void:
	if session.hole == null:
		return
	var surf := session.hole.surface_at(p.x, p.z)
	var cue := String(LAND_CUE.get(surf, ""))
	if cue == "":
		return
	var strength := clampf(impact_vy / 14.0, 0.0, 1.0)
	if count > 1:
		strength = maxf(strength, 0.3)  # several contacts in one frame (fast-forward)
	if strength < 0.06:
		return
	_sfx(cue, 0.35 + strength * 0.75, randf_range(0.93, 1.07))
	if impact_vy > 3.0:
		_burst(p, "sand" if surf == Surface.Type.BUNKER else ("green" if surf in [Surface.Type.GREEN, Surface.Type.FRINGE] else "turf"), strength)
		if rig != null and impact_vy > 12.0:
			rig.add_shake(0.05)


func _on_collision(kind: String, p: Vector3) -> void:
	match kind:
		"pin":
			_pin_hit = true
			_sfx("flag")
		"rim", "cup_wall":
			_rim_hit = true
			if _rim_cool <= 0.0:
				_rim_cool = 0.12
				_sfx("rim", 0.7)
		"trunk":
			_sfx("tree")
		"canopy":
			_sfx("tree", 0.5, 1.2)


# ------------------------------------------------------------------ result (ball stopped)

func _on_shot_resolved(r: ShotResult) -> void:
	if r == null:
		return
	var hs := session.current_hole_state()
	if r.holed and hs != null and hs.complete:
		var rel := hs.relative_to_par()
		var ace := hs.strokes == 1 and hs.penalties == 0
		if ace or rel <= -1:
			_sfx("cheer")
			_sfx("applause", 0.8)
		elif rel == 0:
			_sfx("applause", 0.8)
		else:
			_sfx("applause", 0.4)
		_callout(score_callout(hs.strokes, hs.penalties, rel))
	elif r.penalty > 0:
		_sfx("groan", 0.8)
		_callout(["In the water" if r.hazard == "WATER" else "Out of bounds", "bad"])
	elif _rim_hit and session.hole != null and session.hole.has_cup \
			and Units.horizontal_distance(r.final_pos, session.hole.cup_position()) < 2.0:
		_sfx("groan", 0.6)
		_callout(["Lipped out!", "near"])
	elif _pin_hit:
		_callout(["Off the flagstick!", "near"])


## [text, tone] for a finished hole. Tones: ace, eagle, birdie, par, over.
static func score_callout(strokes: int, penalties: int, rel: int) -> Array:
	if strokes == 1 and penalties == 0:
		return ["Hole in one!", "ace"]
	match rel:
		-3:
			return ["Albatross!", "ace"]
		-2:
			return ["Eagle!", "eagle"]
		-1:
			return ["Birdie!", "birdie"]
		0:
			return ["Par", "par"]
		1:
			return ["Bogey", "over"]
		2:
			return ["Double bogey", "over"]
	if rel < -3:
		return ["%d under par!" % -rel, "ace"]
	return ["+%d" % rel, "over"]


const TONE_COLOR := {
	"ace": Color(1.0, 0.82, 0.25), "eagle": Color(1.0, 0.86, 0.35), "birdie": Color(0.5, 0.92, 1.0),
	"par": Color(1, 1, 1), "over": Color(0.85, 0.88, 0.92), "bad": Color(1.0, 0.55, 0.45), "near": Color(1.0, 0.93, 0.7),
}


## Big outcome text in the upper third, a quick pop then fade. Reduced motion: fade only.
func _callout(spec: Array) -> void:
	if _callout_layer == null or spec.size() < 2:
		return
	for c in _callout_layer.get_children():
		c.queue_free()
	var tone := String(spec[1])
	var big := tone in ["ace", "eagle", "birdie"]
	var l := Label.new()
	l.text = String(spec[0])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", UiKit.font_semi())
	l.add_theme_font_size_override("font_size", 72 if big else 52)
	l.add_theme_color_override("font_color", TONE_COLOR.get(tone, Color.WHITE))
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.04, 0.85))
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.anchor_top = 0.24
	l.anchor_bottom = 0.24
	l.offset_top = -60
	l.offset_bottom = 60
	l.name = "Callout"
	_callout_layer.add_child(l)
	l.pivot_offset = Vector2(get_viewport().get_visible_rect().size.x * 0.5, 60)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	if _reduced():
		tw.tween_property(l, "modulate:a", 1.0, 0.2)
	else:
		l.scale = Vector2(0.55, 0.55)
		tw.tween_property(l, "modulate:a", 1.0, 0.15)
		tw.parallel().tween_property(l, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.5 if big else 1.1)
	tw.tween_property(l, "modulate:a", 0.0, 0.45)
	tw.tween_callback(l.queue_free)


## Text of the visible callout ("" if none); used by tests and the smoke driver.
func current_callout() -> String:
	if _callout_layer == null:
		return ""
	for c in _callout_layer.get_children():
		if c is Label and not c.is_queued_for_deletion():
			return (c as Label).text
	return ""


# ------------------------------------------------------------------ particles

func _mat(kind: String) -> StandardMaterial3D:
	if _mats.has(kind):
		return _mats[kind]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	_mats[kind] = m
	return m


## One-shot impact burst: turf chunks, green dew, sand spray or a water splash (+ ripple ring).
## Skipped with reduced motion. Sizes scale with camera distance so it reads from the chase view.
func _burst(p: Vector3, kind: String, strength: float) -> void:
	if _reduced() or rig == null:
		return
	var k := clampf(rig.cam.global_position.distance_to(p) / 15.0, 1.0, 6.0) if rig.mode == CameraRig.Mode.BEHIND \
			else clampf(rig.cam.size * 0.02, 1.0, 8.0)
	var root := Node3D.new()
	root.position = p + Vector3.UP * 0.03
	add_child(root)
	var ps := CPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 0.95
	ps.direction = Vector3.UP
	ps.scale_amount_min = 0.6
	ps.scale_amount_max = 1.2
	var c0: Color
	var c1: Color
	var size := 0.06
	match kind:
		"sand":
			ps.amount = int(24 + strength * 30)
			ps.lifetime = 0.9
			ps.spread = 55.0
			ps.initial_velocity_min = 0.8
			ps.initial_velocity_max = 2.4 + strength * 2.0
			ps.gravity = Vector3(0, -6.0, 0)
			ps.damping_min = 1.0
			ps.damping_max = 2.0
			c0 = Color(0.93, 0.83, 0.6, 0.95)
			c1 = Color(0.9, 0.8, 0.58, 0.0)
			size = 0.07
		"splash":
			ps.amount = 44
			ps.lifetime = 1.1
			ps.spread = 22.0
			ps.initial_velocity_min = 2.0
			ps.initial_velocity_max = 5.0
			ps.gravity = Vector3(0, -9.0, 0)
			c0 = Color(0.92, 0.97, 1.0, 0.95)
			c1 = Color(0.6, 0.8, 1.0, 0.0)
			size = 0.08
			_ripple(root, k)
		"green":
			ps.amount = int(6 + strength * 8)
			ps.lifetime = 0.5
			ps.spread = 40.0
			ps.initial_velocity_min = 0.5
			ps.initial_velocity_max = 1.5
			ps.gravity = Vector3(0, -8.0, 0)
			c0 = Color(0.75, 0.95, 0.75, 0.8)
			c1 = Color(0.6, 0.9, 0.6, 0.0)
			size = 0.04
		_:
			ps.amount = int(10 + strength * 16)
			ps.lifetime = 0.8
			ps.spread = 35.0
			ps.initial_velocity_min = 1.0
			ps.initial_velocity_max = 2.0 + strength * 2.5
			ps.gravity = Vector3(0, -9.8, 0)
			c0 = Color(0.34, 0.52, 0.2, 1.0)
			c1 = Color(0.36, 0.27, 0.16, 0.0)
	ps.initial_velocity_min *= sqrt(k)
	ps.initial_velocity_max *= sqrt(k)
	ps.gravity *= sqrt(k)
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size) * k
	qm.material = _mat("p")
	ps.mesh = qm
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	ps.color_ramp = g
	root.add_child(ps)
	ps.emitting = true
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if is_instance_valid(root):
			root.queue_free())


func _ripple(root: Node3D, k: float) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 24
	tm.ring_segments = 6
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.9, 0.96, 1.0, 0.7)
	ring.material_override = rm
	ring.scale = Vector3.ONE * 0.2 * k
	root.add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3(1.6, 1.0, 1.6) * k, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(rm, "albedo_color:a", 0.0, 1.2)

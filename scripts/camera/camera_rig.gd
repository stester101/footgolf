class_name CameraRig
extends Node3D
## Behind-ball aiming camera, smooth follow during motion, and tactical overhead view.

enum Mode { BEHIND, OVERHEAD }

var cam := Camera3D.new()
var mode: int = Mode.BEHIND
var hole: HoleDefinition
## Accessibility: follow the ball tightly instead of sweeping behind it.
var reduced_motion := false
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _initialised := false
var _chase_dir := Vector3(0, 0, 1)


func _ready() -> void:
	cam.fov = 68.0
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.near = 0.05
	cam.far = 3000.0
	add_child(cam)
	cam.current = true


func set_hole(h: HoleDefinition) -> void:
	hole = h
	_initialised = false
	_cup_t = 0.0
	_cup_hold = false
	_ball_prev = Vector3.INF


func set_mode(m: int) -> void:
	if mode == m:
		return
	mode = m
	_initialised = false
	if mode == Mode.OVERHEAD:
		_apply_overhead()
	else:
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE


func toggle_mode() -> void:
	set_mode(Mode.OVERHEAD if mode == Mode.BEHIND else Mode.BEHIND)


func _apply_overhead() -> void:
	if hole == null:
		return
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var pts: Array[Vector2] = [hole.tee, hole.pin]
	for seg in hole.fairway:
		pts.append(seg["p0"])
		pts.append(seg["p1"])
	var up2 := (hole.pin - hole.tee).normalized()
	var side2 := Vector2(-up2.y, up2.x)
	var center := (hole.tee + hole.pin) * 0.5
	var max_along := 0.0
	var max_side := 0.0
	for p in pts:
		max_along = maxf(max_along, absf((p - center).dot(up2)))
		max_side = maxf(max_side, absf((p - center).dot(side2)))
	var pad := float(hole.camera.get("overhead_padding", 1.15))
	var vp := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(720, 1280)
	var aspect := vp.x / maxf(vp.y, 1.0)
	# The top HUD and bottom panel cover roughly 45% of the screen: size the view so the whole hole
	# fits in the free middle band (zoom in from there).
	cam.size = maxf((max_along * 2.0 + 30.0) * pad, (max_side * 2.0 + 50.0) / maxf(aspect, 0.1)) * 1.55
	var c3 := Vector3(center.x, hole.terrain_height(center.x, center.y), center.y)
	cam.global_transform = Transform3D(Basis(), c3 + Vector3(0, 600, 0))
	cam.look_at(c3, Vector3(up2.x, 0, up2.y))
	_fit_size = cam.size
	_fit_pos = cam.global_position


# ------------------------------------------------------------------ overhead pan / zoom

var _fit_size := 300.0
var _fit_pos := Vector3.ZERO
const MIN_OVERHEAD_SIZE := 25.0


func _units_per_px() -> float:
	var vp := get_viewport().get_visible_rect().size
	return cam.size / maxf(vp.y, 1.0)  # KEEP_HEIGHT: size = visible height in metres


## Drag the map: content follows the finger.
func overhead_pan(delta_px: Vector2) -> void:
	if mode != Mode.OVERHEAD:
		return
	var upp := _units_per_px()
	var b := cam.global_transform.basis
	var move := -b.x * delta_px.x * upp + b.y * delta_px.y * upp
	move.y = 0.0
	cam.global_position += move
	_clamp_overhead()


## Zoom by factor (>1 zooms in) keeping the world point under screen_pos fixed.
func overhead_zoom(factor: float, screen_pos: Vector2) -> void:
	if mode != Mode.OVERHEAD or factor <= 0.0:
		return
	var vp := get_viewport().get_visible_rect().size
	var from_center := screen_pos - vp * 0.5
	var upp_old := _units_per_px()
	cam.size = clampf(cam.size / factor, MIN_OVERHEAD_SIZE, _fit_size * 1.6)
	var upp_new := _units_per_px()
	var b := cam.global_transform.basis
	var shift := b.x * from_center.x * (upp_old - upp_new) - b.y * from_center.y * (upp_old - upp_new)
	shift.y = 0.0
	cam.global_position += shift
	_clamp_overhead()


func overhead_fit() -> void:
	if mode == Mode.OVERHEAD:
		cam.size = _fit_size
		cam.global_position = _fit_pos


func _clamp_overhead() -> void:
	var r := hole.bounds.grow(40.0)
	var p := cam.global_position
	p.x = clampf(p.x, r.position.x, r.end.x)
	p.z = clampf(p.z, r.position.y, r.end.y)
	cam.global_position = p


## Camera feel (behind view only). Flight: chase with landing anticipation (the look point leads
## towards where the ball will come down) and a slight speed FOV. Putt / roll near the cup: lower and
## closer, framing ball and cup together. Cup drop: a short close-up of the cup (gentle orbit unless
## reduced motion). Reduced motion keeps the tight follow, no FOV change, orbit or shake.
const BASE_FOV := 68.0
const CUP_MOMENT_S := 1.8
const PUTT_CAM_RANGE := 22.0
var _ball_prev := Vector3.INF
var _ball_vel := Vector3.ZERO
var _cup_t := 0.0
var _cup_hold := false  # keep the cup framing after the moment until the next shot / hole
var _cup_pos := Vector3.ZERO
var _cup_dir := Vector3(0, 0, 1)
var _cup_ang := 0.0
var _shake := 0.0
var _shake_t := 0.0


## Hole-out close-up for CUP_MOMENT_S seconds (FxDirector calls this when the ball drops).
func cup_moment(cup: Vector3) -> void:
	if mode != Mode.BEHIND:
		return
	_cup_pos = cup
	_cup_dir = _chase_dir if _chase_dir.length() > 0.1 else Vector3(0, 0, 1)
	_cup_ang = 0.0
	_cup_t = CUP_MOMENT_S
	_cup_hold = true


func in_cup_moment() -> bool:
	return _cup_hold


## Tiny decaying shake (kick contact / hard landing); ignored with reduced motion.
func add_shake(amount: float) -> void:
	if not reduced_motion:
		_shake = maxf(_shake, clampf(amount, 0.0, 0.25))


## Where a descending ball will meet the ground (gravity only, no drag/wind): good enough to aim the camera.
func _predict_landing(ball: Vector3, v: Vector3) -> Vector3:
	var g := 9.81
	var gh := hole.terrain_height(ball.x, ball.z) if hole != null else 0.0
	var h := maxf(0.0, ball.y - gh)
	var t := (v.y + sqrt(maxf(0.0, v.y * v.y + 2.0 * g * h))) / g
	t = clampf(t, 0.0, 3.0)
	return Vector3(ball.x + v.x * t, gh, ball.z + v.z * t)


## Called every frame by the round controller.
func update_rig(delta: float, ball: Vector3, aim: Vector3, moving: bool, rolling: bool = false) -> void:
	if mode == Mode.OVERHEAD:
		return
	if delta > 0.0 and _ball_prev != Vector3.INF:
		var v := (ball - _ball_prev) / delta
		_ball_vel = _ball_vel.lerp(v, 1.0 - exp(-12.0 * delta)) if v.length() < 200.0 else _ball_vel
	_ball_prev = ball
	if not moving:
		_ball_vel = Vector3.ZERO
	elif _cup_hold and _cup_t <= 0.0:
		_cup_hold = false  # a new shot is under way
	var cup := hole.cup_position() if hole != null and hole.has_cup else Vector3.INF
	var desired_pos: Vector3
	var desired_look: Vector3
	var fov := BASE_FOV
	var fast := false  # use the slower, sweeping follow rates
	if _cup_hold:
		_cup_t = maxf(0.0, _cup_t - delta)
		if not reduced_motion and _cup_t > 0.0:
			_cup_ang += delta * deg_to_rad(14.0)
		var d := _cup_dir.rotated(Vector3.UP, _cup_ang)
		desired_pos = _cup_pos - d * 2.6 + Vector3.UP * 1.15
		# look below the cup so it sits in the upper free band, above the result card
		desired_look = _cup_pos - Vector3.UP * 0.9
	elif moving and rolling:
		var vh := Vector3(_ball_vel.x, 0, _ball_vel.z)
		if vh.length() > 0.3 and vh.normalized().dot(_chase_dir) > -0.2:  # no 180° swing on spin-back
			_chase_dir = _chase_dir.slerp(vh.normalized(), clampf(delta * 2.0, 0.0, 1.0)).normalized()
		desired_pos = ball - _chase_dir * 5.5 + Vector3.UP * 2.4
		desired_look = ball + _chase_dir * 3.5
		if cup != Vector3.INF:
			var dc := Units.horizontal_distance(ball, cup)
			if dc < PUTT_CAM_RANGE:
				# putt cam: drop lower and frame the ball running at the cup
				var w := 1.0 - dc / PUTT_CAM_RANGE
				desired_pos = ball - _chase_dir * lerpf(5.5, 3.6, w) + Vector3.UP * lerpf(2.4, 1.3, w)
				desired_look = desired_look.lerp(ball.lerp(cup, 0.5), w * 0.8)
	elif moving:
		var agl := 0.0
		if hole != null:
			agl = maxf(0.0, ball.y - hole.terrain_height(ball.x, ball.z))
		desired_pos = ball - _chase_dir * (11.0 + agl * 0.25) + Vector3.UP * (3.5 + agl * 0.35)
		desired_look = ball + _chase_dir * 2.0
		if _ball_vel.y < -1.0 and hole != null:
			# landing anticipation: lead the look point towards the predicted landing spot
			var land := _predict_landing(ball, _ball_vel)
			var lead := clampf(-_ball_vel.y / 12.0, 0.0, 1.0) * 0.45
			desired_look = desired_look.lerp(land, lead)
		if not reduced_motion:
			fov = BASE_FOV + clampf(_ball_vel.length() / 40.0, 0.0, 1.0) * 6.0
		fast = true
	else:
		_chase_dir = Vector3(aim.x, 0, aim.z).normalized()
		desired_pos = ball - _chase_dir * 6.5 + Vector3.UP * 2.1
		desired_look = ball + _chase_dir * 16.0 + Vector3.UP * 0.4
	if hole != null:
		var gh := hole.terrain_height(desired_pos.x, desired_pos.z) + (0.5 if _cup_hold else 1.0)
		desired_pos.y = maxf(desired_pos.y, gh)
	if not _initialised:
		_pos = desired_pos
		_look = desired_look
		_initialised = true
	else:
		var slow := fast and not reduced_motion
		var kp := 1.0 - exp(-(3.0 if slow else 10.0) * delta)
		var kl := 1.0 - exp(-(6.0 if slow else 14.0) * delta)
		_pos = _pos.lerp(desired_pos, kp)
		_look = _look.lerp(desired_look, kl)
	cam.fov = lerpf(cam.fov, fov, 1.0 - exp(-4.0 * delta))
	var off := Vector3.ZERO
	if _shake > 0.001:
		_shake_t += delta * 40.0
		off = Vector3(sin(_shake_t * 1.3), sin(_shake_t * 1.7 + 1.0), 0.0) * _shake
		_shake *= exp(-10.0 * delta)
	if (_look - _pos).length() > 0.01:
		cam.global_transform = Transform3D(Basis(), _pos)
		cam.look_at(_look, Vector3.UP)
		if off != Vector3.ZERO:
			cam.global_position += cam.global_transform.basis * off


func snap() -> void:
	_initialised = false
	_cup_t = 0.0
	_cup_hold = false


## Ground point under a screen position (iterative terrain intersection).
func screen_to_ground(screen_pos: Vector2) -> Variant:
	if hole == null:
		return null
	var o := cam.project_ray_origin(screen_pos)
	var d := cam.project_ray_normal(screen_pos)
	if absf(d.y) < 1e-4:
		return null
	var h := hole.terrain_height(o.x, o.z)
	var p := o
	for i in 6:
		var t := (h - o.y) / d.y
		if t < 0.0:
			return null
		p = o + d * t
		h = hole.terrain_height(p.x, p.z)
	return Vector3(p.x, h, p.z)

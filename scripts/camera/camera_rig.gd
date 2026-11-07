class_name CameraRig
extends Node3D
## Behind-ball aiming camera, smooth follow during motion, and tactical overhead view.

enum Mode { BEHIND, OVERHEAD }

var cam := Camera3D.new()
var mode: int = Mode.BEHIND
var hole: HoleDefinition
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


func set_mode(m: int) -> void:
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
	cam.size = maxf((max_along * 2.0 + 30.0) * pad, (max_side * 2.0 + 50.0) / maxf(aspect, 0.1))
	var c3 := Vector3(center.x, hole.terrain_height(center.x, center.y), center.y)
	cam.global_transform = Transform3D(Basis(), c3 + Vector3(0, 600, 0))
	cam.look_at(c3, Vector3(up2.x, 0, up2.y))


## Called every frame by the round controller.
func update_rig(delta: float, ball: Vector3, aim: Vector3, moving: bool) -> void:
	if mode == Mode.OVERHEAD:
		return
	var desired_pos: Vector3
	var desired_look: Vector3
	if moving:
		var agl := 0.0
		if hole != null:
			agl = maxf(0.0, ball.y - hole.terrain_height(ball.x, ball.z))
		desired_pos = ball - _chase_dir * (11.0 + agl * 0.25) + Vector3.UP * (3.5 + agl * 0.35)
		desired_look = ball + _chase_dir * 2.0
	else:
		_chase_dir = Vector3(aim.x, 0, aim.z).normalized()
		desired_pos = ball - _chase_dir * 6.5 + Vector3.UP * 2.1
		desired_look = ball + _chase_dir * 16.0 + Vector3.UP * 0.4
	if hole != null:
		var gh := hole.terrain_height(desired_pos.x, desired_pos.z) + 1.0
		desired_pos.y = maxf(desired_pos.y, gh)
	if not _initialised:
		_pos = desired_pos
		_look = desired_look
		_initialised = true
	else:
		var kp := 1.0 - exp(-(3.0 if moving else 10.0) * delta)
		var kl := 1.0 - exp(-(6.0 if moving else 14.0) * delta)
		_pos = _pos.lerp(desired_pos, kp)
		_look = _look.lerp(desired_look, kl)
	if (_look - _pos).length() > 0.01:
		cam.global_transform = Transform3D(Basis(), _pos)
		cam.look_at(_look, Vector3.UP)


func snap() -> void:
	_initialised = false


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

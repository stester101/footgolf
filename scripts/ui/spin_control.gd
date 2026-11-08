class_name SpinControl
extends Control
## Ball strike-point picker: drag the dot up (topspin) or down (backspin). Vertical only.
## Double-tap to reset to centre. Emits spin in [-1, 1] snapped to 0.05.

signal spin_changed(value: float)

var spin := 0.0
## Marker colour (changes with the active player).
var accent := Color("#A0F344")
var _dragging := false
var _last_tap_ms := 0
var _touch_index := -1


var _ball: ColorRect
var _ground: Control
var lie_colour := Color("#3E9A3A")


func set_lie_colour(c: Color) -> void:
	lie_colour = c
	if _ground != null:
		_ground.queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(128, 128)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Strike point: up = topspin, down = backspin"
	# ground under the ball, tinted by the lie (grass, rough, sand, green...)
	_ground = Control.new()
	_ground.show_behind_parent = true
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ground.draw.connect(func() -> void:
		var c := size * 0.5
		var r := _radius() - 3.0
		_ground.draw_circle(c, r, Color(lie_colour, 0.9))
		_ground.draw_arc(c, r, 0, TAU, 48, Color(0, 0, 0, 0.25), 2.0, true))
	add_child(_ground)
	# Rendered golf ball behind the guides (lit sphere, dimples, soft shadow; see golf_ball.gdshader)
	_ball = ColorRect.new()
	_ball.show_behind_parent = true
	_ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/golf_ball.gdshader")
	_ball.material = mat
	add_child(_ball)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _ball != null:
		var side := _ball_r() * 2.0 * 1.28
		_ball.size = Vector2(side, side)
		_ball.position = size * 0.5 - _ball.size * 0.5


func set_spin(v: float) -> void:
	spin = clampf(v, -1.0, 1.0)
	queue_redraw()


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - 5.0


func _ball_r() -> float:
	return _radius() * 0.66


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and _touch_index < 0:
			_touch_index = touch.index
			_dragging = true
			_apply_pos(touch.position)
		elif not touch.pressed and touch.index == _touch_index:
			_touch_index = -1
			_dragging = false
		accept_event()
	elif event is InputEventScreenDrag and _touch_index == (event as InputEventScreenDrag).index:
		_apply_pos((event as InputEventScreenDrag).position)
		accept_event()
	elif event is InputEventMouseButton and _touch_index < 0 and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			var now := Time.get_ticks_msec()
			if now - _last_tap_ms < 300:
				_apply(0.0)
				_last_tap_ms = 0
				_dragging = false
				accept_event()
				return
			_last_tap_ms = now
			_dragging = true
			_apply_pos(mb.position)
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging and _touch_index < 0:
		_apply_pos((event as InputEventMouseMotion).position)
		accept_event()


func _apply_pos(p: Vector2) -> void:
	var c := size * 0.5
	_apply(clampf((c.y - p.y) / (_ball_r() * 0.8), -1.0, 1.0))


func _apply(v: float) -> void:
	var snapped := snappedf(v, 0.05)
	if is_equal_approx(snapped, spin):
		return
	spin = snapped
	queue_redraw()
	spin_changed.emit(spin)


func _draw() -> void:
	var c := size * 0.5
	var r := _radius()
	var br := _ball_r()
	# outer ring, ticks and spin arrows; the ball itself is the shader child behind this drawing
	draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.55), 2.0, true)
	for dir in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		draw_line(c + dir * (r - 7.0), c + dir * (r + 1.0), Color(1, 1, 1, 0.7), 2.0, true)
	var up := PackedVector2Array([c + Vector2(0, -r + 6.0), c + Vector2(-8, -r + 18.0), c + Vector2(8, -r + 18.0)])
	var dn := PackedVector2Array([c + Vector2(0, r - 6.0), c + Vector2(-8, r - 18.0), c + Vector2(8, r - 18.0)])
	draw_colored_polygon(up, accent)
	draw_colored_polygon(dn, accent)
	# strike-point guides on the ball
	draw_line(c + Vector2(0, -br * 0.9), c + Vector2(0, br * 0.9), Color(0.04, 0.12, 0.25, 0.45), 1.5, true)
	draw_line(c + Vector2(-br * 0.16, 0), c + Vector2(br * 0.16, 0), Color(0.04, 0.12, 0.25, 0.45), 1.5, true)
	var dot := c + Vector2(0, -spin * br * 0.8)
	draw_circle(dot, 10.0, Color(0.04, 0.12, 0.25, 0.9))
	draw_circle(dot, 7.5, accent)

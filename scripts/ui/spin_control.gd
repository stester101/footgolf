class_name SpinControl
extends Control
## Ball strike-point picker: drag the dot up (topspin) or down (backspin). Vertical only.
## Double-tap to reset to centre. Emits spin in [-1, 1] snapped to 0.05.

signal spin_changed(value: float)

var spin := 0.0
var _dragging := false
var _last_tap_ms := 0
var _touch_index := -1


func _init() -> void:
	custom_minimum_size = Vector2(150, 150)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Strike point: up = topspin, down = backspin"


func set_spin(v: float) -> void:
	spin = clampf(v, -1.0, 1.0)
	queue_redraw()


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - 6.0


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
	_apply(clampf((c.y - p.y) / (_radius() * 0.8), -1.0, 1.0))


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
	# flat ivory ball, thin outline, quiet guides; no shading or glow
	draw_circle(c, r, UiKit.C_TEXT)
	draw_arc(c, r, 0, TAU, 48, UiKit.C_MUTED, 2.5, true)
	draw_line(c + Vector2(0, -r * 0.82), c + Vector2(0, r * 0.82), Color(UiKit.C_SURFACE, 0.35), 2.0, true)
	draw_line(c + Vector2(-r * 0.18, 0), c + Vector2(r * 0.18, 0), Color(UiKit.C_SURFACE, 0.35), 2.0, true)
	for t in [-0.8, -0.4, 0.4, 0.8]:
		draw_line(c + Vector2(-r * 0.1, -t * r * 0.8), c + Vector2(r * 0.1, -t * r * 0.8), Color(UiKit.C_SURFACE, 0.35), 2.0, true)
	var dot := c + Vector2(0, -spin * r * 0.8)
	draw_circle(dot, 11.0, UiKit.C_SURFACE)
	draw_circle(dot, 8.0, UiKit.C_ACCENT)
	if modulate.a < 0.99:
		draw_circle(c, r, Color(UiKit.C_SURFACE, 0.4))

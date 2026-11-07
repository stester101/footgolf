class_name SpinControl
extends Control
## Ball strike-point picker: drag the dot up (topspin) or down (backspin). Vertical only.
## Double-tap to reset to centre. Emits spin in [-1, 1] snapped to 0.05.

signal spin_changed(value: float)

var spin := 0.0
var _dragging := false
var _last_tap_ms := 0


func _init() -> void:
	custom_minimum_size = Vector2(112, 112)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Strike point: up = topspin, down = backspin"


func set_spin(v: float) -> void:
	spin = clampf(v, -1.0, 1.0)
	queue_redraw()


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - 6.0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
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
	elif event is InputEventMouseMotion and _dragging:
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
	var dis := modulate.a < 0.99
	# ball with simple shading + dimples
	draw_circle(c + Vector2(3, 4), r, Color(0, 0, 0, 0.35))
	draw_circle(c, r, Color(0.93, 0.94, 0.92))
	draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.55, Color(1, 1, 1, 0.5))
	for i in 14:
		var a := TAU * i / 14.0
		for ring in [0.45, 0.75]:
			draw_circle(c + Vector2(cos(a), sin(a)) * r * ring, 2.2, Color(0.75, 0.76, 0.74))
	draw_arc(c, r, 0, TAU, 48, Color(0.55, 0.57, 0.55), 2.0, true)
	# vertical guide
	draw_line(c + Vector2(0, -r * 0.85), c + Vector2(0, r * 0.85), Color(0.2, 0.25, 0.22, 0.5), 2.0, true)
	draw_line(c + Vector2(-r * 0.15, 0), c + Vector2(r * 0.15, 0), Color(0.2, 0.25, 0.22, 0.5), 2.0, true)
	# strike dot
	var dot := c + Vector2(0, -spin * r * 0.8)
	var col := Color(0.86, 0.15, 0.15) if spin < -0.01 else (Color(0.15, 0.45, 0.9) if spin > 0.01 else Color(0.15, 0.15, 0.15))
	draw_circle(dot, 11.0, Color(1, 1, 1))
	draw_circle(dot, 8.0, col)
	if dis:
		draw_circle(c, r, Color(0.1, 0.1, 0.1, 0.4))

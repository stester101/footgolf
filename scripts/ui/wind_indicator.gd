class_name WindIndicator
extends Control
## Small arrow showing where the wind blows TOWARD, relative to the camera view.

var screen_angle := 0.0  # radians; 0 = up the screen (away from camera)
var speed_mps := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(44, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_wind(angle: float, spd: float) -> void:
	screen_angle = angle
	speed_mps = spd
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.45
	draw_circle(c, r, Color(0, 0, 0, 0.35))
	if speed_mps < 0.05:
		draw_circle(c, 4, Color(1, 1, 1, 0.8))
		return
	var d := Vector2(sin(screen_angle), -cos(screen_angle))
	var tip := c + d * r * 0.85
	var tail := c - d * r * 0.7
	var side := Vector2(-d.y, d.x) * r * 0.35
	draw_line(tail, tip, Color(1, 1, 1), 3.0, true)
	draw_colored_polygon(PackedVector2Array([tip, tip - d * r * 0.45 + side, tip - d * r * 0.45 - side]), Color(1, 1, 1))

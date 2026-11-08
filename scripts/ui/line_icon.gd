class_name LineIcon
extends Control
## Consistent thin line icons drawn procedurally (stroke ≈ 1.75 logical units ≈ 3.5 px on the 720 px
## canvas). No emoji, no image assets. Set `kind`, `color`, optionally `rotation_rad` (for arrows).

var kind := "arrow_up"
var color := UiKit.C_TEXT
var rotation_rad := 0.0
var stroke := 3.5


static func make(p_kind: String, px: float = 36.0, p_color: Color = UiKit.C_TEXT) -> LineIcon:
	var i := LineIcon.new()
	i.kind = p_kind
	i.color = p_color
	i.custom_minimum_size = Vector2(px, px)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func set_kind(k: String) -> void:
	if k != kind:
		kind = k
		queue_redraw()


func set_rotation_rad(r: float) -> void:
	if not is_equal_approx(r, rotation_rad):
		rotation_rad = r
		queue_redraw()


func set_color(c: Color) -> void:
	if c != color:
		color = c
		queue_redraw()


func _line(a: Vector2, b: Vector2) -> void:
	draw_line(a, b, color, stroke, true)


func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 0.0:
		return
	var c := size * 0.5
	var u := s / 24.0  # icons are designed on a 24-unit grid
	var P := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * u
	match kind:
		"arrow_up":
			_arrow(c, u, rotation_rad)
		"pause":
			_line(P.call(-4.5, -7), P.call(-4.5, 7))
			_line(P.call(4.5, -7), P.call(4.5, 7))
		"map":
			var pts := PackedVector2Array([P.call(-9, -6), P.call(-3, -8), P.call(3, -6), P.call(9, -8),
				P.call(9, 6), P.call(3, 8), P.call(-3, 6), P.call(-9, 8), P.call(-9, -6)])
			draw_polyline(pts, color, stroke, true)
			_line(P.call(-3, -8), P.call(-3, 6))
			_line(P.call(3, -6), P.call(3, 8))
		"list":
			for row in 3:
				var y := -6.0 + row * 6.0
				draw_circle(P.call(-8, y), 1.1 * u, color)
				_line(P.call(-4, y), P.call(9, y))
		"plus":
			_line(P.call(-7, 0), P.call(7, 0))
			_line(P.call(0, -7), P.call(0, 7))
		"minus":
			_line(P.call(-7, 0), P.call(7, 0))
		"fit":
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					var corner: Vector2 = P.call(sx * 8, sy * 8)
					_line(corner, corner + Vector2(-sx * 5 * u, 0))
					_line(corner, corner + Vector2(0, -sy * 5 * u))
		"target":
			draw_arc(c, 6.5 * u, 0, TAU, 32, color, stroke, true)
			_line(P.call(0, -10), P.call(0, -4))
			_line(P.call(0, 4), P.call(0, 10))
			_line(P.call(-10, 0), P.call(-4, 0))
			_line(P.call(4, 0), P.call(10, 0))
		"swap":
			_line(P.call(-8, -3.5), P.call(8, -3.5))
			_line(P.call(8, -3.5), P.call(4, -7.5))
			_line(P.call(8, 3.5), P.call(-8, 3.5))
			_line(P.call(-8, 3.5), P.call(-4, 7.5))
		"arrow_right":
			_line(P.call(-8, 0), P.call(8, 0))
			_line(P.call(8, 0), P.call(3, -5))
			_line(P.call(8, 0), P.call(3, 5))
		"close":
			_line(P.call(-6, -6), P.call(6, 6))
			_line(P.call(6, -6), P.call(-6, 6))
		"search":
			draw_arc(P.call(-2, -2), 6.0 * u, 0, TAU, 28, color, stroke, true)
			_line(P.call(2.4, 2.4), P.call(8, 8))
		"player":
			draw_arc(P.call(1, -7), 2.4 * u, 0, TAU, 16, color, stroke, true)
			_line(P.call(1, -4.5), P.call(0, 2))
			_line(P.call(0, 2), P.call(-4, 8))
			_line(P.call(0, 2), P.call(5, 5))
			_line(P.call(5, 5), P.call(7, 8))
			_line(P.call(1, -3), P.call(-4, -1))
			_line(P.call(1, -3), P.call(6, -1))
		"people":
			draw_arc(P.call(-3.5, -4.5), 2.6 * u, 0, TAU, 16, color, stroke, true)
			draw_arc(P.call(4, -3.5), 2.2 * u, 0, TAU, 16, color, stroke, true)
			draw_arc(P.call(-3.5, 8), 5.5 * u, PI, TAU, 16, color, stroke, true)
			draw_arc(P.call(4, 7.5), 4.5 * u, PI, TAU, 16, color, stroke, true)
		"course":
			_line(P.call(0, -9), P.call(0, 3))
			draw_polyline(PackedVector2Array([P.call(0, -9), P.call(7, -6), P.call(0, -3)]), color, stroke, true)
			var ell := PackedVector2Array()
			for k in 25:
				var ang2 := TAU * float(k) / 24.0
				ell.append(P.call(9.0 * cos(ang2), 6.5 + 2.5 * sin(ang2)))
			draw_polyline(ell, color, stroke, true)
		"gear":
			draw_arc(P.call(0, 0), 3.2 * u, 0, TAU, 20, color, stroke, true)
			draw_arc(P.call(0, 0), 6.0 * u, 0, TAU, 28, color, stroke, true)
			for k in 8:
				var ang3 := TAU * float(k) / 8.0
				_line(P.call(6.0 * cos(ang3), 6.0 * sin(ang3)), P.call(8.8 * cos(ang3), 8.8 * sin(ang3)))
		"bars":
			for k in 3:
				var bx := -6.0 + 6.0 * k
				var bh := 5.0 + 5.0 * k
				draw_polyline(PackedVector2Array([P.call(bx - 2, 8), P.call(bx - 2, 8 - bh), P.call(bx + 2, 8 - bh), P.call(bx + 2, 8)]), color, stroke, true)
		"help":
			draw_arc(P.call(0, 0), 8.5 * u, 0, TAU, 32, color, stroke, true)
			draw_arc(P.call(0, -2), 3.2 * u, deg_to_rad(-200), deg_to_rad(40), 14, color, stroke, true)
			_line(P.call(1.8, 0.6), P.call(0, 2.6))
			draw_circle(P.call(0, 5.6), 1.2 * u, color)
		"star":
			var sp := PackedVector2Array()
			for k in 11:
				var r2 := 9.0 if k % 2 == 0 else 3.8
				var an := -PI / 2.0 + PI * float(k) / 5.0
				sp.append(P.call(r2 * cos(an), r2 * sin(an)))
			draw_polyline(sp, color, stroke, true)
		"chevron_left":
			draw_polyline(PackedVector2Array([P.call(3, -6), P.call(-3, 0), P.call(3, 6)]), color, stroke, true)
		"trophy":
			draw_polyline(PackedVector2Array([P.call(-5, -7), P.call(5, -7), P.call(5, -2), P.call(2.5, 2), P.call(-2.5, 2), P.call(-5, -2), P.call(-5, -7)]), color, stroke, true)
			draw_polyline(PackedVector2Array([P.call(-5, -5.5), P.call(-8.5, -5.5), P.call(-7.5, -1), P.call(-4.5, -0.5)]), color, stroke, true)
			draw_polyline(PackedVector2Array([P.call(5, -5.5), P.call(8.5, -5.5), P.call(7.5, -1), P.call(4.5, -0.5)]), color, stroke, true)
			_line(P.call(0, 2), P.call(0, 6))
			_line(P.call(-4, 7), P.call(4, 7))
		"chevron_right":
			draw_polyline(PackedVector2Array([P.call(-3, -6), P.call(3, 0), P.call(-3, 6)]), color, stroke, true)
		"chevron_down":
			draw_polyline(PackedVector2Array([P.call(-6, -3), P.call(0, 3), P.call(6, -3)]), color, stroke, true)
		"check":
			draw_polyline(PackedVector2Array([P.call(-7, 0), P.call(-2, 5), P.call(7, -5)]), color, stroke, true)
		"sliders":
			for row in [[-6.0, -3.0], [0.0, 3.0], [6.0, -1.0]]:
				_line(P.call(-8, row[0]), P.call(8, row[0]))
				draw_circle(P.call(row[1], row[0]), 2.2 * u, color)
		"sort":
			_line(P.call(-4, 7), P.call(-4, -7))
			_line(P.call(-4, -7), P.call(-7, -4))
			_line(P.call(-4, -7), P.call(-1, -4))
			_line(P.call(5, -7), P.call(5, 7))
			_line(P.call(5, 7), P.call(2, 4))
			_line(P.call(5, 7), P.call(8, 4))
		"shuffle":
			draw_polyline(PackedVector2Array([P.call(-8, -5), P.call(-3, -5), P.call(3, 5), P.call(7, 5)]), color, stroke, true)
			draw_polyline(PackedVector2Array([P.call(-8, 5), P.call(-3, 5), P.call(3, -5), P.call(7, -5)]), color, stroke, true)
			_line(P.call(7, 5), P.call(4, 2))
			_line(P.call(7, 5), P.call(4, 8))
			_line(P.call(7, -5), P.call(4, -8))
			_line(P.call(7, -5), P.call(4, -2))
		"refresh":
			draw_arc(P.call(0, 0), 6.5 * u, deg_to_rad(-40), deg_to_rad(250), 24, color, stroke, true)
			_line(P.call(5, -4.2), P.call(8.5, -4.5))
			_line(P.call(5, -4.2), P.call(5.5, -8))
		"funnel":
			draw_polyline(PackedVector2Array([P.call(-8, -7), P.call(8, -7), P.call(2, 0), P.call(2, 7), P.call(-2, 5), P.call(-2, 0), P.call(-8, -7)]), color, stroke, true)
		"flag":
			_line(P.call(-5, -9), P.call(-5, 9))
			draw_polyline(PackedVector2Array([P.call(-5, -9), P.call(7, -5), P.call(-5, -1)]), color, stroke, true)


func _arrow(c: Vector2, u: float, rot: float) -> void:
	# up-pointing arrow rotated by rot (0 = up, clockwise)
	var xf := Transform2D(rot, c)
	var pts := [Vector2(0, 9), Vector2(0, -8), Vector2(-5.5, -2.5), Vector2(0, -8), Vector2(5.5, -2.5)]
	var out := PackedVector2Array()
	for p in pts:
		out.append(xf * (p * u))
	_line(out[0], out[1])
	_line(out[1], out[2])
	_line(out[3], out[4])

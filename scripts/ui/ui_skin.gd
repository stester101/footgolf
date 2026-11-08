class_name UiSkin
extends StyleBox
## Shared material for the design system: vertical gradient body, soft drop shadow, upper-edge
## highlight and a fine border. Raised by default, `recessed` for inset controls. Drawn with plain
## canvas polygons (no textures, no shaders, no render targets), so it is cheap on Android.

var top := Color(0.14, 0.24, 0.42, 0.82)
var bottom := Color(0.04, 0.10, 0.21, 0.90)
var border := Color(0.40, 0.53, 0.67, 0.55)
var highlight := 0.30   # alpha of the 1 px upper-edge highlight
var glow := 0.0         # alpha of the soft inner rim light (frosted-glass edge)
var rim := Color(0.70, 0.88, 1.0)
var gloss := 0.0        # alpha of the soft reflection over the top half
var shadow := 0.0       # alpha of the drop shadow (0 = none)
var radius := 6.0
var recessed := false


static func _outline(rect: Rect2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if r < 0.75:
		pts.append(rect.position)
		pts.append(Vector2(rect.end.x, rect.position.y))
		pts.append(rect.end)
		pts.append(Vector2(rect.position.x, rect.end.y))
		return pts
	var corners := [Vector2(rect.end.x - r, rect.position.y + r), Vector2(rect.end.x - r, rect.end.y - r),
		Vector2(rect.position.x + r, rect.end.y - r), Vector2(rect.position.x + r, rect.position.y + r)]
	for ci in 4:
		var a0 := -PI * 0.5 + PI * 0.5 * ci
		for s in 6:
			var a := a0 + PI * 0.5 * float(s) / 5.0
			pts.append((corners[ci] as Vector2) + Vector2(cos(a), sin(a)) * r)
	return pts


static func _fill(ci: RID, pts: PackedVector2Array, c_top: Color, c_bot: Color, y0: float, h: float) -> void:
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for i in pts.size():
		cols[i] = c_top.lerp(c_bot, clampf((pts[i].y - y0) / maxf(h, 1.0), 0.0, 1.0))
	RenderingServer.canvas_item_add_polygon(ci, pts, cols)


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x < 2.0 or rect.size.y < 2.0:
		return
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	if shadow > 0.0 and not recessed:
		for k in 3:
			var sr := Rect2(rect.position + Vector2(0, 3.0 + 4.0 * k), rect.size).grow(float(k) * 2.0)
			var sc := Color(0, 0, 0, shadow * (0.42 - 0.13 * k))
			_fill(to_canvas_item, _outline(sr, r + k * 2.0), sc, sc, 0.0, 1.0)
	var body := _outline(rect, r)
	_fill(to_canvas_item, body, top, bottom, rect.position.y, rect.size.y)
	if gloss > 0.0:
		var gr := Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.5))
		_fill(to_canvas_item, _outline(gr, r), Color(1, 1, 1, gloss), Color(1, 1, 1, 0.0), gr.position.y, gr.size.y)
	if recessed:
		var ir := Rect2(rect.position + Vector2(r * 0.5, 0), Vector2(maxf(rect.size.x - r, 1.0), minf(7.0, rect.size.y)))
		_fill(to_canvas_item, _outline(ir, 0.0), Color(0, 0, 0, 0.35), Color(0, 0, 0, 0.0), ir.position.y, ir.size.y)
	var bp := body.duplicate()
	bp.append(body[0])
	var bc := PackedColorArray()
	bc.resize(bp.size())
	bc.fill(border)
	RenderingServer.canvas_item_add_polyline(to_canvas_item, bp, bc, 1.0, true)
	if glow > 0.0 and rect.size.x > 8.0 and rect.size.y > 8.0:
		var ir2 := rect.grow(-2.0)
		var gp := _outline(ir2, maxf(r - 2.0, 0.0))
		gp.append(gp[0])
		var gc := PackedColorArray()
		gc.resize(gp.size())
		for i in gp.size():
			gc[i] = Color(rim.r, rim.g, rim.b, glow * lerpf(1.0, 0.25, clampf((gp[i].y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)))
		RenderingServer.canvas_item_add_polyline(to_canvas_item, gp, gc, 1.5, true)
	if highlight > 0.0 and not recessed:
		var y := rect.position.y + 1.0
		RenderingServer.canvas_item_add_polyline(to_canvas_item,
			PackedVector2Array([Vector2(rect.position.x + r * 0.7, y), Vector2(rect.end.x - r * 0.7, y)]),
			PackedColorArray([Color(1, 1, 1, highlight), Color(1, 1, 1, highlight * 0.2)]), 1.0, true)

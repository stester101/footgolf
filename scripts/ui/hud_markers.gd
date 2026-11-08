class_name HudMarkers
extends Control
## HUD overlay that draws compact charcoal distance labels with a thin leader line to a hollow
## anchor circle, at the screen projection of LIVE world positions (pin, map target).
## Read-only: it never changes world positions, the camera or any calculation.

var camera: Camera3D
var pin_world := Vector3.INF
var pin_text := ""
var target_world := Vector3.INF
var target_dist_text := ""
var target_sub_text := ""
var show_target := false
var margin := Vector2(24, 140)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if camera == null or not is_instance_valid(camera):
		return
	if pin_world != Vector3.INF and pin_text != "":
		_marker(pin_world, "PIN", pin_text, "", Vector2(26, -62))
	if show_target and target_world != Vector3.INF:
		_marker(target_world, "", target_dist_text, target_sub_text, Vector2(26, -56))


func _screen(p: Vector3) -> Variant:
	if camera.is_position_behind(p):
		return null
	var sp := camera.unproject_position(p)
	var vp := get_viewport_rect().size
	if sp.x < -40 or sp.y < -40 or sp.x > vp.x + 40 or sp.y > vp.y + 40:
		return null
	return sp


func _marker(world: Vector3, tag: String, value: String, sub: String, offset: Vector2) -> void:
	var sp = _screen(world)
	if sp == null:
		return
	var pt: Vector2 = sp
	var f_tag := ThemeDB.fallback_font
	var f_val := UiKit.font_num()
	var tag_w := f_tag.get_string_size(tag + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x if tag != "" else 0.0
	var val_w := f_val.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var sub_w := f_tag.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x if sub != "" else 0.0
	var w := maxf(tag_w + val_w, sub_w) + 28.0
	var h := 50.0 if sub == "" else 76.0
	var vp := get_viewport_rect().size
	var pos := pt + offset
	pos.x = clampf(pos.x, margin.x, vp.x - margin.x - w)
	pos.y = clampf(pos.y, margin.y, vp.y - 300.0)
	var rect := Rect2(pos, Vector2(w, h))
	# leader line (thin ivory) from the label edge to the hollow anchor circle
	var attach := Vector2(clampf(pt.x, rect.position.x + 6.0, rect.end.x - 6.0), rect.end.y)
	if pt.y < rect.position.y:
		attach.y = rect.position.y
	draw_line(attach, pt, UiKit.C_TEXT, 2.5, true)
	draw_arc(pt, 8.0, 0.0, TAU, 24, UiKit.C_TEXT, 3.0, true)
	var sk: UiSkin = UiKit.skin("glass", 4, 0, 0).duplicate()
	sk.border = Color(1, 1, 1, 0.9)
	draw_style_box(sk, rect)
	if pt.y >= rect.end.y:  # white pointer toward the anchor
		draw_colored_polygon(PackedVector2Array([Vector2(attach.x - 8, rect.end.y - 1), Vector2(attach.x + 8, rect.end.y - 1), Vector2(attach.x, rect.end.y + 11)]), Color(1, 1, 1, 0.95))
	var x := rect.position.x + 14.0
	var base_y := rect.position.y + (35.0 if sub == "" else 34.0)
	if tag != "":
		draw_string(f_tag, Vector2(x, base_y - 2.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiKit.C_MUTED)
		x += tag_w
	draw_string(f_val, Vector2(x, base_y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiKit.C_TEXT)
	if sub != "":
		draw_string(f_tag, Vector2(rect.position.x + 14.0, rect.position.y + 64.0), sub.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiKit.C_MUTED)

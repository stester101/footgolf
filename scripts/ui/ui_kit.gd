class_name UiKit
extends RefCounted
## Shared theme and widget helpers. Portrait base resolution 720x1280.

const C_PANEL := Color(0.05, 0.09, 0.07, 0.82)
const C_PANEL_SOLID := Color(0.06, 0.10, 0.08, 0.96)
const C_ACCENT := Color(0.18, 0.66, 0.32)
const C_ACCENT_DARK := Color(0.12, 0.45, 0.22)
const C_WARN := Color(0.95, 0.68, 0.2)
const C_TEXT := Color(0.96, 0.97, 0.95)
const C_MUTED := Color(0.72, 0.78, 0.74)
const C_DEV := Color(0.85, 0.45, 0.95)


static func box(color: Color, radius: int = 18, pad: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.7
	sb.content_margin_bottom = pad * 0.7
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	t.set_stylebox("panel", "PanelContainer", box(C_PANEL))
	t.set_stylebox("panel", "Panel", box(C_PANEL_SOLID, 0, 0))
	var btn_n := box(Color(0.16, 0.22, 0.19, 0.95), 14, 14)
	var btn_h := box(Color(0.22, 0.30, 0.26, 0.95), 14, 14)
	var btn_p := box(C_ACCENT_DARK, 14, 14)
	var btn_d := box(Color(0.12, 0.14, 0.13, 0.7), 14, 14)
	t.set_stylebox("normal", "Button", btn_n)
	t.set_stylebox("hover", "Button", btn_h)
	t.set_stylebox("pressed", "Button", btn_p)
	t.set_stylebox("hover_pressed", "Button", btn_p)
	t.set_stylebox("disabled", "Button", btn_d)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.55, 0.52))
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	t.set_stylebox("normal", "LineEdit", box(Color(0.12, 0.16, 0.14, 1.0), 10, 12))
	t.set_stylebox("focus", "LineEdit", box(Color(0.14, 0.2, 0.17, 1.0), 10, 12))
	t.set_stylebox("panel", "TabContainer", box(C_PANEL_SOLID, 10, 10))
	t.set_font_size("font_size", "TabContainer", 24)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_constant("h_separation", "GridContainer", 18)
	t.set_constant("v_separation", "GridContainer", 6)
	return t


static func label(text: String, size: int = 26, color: Color = C_TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Multi-line wrapping text for use inside VBox containers.
static func text(t: String, size: int = 24, color: Color = C_TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return label(t, size, color, align, true)


static func button(text: String, cb: Callable, min_h: int = 72, size: int = 26) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func primary(b: Button, color: Color = C_ACCENT) -> Button:
	b.add_theme_stylebox_override("normal", box(color, 16, 16))
	b.add_theme_stylebox_override("hover", box(color.lightened(0.1), 16, 16))
	b.add_theme_stylebox_override("pressed", box(color.darkened(0.2), 16, 16))
	return b


static func panel(color: Color = C_PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Full-screen dimmed overlay root that swallows input (so drags don't aim).
static func overlay(dim: float = 0.55) -> Control:
	var root := ColorRect.new()
	root.color = Color(0, 0, 0, dim)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	return root


static func spin(minv: float, maxv: float, step: float, value: float, cb: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(190, 56)
	s.select_all_on_focus = true
	s.get_line_edit().add_theme_font_size_override("font_size", 24)
	if cb.is_valid():
		s.value_changed.connect(cb)
	return s


static func clear(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()


## Safe-area margins in viewport (canvas) units: [left, top, right, bottom].
static func safe_margins(vp: Viewport) -> Array:
	var out := [16.0, 16.0, 16.0, 16.0]
	if DisplayServer.get_name() == "headless":
		return out
	var win_size := Vector2(DisplayServer.window_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var screen := Vector2(DisplayServer.screen_get_size())
	if win_size.x <= 0 or safe.size.x <= 0 or screen.x <= 0:
		return out
	var vis := vp.get_visible_rect().size
	var sx := vis.x / win_size.x
	var sy := vis.y / win_size.y
	out[0] = maxf(16.0, safe.position.x * sx)
	out[1] = maxf(16.0, safe.position.y * sy)
	out[2] = maxf(16.0, (screen.x - safe.end.x) * sx)
	out[3] = maxf(16.0, (screen.y - safe.end.y) * sy)
	return out

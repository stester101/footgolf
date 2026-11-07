class_name UiKit
extends RefCounted
## Shared theme and widget helpers. Portrait base resolution 720x1280.

## Design tokens (UI handover). 1 logical unit = 2 px on the 720 px-wide canvas.
const U := 2
const C_SURFACE := Color("#232723")      # scoreboard, plates, rows, scorecard
const C_RAISED := Color("#2D322D")       # buttons sitting on a surface (derived, slightly lighter)
const C_BG := Color("#181B18")           # full-screen menus without a game behind them
const C_TEXT := Color("#F1EFE7")         # primary text / action fill
const C_MUTED := Color("#A5AAA1")        # secondary text, inactive
const C_ACCENT := Color("#A9BCA2")       # selected underline, small indicators, holed
const C_SELECTED := Color("#626B5E")     # current scorecard row, selected list items
const C_DIVIDER := Color("#62675F")      # quiet separators
const C_ACTION_TEXT := Color("#232723")  # text on ivory buttons
const C_WARN := Color("#D8C9A8")         # penalties / hazards (muted sand; no gold, no neon)
const C_DEV := Color("#B7B2C6")          # developer-only labels
const RADIUS := 6                        # 3 logical units
# legacy names used across the UI
const C_PANEL := C_SURFACE
const C_PANEL_SOLID := C_SURFACE
const C_ACCENT_DARK := C_SELECTED

static var _semi: FontVariation
static var _num: FontVariation


## Medium/semibold emphasis (embolden over the bundled sans; no remote font).
static func font_semi() -> FontVariation:
	if _semi == null:
		_semi = FontVariation.new()
		_semi.base_font = ThemeDB.fallback_font
		_semi.variation_embolden = 0.35
		_semi.opentype_features = {"tnum": 1}
	return _semi


## Tabular digits for scores and distances (where the font provides them).
static func font_num() -> FontVariation:
	if _num == null:
		_num = FontVariation.new()
		_num.base_font = ThemeDB.fallback_font
		_num.variation_embolden = 0.2
		_num.opentype_features = {"tnum": 1}
	return _num


static func box(color: Color, radius: int = 6, pad: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(mini(radius, 8))  # small, consistent corners: no pills
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.7
	sb.content_margin_bottom = pad * 0.7
	return sb


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	t.set_stylebox("panel", "PanelContainer", box(C_SURFACE))
	t.set_stylebox("panel", "Panel", box(C_SURFACE, 0, 0))
	t.set_stylebox("normal", "Button", box(C_RAISED, RADIUS, 14))
	t.set_stylebox("hover", "Button", box(C_RAISED.lightened(0.06), RADIUS, 14))
	t.set_stylebox("pressed", "Button", box(C_SELECTED, RADIUS, 14))
	t.set_stylebox("hover_pressed", "Button", box(C_SELECTED, RADIUS, 14))
	t.set_stylebox("disabled", "Button", box(C_RAISED.darkened(0.15), RADIUS, 14))
	var focus := StyleBoxFlat.new()  # visible keyboard/D-pad focus: thin sage outline, no glow
	focus.bg_color = Color(0, 0, 0, 0)
	focus.set_border_width_all(2)
	focus.border_color = C_ACCENT
	focus.set_corner_radius_all(RADIUS)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_pressed_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", C_TEXT)
	t.set_color("font_focus_color", "Button", C_TEXT)
	t.set_color("font_disabled_color", "Button", Color("#7C817A"))
	t.set_color("font_color", "Label", C_TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	var le := box(C_RAISED, RADIUS, 12)
	le.set_border_width_all(1)
	le.border_color = C_DIVIDER
	t.set_stylebox("normal", "LineEdit", le)
	var le_f := le.duplicate()
	le_f.border_color = C_ACCENT
	t.set_stylebox("focus", "LineEdit", le_f)
	t.set_color("font_color", "LineEdit", C_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", C_MUTED)
	t.set_color("caret_color", "LineEdit", C_ACCENT)
	t.set_stylebox("panel", "TabContainer", box(C_SURFACE, RADIUS, 10))
	t.set_font_size("font_size", "TabContainer", 24)
	t.set_color("font_selected_color", "TabContainer", C_TEXT)
	t.set_color("font_unselected_color", "TabContainer", C_MUTED)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_constant("h_separation", "GridContainer", 18)
	t.set_constant("v_separation", "GridContainer", 6)
	# list popups (OptionButton) in the same matte style
	t.set_stylebox("panel", "PopupMenu", box(C_SURFACE, RADIUS, 8))
	t.set_stylebox("hover", "PopupMenu", box(C_SELECTED, 4, 6))
	t.set_color("font_color", "PopupMenu", C_TEXT)
	t.set_color("font_hover_color", "PopupMenu", C_TEXT)
	t.set_font_size("font_size", "PopupMenu", 24)
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


## Ivory action button (dark text). The colour argument is kept for old call sites and ignored.
static func primary(b: Button, _color: Color = C_TEXT) -> Button:
	b.add_theme_stylebox_override("normal", box(C_TEXT, RADIUS, 16))
	b.add_theme_stylebox_override("hover", box(C_TEXT.lightened(0.08), RADIUS, 16))
	b.add_theme_stylebox_override("pressed", box(C_TEXT.darkened(0.12), RADIUS, 16))
	b.add_theme_stylebox_override("hover_pressed", box(C_TEXT.darkened(0.12), RADIUS, 16))
	b.add_theme_stylebox_override("disabled", box(C_RAISED.darkened(0.15), RADIUS, 16))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, C_ACTION_TEXT)
	b.add_theme_color_override("font_disabled_color", C_MUTED)
	return b


## Selected list item / toggle: muted sage-grey fill, ivory text.
static func selected(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", box(C_SELECTED, RADIUS, 14))
	b.add_theme_stylebox_override("hover", box(C_SELECTED, RADIUS, 14))
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
	root.color = Color(0.09, 0.10, 0.09, dim)  # matte neutral scrim, no blur
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
	var out := [32.0, 32.0, 32.0, 32.0]  # 16 logical units
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
	out[0] = maxf(32.0, safe.position.x * sx)
	out[1] = maxf(32.0, safe.position.y * sy)
	out[2] = maxf(32.0, (screen.x - safe.end.x) * sx)
	out[3] = maxf(32.0, (screen.y - safe.end.y) * sy)
	return out


## Player card button: flag icon, name on line 1, nation/era (+ stats in test mode) on line 2.
## Stores the footballer id in meta "footballer_id".
static func player_button(fb: Footballer, show_stats: bool, used: bool, selected: bool, cb: Callable) -> Button:
	var b := button("", cb, 84, 23)
	b.icon = Flags.texture(fb.country_code)
	b.expand_icon = false
	b.add_theme_constant_override("h_separation", 14)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.set_meta("footballer_id", fb.id)
	var era := ""
	if fb.career_years != "":
		var parts := fb.career_years.split("–")
		era = parts[0] if parts.size() == 2 and parts[0] == parts[1] else fb.career_years
	elif fb.birth_year > 0:
		era = "b. %d" % fb.birth_year
	var line2 := fb.nationality + ("  ·  " + era if era != "" else "")
	var txt := "%s%s\n%s" % [fb.name, "   —  USED" if used else "", line2]
	if show_stats:
		txt += "\n%s  ·  %s" % [plural(fb.caps, "cap"), plural(fb.goals, "goal")]
		b.custom_minimum_size.y = 108
	b.text = txt
	b.disabled = used
	if selected:
		UiKit.selected(b)
	return b


static func plural(n: int, word: String) -> String:
	return "%d %s%s" % [n, word, "" if n == 1 else "s"]

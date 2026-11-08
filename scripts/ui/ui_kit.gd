class_name UiKit
extends RefCounted
## Shared theme and widget helpers. Portrait base resolution 720x1280.

## Design tokens (UI handover). 1 logical unit = 2 px on the 720 px-wide canvas.
const U := 2
const C_SURFACE := Color("#0B1F3B")      # deep green score plates over the live course
const C_RAISED := Color("#243B5E")       # raised controls
const C_BG := Color("#0A0F1A")           # menu backdrop
const C_TEXT := Color("#FFFFFF")         # warm chalk
const C_MUTED := Color("#B8C8DA")        # secondary text
const C_ACCENT := Color("#A0F344")       # turf green: selections and primary action
const C_SELECTED := Color("#2F5D9E")     # current row / selected list item
const C_DIVIDER := Color("#6688AA")      # separators
const C_ACTION_TEXT := Color("#0B1F3B")  # text on primary action
const C_CYAN := Color("#8FD8FF")          # accent lines and current-row edge
const C_WARN := Color("#E9BC70")         # hazard / scoring highlight
const C_DEV := Color("#B7B2C6")          # developer-only labels
const RADIUS := 6                        # 3 logical units
# legacy names used across the UI
const C_PANEL := C_SURFACE
const C_PANEL_SOLID := C_SURFACE
const C_ACCENT_DARK := C_SELECTED

static var _semi: FontVariation
static var _num: FontVariation
static var _skins: Dictionary = {}
static var _display: FontVariation
static var _caps: FontVariation
const SKIN_ROUND := 1.9   # soft corners: skin radii are scaled by this


## Medium/semibold emphasis (embolden over the bundled sans; no remote font).
static func font_semi() -> FontVariation:
	if _semi == null:
		_semi = FontVariation.new()
		_semi.base_font = ThemeDB.fallback_font
		_semi.variation_embolden = 0.35
		_semi.opentype_features = {"tnum": 1}
	return _semi


## Bold italic display face for result headlines (PAR, BIRDIE, ROUND COMPLETE).
static func font_display() -> FontVariation:
	if _display == null:
		_display = FontVariation.new()
		_display.base_font = ThemeDB.fallback_font
		_display.variation_embolden = 0.8
		_display.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
		_display.spacing_glyph = 2
	return _display


## Semibold with open letter-spacing for small capital labels.
static func font_caps() -> FontVariation:
	if _caps == null:
		_caps = FontVariation.new()
		_caps.base_font = ThemeDB.fallback_font
		_caps.variation_embolden = 0.35
		_caps.spacing_glyph = 1
	return _caps


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


## Shared materials (see UiSkin). Cached per kind and padding so every screen reuses the same resources.
## kinds: glass (panels), btn / btn_hover / btn_press (secondary buttons), recess (inactive selectors,
## inputs), lime (active selector), action / action_hover / action_press (primary buttons), disabled,
## header / header_deep (scoreboard), tile (white tiles), select (selected rows)
static func skin(kind: String, radius: float = 6.0, padx: float = 14.0, pady: float = 8.0) -> UiSkin:
	var key := "%s|%.1f|%.1f|%.1f" % [kind, radius, padx, pady]
	if _skins.has(key):
		return _skins[key]
	var k := UiSkin.new()
	k.radius = radius * SKIN_ROUND
	k.set_content_margin(SIDE_LEFT, padx)
	k.set_content_margin(SIDE_RIGHT, padx)
	k.set_content_margin(SIDE_TOP, pady)
	k.set_content_margin(SIDE_BOTTOM, pady)
	match kind:
		"btn":
			k.top = Color(0.28, 0.44, 0.66, 0.88)
			k.bottom = Color(0.11, 0.23, 0.43, 0.92)
			k.border = Color(0.72, 0.88, 1.0, 0.55)
			k.highlight = 0.45
			k.glow = 0.12
			k.gloss = 0.10
			k.shadow = 0.32
		"btn_hover":
			k.top = Color(0.34, 0.52, 0.76, 0.92)
			k.bottom = Color(0.15, 0.28, 0.50, 0.94)
			k.border = Color(0.80, 0.93, 1.0, 0.70)
			k.highlight = 0.55
			k.glow = 0.16
			k.gloss = 0.12
			k.shadow = 0.32
		"btn_press":
			k.top = Color(0.05, 0.11, 0.23, 0.96)
			k.bottom = Color(0.10, 0.19, 0.34, 0.96)
			k.border = Color(0.50, 0.65, 0.82, 0.50)
			k.recessed = true
		"recess":
			k.top = Color(0.04, 0.10, 0.20, 0.78)
			k.bottom = Color(0.09, 0.18, 0.32, 0.78)
			k.border = Color(0.62, 0.80, 0.96, 0.40)
			k.recessed = true
		"lime":
			k.top = Color("#C6FF70")
			k.bottom = Color("#8DDB2A")
			k.border = Color(0.90, 1.0, 0.70, 0.85)
			k.highlight = 0.60
			k.shadow = 0.40
		"action":
			k.top = Color("#52AAFF")
			k.bottom = Color("#1B60D0")
			k.border = Color(0.78, 0.90, 1.0, 0.80)
			k.highlight = 0.65
			k.glow = 0.22
			k.gloss = 0.14
			k.shadow = 0.45
		"action_hover":
			k.top = Color("#6BB8FF")
			k.bottom = Color("#2A70E0")
			k.border = Color(0.85, 0.94, 1.0, 0.85)
			k.highlight = 0.60
			k.gloss = 0.08
			k.shadow = 0.45
		"action_press":
			k.top = Color("#1B60D0")
			k.bottom = Color("#144AA0")
			k.border = Color(0.70, 0.84, 1.0, 0.60)
			k.recessed = true
		"disabled":
			k.top = Color(0.28, 0.40, 0.56, 0.60)
			k.bottom = Color(0.18, 0.28, 0.44, 0.60)
			k.border = Color(0.62, 0.76, 0.92, 0.28)
			k.highlight = 0.14
		"header":
			k.top = Color("#2A74D6")
			k.bottom = Color("#0F3F8E")
			k.border = Color(1, 1, 1, 0.28)
			k.highlight = 0.65
			k.glow = 0.20
			k.gloss = 0.14
			k.shadow = 0.38
		"header_deep":
			k.top = Color("#0F3F8E")
			k.bottom = Color("#0A2F70")
			k.border = Color(1, 1, 1, 0.18)
			k.highlight = 0.25
		"tile":
			k.top = Color("#FFFFFF")
			k.bottom = Color("#D3DDEC")
			k.border = Color(1, 1, 1, 0.90)
			k.shadow = 0.25
		"select":
			k.top = Color("#3F7FDB")
			k.bottom = Color("#1F4FA3")
			k.border = Color(0.75, 0.88, 1.0, 0.70)
			k.highlight = 0.50
			k.shadow = 0.30
		_:  # glass: frosted blue-grey, light rim, soft shadow
			k.top = Color(0.36, 0.52, 0.70, 0.66)
			k.bottom = Color(0.10, 0.22, 0.40, 0.82)
			k.border = Color(0.72, 0.88, 1.0, 0.48)
			k.highlight = 0.50
			k.glow = 0.14
			k.gloss = 0.12
			k.shadow = 0.30
	_skins[key] = k
	return k


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	t.set_stylebox("panel", "PanelContainer", skin("glass", 8, 14, 10))
	t.set_stylebox("panel", "Panel", box(C_SURFACE, 0, 0))
	t.set_stylebox("normal", "Button", skin("btn", 6, 14, 10))
	t.set_stylebox("hover", "Button", skin("btn_hover", 6, 14, 10))
	t.set_stylebox("pressed", "Button", skin("btn_press", 6, 14, 10))
	t.set_stylebox("hover_pressed", "Button", skin("btn_press", 6, 14, 10))
	t.set_stylebox("disabled", "Button", skin("disabled", 6, 14, 10))
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
	t.set_color("font_disabled_color", "Button", Color("#7F8FA8"))
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
	t.set_stylebox("panel", "TabContainer", skin("glass", 8, 10, 10))
	t.set_font_size("font_size", "TabContainer", 24)
	t.set_color("font_selected_color", "TabContainer", C_TEXT)
	t.set_color("font_unselected_color", "TabContainer", C_MUTED)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	t.set_constant("h_separation", "GridContainer", 18)
	t.set_constant("v_separation", "GridContainer", 6)
	# list popups (OptionButton) in the same matte style
	t.set_stylebox("panel", "PopupMenu", skin("glass", 8, 8, 8))
	t.set_stylebox("hover", "PopupMenu", skin("select", 4, 6, 4))
	t.set_color("font_color", "PopupMenu", C_TEXT)
	t.set_color("font_hover_color", "PopupMenu", C_TEXT)
	t.set_font_size("font_size", "PopupMenu", 24)
	# switches and check boxes: recessed row, same text colours as buttons
	for st in ["normal", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckButton", skin("recess", 6, 14, 10))
	t.set_stylebox("hover", "CheckButton", skin("btn", 6, 14, 10))
	for c in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(c, "CheckButton", C_TEXT)
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


## Primary action button: electric-blue raised material, white text. The colour argument is ignored.
static func primary(b: Button, _color: Color = C_ACCENT) -> Button:
	b.add_theme_stylebox_override("normal", skin("action", RADIUS, 16, 10))
	b.add_theme_stylebox_override("hover", skin("action_hover", RADIUS, 16, 10))
	b.add_theme_stylebox_override("pressed", skin("action_press", RADIUS, 16, 10))
	b.add_theme_stylebox_override("hover_pressed", skin("action_press", RADIUS, 16, 10))
	b.add_theme_stylebox_override("disabled", skin("disabled", RADIUS, 16, 10))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))
	return b


## Selected list item / toggle: raised blue.
static func selected(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", skin("select", RADIUS, 14, 10))
	b.add_theme_stylebox_override("hover", skin("select", RADIUS, 14, 10))
	return b


static func panel(color: Color = C_PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", skin("glass", 8, 14, 10))
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
	root.color = Color(0.03, 0.06, 0.12, dim)  # navy scrim, no blur
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

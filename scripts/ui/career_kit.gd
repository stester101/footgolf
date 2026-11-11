class_name CareerKit
extends RefCounted
## Shared Career widgets (see docs/career/CAREER_UI_DESIGN.md): page shells, hero numbers, tier colours, event
## cards, rank rows with movement arrows, tab bar, segmented control, count-up and fade-in motion. Presentation
## only. All font sizes pass through fs() (Settings > Larger text); all motion is skipped under Reduced motion.
## Canvas is 720 px wide: 96 px = 48 dp minimum touch target.

const TOUCH := 96
const C_REGULAR := Color("#4FA3FF")
const C_FLAGSHIP := Color("#B98CFF")
const C_MAJOR := Color("#FFC845")
const C_FINALE := Color("#FF7A59")
const C_UP := Color("#7CF27C")
const C_DOWN := Color("#FF6B6B")
const C_LIME := Color("#B6F75A")
const C_LIME_TEXT := Color("#0E2A07")
const C_CARD := Color(0.075, 0.135, 0.245, 0.94)
const C_CARD_HOVER := Color(0.11, 0.19, 0.33, 0.96)
const C_CARD_PRESS := Color(0.05, 0.10, 0.19, 0.98)
const C_EDGE := Color(0.55, 0.72, 0.95, 0.20)
const C_MUTED := Color("#9FB3CB")
const C_FAINT := Color("#6F86A3")
const NATION_FLAGS := {"England": "ENG", "Scotland": "SCO", "Wales": "WAL", "Northern Ireland": "NIR", "Ireland": "IRL",
	"Spain": "ESP", "Germany": "GER", "France": "FRA", "Italy": "ITA", "Netherlands": "NED", "Belgium": "BEL", "Argentina": "ARG"}
const NATION_CODES := {"USA": "USA", "Australia": "AUS", "Austria": "AUT", "Canada": "CAN", "Chile": "CHI", "China": "CHN",
	"Colombia": "COL", "Denmark": "DEN", "Finland": "FIN", "India": "IND", "Japan": "JPN", "Mexico": "MEX", "New Zealand": "NZL",
	"Norway": "NOR", "Paraguay": "PAR", "South Africa": "RSA", "South Korea": "KOR", "Sweden": "SWE", "Thailand": "THA",
	"Venezuela": "VEN"}


# ------------------------------------------------------------------ tokens

static func fs(n: float) -> int:
	return int(round(n * App.settings.text_scale()))


static func reduced() -> bool:
	return bool(App.settings.reduced_motion)


static func tier_color(cat: String) -> Color:
	return {"regular": C_REGULAR, "flagship": C_FLAGSHIP, "major": C_MAJOR, "finale": C_FINALE}.get(cat, C_REGULAR)


static func tier_label(cat: String) -> String:
	return {"regular": "LBT EVENT", "flagship": "FLAGSHIP", "major": "MAJOR", "finale": "LBT CHAMPIONSHIP"}.get(cat, cat.to_upper())


static func nation_code(nation: String) -> String:
	if NATION_FLAGS.has(nation):
		return NATION_FLAGS[nation]
	return NATION_CODES.get(nation, nation.substr(0, 3).to_upper())


static func money_short(n: int) -> String:
	var a := absi(n)
	var s := ""
	if a >= 1000000:
		s = "£%.1fm" % (a / 1000000.0)
	elif a >= 10000:
		s = "£%dk" % int(round(a / 1000.0))
	elif a >= 1000:
		s = "£%.1fk" % (a / 1000.0)
	else:
		s = "£%d" % a
	return ("-" if n < 0 else "") + s.replace(".0k", "k").replace(".0m", "m")


static func ordinal(n: int) -> String:
	return QualificationManager._ord(n) if n > 0 else "-"


# ------------------------------------------------------------------ styles and text

static func flat(bg: Color, radius: int = 16, pad: float = 18.0, edge: Color = C_EDGE, bw: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(pad)
	sb.content_margin_top = pad * 0.8
	sb.content_margin_bottom = pad * 0.8
	if bw > 0:
		sb.set_border_width_all(bw)
		sb.border_color = edge
	sb.anti_aliasing = true
	return sb


## Card style with a coloured stripe down the left edge (tier / status accent).
static func striped(bg: Color, stripe: Color, radius: int = 16, pad: float = 18.0) -> StyleBoxFlat:
	var sb := flat(bg, radius, pad, stripe, 0)
	sb.border_width_left = 8
	sb.border_color = stripe
	sb.content_margin_left = pad + 8
	return sb


static func glass(top: Color, bottom: Color, radius: float = 22.0, pad: float = 22.0) -> UiSkin:
	var k := UiSkin.new()
	k.top = top
	k.bottom = bottom
	k.border = Color(0.75, 0.88, 1.0, 0.30)
	k.highlight = 0.45
	k.glow = 0.14
	k.gloss = 0.07
	k.shadow = 0.35
	k.radius = radius
	k.set_content_margin_all(pad)
	return k


## Label. kind: "" (regular), "semi", "caps", "display", "num".
static func text(t: String, size: float = 24.0, color: Color = Color.WHITE, kind: String = "", wrap: bool = false, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(t, fs(size), color, align, wrap)
	match kind:
		"semi":
			l.add_theme_font_override("font", UiKit.font_semi())
		"caps":
			l.add_theme_font_override("font", UiKit.font_caps())
		"display":
			l.add_theme_font_override("font", UiKit.font_display())
		"num":
			l.add_theme_font_override("font", UiKit.font_num())
	return l


static func caption(t: String, color: Color = UiKit.C_CYAN) -> Label:
	return text(t.to_upper(), 18, color, "caps")


static func trim(l: Label) -> Label:
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	return l


static func spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func section(title: String, right: String = "") -> Control:
	var h := UiKit.hbox(10)
	h.add_child(trim(caption(title)))
	if right != "":
		h.add_child(text(right, 18, C_FAINT, "caps"))
	return h


static func card(content: Control, style: StyleBox = null) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style if style != null else flat(C_CARD))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(content)
	return p


## A text card: caption title plus wrapped lines (replacement for the old recess cards).
static func info_card(title: String, lines: Array, accent: Color = UiKit.C_CYAN) -> PanelContainer:
	var v := UiKit.vbox(6)
	if title != "":
		v.add_child(caption(title, accent))
	for l in lines:
		if String(l) == "":
			continue
		v.add_child(text(String(l), 22, Color.WHITE, "", true))
	return card(v, striped(C_CARD, accent) if accent != UiKit.C_CYAN else null)


static func chip(t: String, color: Color, filled: bool = false, size: float = 16.0) -> PanelContainer:
	var sb := flat(color if filled else Color(color.r, color.g, color.b, 0.16), 10, 10.0, Color(color.r, color.g, color.b, 0.55), 0 if filled else 1)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	var l := text(t.to_upper(), size, Color("#0B1426") if filled else color, "caps")
	var p := card(l, sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return p


static func tier_chip(cat: String) -> PanelContainer:
	return chip(tier_label(cat), tier_color(cat))


## Flag (when we draw one) or a three-letter nation code plate.
static func nation_chip(nation: String, h: float = 34.0) -> Control:
	var code := nation_code(nation)
	if NATION_FLAGS.has(nation):
		var tr := TextureRect.new()
		tr.texture = Flags.texture(code)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(h * 1.5, h)
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var sb := flat(Color(1, 1, 1, 0.14), 6, 6.0, Color(1, 1, 1, 0.35), 1)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	var p := card(text(code, 16, Color.WHITE, "caps", false, HORIZONTAL_ALIGNMENT_CENTER), sb)
	p.custom_minimum_size = Vector2(h * 1.5, h)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


# ------------------------------------------------------------------ buttons

static func _btn_styles(b: Button, normal: StyleBox, hover: StyleBox, press: StyleBox) -> void:
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", press)
	b.add_theme_stylebox_override("hover_pressed", press)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", flat(Color(0.12, 0.17, 0.26, 0.7), 16, 18.0, Color(1, 1, 1, 0.08)))


static func _wire(b: Button, cb: Callable, ui_id: String, press_text: String) -> void:
	b.focus_mode = Control.FOCUS_ALL
	if ui_id != "":
		b.set_meta("ui_id", ui_id)
	if press_text != "":
		b.set_meta("press_text", press_text)
	if cb.is_valid():
		b.pressed.connect(cb)


## Centred content laid over a fixed-height Button (CTA). Content must not wrap.
static func _fill(b: Button, content: Control, margin: int = 22) -> void:
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", margin)
	mc.add_theme_constant_override("margin_right", margin)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(content)
	b.add_child(mc)


static func _ignore_tree(n: Node) -> void:
	for ch in n.get_children():
		if ch is Control:
			(ch as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_tree(ch)


## The one primary action of a screen: lime, 120 px, display text, optional subline.
static func cta(t: String, sub: String, cb: Callable, ui_id: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 124 if sub != "" else 112)
	_btn_styles(b, UiKit.skin("lime", 8, 16, 10), UiKit.skin("lime", 8, 16, 10), UiKit.skin("btn_press", 8, 16, 10))
	b.add_theme_stylebox_override("disabled", UiKit.skin("disabled", 8, 16, 10))
	var v := UiKit.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var h := UiKit.hbox(14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(text(t, 34, C_LIME_TEXT, "display"))
	var arrow := LineIcon.make("chevron_right", 34, C_LIME_TEXT)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(arrow)
	v.add_child(h)
	if sub != "":
		v.add_child(text(sub, 19, Color(0.06, 0.16, 0.04, 0.8), "semi", false, HORIZONTAL_ALIGNMENT_CENTER))
	_fill(b, v)
	_ignore_tree(v)
	_wire(b, cb, ui_id, t)
	return b


## Secondary action: glass button, 96 px.
static func ghost(t: String, cb: Callable, ui_id: String, color: Color = Color.WHITE) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, TOUCH)
	_btn_styles(b, flat(Color(0.12, 0.21, 0.37, 0.92), 16, 18.0, Color(0.70, 0.85, 1.0, 0.35)),
		flat(Color(0.16, 0.27, 0.46, 0.96), 16, 18.0, Color(0.80, 0.92, 1.0, 0.5)), flat(C_CARD_PRESS, 16, 18.0))
	b.text = t
	b.add_theme_font_override("font", UiKit.font_semi())
	b.add_theme_font_size_override("font_size", fs(25))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, color)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	_wire(b, cb, ui_id, t)
	return b


## Text-only link button (still 96 px tall for the touch target).
static func link(t: String, cb: Callable, ui_id: String, color: Color = C_MUTED) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, TOUCH)
	var e := StyleBoxEmpty.new()
	_btn_styles(b, e, e, e)
	b.text = t
	b.add_theme_font_size_override("font_size", fs(21))
	b.add_theme_font_override("font", UiKit.font_semi())
	for c in ["font_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, color)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	_wire(b, cb, ui_id, t)
	return b


## Tappable card: a PanelContainer holding a full-size Button (drawn behind, takes the tap) and the content on
## top (mouse-transparent). The card sizes to its content (wrapping text included). Optional stripe accent and
## highlight border; `styles` = [normal, hover, pressed] overrides the card look. The Button is in meta "button".
static func tap_card(content: Control, cb: Callable, ui_id: String, accent: Color = Color(0, 0, 0, 0), min_h: float = TOUCH, highlight: bool = false,
		press_text: String = "", styles: Array = [], pad: float = 18.0) -> Control:
	var wrap := PanelContainer.new()
	wrap.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	wrap.custom_minimum_size = Vector2(0, min_h)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	var b := Button.new()
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	if not styles.is_empty():
		_btn_styles(b, styles[0], styles[1], styles[2])
	else:
		var base := C_CARD.lerp(Color(0.16, 0.30, 0.20, 0.95), 0.55) if highlight else C_CARD
		if accent.a > 0.0:
			_btn_styles(b, striped(base, accent), striped(C_CARD_HOVER, accent), striped(C_CARD_PRESS, accent))
		else:
			_btn_styles(b, flat(base), flat(C_CARD_HOVER), flat(C_CARD_PRESS))
		if highlight:
			var hl := (b.get_theme_stylebox("normal") as StyleBoxFlat)
			hl.border_width_top = 2
			hl.border_width_right = 2
			hl.border_width_bottom = 2
			hl.border_color = C_LIME if accent.a <= 0.0 else accent
	wrap.add_child(b)
	var mc := MarginContainer.new()
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", int(pad + (8.0 if accent.a > 0.0 else 0.0)))
	mc.add_theme_constant_override("margin_right", int(pad))
	mc.add_theme_constant_override("margin_top", int(pad * 0.75))
	mc.add_theme_constant_override("margin_bottom", int(pad * 0.75))
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if content.size_flags_vertical == Control.SIZE_FILL:
		content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mc.add_child(content)
	_ignore_tree(content)
	wrap.add_child(mc)
	wrap.set_meta("button", b)
	_wire(b, cb, ui_id, press_text)
	return wrap


static func button_of(card: Control) -> Button:
	return card.get_meta("button") as Button


## Row: round icon, title + subtitle, right value, chevron. 104 px.
static func row(icon: String, title: String, sub: String, right: String, cb: Callable, ui_id: String, icon_color: Color = UiKit.C_CYAN) -> Control:
	var h := UiKit.hbox(18)
	h.add_child(icon_disc(icon, icon_color))
	var tv := UiKit.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_child(trim(text(title, 27, Color.WHITE, "semi")))
	if sub != "":
		tv.add_child(trim(text(sub, 19, C_MUTED)))
	h.add_child(tv)
	if right != "":
		var r := text(right, 22, Color.WHITE, "num", false, HORIZONTAL_ALIGNMENT_RIGHT)
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(r)
	var ch := LineIcon.make("chevron_right", 28, Color(1, 1, 1, 0.6))
	ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ch)
	return tap_card(h, cb, ui_id, Color(0, 0, 0, 0), 104, false, title, [], 16.0)


static func icon_disc(icon: String, color: Color, d: float = 60.0) -> Control:
	var p := PanelContainer.new()
	var sb := flat(Color(color.r, color.g, color.b, 0.16), int(d * 0.5), 0.0, Color(color.r, color.g, color.b, 0.45), 1)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(d, d)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(LineIcon.make(icon, d * 0.55, color))
	p.add_child(cc)
	return p


## Segmented control: equal-width options, the selected one lime. Calls cb(index).
static func segmented(labels: Array, current: int, cb: Callable, id_prefix: String) -> Control:
	var p := PanelContainer.new()
	var bg := flat(Color(0.03, 0.07, 0.14, 0.9), 18, 6.0, C_EDGE, 1)
	bg.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", bg)
	var h := UiKit.hbox(6)
	p.add_child(h)
	for i in labels.size():
		var b := Button.new()
		b.text = String(labels[i])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 84)
		b.add_theme_font_override("font", UiKit.font_caps())
		b.add_theme_font_size_override("font_size", fs(20))
		var on := i == current
		if on:
			_btn_styles(b, UiKit.skin("lime", 6, 10, 6), UiKit.skin("lime", 6, 10, 6), UiKit.skin("lime", 6, 10, 6))
		else:
			var e := flat(Color(0, 0, 0, 0), 14, 10.0, Color(0, 0, 0, 0), 0)
			_btn_styles(b, e, flat(Color(1, 1, 1, 0.06), 14, 10.0, Color(0, 0, 0, 0), 0), flat(Color(0, 0, 0, 0.2), 14, 10.0, Color(0, 0, 0, 0), 0))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, C_LIME_TEXT if on else C_MUTED)
		var idx := i
		_wire(b, func() -> void: cb.call(idx), "%s_%d" % [id_prefix, i], String(labels[i]))
		h.add_child(b)
	return p


# ------------------------------------------------------------------ data widgets

## Big number tile: caption, value (count-up when `num` >= 0), small subline.
static func stat(cap: String, value: String, sub: String = "", color: Color = Color.WHITE, size: float = 44.0, num: float = -1.0, fmt: Callable = Callable()) -> VBoxContainer:
	var v := UiKit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(caption(cap, C_MUTED))
	var l := text(value, size, color, "display")
	v.add_child(l)
	if num >= 0.0 and fmt.is_valid():
		count_up(l, num, fmt)
	if sub != "":
		v.add_child(trim(text(sub, 18, C_MUTED)))
	return v


static func progress(value: float, color: Color = C_LIME, h: float = 12.0) -> Control:
	var b := Bar.new()
	b.target = clampf(value, 0.0, 1.0)
	b.color = color
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if reduced():
		b.value = b.target
	else:
		b.ready.connect(func() -> void:
			var tw := b.create_tween()
			tw.tween_property(b, "value", b.target, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.15), CONNECT_ONE_SHOT)
	return b


static func move_arrow(delta: int, show_number: bool = true, size: float = 18.0) -> Control:
	var h := UiKit.hbox(4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var a := Arrow.new()
	a.delta = delta
	a.custom_minimum_size = Vector2(size, size)
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(a)
	if show_number and delta != 0:
		h.add_child(text(str(absi(delta)), size, C_UP if delta > 0 else C_DOWN, "num"))
	return h


## One table row: rank, movement, name (+ nation code), sub, value. The player's row is highlighted.
static func rank_row(rank: String, name: String, value: String, delta: int = 0, is_me: bool = false, sub: String = "", has_move: bool = true) -> Control:
	var h := UiKit.hbox(10)
	var rl := text(rank, 23, Color.WHITE if not is_me else C_LIME, "num", false, HORIZONTAL_ALIGNMENT_RIGHT)
	rl.custom_minimum_size.x = 58
	h.add_child(rl)
	var mv := Control.new()
	mv.custom_minimum_size = Vector2(46, 0)
	mv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if has_move:
		var a := move_arrow(delta, true, 16)
		a.position = Vector2(4, 8)
		mv.add_child(a)
	h.add_child(mv)
	var nm := trim(text(name, 23, Color.WHITE if not is_me else C_LIME, "semi" if is_me else ""))
	h.add_child(nm)
	if sub != "":
		h.add_child(text(sub, 18, C_MUTED, "num", false, HORIZONTAL_ALIGNMENT_RIGHT))
	var vl := text(value, 23, Color.WHITE if not is_me else C_LIME, "num", false, HORIZONTAL_ALIGNMENT_RIGHT)
	vl.custom_minimum_size.x = 96
	h.add_child(vl)
	var sb := flat(Color(0.63, 0.95, 0.27, 0.16) if is_me else Color(0, 0, 0, 0), 10, 8.0, Color(0.71, 0.97, 0.35, 0.6) if is_me else Color(0, 0, 0, 0), 1 if is_me else 0)
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	return card(h, sb)


static func line_marker(t: String, color: Color = UiKit.C_WARN) -> Control:
	var h := UiKit.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l1 := ColorRect.new()
	l1.color = Color(color.r, color.g, color.b, 0.5)
	l1.custom_minimum_size = Vector2(24, 2)
	l1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l1)
	h.add_child(text(t.to_upper(), 16, color, "caps"))
	var l2 := ColorRect.new()
	l2.color = Color(color.r, color.g, color.b, 0.5)
	l2.custom_minimum_size = Vector2(0, 2)
	l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l2)
	return h


## Trophy: a cup icon in the kind's colour with a count. Dimmed when zero.
static func trophy(kind_label: String, count: int, color: Color) -> Control:
	var v := UiKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var on := count > 0
	var col := color if on else Color(0.55, 0.62, 0.72, 0.35)
	var cc := CenterContainer.new()
	cc.add_child(icon_disc("trophy", col, 72))
	v.add_child(cc)
	v.add_child(text(str(count), 30, col if on else C_FAINT, "display", false, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(text(kind_label.to_upper(), 14, col if on else C_FAINT, "caps", true, HORIZONTAL_ALIGNMENT_CENTER))
	return v


# ------------------------------------------------------------------ motion

## Counts a label up from 0 to `to` (formatted by fmt(float) -> String). Instant under Reduced motion.
static func count_up(l: Label, to: float, fmt: Callable, dur: float = 0.7) -> void:
	l.text = String(fmt.call(to))
	if reduced() or to == 0.0:
		return
	var setter := func(v: float) -> void:
		if is_instance_valid(l):
			l.text = String(fmt.call(v))
	setter.call(0.0)
	l.ready.connect(func() -> void:
		var tw := l.create_tween()
		tw.tween_method(setter, 0.0, to, dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT).set_delay(0.1), CONNECT_ONE_SHOT)


## Fade a block in after `i` x 60 ms (staggered page entrance). No-op under Reduced motion.
static func appear(c: Control, i: int = 0) -> Control:
	if reduced():
		return c
	c.modulate.a = 0.0
	c.ready.connect(func() -> void:
		var tw := c.create_tween()
		tw.tween_property(c, "modulate:a", 1.0, 0.28).set_delay(0.04 + 0.06 * i), CONNECT_ONE_SHOT)
	return c


# ------------------------------------------------------------------ page shells

## Career backdrop: deep navy with a tinted glow behind the header (opaque: hides the menu backdrop).
static func backdrop(tint: Color = C_REGULAR) -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.colors = PackedColorArray([Color("#0E2244"), Color("#08111F"), Color("#050A13")])
	g.offsets = PackedFloat32Array([0.0, 0.42, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 256
	var bg := TextureRect.new()
	bg.texture = gt
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var rg := Gradient.new()
	rg.colors = PackedColorArray([Color(tint.r, tint.g, tint.b, 0.30), Color(tint.r, tint.g, tint.b, 0.0)])
	var rt := GradientTexture2D.new()
	rt.gradient = rg
	rt.fill = GradientTexture2D.FILL_RADIAL
	rt.fill_from = Vector2(0.5, 0.5)
	rt.fill_to = Vector2(1.0, 0.5)
	rt.width = 128
	rt.height = 128
	var glow := TextureRect.new()
	glow.texture = rt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.anchor_left = -0.4
	glow.anchor_right = 1.1
	glow.anchor_top = -0.25
	glow.anchor_bottom = 0.35
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(glow)
	return root


static func back_button(cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(TOUCH, TOUCH)
	_btn_styles(b, flat(Color(1, 1, 1, 0.08), 28, 0.0, Color(1, 1, 1, 0.18), 1), flat(Color(1, 1, 1, 0.16), 28, 0.0, Color(1, 1, 1, 0.3), 1),
		flat(Color(0, 0, 0, 0.3), 28, 0.0))
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(LineIcon.make("chevron_left", 40))
	b.add_child(cc)
	_wire(b, cb, "back", "")
	return b


## Detail page: backdrop, back + title header, scrolling body, fixed footer. Same keys as MainMenu._page:
## {root, body, footer, scroll, head}.
static func page(menu: MainMenu, title: String, sub: String = "", tint: Color = C_REGULAR) -> Dictionary:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_meta("career_page", true)
	root.add_child(backdrop(tint))
	var sm := menu._safe()
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", int(sm[0]) - 4)
	m.add_theme_constant_override("margin_right", int(sm[2]) - 4)
	m.add_theme_constant_override("margin_top", int(sm[1]))
	m.add_theme_constant_override("margin_bottom", int(sm[3]) - 8)
	root.add_child(m)
	var v := UiKit.vbox(16)
	m.add_child(v)
	var head := UiKit.hbox(18)
	head.add_child(back_button(menu._pop))
	var tv := UiKit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	if sub != "":
		tv.add_child(caption(sub, tint.lerp(Color.WHITE, 0.25)))
	var tl := trim(text(title, 36, Color.WHITE, "display"))
	tv.add_child(tl)
	head.add_child(tv)
	v.add_child(head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 14
	v.add_child(sc)
	var body := UiKit.vbox(16)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	var footer := UiKit.vbox(8)
	v.add_child(footer)
	return {"root": root, "body": body, "footer": footer, "scroll": sc, "head": head}


# ------------------------------------------------------------------ rank movement (UI-only cache)

static var _moves: Dictionary = {}
static var _moves_key := ""


static func _cache_path(c: CareerManager) -> String:
	return "user://career_ui_ranks_%s.json" % c.store.dir.md5_text().substr(0, 8)


## Remembers the previous World Ranking / Season Standings tables (presentation cache, never part of the save)
## and returns {world: {id: delta}, ss: {id: delta}} (positive = moved up since the previous table).
static func note_ranks(c: CareerManager) -> Dictionary:
	var wn := ((c.world()["applied"]) as Dictionary).size()
	var sn := ((c.standings()["applied"]) as Dictionary).size()
	var key := "%s|%d|%d|%d|%d" % [c.store.dir, c.career_seed(), c.season_number(), wn, sn]
	if key == _moves_key:
		return _moves
	var path := _cache_path(c)
	var d: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			d = parsed
	var wt := c.world_table()
	var kinds := {"world": [str(c.career_seed()), wn, RankingManager.rank_map(wt)],
		"ss": ["%d|%d" % [c.career_seed(), c.season_number()], sn, RankingManager.rank_map(c.standings_table(wt))]}
	var changed := false
	var out := {}
	for k in kinds:
		var spec: Array = kinds[k]
		var e: Dictionary = d.get(k, {})
		if String(e.get("key", "")) != String(spec[0]):
			e = {"key": spec[0], "n": spec[1], "cur": spec[2], "prev": {}}
			changed = true
		elif int(e.get("n", -1)) != int(spec[1]):
			e["prev"] = e.get("cur", {})
			e["cur"] = spec[2]
			e["n"] = spec[1]
			changed = true
		d[k] = e
		var prev: Dictionary = e.get("prev", {})
		var cur: Dictionary = spec[2]
		var mv := {}
		for id in cur:
			if prev.has(id):
				mv[id] = int(prev[id]) - int(cur[id])
		out[k] = mv
	# the player's own arrow always shows the movement from the last event (matches the hero and the report)
	var last := CareerWorldPages._last_result(c)
	if not last.is_empty():
		(out["world"] as Dictionary)[CareerManager.PLAYER] = int(last.get("world_rank_before", 0)) - int(last.get("world_rank_after", 0))
		if sn > 0 and int(last.get("season_rank_before", 0)) > 0:
			(out["ss"] as Dictionary)[CareerManager.PLAYER] = int(last.get("season_rank_before", 0)) - int(last.get("season_rank_after", 0))
	if changed:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(d))
	_moves = out
	_moves_key = key
	return out


# ------------------------------------------------------------------ drawn bits

class Arrow extends Control:
	var delta := 0

	func _draw() -> void:
		var s := size
		if delta > 0:
			draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.5, s.y * 0.12), Vector2(s.x * 0.95, s.y * 0.85), Vector2(s.x * 0.05, s.y * 0.85)]), C_UP)
		elif delta < 0:
			draw_colored_polygon(PackedVector2Array([Vector2(s.x * 0.05, s.y * 0.15), Vector2(s.x * 0.95, s.y * 0.15), Vector2(s.x * 0.5, s.y * 0.88)]), C_DOWN)
		else:
			draw_rect(Rect2(Vector2(s.x * 0.2, s.y * 0.44), Vector2(s.x * 0.6, maxf(2.0, s.y * 0.12))), C_FAINT)


class Bar extends Control:
	var color := Color.WHITE
	var target := 0.0
	var value := 0.0:
		set(v):
			value = v
			queue_redraw()

	func _draw() -> void:
		var r := size.y * 0.5
		_pill(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.10), r)
		if value > 0.0:
			_pill(Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * value), size.y)), color, r)

	func _pill(rect: Rect2, c: Color, r: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(int(r))
		sb.anti_aliasing = true
		draw_style_box(sb, rect)

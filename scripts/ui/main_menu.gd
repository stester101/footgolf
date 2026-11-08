class_name MainMenu
extends Control
## Foot Golf main menu and menu navigation.
##
## Navigation (a stack of pages; every page has the same Back control and Android Back pops one):
##   Main menu
##     Single Player / Course Select -> Round Setup -> Start Round -> gameplay
##     Multiplayer (Coming Soon; future: Host / Join -> Lobby -> Course Select -> Round Setup)
##     Settings -> Gameplay / Controls / Audio + Visual / Developer
##     Statistics -> Overview / Round History / Records
##     How to Play (tutorial)
## Only features that exist are functional; the rest are clearly labelled placeholders.

signal play_requested(course_id: String, dev: bool, mulligans: int, players: int)

const WORD_GREEN := Color("#3AB52B")

## Remembered while the app runs, so Round Setup reopens with the previous choice.
static var _last_mulligans := 0
static var _last_players := 1

var _pages: Control
var _stack: Array[Control] = []
var _tutorial: Tutorial
var _overlay: Control


func setup() -> void:
	theme = UiKit.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_backdrop()
	_pages = Control.new()
	_pages.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pages)
	_push(_build_home())
	if not App.settings.tutorial_seen and not OS.get_cmdline_user_args().has("--smoke-test"):
		show_tutorial.call_deferred()


# ------------------------------------------------------------------ backdrop

func _build_backdrop() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#060C17")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# soft light pools in the mood of a dark clubhouse: cool window glow, warm lamp, blue floor
	_glow(Rect2(-0.40, 0.00, 1.20, 0.60), Color(0.22, 0.48, 0.62, 0.40))
	_glow(Rect2(0.45, -0.12, 0.95, 0.52), Color(0.95, 0.62, 0.28, 0.28))
	_glow(Rect2(-0.25, 0.50, 1.50, 0.70), Color(0.10, 0.22, 0.44, 0.40))


func _glow(r: Rect2, col: Color) -> void:
	var g := Gradient.new()
	g.colors = PackedColorArray([col, Color(col.r, col.g, col.b, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	var tr := TextureRect.new()
	tr.texture = t
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.anchor_left = r.position.x
	tr.anchor_top = r.position.y
	tr.anchor_right = r.end.x
	tr.anchor_bottom = r.end.y
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)


# ------------------------------------------------------------------ navigation

func _push(page: Control) -> void:
	if not _stack.is_empty():
		_stack.back().visible = false
	_pages.add_child(page)
	_stack.append(page)


func _pop() -> void:
	if _stack.size() <= 1:
		return
	var p: Control = _stack.pop_back()
	p.queue_free()
	_stack.back().visible = true


## Shows an overlay (par editor, export, tutorial) above the pages. The page beneath is hidden
## while it is open, so nothing shows through, and comes back when the overlay closes.
func _present(root: Control) -> void:
	_overlay = root
	if not _stack.is_empty():
		_stack.back().visible = false
	add_child(root)
	root.tree_exited.connect(func() -> void:
		if _overlay == root:
			_overlay = null
			if not _stack.is_empty():
				_stack.back().visible = true)


## Android Back: close a tutorial or overlay first, then go up one page. False = at the main menu.
func handle_back() -> bool:
	if _tutorial != null and is_instance_valid(_tutorial):
		_tutorial.finished.emit()
		return true
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
		return true
	if _stack.size() > 1:
		_pop()
		return true
	return false


# ------------------------------------------------------------------ shared building blocks

func _safe() -> Array:
	return UiKit.safe_margins(get_viewport())


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.72, 0.88, 1.0, 0.22)
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _caption(text: String) -> Label:
	var l := UiKit.label(text, 19, UiKit.C_CYAN)
	l.add_theme_font_override("font", UiKit.font_caps())
	return l


func _icon_button(kind: String, cb: Callable, ui_id: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(68, 68)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("ui_id", ui_id)
	b.add_theme_stylebox_override("normal", UiKit.skin("btn", 6, 0, 0))
	b.add_theme_stylebox_override("hover", UiKit.skin("btn_hover", 6, 0, 0))
	b.add_theme_stylebox_override("pressed", UiKit.skin("btn_press", 6, 0, 0))
	b.pressed.connect(cb)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(LineIcon.make(kind, 34))
	b.add_child(c)
	return b


## Standard sub-page: glass panel with Back + title, scrolling body, fixed footer.
## Returns {root, body, footer, scroll}.
func _page(title: String) -> Dictionary:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := _safe()
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", int(sm[0]) + 28)
	m.add_theme_constant_override("margin_right", int(sm[2]) + 28)
	m.add_theme_constant_override("margin_top", int(sm[1]) + 36)
	m.add_theme_constant_override("margin_bottom", int(sm[3]) + 28)
	root.add_child(m)
	var panel := UiKit.panel(UiKit.C_PANEL_SOLID)
	m.add_child(panel)
	var v := UiKit.vbox(14)
	panel.add_child(v)
	var head := UiKit.hbox(14)
	head.add_child(_icon_button("chevron_left", _pop, "back"))
	var t := UiKit.label(title, 38, Color.WHITE)
	t.add_theme_font_override("font", UiKit.font_semi())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(t)
	v.add_child(head)
	v.add_child(_rule())
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 14
	v.add_child(sc)
	var body := UiKit.vbox(12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	var footer := UiKit.vbox(10)
	v.add_child(footer)
	return {"root": root, "body": body, "footer": footer, "scroll": sc}


## One tappable row: icon, title, optional subtitle, chevron.
func _nav_row(icon: String, title: String, subtitle: String, cb: Callable, ui_id: String = "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 96)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("press_text", title)
	if ui_id != "":
		b.set_meta("ui_id", ui_id)
	b.add_theme_stylebox_override("normal", UiKit.skin("btn", 6, 0, 0))
	b.add_theme_stylebox_override("hover", UiKit.skin("btn_hover", 6, 0, 0))
	b.add_theme_stylebox_override("pressed", UiKit.skin("btn_press", 6, 0, 0))
	b.pressed.connect(cb)
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 20)
	mc.add_theme_constant_override("margin_right", 18)
	var h := UiKit.hbox(18)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := LineIcon.make(icon, 46)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var tv := UiKit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := UiKit.label(title, 30, Color.WHITE)
	tl.add_theme_font_override("font", UiKit.font_semi())
	tv.add_child(tl)
	if subtitle != "":
		tv.add_child(UiKit.label(subtitle, 19, UiKit.C_MUTED))
	h.add_child(tv)
	var ch := LineIcon.make("chevron_right", 30, Color(1, 1, 1, 0.85))
	ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ch)
	mc.add_child(h)
	b.add_child(mc)
	return b


func _primary_button(text: String, cb: Callable, ui_id: String) -> Button:
	var b := UiKit.primary(Button.new())
	b.custom_minimum_size = Vector2(0, 92)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("ui_id", ui_id)
	b.set_meta("press_text", text)
	b.pressed.connect(cb)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 32, Color.WHITE)
	l.add_theme_font_override("font", UiKit.font_semi())
	c.add_child(l)
	b.add_child(c)
	return b


func _note(text: String) -> Label:
	var l := UiKit.text(text, 19, UiKit.C_MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# ------------------------------------------------------------------ main menu

func _build_home() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := _safe()
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", int(sm[0]) + 44)
	m.add_theme_constant_override("margin_right", int(sm[2]) + 44)
	m.add_theme_constant_override("margin_top", int(sm[1]) + 28)
	m.add_theme_constant_override("margin_bottom", int(sm[3]) + 28)
	root.add_child(m)
	var v := UiKit.vbox(8)
	m.add_child(v)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/branding/fg_logo.png")
	var side := clampf(get_viewport_rect().size.y * 0.22, 150.0, 290.0)
	logo.custom_minimum_size = Vector2(side, side)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(logo)
	# wordmark: FOOT in metallic white, GOLF in darker green, with a green swoosh
	var wm := UiKit.hbox(10)
	wm.alignment = BoxContainer.ALIGNMENT_CENTER
	wm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in [["FOOT", Color("#EEF3F9"), Color(0.10, 0.26, 0.52, 0.95)], ["GOLF", WORD_GREEN, Color(0.02, 0.20, 0.06, 0.95)]]:
		var l := UiKit.label(String(part[0]), 84, part[1])
		l.add_theme_font_override("font", UiKit.font_display())
		l.add_theme_color_override("font_outline_color", part[2])
		l.add_theme_constant_override("outline_size", 8)
		wm.add_child(l)
	v.add_child(wm)
	var sw := Control.new()
	sw.custom_minimum_size = Vector2(520, 22)
	sw.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ln := Line2D.new()
	ln.width = 9.0
	ln.default_color = Color("#47C22D")
	ln.antialiased = true
	var taper := Curve.new()
	taper.add_point(Vector2(0.0, 0.3))
	taper.add_point(Vector2(0.5, 1.0))
	taper.add_point(Vector2(1.0, 0.3))
	ln.width_curve = taper
	for k in 21:
		var tt := float(k) / 20.0
		ln.add_point(Vector2(520.0 * tt, 5.0 + 11.0 * sin(PI * tt)))
	sw.add_child(ln)
	v.add_child(sw)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(gap)
	# menu cards (scroll if the screen is short)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 14
	v.add_child(sc)
	var list := UiKit.vbox(12)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	list.add_child(_nav_row("player", "Single Player", "", _open_course_select, "menu_single"))
	list.add_child(_multiplayer_card())
	list.add_child(_nav_row("course", "Course Select", "", _open_course_select, "menu_courses"))
	list.add_child(_nav_row("gear", "Settings", "", _open_settings, "menu_settings"))
	list.add_child(_nav_row("bars", "Statistics", "", _open_statistics, "menu_stats"))
	list.add_child(_nav_row("help", "How to Play", "", show_tutorial, "menu_help"))
	# tagline
	var tag := UiKit.hbox(14)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		if i == 1:
			var tl := UiKit.label("KICK  ·  SCORE  ·  ENJOY", 20, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
			tl.add_theme_font_override("font", UiKit.font_caps())
			tag.add_child(tl)
		else:
			var line := ColorRect.new()
			line.color = Color(0.45, 0.65, 0.95, 0.45)
			line.custom_minimum_size = Vector2(0, 2)
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tag.add_child(line)
	v.add_child(tag)
	return root


## Multiplayer is not built yet: a disabled card marked Coming Soon. Future flow:
## Host / Join -> Lobby -> Course Select -> Round Setup (no networking in this version).
func _multiplayer_card() -> Control:
	var b := _nav_row("people", "Multiplayer", "", func() -> void: pass, "menu_multiplayer")
	b.disabled = true
	b.set_meta("press_text", "Multiplayer")
	b.add_theme_stylebox_override("disabled", UiKit.skin("btn", 6, 0, 0))
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiKit.skin("select", 6, 14, 3))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pl := UiKit.label("Coming Soon", 19, Color.WHITE)
	pl.add_theme_font_override("font", UiKit.font_semi())
	pill.add_child(pl)
	# put the pill under the title (second line of the title column)
	var tv: VBoxContainer = ((b.get_child(0) as MarginContainer).get_child(0) as HBoxContainer).get_child(1) as VBoxContainer
	tv.add_child(pill)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.modulate = Color(1, 1, 1, 0.8)
	return b


# ------------------------------------------------------------------ course select + round setup

func _open_course_select() -> void:
	var pg := _page("Course Select")
	var body: VBoxContainer = pg["body"]
	var current: Control = null
	for c in App.courses():
		var card := _course_card(c)
		if String(c["id"]) == App.settings.last_course:
			current = card
		body.add_child(card)
	_push(pg["root"])
	if current != null:
		(pg["scroll"] as ScrollContainer).ensure_control_visible.call_deferred(current)


func _course_card(c: Dictionary) -> Button:
	var cid := String(c["id"])
	var last := cid == App.settings.last_course
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 132)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("press_text", String(c["name"]))
	b.set_meta("ui_id", "course_" + cid)
	var kind := "select" if last else "btn"
	b.add_theme_stylebox_override("normal", UiKit.skin(kind, 6, 0, 0))
	b.add_theme_stylebox_override("hover", UiKit.skin("select" if last else "btn_hover", 6, 0, 0))
	b.add_theme_stylebox_override("pressed", UiKit.skin("btn_press", 6, 0, 0))
	b.pressed.connect(func() -> void: _open_round_setup(cid))
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 22)
	mc.add_theme_constant_override("margin_right", 18)
	mc.add_theme_constant_override("margin_top", 10)
	mc.add_theme_constant_override("margin_bottom", 10)
	var h := UiKit.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tv := UiKit.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UiKit.label(String(c["name"]), 32, Color.WHITE)
	nm.add_theme_font_override("font", UiKit.font_semi())
	tv.add_child(nm)
	var holes := (c.get("holes", []) as Array).size()
	var info := UiKit.label("%d HOLES  ·  PAR %d%s" % [holes, App.course_par(cid), "  ·  LAST PLAYED" if last else ""], 18, UiKit.C_CYAN)
	info.add_theme_font_override("font", UiKit.font_caps())
	tv.add_child(info)
	var bl := UiKit.label(String(c.get("blurb", "")), 20, Color(1, 1, 1, 0.78))
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(bl)
	h.add_child(tv)
	var ch := LineIcon.make("chevron_right", 30, Color(1, 1, 1, 0.85))
	ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ch)
	mc.add_child(h)
	b.add_child(mc)
	return b


func _open_round_setup(course_id: String) -> void:
	var info := App.course_info(course_id)
	var pg := _page("Round Setup")
	var body: VBoxContainer = pg["body"]
	# selected course
	var cp := PanelContainer.new()
	cp.add_theme_stylebox_override("panel", UiKit.skin("select", 6, 20, 14))
	cp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cv := UiKit.vbox(2)
	var cn := UiKit.label(String(info.get("name", course_id)), 36, Color.WHITE)
	cn.add_theme_font_override("font", UiKit.font_semi())
	cv.add_child(cn)
	var ci := UiKit.label("%d HOLES  ·  PAR %d" % [(info.get("holes", []) as Array).size(), App.course_par(course_id)], 19, Color(1, 1, 1, 0.9))
	ci.add_theme_font_override("font", UiKit.font_caps())
	cv.add_child(ci)
	cv.add_child(UiKit.text(String(info.get("blurb", "")), 21, Color(1, 1, 1, 0.8)))
	cp.add_child(cv)
	body.add_child(cp)
	# players: 1 = solo, 2 to 4 = pass-and-play on this phone (one shot each, in turn)
	body.add_child(_caption("PLAYERS"))
	var pchoices := HBoxContainer.new()
	pchoices.add_theme_constant_override("separation", 10)
	var pbtns: Array[Button] = []
	var prefresh := func() -> void:
		for i in pbtns.size():
			var on := (i + 1) == _last_players
			pbtns[i].add_theme_stylebox_override("normal", UiKit.skin("lime" if on else "recess", 6, 16, 8))
			pbtns[i].add_theme_stylebox_override("hover", UiKit.skin("lime" if on else "btn", 6, 16, 8))
			pbtns[i].add_theme_color_override("font_color", Color("#0E2A07") if on else Color.WHITE)
			pbtns[i].add_theme_color_override("font_hover_color", Color("#0E2A07") if on else Color.WHITE)
	for n in 4:
		var pb := Button.new()
		pb.text = "Solo" if n == 0 else "%d players" % (n + 1)
		pb.custom_minimum_size = Vector2(0, 62)
		pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pb.focus_mode = Control.FOCUS_NONE
		pb.add_theme_font_size_override("font_size", 21)
		pb.add_theme_font_override("font", UiKit.font_semi())
		pb.set_meta("ui_id", "players_%d" % (n + 1))
		var count := n + 1
		pb.pressed.connect(func() -> void:
			_last_players = count
			prefresh.call())
		pbtns.append(pb)
		pchoices.add_child(pb)
	prefresh.call()
	body.add_child(pchoices)
	body.add_child(_note("Pass-and-play: each player takes one shot in turn on this phone. Footballers are shared, so each can be used once per round."))
	# mulligans
	body.add_child(_caption("MULLIGANS"))
	var choices := HFlowContainer.new()
	choices.add_theme_constant_override("h_separation", 10)
	choices.add_theme_constant_override("v_separation", 10)
	var btns: Array[Button] = []
	var values := [0, 1, 3, 5, -1]
	var names := ["Off", "1", "3", "5", "Unlimited"]
	var refresh := func() -> void:
		for i in btns.size():
			var on: bool = int(values[i]) == _last_mulligans
			btns[i].add_theme_stylebox_override("normal", UiKit.skin("lime" if on else "recess", 6, 16, 8))
			btns[i].add_theme_stylebox_override("hover", UiKit.skin("lime" if on else "btn", 6, 16, 8))
			btns[i].add_theme_color_override("font_color", Color("#0E2A07") if on else Color.WHITE)
			btns[i].add_theme_color_override("font_hover_color", Color("#0E2A07") if on else Color.WHITE)
	for i in values.size():
		var cb := Button.new()
		cb.text = String(names[i])
		cb.custom_minimum_size = Vector2(0, 62)
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 24)
		cb.add_theme_font_override("font", UiKit.font_semi())
		cb.set_meta("ui_id", "mulligan_%s" % String(names[i]).to_lower())
		var v := int(values[i])
		cb.pressed.connect(func() -> void:
			_last_mulligans = v
			refresh.call())
		btns.append(cb)
		choices.add_child(cb)
	refresh.call()
	body.add_child(choices)
	body.add_child(_note("Redo the last shot from its result screen. The choice stays fixed for this round."))
	# rules in force (read-only here; changed in Settings > Gameplay)
	body.add_child(_caption("RULES FOR THIS ROUND"))
	var rules := PanelContainer.new()
	rules.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 18, 12))
	rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rv := UiKit.vbox(6)
	for pair in [["Hole size", "%s in" % _trim(App.settings.physics.cup_diameter_in())],
			["Auto hole-out", "%s ft" % _trim(App.settings.holeout_radius_ft)],
			["Maximum score", "None"]]:
		var rr := UiKit.hbox(10)
		var rl := UiKit.label(String(pair[0]), 22, UiKit.C_MUTED)
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rr.add_child(rl)
		var rv2 := UiKit.label(String(pair[1]), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
		rv2.add_theme_font_override("font", UiKit.font_semi())
		rr.add_child(rv2)
		rv.add_child(rr)
	rules.add_child(rv)
	body.add_child(rules)
	body.add_child(_note("Change hole size and auto hole-out in Settings > Gameplay."))
	(pg["footer"] as VBoxContainer).add_child(_primary_button("Start round", func() -> void:
		play_requested.emit(course_id, false, _last_mulligans, _last_players), "start_round"))
	_push(pg["root"])


static func _trim(v: float) -> String:
	return str(int(round(v))) if absf(v - round(v)) < 0.005 else "%.2f" % v


# ------------------------------------------------------------------ settings

func _open_settings() -> void:
	var pg := _page("Settings")
	var body: VBoxContainer = pg["body"]
	body.add_child(_nav_row("flag", "Gameplay", "Hole size, auto hole-out, hole pars", _open_settings_gameplay, "settings_gameplay"))
	body.add_child(_nav_row("target", "Controls", "Aiming and shot controls", _open_settings_controls, "settings_controls"))
	body.add_child(_nav_row("sliders", "Audio / Visual", "Sound and ball trail", _open_settings_visual, "settings_visual"))
	body.add_child(_nav_row("gear", "Developer", "Testing tools, data, build info", _open_settings_developer, "settings_developer"))
	_push(pg["root"])


func _setting_row(label: String, control: Control) -> Control:
	var row := UiKit.hbox(12)
	var l := UiKit.label(label, 24, Color.WHITE)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	row.add_child(control)
	return row


func _open_settings_gameplay() -> void:
	var pg := _page("Gameplay")
	var body: VBoxContainer = pg["body"]
	var st: SettingsStore = App.settings
	body.add_child(_setting_row("Auto hole-out radius (ft)", UiKit.spin(0, 10, 0.5, st.holeout_radius_ft, func(val: float) -> void:
		st.holeout_radius_ft = ScoringService.clamp_radius_ft(val)
		st.save())))
	body.add_child(_setting_row("Hole size (diameter, in)", UiKit.spin(4.25, 40, 0.25, st.physics.cup_diameter_in(), func(val: float) -> void:
		st.physics.set_cup_diameter_in(val)
		st.save())))
	body.add_child(_note("Regulation is 4.25 in. The game default is a friendlier 12 in. 0 ft hole-out means the ball must drop."))
	body.add_child(_nav_row("flag", "Edit hole pars", "Applies to rounds started afterwards", _show_par_editor))
	_push(pg["root"])


## Placeholder: the aiming and shot controls are fixed in this version.
func _open_settings_controls() -> void:
	var pg := _page("Controls")
	var body: VBoxContainer = pg["body"]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 20, 16))
	var v := UiKit.vbox(6)
	var t := UiKit.label("Coming later", 26, Color.WHITE)
	t.add_theme_font_override("font", UiKit.font_semi())
	v.add_child(t)
	v.add_child(_note("Aiming (drag), spin and trajectory are fixed for now. Options such as control scheme and left-handed layout will appear here."))
	p.add_child(v)
	body.add_child(p)
	_push(pg["root"])


func _open_settings_visual() -> void:
	var pg := _page("Audio / Visual")
	var body: VBoxContainer = pg["body"]
	var st: SettingsStore = App.settings
	var trail := CheckButton.new()
	trail.text = "Show ball trail"
	trail.button_pressed = st.show_trail
	trail.toggled.connect(func(on: bool) -> void:
		st.show_trail = on
		st.save())
	body.add_child(trail)
	body.add_child(_note("Audio: none yet (silent). Sound and vibration are planned."))
	_push(pg["root"])


func _open_settings_developer() -> void:
	var pg := _page("Developer")
	var body: VBoxContainer = pg["body"]
	var st: SettingsStore = App.settings
	body.add_child(_nav_row("gear", "Developer Test", "All 17 holes with the developer panel", func() -> void: play_requested.emit("all", true, 0, 1), "developer_test"))
	var stats := CheckButton.new()
	stats.text = "TEST MODE: show caps/goals before shot"
	stats.button_pressed = st.show_stats
	stats.toggled.connect(func(on: bool) -> void:
		st.show_stats = on
		st.save())
	body.add_child(stats)
	var ds := CheckButton.new()
	ds.text = "Use real footballers (off = synthetic test set)"
	ds.button_pressed = st.dataset == "real"
	var ds_label := _note(App.dataset_label())
	ds.toggled.connect(func(on: bool) -> void:
		st.dataset = "real" if on else "test"
		st.save()
		App.load_dataset()
		ds_label.text = App.dataset_label())
	body.add_child(ds)
	body.add_child(ds_label)
	body.add_child(_nav_row("flag", "Reset footballer database", "Back to the bundled seed", func() -> void: App.repo.reset_to_seed()))
	body.add_child(_nav_row("list", "Export data", "Copy a summary or save CSV / JSON files", _show_export))
	body.add_child(_note("Foot Golf  ·  %s" % App.build_label()))
	_push(pg["root"])


# ------------------------------------------------------------------ statistics (overview real, rest placeholders)

func _open_statistics() -> void:
	var pg := _page("Statistics")
	var body: VBoxContainer = pg["body"]
	body.add_child(_nav_row("bars", "Overview", "What is recorded on this device", _open_stats_overview, "stats_overview"))
	body.add_child(_nav_row("list", "Round History", "Finished rounds", func() -> void: _open_placeholder("Round History",
		"Finished rounds will be listed here once saving and History are built. Shots are already recorded for export (Settings > Developer > Export data)."), "stats_history"))
	body.add_child(_nav_row("target", "Records", "Personal bests", func() -> void: _open_placeholder("Records",
		"Personal bests per course and rule set will appear here once History is built."), "stats_records"))
	_push(pg["root"])


func _open_stats_overview() -> void:
	var pg := _page("Overview")
	var body: VBoxContainer = pg["body"]
	var rounds := 0
	var holes := 0
	var shots := 0
	if App.telemetry != null:
		var recs := App.telemetry.load_records()
		rounds = TelemetryLog.of_type(recs, "round_start").size()
		holes = TelemetryLog.of_type(recs, "hole").size()
		shots = TelemetryLog.of_type(recs, "shot").size()
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 10)
	for pair in [["ROUNDS", rounds], ["HOLES", holes], ["SHOTS", shots]]:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 12, 14))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UiKit.vbox(0)
		var n := UiKit.label(str(int(pair[1])), 44, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		n.add_theme_font_override("font", UiKit.font_semi())
		v.add_child(n)
		var c := UiKit.label(String(pair[0]), 16, UiKit.C_CYAN, HORIZONTAL_ALIGNMENT_CENTER)
		c.add_theme_font_override("font", UiKit.font_caps())
		v.add_child(c)
		p.add_child(v)
		grid.add_child(p)
	body.add_child(grid)
	body.add_child(_note("Recorded on this device. Full statistics (fairways, greens, putts) come with History."))
	body.add_child(_nav_row("list", "Export data", "Copy a summary or save CSV / JSON files", _show_export))
	_push(pg["root"])


func _open_placeholder(title: String, text: String) -> void:
	var pg := _page(title)
	var body: VBoxContainer = pg["body"]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 20, 16))
	var v := UiKit.vbox(6)
	var t := UiKit.label("Coming later", 26, Color.WHITE)
	t.add_theme_font_override("font", UiKit.font_semi())
	v.add_child(t)
	v.add_child(_note(text))
	p.add_child(v)
	body.add_child(p)
	_push(pg["root"])


# ------------------------------------------------------------------ tutorial, par editor, export (existing screens)

func show_tutorial() -> void:
	if _tutorial != null and is_instance_valid(_tutorial):
		return
	_tutorial = Tutorial.new()
	_present(_tutorial)
	_tutorial.setup()
	_tutorial.finished.connect(func() -> void:
		App.settings.tutorial_seen = true
		App.settings.save()
		_tutorial.queue_free()
		_tutorial = null)


## Per-hole par editor (3/4/5 or anything 2-8). Applies to rounds started afterwards.
func _show_par_editor() -> void:
	var root := UiKit.overlay(0.7)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 32)
	root.add_child(m)
	var p := UiKit.panel(UiKit.C_SURFACE)
	m.add_child(p)
	var v := UiKit.vbox(12)
	p.add_child(v)
	v.add_child(UiKit.label("Hole pars", 34))
	v.add_child(UiKit.text("Set each hole's par. Scores have no maximum; par only changes the +/- shown. Applies to the next round.", 19, UiKit.C_MUTED))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.scroll_deadzone = 14
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := UiKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for info in App.all_hole_infos():
		var hid: String = info["id"]
		var row := UiKit.hbox(10)
		var nm := UiKit.label("%s\n%d yd" % [info["name"], info["yards"]], 22)
		UiKit.expand(nm)
		row.add_child(nm)
		var sp := UiKit.spin(2, 8, 1, App.par_for(hid, info["base_par"]), func(val: float) -> void:
			var pv := int(val)
			if pv == int(info["base_par"]):
				App.settings.par_overrides.erase(hid)
			else:
				App.settings.par_overrides[hid] = pv
			App.settings.save())
		row.add_child(sp)
		list.add_child(row)
	v.add_child(UiKit.button("Reset all to defaults", func() -> void:
		App.settings.par_overrides.clear()
		App.settings.save()
		root.queue_free()
		_show_par_editor(), 64, 22))
	v.add_child(UiKit.primary(UiKit.button("Done", func() -> void: root.queue_free(), 84, 28)))
	_present(root)


## Export recorded play data (user://telemetry): copy a summary, save CSV + JSON files, or clear it.
func _show_export() -> void:
	var tl: TelemetryLog = App.telemetry
	var root := UiKit.overlay(0.7)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var p := UiKit.panel(UiKit.C_SURFACE)
	p.custom_minimum_size = Vector2(600, 0)
	center.add_child(p)
	var v := UiKit.vbox(12)
	p.add_child(v)
	v.add_child(UiKit.label("Export data", 34))
	var counts := UiKit.text("", 20, UiKit.C_MUTED)
	counts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(counts)
	var status := UiKit.text("", 20, UiKit.C_TEXT)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var refresh := func() -> void:
		var recs := tl.load_records()
		counts.text = "Recorded on this device: %d rounds, %d holes, %d shots." % [
			TelemetryLog.of_type(recs, "round_start").size(), TelemetryLog.of_type(recs, "hole").size(),
			TelemetryLog.of_type(recs, "shot").size()]
	refresh.call()
	v.add_child(UiKit.button("Copy summary", func() -> void:
		var txt := TelemetryLog.summary_text(tl.load_records())
		DisplayServer.clipboard_set(txt)
		status.text = "Summary copied to the clipboard (%d lines)." % txt.count("\n"), 70, 22))
	v.add_child(UiKit.button("Save files", func() -> void:
		var res := tl.export_files()
		if bool(res["ok"]):
			status.text = "Saved %d files to:\n%s" % [(res["files"] as Array).size(), res["dir"]]
		else:
			status.text = "Could not save files (%s)." % res["error"], 70, 22))
	var clear_b := UiKit.button("Clear data", Callable(), 70, 22)
	clear_b.pressed.connect(func() -> void:
		if not clear_b.has_meta("armed"):
			clear_b.set_meta("armed", true)
			clear_b.text = "Tap again to delete all recorded data"
			return
		clear_b.remove_meta("armed")
		clear_b.text = "Clear data"
		var n := tl.clear()
		status.text = "Deleted %d data files." % n
		refresh.call())
	clear_b.add_theme_color_override("font_color", UiKit.C_WARN)
	v.add_child(clear_b)
	v.add_child(status)
	v.add_child(UiKit.primary(UiKit.button("Done", func() -> void: root.queue_free(), 84, 28)))
	_present(root)

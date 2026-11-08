class_name MainMenu
extends Control
## Foot Golf main menu and menu navigation.
##
## Navigation (a stack of pages; every page has the same Back control and Android Back pops one):
##   Main menu
##     Single Player / Course Select -> Round Setup -> Start Round -> gameplay
##     Online Multiplayer -> Host / Join -> Lobby -> Round
##     Settings -> Gameplay / Controls / Audio + Visual / Developer
##     Statistics -> Overview / Round History / Records
##     How to Play (tutorial)
## Only features that exist are functional; the rest are clearly labelled placeholders.

signal play_requested(course_id: String, dev: bool, mulligans: int, players: int, rules: RoundConfig)

const WORD_GREEN := Color("#3AB52B")

## Remembered while the app runs, so Round Setup reopens with the previous choice.
static var _last_mulligans := 0
static var _last_players := 1
## Names for pass-and-play players (edited in Round Setup).
static var player_names: Array = ["Player 1", "Player 2", "Player 3", "Player 4"]
## Local profile per player slot ("" = guest; guests use the first profile's favourites).
static var player_profile_ids: Array = ["", "", "", ""]
static var _profile_slots_init := false

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
	if bool(p.get_meta("online_page", false)):
		App.online.leave()
		if App.local_relay.is_running():
			# Give the relay a moment to tell guests the room closed, then shut it down.
			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				if App.local_relay.rooms.is_empty():
					App.local_relay.stop())
		# Leaving the lobby also removes its connection page.
		if not _stack.is_empty() and bool(_stack.back().get_meta("online_page", false)):
			var previous: Control = _stack.pop_back()
			previous.queue_free()
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


## Online play is hotspot-only: the host turns on the phone's hotspot and taps Host; friends join
## that hotspot and tap Join. The host phone runs the game server (LocalRelay).
func _multiplayer_card() -> Control:
	return _nav_row("people", "Online Multiplayer", "Phone hotspot · 2–4 phones", _open_online, "menu_multiplayer")


func _online_cfg() -> ConfigFile:
	var config := ConfigFile.new()
	config.load("user://online.cfg")
	return config


func _online_name() -> String:
	var n := String(_online_cfg().get_value("online", "name", "Player")).strip_edges()
	return "Player" if n.is_empty() else n


## Glass sub-panel used by every online page (same material as Round Setup's course/rules cards).
func _online_card(kind: String = "recess") -> Array:
	var cp := PanelContainer.new()
	cp.add_theme_stylebox_override("panel", UiKit.skin(kind, 6, 20, 14))
	cp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cv := UiKit.vbox(8)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cp.add_child(cv)
	return [cp, cv]


## Numbered instruction card.
func _online_steps(title: String, steps: Array) -> Control:
	var card := _online_card()
	var cv: VBoxContainer = card[1]
	cv.add_child(_caption(title))
	for i in steps.size():
		var row := UiKit.hbox(14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var badge := PanelContainer.new()
		badge.add_theme_stylebox_override("panel", UiKit.skin("lime", 6, 0, 0))
		badge.custom_minimum_size = Vector2(40, 40)
		badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bl := UiKit.label(str(i + 1), 24, Color("#0E2A07"), HORIZONTAL_ALIGNMENT_CENTER)
		bl.add_theme_font_override("font", UiKit.font_semi())
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_child(bl)
		row.add_child(badge)
		var tl := UiKit.text(String(steps[i]), 22, Color.WHITE)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tl)
		cv.add_child(row)
	return card[0]


func _online_field(title: String, value: String, hint: String, big: bool = false) -> Array:
	var box := UiKit.vbox(6)
	box.add_child(_caption(title))
	var field := LineEdit.new()
	field.text = value
	field.placeholder_text = hint
	field.custom_minimum_size.y = 76 if big else 64
	field.add_theme_font_size_override("font_size", 34 if big else 23)
	if big:
		field.alignment = HORIZONTAL_ALIGNMENT_CENTER
		field.add_theme_font_override("font", UiKit.font_semi())
	box.add_child(field)
	return [box, field]


func _secondary_button(text: String, cb: Callable, ui_id: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 62)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_font_override("font", UiKit.font_semi())
	b.set_meta("ui_id", ui_id)
	b.pressed.connect(cb)
	return b


func _open_online() -> void:
	var pg := _page("Online Multiplayer")
	var body: VBoxContainer = pg.body
	var config := _online_cfg()
	var nf := _online_field("YOUR NAME", String(config.get_value("online", "name", "Player")), "Name")
	var nickname: LineEdit = nf[1]
	nickname.max_length = 24
	nickname.text_changed.connect(func(t: String) -> void:
		var c := _online_cfg()
		c.set_value("online", "name", t.strip_edges())
		c.save("user://online.cfg"))
	body.add_child(nf[0])
	body.add_child(_online_steps("HOW IT WORKS", [
		"One phone hosts: turn on its hotspot, then tap Host a game.",
		"Everyone else connects their phone to that hotspot, then taps Join a game.",
		"Enter the room code shown on the host phone. No internet or IP address needed."]))
	body.add_child(_nav_row("people", "Host a game", "Your phone's hotspot carries the game", _open_online_host, "online_host_menu"))
	body.add_child(_nav_row("flag", "Join a game", "Connect to the host's hotspot first", _open_online_join, "online_join_menu"))
	body.add_child(_note("Keep the app open on the host phone during the round."))
	_push(pg.root)


## Watches App.online and opens the lobby when a seat is assigned.
func _watch_online_connection(pg: Dictionary, status_label: Label, buttons: Array) -> void:
	var update := func() -> void:
		if not is_instance_valid(status_label): return
		if App.online.active or not App.online.status.begins_with("Not connected"):
			status_label.text = App.online.status
		for b: Button in buttons:
			b.disabled = App.online.active
		if App.online.seat >= 0 and not bool((pg.root as Control).get_meta("lobby_open", false)):
			(pg.root as Control).set_meta("lobby_open", true)
			_open_online_lobby()
	App.online.changed.connect(update)
	(pg.root as Control).tree_exiting.connect(func() -> void:
		if App.online.changed.is_connected(update): App.online.changed.disconnect(update))


func _open_online_host() -> void:
	var pg := _page("Host a game")
	var body: VBoxContainer = pg.body
	(pg.root as Control).set_meta("online_page", true)
	body.add_child(_online_steps("HOSTING", [
		"Turn on your phone's hotspot (Settings, Hotspot / Tethering).",
		"Tap Start hosting below.",
		"Friends connect to your hotspot, tap Join a game and enter the room code."]))
	var addr_card := _online_card("select")
	var av: VBoxContainer = addr_card[1]
	av.add_child(_caption("YOUR HOTSPOT ADDRESS"))
	var addr_label := UiKit.label("", 40, Color.WHITE)
	addr_label.add_theme_font_override("font", UiKit.font_semi())
	av.add_child(addr_label)
	var addr_note := _note("")
	av.add_child(addr_note)
	body.add_child(addr_card[0])
	var refresh_addr := func() -> void:
		var best := HostFinder.best_host_address(IP.get_local_addresses())
		addr_label.text = best if best != "" else "No hotspot found"
		addr_note.text = "Friends find this phone automatically once they are on your hotspot." if best != "" \
			else "Turn on your phone's hotspot, then come back to this screen."
	refresh_addr.call()
	var status_label := UiKit.text("Ready when you are.", 21, UiKit.C_MUTED)
	body.add_child(status_label)
	var host_game := func() -> void:
		var listen_port := LocalRelay.DEFAULT_PORT
		if not (App.local_relay.is_running() and App.local_relay.port == listen_port):
			var err := App.local_relay.start(listen_port)
			if err != OK:
				status_label.text = "Could not start the game server on port %d (error %d)." % [listen_port, err]
				return
		refresh_addr.call()
		App.online.connect_room("ws://127.0.0.1:%d" % listen_port, _online_name(), "")
	var host := _primary_button("Start hosting", host_game, "online_host")
	(pg.footer as VBoxContainer).add_child(host)
	_watch_online_connection(pg, status_label, [host])
	_push(pg.root)


func _open_online_join() -> void:
	var pg := _page("Join a game")
	var body: VBoxContainer = pg.body
	(pg.root as Control).set_meta("online_page", true)
	body.add_child(_online_steps("JOINING", [
		"Open Wi-Fi settings and connect to the host phone's hotspot.",
		"Come back here: the host is found automatically.",
		"Type the room code from the host's screen and tap Join."]))
	var finder := HostFinder.new()
	(pg.root as Control).add_child(finder)
	var found_card := _online_card("select")
	var fv: VBoxContainer = found_card[1]
	fv.add_child(_caption("HOST PHONE"))
	var found_label := UiKit.label("Looking for the host…", 30, Color.WHITE)
	found_label.add_theme_font_override("font", UiKit.font_semi())
	fv.add_child(found_label)
	var found_note := _note("Make sure you are connected to the host's hotspot.")
	fv.add_child(found_note)
	body.add_child(found_card[0])
	var cf := _online_field("ROOM CODE", "", "6-character code", true)
	var code_field: LineEdit = cf[1]
	code_field.max_length = 6
	code_field.text_changed.connect(func(t: String) -> void:
		var up := t.to_upper()
		if up != t:
			var pos := code_field.caret_column
			code_field.text = up
			code_field.caret_column = pos)
	body.add_child(cf[0])
	var manual := UiKit.vbox(6)
	manual.visible = false
	var config := _online_cfg()
	var mf := _online_field("HOST ADDRESS", String(config.get_value("online", "host_ip", "")), "e.g. 192.168.43.1")
	var address: LineEdit = mf[1]
	manual.add_child(mf[0])
	body.add_child(manual)
	var again := _secondary_button("Search again", func() -> void: pass, "online_search")
	var manual_btn := _secondary_button("Enter address manually", func() -> void: pass, "online_manual")
	var row := UiKit.hbox(10)
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(again)
	row.add_child(manual_btn)
	body.add_child(row)
	var status_label := UiKit.text("", 21, UiKit.C_MUTED)
	body.add_child(status_label)
	var join := _primary_button("Join", func() -> void: pass, "online_join")
	(pg.footer as VBoxContainer).add_child(join)
	var state := {"ip": ""}
	var refresh_join := func() -> void:
		join.disabled = App.online.active or (state.ip == "" and not (manual.visible and address.text.strip_edges() != ""))
	var search := func() -> void:
		state.ip = ""
		found_label.text = "Looking for the host…"
		found_label.add_theme_color_override("font_color", Color.WHITE)
		found_note.text = "Make sure you are connected to the host's hotspot."
		again.disabled = true
		var n := finder.start()
		if n == 0:
			finder.finished.emit([])
		refresh_join.call()
	finder.found.connect(func(ip: String) -> void:
		if state.ip == "":
			state.ip = ip
			found_label.text = "Host found · %s" % ip
			found_label.add_theme_color_override("font_color", Color("#A0F344"))
			found_note.text = "Enter the room code and tap Join."
			refresh_join.call())
	finder.finished.connect(func(hosts: Array) -> void:
		again.disabled = false
		if hosts.is_empty():
			found_label.text = "No host found"
			found_label.add_theme_color_override("font_color", UiKit.C_WARN)
			found_note.text = "Check you are on the host's hotspot and the host has tapped Start hosting, then search again. Or enter the address manually."
		elif hosts.size() > 1:
			found_note.text = "%d hosts answered; using %s. Enter the address manually to pick another." % [hosts.size(), hosts[0]]
		refresh_join.call())
	again.pressed.connect(search)
	manual_btn.pressed.connect(func() -> void:
		manual.visible = not manual.visible
		manual_btn.text = "Hide manual address" if manual.visible else "Enter address manually"
		refresh_join.call())
	address.text_changed.connect(func(_t: String) -> void: refresh_join.call())
	var join_game := func() -> void:
		var host_ip: String = address.text.strip_edges() if manual.visible and address.text.strip_edges() != "" else String(state.ip)
		var join_port := LocalRelay.DEFAULT_PORT
		if host_ip.contains(":"):
			join_port = int(host_ip.get_slice(":", 1))
			host_ip = host_ip.get_slice(":", 0)
		if not NetTransport.is_private_host(host_ip) or join_port <= 0 or join_port > 65535:
			status_label.text = "That does not look like a hotspot address (like 192.168.43.1)."
			return
		if code_field.text.strip_edges().length() != 6:
			status_label.text = "Enter the six-character room code from the host's screen."
			return
		if manual.visible:
			var c := _online_cfg()
			c.set_value("online", "host_ip", address.text.strip_edges())
			c.save("user://online.cfg")
		finder.cancel()
		App.online.connect_room("ws://%s:%d" % [host_ip, join_port], _online_name(), code_field.text.strip_edges())
	join.pressed.connect(join_game)
	_watch_online_connection(pg, status_label, [join])
	_push(pg.root)
	search.call_deferred()


func _open_online_lobby() -> void:
	var pg := _page("Lobby")
	(pg.root as Control).set_meta("online_page", true)
	var body: VBoxContainer = pg.body
	var is_host := App.online.seat == 0
	var online_rules := RoundConfig.from_settings(App.settings)  # host's saved defaults, editable here
	var code_card := _online_card("select")
	var cv: VBoxContainer = code_card[1]
	cv.add_child(_caption("ROOM CODE"))
	var code_text := " ".join(Array(App.online.code.split("")).map(func(c: String) -> String: return c))
	var code_label := UiKit.label(code_text, 76, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	code_label.add_theme_font_override("font", UiKit.font_display())
	cv.add_child(code_label)
	if is_host:
		var best := HostFinder.best_host_address(IP.get_local_addresses())
		cv.add_child(_note("Friends: connect to your hotspot, tap Join a game, enter this code.%s" % (
			"\nHotspot address: %s" % best if best != "" else "\nNo hotspot address found. Turn your hotspot on.")))
	else:
		cv.add_child(_note("Connected. Waiting for the host to start the round."))
	body.add_child(code_card[0])
	body.add_child(_caption("PLAYERS"))
	var roster := UiKit.vbox(8)
	body.add_child(roster)
	var courses := OptionButton.new()
	courses.custom_minimum_size.y = 64
	var course_list := App.courses()
	for c in course_list: courses.add_item(String(c.name))
	if is_host:
		body.add_child(_caption("COURSE"))
		body.add_child(courses)
		body.add_child(_caption("DIFFICULTY (frozen for everyone at start)"))
		_difficulty_controls(body, online_rules, Callable())
	body.add_child(_note("Host settings are frozen at start. Footballers are shared: each can be used once. Mulligans: %s." % ("Unlimited" if _last_mulligans < 0 else str(_last_mulligans))))
	body.add_child(_note("A lost connection pauses the round for up to 60 seconds. Leaving ends the room."))
	var status_label := UiKit.text("", 21, UiKit.C_MUTED)
	body.add_child(status_label)
	var ready := CheckButton.new()
	ready.text = "Ready to play"
	ready.custom_minimum_size.y = 64
	ready.toggled.connect(func(value: bool) -> void: App.online.set_ready(value))
	(pg.footer as VBoxContainer).add_child(ready)
	var start := _primary_button("Start online round", func() -> void:
		App.online.start_game(String(course_list[courses.selected].id), _last_mulligans, online_rules), "online_start")
	start.visible = is_host
	(pg.footer as VBoxContainer).add_child(start)
	var update := func() -> void:
		if not is_instance_valid(roster): return
		for child in roster.get_children():
			roster.remove_child(child)
			child.queue_free()
		var all_ready := App.online.players.size() >= 2 and not App.online.paused
		var colors := [Color("#64CC54"), Color("#F16C72"), Color("#E9CA57"), Color("#5C9FEB")]
		for i in App.online.players.size():
			var player: Dictionary = App.online.players[i]
			var suffix := "READY" if bool(player.ready) else "NOT READY"
			if not bool(player.connected): suffix = "RECONNECTING"
			var card := _online_card()
			var rowh := UiKit.hbox(12)
			rowh.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var dot := ColorRect.new()
			dot.color = colors[i]
			dot.custom_minimum_size = Vector2(10, 40)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rowh.add_child(dot)
			var nm := String(player.name) + (" (you)" if i == App.online.seat else "") + ("  · host" if i == 0 else "")
			var nl := UiKit.label(nm, 26, Color.WHITE)
			nl.add_theme_font_override("font", UiKit.font_semi())
			nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			rowh.add_child(nl)
			rowh.add_child(UiKit.label(suffix, 19, UiKit.C_ACCENT if bool(player.ready) and bool(player.connected) else UiKit.C_WARN))
			card[1].add_child(rowh)
			roster.add_child(card[0])
			all_ready = all_ready and bool(player.ready) and bool(player.connected)
			if i == App.online.seat: ready.set_pressed_no_signal(bool(player.ready))
		start.disabled = not all_ready
		status_label.text = App.online.status if App.online.players.size() >= 2 else "Waiting for friends to join…"
	App.online.changed.connect(update)
	(pg.root as Control).tree_exiting.connect(func() -> void:
		if App.online.changed.is_connected(update): App.online.changed.disconnect(update))
	update.call()
	_push(pg.root)


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
	var rc := RoundConfig.from_settings(App.settings)  # defaults from Settings; frozen once the round starts
	_sync_profile_slots()
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
	var names_box := UiKit.vbox(8)
	var names_upd := func() -> void:
		names_box.visible = _last_players > 1
		for i in names_box.get_child_count():
			(names_box.get_child(i) as Control).visible = i < _last_players
	for n in 4:
		var slot_row := UiKit.hbox(8)
		var ne := LineEdit.new()
		ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ne.text = String(player_names[n])
		ne.placeholder_text = "Player %d" % (n + 1)
		ne.custom_minimum_size = Vector2(0, 58)
		ne.max_length = 14
		ne.add_theme_font_size_override("font_size", 24)
		ne.add_theme_color_override("font_color", [Color("#A0F344"), Color("#D63A44"), Color("#FFD84A"), Color("#52AAFF")][n])
		var idx := n
		ne.text_changed.connect(func(t: String) -> void: player_names[idx] = t.strip_edges() if t.strip_edges() != "" else "Player %d" % (idx + 1))
		var pbtn := Button.new()
		pbtn.custom_minimum_size = Vector2(190, 58)
		pbtn.focus_mode = Control.FOCUS_NONE
		pbtn.clip_text = true
		pbtn.add_theme_font_size_override("font_size", 20)
		pbtn.add_theme_stylebox_override("normal", UiKit.skin("recess", 6, 12, 8))
		pbtn.add_theme_stylebox_override("hover", UiKit.skin("btn", 6, 12, 8))
		pbtn.set_meta("ui_id", "profile_slot_%d" % (n + 1))
		var shown_profile := func() -> void: pbtn.text = _profile_label(String(player_profile_ids[idx]))
		shown_profile.call()
		pbtn.pressed.connect(func() -> void:
			player_profile_ids[idx] = _next_profile_id(String(player_profile_ids[idx]))
			var pid := String(player_profile_ids[idx])
			player_names[idx] = String(App.profiles.get_profile(pid).get("name", "Player %d" % (idx + 1)))
			ne.text = String(player_names[idx])
			shown_profile.call())
		slot_row.add_child(pbtn)
		slot_row.add_child(ne)
		names_box.add_child(slot_row)
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
			prefresh.call()
			names_upd.call())
		pbtns.append(pb)
		pchoices.add_child(pb)
	prefresh.call()
	body.add_child(pchoices)
	body.add_child(names_box)
	names_upd.call()
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
	# difficulty: pre-filled from Settings > Gameplay, frozen for the round when it starts
	body.add_child(_caption("DIFFICULTY"))
	_difficulty_controls(body, rc, Callable())
	body.add_child(_note("These values are fixed for the whole round. Settings > Gameplay holds the defaults that fill this page."))
	(pg["footer"] as VBoxContainer).add_child(_primary_button("Start round", func() -> void:
		play_requested.emit(course_id, false, _last_mulligans, _last_players, rc), "start_round"))
	_push(pg["root"])


static func _trim(v: float) -> String:
	return str(int(round(v))) if absf(v - round(v)) < 0.005 else "%.2f" % v


## Profile slot helpers (Round Setup).
static func _profile_label(profile_id: String) -> String:
	var pr := App.profiles.get_profile(profile_id)
	return "Guest" if pr.is_empty() else String(pr["name"])


## Guest -> profile 1 -> profile 2 ... -> guest.
static func _next_profile_id(current: String) -> String:
	var ids: Array = [""]
	for pr in App.profiles.all_profiles():
		ids.append(String(pr["id"]))
	return String(ids[(ids.find(current) + 1) % ids.size()])


## First visit: slot 1 is the first profile. Every visit: deleted profiles fall back to guest and
## slots on a profile show its current name.
static func _sync_profile_slots() -> void:
	if not _profile_slots_init:
		_profile_slots_init = true
		var all := App.profiles.all_profiles()
		if not all.is_empty():
			player_profile_ids[0] = String(all[0]["id"])
	for n in 4:
		var pr := App.profiles.get_profile(String(player_profile_ids[n]))
		if pr.is_empty():
			if String(player_profile_ids[n]) != "":
				player_names[n] = "Player %d" % (n + 1)
			player_profile_ids[n] = ""
		else:
			player_names[n] = String(pr["name"])


func _choice_row(labels: Array, current: int, cb: Callable, id_prefix: String) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	var btns: Array[Button] = []
	var cur := [current]
	var paint := func() -> void:
		for i in btns.size():
			var on: bool = i == int(cur[0])
			btns[i].add_theme_stylebox_override("normal", UiKit.skin("lime" if on else "recess", 6, 16, 8))
			btns[i].add_theme_stylebox_override("hover", UiKit.skin("lime" if on else "btn", 6, 16, 8))
			btns[i].add_theme_color_override("font_color", Color("#0E2A07") if on else Color.WHITE)
			btns[i].add_theme_color_override("font_hover_color", Color("#0E2A07") if on else Color.WHITE)
	for i in labels.size():
		var b := Button.new()
		b.text = String(labels[i])
		b.custom_minimum_size = Vector2(0, 62)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_font_override("font", UiKit.font_semi())
		b.set_meta("ui_id", "%s_%d" % [id_prefix, i])
		var idx := i
		b.pressed.connect(func() -> void:
			cur[0] = idx
			paint.call()
			cb.call(idx))
		btns.append(b)
		flow.add_child(b)
	paint.call()
	return flow


## Shared by Round Setup (round-only copy) and Settings > Gameplay (on_change writes the defaults).
func _difficulty_controls(body: VBoxContainer, rc: RoundConfig, on_change: Callable) -> void:
	var changed := func() -> void:
		if on_change.is_valid():
			on_change.call()
	var cup := UiKit.spin(RoundConfig.MIN_CUP_FT, RoundConfig.MAX_CUP_FT, 0.05, rc.cup_diameter_ft, func(v: float) -> void:
		rc.cup_diameter_ft = v
		changed.call())
	cup.set_meta("ui_id", "cup_size")
	body.add_child(_setting_row("Hole size (diameter, ft)", cup))
	var gimme := UiKit.spin(0, 10, 0.5, rc.gimme_ft, func(v: float) -> void:
		rc.gimme_ft = ScoringService.clamp_radius_ft(v)
		changed.call())
	gimme.set_meta("ui_id", "gimme")
	body.add_child(_setting_row("Gimme (ft from cup edge, 0 = none)", gimme))
	body.add_child(_note("Regulation hole is about 0.35 ft (4.25 in). A ball at rest within the gimme distance of the cup edge is holed automatically (1 stroke); 0 ft means it must drop."))
	body.add_child(_caption("TEES"))
	body.add_child(_choice_row(["Blue (back)", "Yellow", "Red (forward)"], HoleDefinition.TEE_COLORS.find(rc.tee_color), func(i: int) -> void:
		rc.tee_color = HoleDefinition.TEE_COLORS[i]
		changed.call(), "tees"))
	body.add_child(_caption("PIN POSITIONS"))
	body.add_child(_choice_row(["Fixed", "Varied"], 1 if rc.pin_varied else 0, func(i: int) -> void:
		rc.pin_varied = i == 1
		changed.call(), "pin_positions"))
	body.add_child(_caption("FOOTBALLER RULE"))
	body.add_child(_choice_row(["Once per match", "Once per mode (Caps and Goals)"], 1 if rc.reuse_per_mode else 0, func(i: int) -> void:
		rc.reuse_per_mode = i == 1
		changed.call(), "reuse"))
	body.add_child(_caption("WIND"))
	var wscale := UiKit.spin(RoundConfig.WIND_SCALE_MIN, RoundConfig.WIND_SCALE_MAX, 0.25, rc.wind_scale, func(v: float) -> void:
		rc.wind_scale = v
		changed.call())
	var wrow := _setting_row("Wind strength (x course wind)", wscale)
	wrow.visible = rc.wind_mode == RoundConfig.WindMode.SCALED
	body.add_child(_choice_row(["Course wind", "No wind", "Scaled"], rc.wind_mode, func(i: int) -> void:
		rc.wind_mode = i
		wrow.visible = i == RoundConfig.WindMode.SCALED
		changed.call(), "wind"))
	body.add_child(wrow)
	body.add_child(_caption("MAXIMUM SCORE"))
	var over := UiKit.spin(RoundConfig.CUSTOM_OVER_MIN, RoundConfig.CUSTOM_OVER_MAX, 1, rc.max_over_par_custom, func(v: float) -> void:
		rc.max_over_par_custom = int(v)
		changed.call())
	var orow := _setting_row("Strokes over par", over)
	orow.visible = rc.max_score_mode == RoundConfig.MaxScore.CUSTOM
	body.add_child(_choice_row(["None", "Par + 5", "Custom"], rc.max_score_mode, func(i: int) -> void:
		rc.max_score_mode = i
		orow.visible = i == RoundConfig.MaxScore.CUSTOM
		changed.call(), "maxscore"))
	body.add_child(orow)
	body.add_child(_note("With a maximum, a hole ends when the player reaches par plus that many strokes (penalties count) and the score is recorded as the maximum."))
	body.add_child(_caption("AIDS AND READ-OUTS"))
	for t in [["Aim arrow", rc.show_aim_arrow, "aim_arrow"], ["Ball trail", rc.show_trail, "trail"],
			["Footballer numbers (caps / goals) before the shot", rc.show_stats, "show_stats"]]:
		var cb := CheckBox.new()
		cb.text = String(t[0])
		cb.button_pressed = bool(t[1])
		cb.add_theme_font_size_override("font_size", 22)
		cb.set_meta("ui_id", String(t[2]))
		var key := String(t[2])
		cb.toggled.connect(func(on: bool) -> void:
			match key:
				"aim_arrow": rc.show_aim_arrow = on
				"trail": rc.show_trail = on
				"show_stats": rc.show_stats = on
			changed.call())
		body.add_child(cb)
	body.add_child(_setting_row("Lie penalty read-out", _choice_row(["Range", "Exact"], 1 if rc.lie_exact else 0, func(i: int) -> void:
		rc.lie_exact = i == 1
		changed.call(), "lie_readout")))


# ------------------------------------------------------------------ settings

func _open_settings() -> void:
	var pg := _page("Settings")
	var body: VBoxContainer = pg["body"]
	body.add_child(_nav_row("flag", "Gameplay", "Hole size, auto hole-out, hole pars", _open_settings_gameplay, "settings_gameplay"))
	body.add_child(_nav_row("star", "Profiles", "Named players and their favourites", _open_profiles, "settings_profiles"))
	body.add_child(_nav_row("target", "Controls", "Aiming and shot controls", _open_settings_controls, "settings_controls"))
	body.add_child(_nav_row("sliders", "Audio / Visual", "Sound and ball trail", _open_settings_visual, "settings_visual"))
	body.add_child(_nav_row("gear", "Developer", "Testing tools, data, build info", _open_settings_developer, "settings_developer"))
	_push(pg["root"])


## Settings row: label left, control right, on a recessed plate (same height as the toggle rows).
func _setting_row(label: String, control: Control) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 18, 10))
	pc.custom_minimum_size = Vector2(0, 84)
	var row := UiKit.hbox(12)
	var l := UiKit.label(label, 23, Color.WHITE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	pc.add_child(row)
	return pc


## Settings switch row (CheckButton on the shared recessed theme).
func _toggle(text: String, on: bool, cb: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.custom_minimum_size = Vector2(0, 84)
	c.add_theme_font_size_override("font_size", 23)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.toggled.connect(cb)
	return c


func _open_settings_gameplay() -> void:
	var pg := _page("Gameplay")
	var body: VBoxContainer = pg["body"]
	var st: SettingsStore = App.settings
	body.add_child(_note("These are the DEFAULTS that pre-fill Round Setup. Each round freezes its own copy."))
	var rcd := RoundConfig.from_settings(st)
	_difficulty_controls(body, rcd, func() -> void: rcd.write_defaults(st))
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
	body.add_child(_toggle("Show ball trail", st.show_trail, func(on: bool) -> void:
		st.show_trail = on
		st.save()))
	body.add_child(_toggle("Vibration on shots and hole-outs", st.vibration, func(on: bool) -> void:
		st.vibration = on
		st.save()))
	body.add_child(_toggle("High graphics (sky, hills, birds, cloud shadows, wind sway)", st.graphics_quality == 1, func(on: bool) -> void:
		st.graphics_quality = 1 if on else 0
		HoleAtmosphere.high_quality = on
		st.save()))
	body.add_child(_toggle("Glow (subtle bloom, High only)", st.graphics_glow, func(on: bool) -> void:
		st.graphics_glow = on
		st.save()))
	body.add_child(_note("Graphics changes apply from the next round."))
	body.add_child(_toggle("Auto-continue after each shot (progress bar)", st.auto_continue, func(on: bool) -> void:
		st.auto_continue = on
		st.save()))
	body.add_child(_toggle("Drag up/down to change trajectory (trial)", st.drag_trajectory, func(on: bool) -> void:
		st.drag_trajectory = on
		st.save()))
	body.add_child(_note("Audio: none yet (silent). Sound is planned."))
	_push(pg["root"])


func _open_settings_developer() -> void:
	var pg := _page("Developer")
	var body: VBoxContainer = pg["body"]
	var st: SettingsStore = App.settings
	body.add_child(_nav_row("gear", "Developer Test", "All 17 holes with the developer panel", func() -> void: play_requested.emit("all", true, 0, 1, RoundConfig.from_settings(App.settings)), "developer_test"))
	body.add_child(_toggle("TEST MODE: show caps/goals before shot", st.show_stats, func(on: bool) -> void:
		st.show_stats = on
		st.save()))
	var ds_label := _note(App.dataset_label())
	body.add_child(_toggle("Use real footballers (off = synthetic test set)", st.dataset == "real", func(on: bool) -> void:
		st.dataset = "real" if on else "test"
		st.save()
		App.load_dataset()
		ds_label.text = App.dataset_label()))
	body.add_child(ds_label)
	body.add_child(_nav_row("flag", "Reset footballer database", "Back to the bundled seed", func() -> void: App.repo.reset_to_seed()))
	body.add_child(_nav_row("list", "Export data", "Copy a summary or save CSV / JSON files", _show_export))
	body.add_child(_note("Foot Golf  ·  %s" % App.build_label()))
	_push(pg["root"])


# ------------------------------------------------------------------ profiles

func _open_profiles() -> void:
	var pg := _page("Profiles")
	var body: VBoxContainer = pg["body"]
	_fill_profiles(body)
	_push(pg["root"])


func _fill_profiles(body: VBoxContainer) -> void:
	UiKit.clear(body)
	var all := App.profiles.all_profiles()
	body.add_child(_note("Named players on this phone. Each has its own favourites (the star in the footballer picker). Pick profiles per player in Round Setup."))
	for pr in all:
		var pid := String(pr["id"])
		var row := UiKit.hbox(8)
		var ne := LineEdit.new()
		ne.text = String(pr["name"])
		ne.max_length = PlayerProfileStore.MAX_NAME_LEN
		ne.custom_minimum_size = Vector2(0, 62)
		ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ne.add_theme_font_size_override("font_size", 24)
		ne.set_meta("ui_id", "profile_name_%s" % pid)
		ne.text_submitted.connect(func(t: String) -> void: App.profiles.rename_profile(pid, t))
		ne.focus_exited.connect(func() -> void:
			if not App.profiles.rename_profile(pid, ne.text):
				ne.text = String(App.profiles.get_profile(pid).get("name", ne.text)))
		row.add_child(ne)
		row.add_child(UiKit.label("%d \u2605" % (pr["favourites"] as Array).size(), 22, UiKit.C_MUTED))
		var del := UiKit.button("Delete", func() -> void:
			if App.profiles.delete_profile(pid):
				_fill_profiles(body), 62, 20)
		del.disabled = all.size() <= 1
		del.set_meta("ui_id", "profile_delete_%s" % pid)
		row.add_child(del)
		body.add_child(row)
	if all.size() < PlayerProfileStore.MAX_PROFILES:
		var add := LineEdit.new()
		add.placeholder_text = "New profile name"
		add.max_length = PlayerProfileStore.MAX_NAME_LEN
		add.custom_minimum_size = Vector2(0, 62)
		add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add.add_theme_font_size_override("font_size", 24)
		add.set_meta("ui_id", "profile_new_name")
		var arow := UiKit.hbox(8)
		arow.add_child(add)
		var addb := UiKit.button("Add", func() -> void:
			if App.profiles.create_profile(add.text) != "":
				_fill_profiles(body), 62, 22)
		addb.set_meta("ui_id", "profile_add")
		arow.add_child(addb)
		body.add_child(arow)
	else:
		body.add_child(_note("Maximum of %d profiles." % PlayerProfileStore.MAX_PROFILES))


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

## Title + thin rule for the glass modals (par editor, export), matching the page headers.
func _modal_title(text: String) -> Control:
	var v := UiKit.vbox(10)
	var t := UiKit.label(text, 38, Color.WHITE)
	t.add_theme_font_override("font", UiKit.font_semi())
	v.add_child(t)
	v.add_child(_rule())
	return v

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
	v.add_child(_modal_title("Hole pars"))
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
		nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
		var rp := PanelContainer.new()
		rp.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 16, 8))
		rp.add_child(row)
		list.add_child(rp)
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
	v.add_child(_modal_title("Export data"))
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

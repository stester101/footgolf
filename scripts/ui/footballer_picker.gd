class_name FootballerPicker
extends Control
## Footballer selector. Main sheet: fixed search + Filters / Sort / Random controls, removable filter
## chips, a count line, and a scrolling list of compact single-line rows (flag, name, career years,
## chevron). A separate Filters panel holds searchable multi-select countries, multi-select birth
## decades and availability. Random respects the active filters and never picks a used footballer.
## Normal play: never shows or sorts/filters by caps/goals. TEST MODE (show_stats) additionally
## shows stats and unlocks stat sorting/filtering (a testing aid; see docs/DECISIONS.md).

signal picked(id: String)
signal closed

const PAGE := 50
const SELECT_BLUE := Color("#52AAFF")

## Remembered between openings within a round (you reopen the picker every shot): search text,
## sort, filters, page size and scroll position. Closing clears the search; a new round resets all.
static var _saved := {"q": "", "sort": "name_az", "nations": {}, "eras": {}, "avail": false,
	"caps_band": 0, "goals_band": 0, "limit": PAGE, "scroll": 0}
static var _saved_round_id := -1
static var _by_player := {}

var session: GameSession
var show_stats := false
## Round Setup opt-in (RoundConfig.order_by_stats): offers the Caps/Goals sort orders; numbers stay hidden unless show_stats.
var stat_sort := false
## Shown in the header, e.g. the ball-to-pin distance.
var context_text := ""

# live state (mirrors _saved)
var _sel_nations: Dictionary = {}
var _sel_eras: Dictionary = {}
var _avail := false
var _fav_only := false
# dev: custom caps / goals ranges (-1 = open ended), on top of the preset bands
var _cr: Array = [-1, -1]
var _gr: Array = [-1, -1]
var _t_cr: Array = [-1, -1]
var _t_gr: Array = [-1, -1]
var _range_edits: Array[LineEdit] = []
var _fav_btn: Button
var _caps_band := 0
var _goals_band := 0
var _sort_key := "name_az"
var _sort_keys: Array[String] = []
var _codes: Dictionary = {}         # nationality -> country code

# main sheet widgets
var _main_panel: PanelContainer
var _search: LineEdit
var _filters_label: Label
var _sort_label: Label
var _sort_popup: PopupMenu
var _chips: HFlowContainer
var _summary: Label
var _sc: ScrollContainer
var _csc: ScrollContainer
var _press_country_scroll := 0
var _list: VBoxContainer
var _debounce: Timer
var _limit := PAGE
var _press_scroll := 0

# filter panel
var _filter_panel: PanelContainer
var _t_nations: Dictionary = {}
var _t_eras: Dictionary = {}
var _t_avail := false
var _t_caps := 0
var _t_goals := 0
var _country_search: LineEdit
var _country_rows: Dictionary = {}  # nationality -> Button
var _country_summary: Label
var _era_btns: Array[Button] = []
var _any_era_btn: Button
var _avail_rows: Array[Button] = []
var _caps_opt: OptionButton
var _goals_opt: OptionButton


func _exit_tree() -> void:
	_saved["q"] = ""  # the text search clears when the picker closes; filters and sort stay


func setup(s: GameSession) -> void:
	session = s
	# every player has their own RoundState, so key the round by player 1's (stable for the whole round)
	var rid := session.slot_round_state(0).get_instance_id()
	if rid != _saved_round_id:
		_saved_round_id = rid
		_by_player.clear()  # new round: everything resets for every player
	# pass-and-play: each player keeps their own filters, sort and search settings for the round
	# Filters belong to the person holding this phone: online that is this phone's seat (also while waiting for
	# someone else's turn); in pass-and-play it is whoever's turn it is.
	var owner_key: int = session.turn
	if session is OnlineSession and (session as OnlineSession).room != null and (session as OnlineSession).room.seat >= 0:
		owner_key = (session as OnlineSession).room.seat
	if not _by_player.has(owner_key):
		_by_player[owner_key] = {"q": "", "sort": "name_az", "nations": {}, "eras": {}, "avail": false,
			"caps_band": 0, "goals_band": 0, "limit": PAGE, "scroll": 0}
	_saved = _by_player[owner_key]
	_sel_nations = (_saved["nations"] as Dictionary).duplicate()
	_sel_eras = (_saved["eras"] as Dictionary).duplicate()
	_avail = bool(_saved["avail"])
	_caps_band = int(_saved["caps_band"])
	_goals_band = int(_saved["goals_band"])
	_sort_key = String(_saved["sort"])
	for fb in session.repo.all_sorted():
		if not _codes.has(fb.nationality):
			_codes[fb.nationality] = fb.country_code if fb.country_code != "" else fb.nationality.substr(0, 3).to_upper()
	theme = UiKit.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiKit.overlay(0.6))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.anchor_top = 0.10  # tall sheet: the banner stays visible above it
	var sm := UiKit.safe_margins(get_viewport()) if is_inside_tree() else [16.0, 16.0, 16.0, 16.0]
	m.add_theme_constant_override("margin_left", int(sm[0]) + 8)
	m.add_theme_constant_override("margin_right", int(sm[2]) + 8)
	m.add_theme_constant_override("margin_top", int(sm[1]) + 24)
	m.add_theme_constant_override("margin_bottom", int(sm[3]) + 16)
	add_child(m)
	_main_panel = _build_main_panel()
	m.add_child(_main_panel)
	_filter_panel = _build_filter_panel()
	_filter_panel.visible = false
	m.add_child(_filter_panel)
	var keep_limit := maxi(int(_saved.get("limit", PAGE)), PAGE)
	var keep_scroll := int(_saved.get("scroll", 0))
	_rebuild()
	if keep_limit > PAGE:
		_limit = keep_limit
		_saved["limit"] = _limit
		_render()
	_sc.get_v_scroll_bar().value_changed.connect(func(val: float) -> void: _saved["scroll"] = int(val))
	if keep_scroll > 0:
		_restore_scroll(keep_scroll)


# ------------------------------------------------------------------ shared widgets

func _icon_button(kind: String, size_px: int, cb: Callable, ui_id: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size_px, size_px)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("ui_id", ui_id)
	b.add_theme_stylebox_override("normal", UiKit.skin("btn", 6, 0, 0))
	b.add_theme_stylebox_override("hover", UiKit.skin("btn_hover", 6, 0, 0))
	b.add_theme_stylebox_override("pressed", UiKit.skin("btn_press", 6, 0, 0))
	b.pressed.connect(cb)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(LineIcon.make(kind, 32))
	b.add_child(c)
	return b


## Button with a leading icon, a label and an optional chevron. Returns [button, label].
func _control_button(kind: String, text: String, chevron: bool, cb: Callable) -> Array:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 64)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_stylebox_override("normal", UiKit.skin("btn", 6, 0, 0))
	b.add_theme_stylebox_override("hover", UiKit.skin("btn_hover", 6, 0, 0))
	b.add_theme_stylebox_override("pressed", UiKit.skin("btn_press", 6, 0, 0))
	b.pressed.connect(cb)
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 14)
	mc.add_theme_constant_override("margin_right", 12)
	var h := UiKit.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := LineIcon.make(kind, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var l := UiKit.label(text, 22, Color.WHITE)
	l.add_theme_font_override("font", UiKit.font_semi())
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(l)
	if chevron:
		var ch := LineIcon.make("chevron_down", 22)
		ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(ch)
	mc.add_child(h)
	b.add_child(mc)
	return [b, l]


## Recessed search field with a leading magnifier. Returns [container, LineEdit].
func _search_field(placeholder: String) -> Array:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 14, 6))
	pc.custom_minimum_size = Vector2(0, 60)
	var h := UiKit.hbox(12)
	var ic := LineIcon.make("search", 32, UiKit.C_MUTED)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var le := LineEdit.new()
	le.placeholder_text = placeholder
	le.clear_button_enabled = true
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le.add_theme_font_size_override("font_size", 26)
	le.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	le.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Run after the focus click positions the caret, so typing replaces the query.
	le.focus_entered.connect(func() -> void: le.call_deferred("select_all"))
	h.add_child(le)
	pc.add_child(h)
	return [pc, le]


func _rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.72, 0.88, 1.0, 0.22)
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ------------------------------------------------------------------ main sheet

func _build_main_panel() -> PanelContainer:
	var p := UiKit.panel(UiKit.C_PANEL_SOLID)
	var v := UiKit.vbox(12)
	p.add_child(v)
	# header
	var head := UiKit.hbox(12)
	var title := UiKit.label("Choose footballer", 34, Color.WHITE)
	title.add_theme_font_override("font", UiKit.font_semi())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(title)
	if context_text != "":
		var ctx := UiKit.label(context_text, 19, UiKit.C_MUTED)
		ctx.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(ctx)
	head.add_child(_icon_button("close", 64, func() -> void: closed.emit(), "picker_close"))
	v.add_child(head)
	v.add_child(_rule())
	if show_stats:
		v.add_child(UiKit.text("TEST MODE: caps & goals shown; stat sorting/filters unlocked (off in Settings)", 17, UiKit.C_WARN))
	# search (fixed)
	var sf := _search_field("Search footballers…")
	_search = sf[1] as LineEdit
	_search.text = String(_saved.get("q", ""))
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.18
	_debounce.timeout.connect(_rebuild)
	add_child(_debounce)
	_search.text_changed.connect(func(t: String) -> void:
		_saved["q"] = t
		_debounce.start())
	v.add_child(sf[0])
	# Filters / Sort / Random (fixed)
	var row := UiKit.hbox(10)
	var fbtn := _control_button("sliders", "Filters", true, _open_filters)
	(fbtn[0] as Button).custom_minimum_size.x = 214
	_filters_label = fbtn[1] as Label
	(fbtn[0] as Button).set_meta("ui_id", "filters")
	row.add_child(fbtn[0])
	var labels: Array = FootballerRepository.SORT_LABELS.duplicate()
	if show_stats or stat_sort:
		labels.append_array(FootballerRepository.STAT_SORT_LABELS)
	_sort_popup = PopupMenu.new()
	for i in labels.size():
		_sort_keys.append(String(labels[i][0]))
		_sort_popup.add_radio_check_item(String(labels[i][1]), i)
	_sort_popup.id_pressed.connect(func(id: int) -> void:
		if _sort_popup.is_item_disabled(id):
			return  # caps/goals sorts need a country filter
		_sort_key = _sort_keys[id]
		_rebuild())
	add_child(_sort_popup)
	var sbtn := _control_button("sort", "", true, func() -> void:
		_sort_popup.popup(Rect2i(Vector2i(((sbtn_ref[0] as Button).global_position + Vector2(0, (sbtn_ref[0] as Button).size.y)).round()), Vector2i(int((sbtn_ref[0] as Button).size.x), 0))))
	sbtn_ref.append(sbtn[0])
	_sort_label = sbtn[1] as Label
	(sbtn[0] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sbtn[0])
	var rnd := _icon_button("shuffle", 64, _on_random, "random")
	rnd.custom_minimum_size.x = 84
	row.add_child(rnd)
	_fav_btn = _icon_button("star", 64, func() -> void:
		_fav_only = not _fav_only
		_rebuild(), "favourites")
	_fav_btn.custom_minimum_size.x = 84
	row.add_child(_fav_btn)
	v.add_child(row)
	# active filter chips (fixed, only when something is active)
	_chips = HFlowContainer.new()
	_chips.add_theme_constant_override("h_separation", 10)
	_chips.add_theme_constant_override("v_separation", 8)
	v.add_child(_chips)
	v.add_child(_rule())
	_summary = UiKit.label("", 20, UiKit.C_MUTED)
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(_summary)
	# scrolling results
	_sc = ScrollContainer.new()
	_sc.scroll_deadzone = 14
	_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_sc)
	_list = UiKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(_list)
	return p


var sbtn_ref: Array = []


## The list has no size until it has been laid out, so wait a couple of frames before scrolling.
func _restore_scroll(px: int) -> void:
	for i in 3:
		if not is_inside_tree():
			return
		await get_tree().process_frame
		if not is_instance_valid(_sc):
			return
		_sc.scroll_vertical = px
		if _sc.scroll_vertical == px:
			return


func _options(limit: int) -> Dictionary:
	return {
		"q": _search.text, "nations": _sel_nations.duplicate(), "eras": _sel_eras.duplicate(),
		"mode": session.mode, "available_only": _avail,
		"caps_band": _caps_band, "goals_band": _goals_band,
		"sort": _sort_key, "limit": limit,
	}


static func _range_on(r: Array) -> bool:
	return int(r[0]) >= 0 or int(r[1]) >= 0


static func _in_range(v: int, r: Array) -> bool:
	return (int(r[0]) < 0 or v >= int(r[0])) and (int(r[1]) < 0 or v <= int(r[1]))


static func _range_text(name: String, r: Array) -> String:
	if int(r[0]) >= 0 and int(r[1]) >= 0:
		return "%s %d–%d" % [name, int(r[0]), int(r[1])]
	return "%s %s" % [name, ("%d+" % int(r[0])) if int(r[0]) >= 0 else ("up to %d" % int(r[1]))]


## Favourites belong to the ACTIVE player's profile (a guest slot uses the first profile).
func _is_fav(footballer_id: String) -> bool:
	return App.profiles.is_favourite(App.profiles.resolve_id(session.active_profile_id()), footballer_id)


func _fav_filter(list: Array) -> Array:
	if not _fav_only and not (show_stats and (_range_on(_cr) or _range_on(_gr))):
		return list
	return list.filter(func(fb: Footballer) -> bool:
		if _fav_only and not _is_fav(fb.id):
			return false
		if show_stats and (not _in_range(fb.caps, _cr) or not _in_range(fb.goals, _gr)):
			return false
		return true)


func _filter_count() -> int:
	return int(not _sel_nations.is_empty()) + int(not _sel_eras.is_empty()) + int(_avail) \
		+ int(_caps_band > 0) + int(_goals_band > 0) + int(_fav_only) + int(_range_on(_cr)) + int(_range_on(_gr))


func _clear_all() -> void:
	_fav_only = false
	_cr = [-1, -1]
	_gr = [-1, -1]
	_sel_nations.clear()
	_sel_eras.clear()
	_avail = false
	_caps_band = 0
	_goals_band = 0
	_rebuild()


func _rebuild() -> void:
	_limit = PAGE
	_saved["q"] = _search.text  # keep the live text while filters and sorts rebuild the list
	_saved["limit"] = PAGE
	_saved["scroll"] = 0
	_sc.scroll_vertical = 0
	_saved["sort"] = _sort_key
	_saved["nations"] = _sel_nations.duplicate()
	_saved["eras"] = _sel_eras.duplicate()
	_saved["avail"] = _avail
	_saved["caps_band"] = _caps_band
	_saved["goals_band"] = _goals_band
	_render()


func _chip(text: String, code: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text + "  ×"
	if code != "":
		b.icon = Flags.texture(code)
		b.expand_icon = false
	b.custom_minimum_size = Vector2(0, 52)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_font_override("font", UiKit.font_semi())
	b.add_theme_constant_override("h_separation", 10)
	b.add_theme_stylebox_override("normal", UiKit.skin("btn", 10, 16, 4))
	b.add_theme_stylebox_override("hover", UiKit.skin("btn_hover", 10, 16, 4))
	b.add_theme_stylebox_override("pressed", UiKit.skin("btn_press", 10, 16, 4))
	b.pressed.connect(cb)
	return b


func _refresh_chips() -> void:
	UiKit.clear(_chips)
	var nats := _sel_nations.keys()
	nats.sort()
	for nat in nats:
		_chips.add_child(_chip(String(nat), String(_codes.get(nat, "")), func() -> void:
			_sel_nations.erase(nat)
			_rebuild()))
	var eras := _sel_eras.keys()
	eras.sort()
	for i in eras:
		_chips.add_child(_chip(String(FootballerRepository.ERAS[int(i)][0]), "", func() -> void:
			_sel_eras.erase(i)
			_rebuild()))
	if _fav_only:
		_chips.add_child(_chip("Favourites", "", func() -> void:
			_fav_only = false
			_rebuild()))
	if _avail:
		_chips.add_child(_chip("Available only", "", func() -> void:
			_avail = false
			_rebuild()))
	if show_stats and _caps_band > 0:
		_chips.add_child(_chip(String(FootballerRepository.CAPS_BANDS[_caps_band][0]), "", func() -> void:
			_caps_band = 0
			_rebuild()))
	if show_stats and _range_on(_cr):
		_chips.add_child(_chip(_range_text("Caps", _cr), "", func() -> void:
			_cr = [-1, -1]
			_rebuild()))
	if show_stats and _range_on(_gr):
		_chips.add_child(_chip(_range_text("Goals", _gr), "", func() -> void:
			_gr = [-1, -1]
			_rebuild()))
	if show_stats and _goals_band > 0:
		_chips.add_child(_chip(String(FootballerRepository.GOALS_BANDS[_goals_band][0]), "", func() -> void:
			_goals_band = 0
			_rebuild()))
	_chips.visible = _filter_count() > 0
	if _chips.visible:
		var clear := Button.new()
		clear.text = "Clear all"
		clear.flat = true
		clear.focus_mode = Control.FOCUS_NONE
		clear.add_theme_font_size_override("font_size", 22)
		clear.add_theme_color_override("font_color", UiKit.C_CYAN)
		clear.add_theme_color_override("font_hover_color", Color.WHITE)
		clear.add_theme_color_override("font_pressed_color", Color.WHITE)
		clear.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		clear.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		clear.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		clear.custom_minimum_size = Vector2(0, 52)
		clear.pressed.connect(_clear_all)
		_chips.add_child(clear)


## "2001–2007" -> "2001–07" (same century); a single year stays; birth year is the fallback.
static func _years_text(fb: Footballer) -> String:
	if fb.career_years != "":
		var parts := fb.career_years.split("–")
		if parts.size() == 2:
			if parts[0] == parts[1]:
				return parts[0]
			if parts[0].length() == 4 and parts[1].length() == 4 and parts[0].substr(0, 2) == parts[1].substr(0, 2):
				return "%s–%s" % [parts[0], parts[1].substr(2)]
		return fb.career_years
	return ("b. %d" % fb.birth_year) if fb.birth_year > 0 else ""


## One compact row: flag, name, career years (right), chevron. Stores meta "footballer_id".
func _footballer_row(fb: Footballer, used: bool, selected: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 68)
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("footballer_id", fb.id)
	var kind := "select" if selected else "btn"
	b.add_theme_stylebox_override("normal", UiKit.skin(kind, 6, 0, 0))
	b.add_theme_stylebox_override("hover", UiKit.skin("select" if selected else "btn_hover", 6, 0, 0))
	b.add_theme_stylebox_override("pressed", UiKit.skin("btn_press", 6, 0, 0))
	b.add_theme_stylebox_override("disabled", UiKit.skin("disabled", 6, 0, 0))
	b.disabled = used
	b.pressed.connect(cb)
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 16)
	mc.add_theme_constant_override("margin_right", 14)
	var h := UiKit.hbox(10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flag := TextureRect.new()
	flag.texture = Flags.texture(fb.country_code)
	flag.custom_minimum_size = Vector2(50, 34)
	flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(flag)
	var nm := UiKit.label(fb.name + ("  ·  USED" if used else ""), 24, Color.WHITE if not used else Color(1, 1, 1, 0.55))
	nm.add_theme_font_override("font", UiKit.font_semi())
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(nm)
	var right := _years_text(fb)
	if show_stats:
		right = "%dc · %dg   %s" % [fb.caps, fb.goals, right]
	var yr := UiKit.label(right, 19, Color(0.85, 0.92, 1.0, 0.85 if not used else 0.45), HORIZONTAL_ALIGNMENT_RIGHT)
	yr.add_theme_font_override("font", UiKit.font_num())
	yr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(yr)
	var fav := _is_fav(fb.id)
	var star := Button.new()
	star.flat = true
	star.focus_mode = Control.FOCUS_NONE
	star.custom_minimum_size = Vector2(56, 60)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for st in ["normal", "hover", "pressed", "disabled"]:
		star.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	var si := LineIcon.make("star", 34, Color("#FFD84A") if fav else Color(1, 1, 1, 0.55))
	si.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var star_c := CenterContainer.new()  # centres the icon in the button (was drifting to the row's bottom edge)
	star_c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	star_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star_c.add_child(si)
	star.add_child(star_c)
	star.pressed.connect(func() -> void:
		var pid := App.profiles.resolve_id(session.active_profile_id())
		App.profiles.set_favourite(pid, fb.id, not App.profiles.is_favourite(pid, fb.id))
		si.set_color(Color("#FFD84A") if _is_fav(fb.id) else Color(1, 1, 1, 0.55))
		if _fav_only:
			_render())
	h.add_child(star)
	var gap := Control.new()  # keeps the star well clear of the arrow so taps do not mis-hit
	gap.custom_minimum_size = Vector2(14, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(gap)
	var chev := LineIcon.make("chevron_right", 26, Color(1, 1, 1, 0.85))
	chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chev)
	mc.add_child(h)
	b.add_child(mc)
	return b


## Only the first _limit matches become rows (the real database has ~10k players).
func _render() -> void:
	UiKit.clear(_list)
	var o := _options(-1)
	var results := _fav_filter(session.repo.query(o, session.pool))
	var total := results.size()
	for i in mini(_limit, total):
		var fb: Footballer = results[i]
		var used := session.pool.is_used(fb.id, session.mode)
		var b := _footballer_row(fb, used, fb.id == session.selected_id, func() -> void: _on_pick(fb.id))
		# Let drags reach the ScrollContainer (touch scrolling); a press only picks if the list didn't scroll.
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.button_down.connect(func() -> void: _press_scroll = _sc.scroll_vertical)
		_list.add_child(b)
	if total == 0:
		_list.add_child(UiKit.text("No footballers match. Try clearing a filter.", 24, UiKit.C_MUTED))
	if total > _limit:
		var more := UiKit.button("Show more (%d of %d shown)" % [_limit, total], func() -> void:
			_limit += PAGE
			_saved["limit"] = _limit
			var keep := _sc.scroll_vertical
			_render()
			_sc.set_deferred("scroll_vertical", keep), 64, 22)
		more.mouse_filter = Control.MOUSE_FILTER_PASS
		_list.add_child(more)
	var avail := 0
	for fb in results:
		if not session.pool.is_used(fb.id, session.mode):
			avail += 1
	_summary.text = "%d footballers available" % avail if avail == total else "%d footballers available · %d used" % [avail, total - avail]
	var n := _filter_count()
	_filters_label.text = "Filters (%d)" % n if n > 0 else "Filters"
	# Caps/Goals sorts only work with a country filter on (greyed out otherwise).
	var stat_ok := not _sel_nations.is_empty()
	for i in _sort_popup.item_count:
		if _sort_keys[i] in ["caps_hi", "caps_lo", "goals_hi", "goals_lo"]:
			_sort_popup.set_item_disabled(i, not stat_ok)
	if not stat_ok and _sort_key in ["caps_hi", "caps_lo", "goals_hi", "goals_lo"]:
		_sort_key = "name_az"
	var idx := maxi(_sort_keys.find(_sort_key), 0)
	_sort_label.text = String(((FootballerRepository.SORT_LABELS + (FootballerRepository.STAT_SORT_LABELS if (show_stats or stat_sort) else []))[idx])[1])
	for i in _sort_popup.item_count:
		_sort_popup.set_item_checked(i, i == idx)
	_refresh_chips()


## Random pick among the AVAILABLE players matching the current filters (stats stay hidden).
func _on_random() -> void:
	var o := _options(-1)
	o["available_only"] = true
	var candidates := _fav_filter(session.repo.query(o, session.pool))
	if candidates.is_empty():
		return
	var fb: Footballer = candidates[randi() % candidates.size()]
	_on_pick(fb.id, true)


func _on_pick(id: String, force: bool = false) -> void:
	if not force and absi(_sc.scroll_vertical - _press_scroll) > 6:
		return
	if session.select_footballer(id):
		picked.emit(id)


# ------------------------------------------------------------------ filter panel

func _section_title(text: String) -> Label:
	var l := UiKit.label(text, 28, Color.WHITE)
	l.add_theme_font_override("font", UiKit.font_semi())
	return l


func _build_filter_panel() -> PanelContainer:
	var p := UiKit.panel(UiKit.C_PANEL_SOLID)
	var v := UiKit.vbox(9)
	p.add_child(v)
	# header: funnel, title, Reset all
	var head := UiKit.hbox(12)
	var fi := LineIcon.make("funnel", 40)
	fi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(fi)
	var title := UiKit.label("Filters", 34, Color.WHITE)
	title.add_theme_font_override("font", UiKit.font_semi())
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var reset := _control_button("refresh", "Reset all", false, _reset_temp)
	(reset[0] as Button).custom_minimum_size = Vector2(210, 60)
	head.add_child(reset[0])
	v.add_child(head)
	v.add_child(_rule())
	# country
	var ch := UiKit.hbox(10)
	ch.add_child(_section_title("Country"))
	_country_summary = UiKit.label("", 21, UiKit.C_CYAN, HORIZONTAL_ALIGNMENT_RIGHT)
	_country_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_country_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ch.add_child(_country_summary)
	v.add_child(ch)
	var cs := _search_field("Search countries…")
	_country_search = cs[1] as LineEdit
	_country_search.text_changed.connect(func(_t: String) -> void: _filter_country_rows())
	v.add_child(cs[0])
	var csc := ScrollContainer.new()
	_csc = csc
	csc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	csc.custom_minimum_size = Vector2(0, 300)
	csc.scroll_deadzone = 14
	csc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var cl := UiKit.vbox(6)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	csc.add_child(cl)
	for nat in session.repo.nationalities():
		var row := _country_row(String(nat))
		_country_rows[nat] = row
		cl.add_child(row)
	v.add_child(csc)
	v.add_child(_rule())
	# born
	v.add_child(_section_title("Born"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_any_era_btn = _era_button("Any", func() -> void:
		_t_eras.clear()
		_refresh_filter_widgets())
	grid.add_child(_any_era_btn)
	_era_btns.clear()
	for i in FootballerRepository.ERAS.size():
		var eb := _era_button(String(FootballerRepository.ERAS[i][0]), func() -> void:
			if _t_eras.has(i):
				_t_eras.erase(i)
			else:
				_t_eras[i] = true
			_refresh_filter_widgets())
		_era_btns.append(eb)
		grid.add_child(eb)
	v.add_child(grid)
	v.add_child(_rule())
	# availability (radio)
	v.add_child(_section_title("Availability"))
	_avail_rows.clear()
	for spec in [["Available only", true], ["All footballers, including used", false]]:
		var on_avail: bool = spec[1]
		var rb := _radio_row(String(spec[0]), func() -> void:
			_t_avail = on_avail
			_refresh_filter_widgets())
		_avail_rows.append(rb)
		v.add_child(rb)
	if show_stats:
		v.add_child(UiKit.label("Test mode: stat filters", 18, UiKit.C_WARN))
		var stat_row := UiKit.hbox(8)
		_caps_opt = _band_option(FootballerRepository.CAPS_BANDS, func(i: int) -> void: _t_caps = i)
		_goals_opt = _band_option(FootballerRepository.GOALS_BANDS, func(i: int) -> void: _t_goals = i)
		stat_row.add_child(_caps_opt)
		stat_row.add_child(_goals_opt)
		v.add_child(stat_row)
		v.add_child(UiKit.label("Custom range (e.g. 80 to 120)", 18, UiKit.C_WARN))
		for spec in [["Caps", _t_cr], ["Goals", _t_gr]]:
			v.add_child(_range_row(String(spec[0]), spec[1] as Array))
	# apply
	var apply := UiKit.primary(Button.new())
	apply.custom_minimum_size = Vector2(0, 72)
	apply.focus_mode = Control.FOCUS_ALL
	apply.set_meta("ui_id", "apply_filters")
	apply.pressed.connect(_apply_filters)
	var ac := CenterContainer.new()
	ac.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ac.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ah := UiKit.hbox(12)
	ah.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ah.add_child(LineIcon.make("check", 34))
	var al := UiKit.label("Apply Filters", 30, Color.WHITE)
	al.add_theme_font_override("font", UiKit.font_semi())
	ah.add_child(al)
	ac.add_child(ah)
	apply.add_child(ac)
	v.add_child(apply)
	return p


func _range_row(label: String, r: Array) -> Control:
	var row := UiKit.hbox(8)
	var l := UiKit.label(label, 22, Color.WHITE)
	l.custom_minimum_size = Vector2(90, 0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	for k in 2:
		var le := LineEdit.new()
		le.placeholder_text = "min" if k == 0 else "max"
		le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		le.custom_minimum_size = Vector2(0, 54)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.add_theme_font_size_override("font_size", 22)
		le.text_changed.connect(func(t: String) -> void: r[k] = int(t) if t.strip_edges().is_valid_int() and int(t) >= 0 else -1)
		le.set_meta("range", r)
		le.set_meta("k", k)
		_range_edits.append(le)
		row.add_child(le)
		if k == 0:
			row.add_child(UiKit.label("to", 20, UiKit.C_MUTED))
	return row


func _sync_range_edits() -> void:
	for le in _range_edits:
		var v := int((le.get_meta("range") as Array)[int(le.get_meta("k"))])
		le.text = "" if v < 0 else str(v)


func _band_option(bands: Array, on_select: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(0, 54)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.add_theme_font_size_override("font_size", 20)
	for b in bands:
		o.add_item(String(b[0]))
	o.item_selected.connect(on_select)
	return o


func _era_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 54)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_font_override("font", UiKit.font_semi())
	b.pressed.connect(cb)
	return b


func _style_toggle(b: Button, on: bool, outline_when_on: bool = false) -> void:
	var kind := "select" if on and not outline_when_on else ("btn_press" if on else "btn")
	b.add_theme_stylebox_override("normal", UiKit.skin(kind, 6, 8, 4))
	b.add_theme_stylebox_override("hover", UiKit.skin(kind if on else "btn_hover", 6, 8, 4))
	b.add_theme_stylebox_override("pressed", UiKit.skin(kind, 6, 8, 4))


func _country_row(nat: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 56)
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("nation", nat)
	b.mouse_filter = Control.MOUSE_FILTER_PASS  # let drags reach the country list so it scrolls by touch
	b.button_down.connect(func() -> void: _press_country_scroll = _csc.scroll_vertical if _csc != null else 0)
	b.pressed.connect(func() -> void:
		if _csc != null and absi(_csc.scroll_vertical - _press_country_scroll) > 4:
			return  # the list scrolled under the finger: not a tap
		if _t_nations.has(nat):
			_t_nations.erase(nat)
		else:
			_t_nations[nat] = true
		_refresh_filter_widgets())
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 16)
	mc.add_theme_constant_override("margin_right", 16)
	var h := UiKit.hbox(16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flag := TextureRect.new()
	flag.texture = Flags.texture(String(_codes.get(nat, "")))
	flag.custom_minimum_size = Vector2(50, 34)
	flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(flag)
	var l := UiKit.label(nat, 25, Color.WHITE)
	l.add_theme_font_override("font", UiKit.font_semi())
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	var tick := LineIcon.make("check", 30)
	tick.name = "Tick"
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tick)
	mc.add_child(h)
	b.add_child(mc)
	return b


func _radio_row(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 54)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiKit.skin("recess", 6, 0, 0))
	b.add_theme_stylebox_override("hover", UiKit.skin("recess", 6, 0, 0))
	b.add_theme_stylebox_override("pressed", UiKit.skin("recess", 6, 0, 0))
	b.pressed.connect(cb)
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 16)
	var h := UiKit.hbox(16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := PanelContainer.new()
	dot.name = "Dot"
	dot.custom_minimum_size = Vector2(36, 36)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot)
	var l := UiKit.label(text, 24, Color.WHITE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	mc.add_child(h)
	b.add_child(mc)
	return b


func _radio_dot_style(on: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(3 if on else 2)
	sb.border_color = SELECT_BLUE if on else Color(1, 1, 1, 0.7)
	sb.set_corner_radius_all(18)
	if on:
		sb.set_expand_margin_all(0)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
	return sb


func _open_filters() -> void:
	_t_nations = _sel_nations.duplicate()
	_t_eras = _sel_eras.duplicate()
	_t_avail = _avail
	_t_caps = _caps_band
	_t_goals = _goals_band
	_t_cr[0] = _cr[0]
	_t_cr[1] = _cr[1]
	_t_gr[0] = _gr[0]
	_t_gr[1] = _gr[1]
	_country_search.text = ""
	# selected countries first (then alphabetical), only on open so rows don't jump while tapping
	var order: Array = session.repo.nationalities()
	order.sort_custom(func(a: String, b: String) -> bool:
		var sa := _t_nations.has(a)
		var sb := _t_nations.has(b)
		if sa != sb:
			return sa
		return a < b)
	for i in order.size():
		(_country_rows[order[i]] as Button).get_parent().move_child(_country_rows[order[i]], i)
	_refresh_filter_widgets()
	_main_panel.visible = false
	_filter_panel.visible = true


func _refresh_filter_widgets() -> void:
	for nat in _country_rows.keys():
		var b: Button = _country_rows[nat]
		var on := _t_nations.has(nat)
		b.add_theme_stylebox_override("normal", UiKit.skin("select" if on else "btn", 6, 0, 0))
		b.add_theme_stylebox_override("hover", UiKit.skin("select" if on else "btn_hover", 6, 0, 0))
		b.add_theme_stylebox_override("pressed", UiKit.skin("btn_press", 6, 0, 0))
		(b.find_child("Tick", true, false) as Control).visible = on
	var names := _t_nations.keys()
	names.sort()
	_country_summary.text = "" if names.is_empty() else (String(names[0]) + ("  +%d" % (names.size() - 1) if names.size() > 1 else ""))
	_style_toggle(_any_era_btn, _t_eras.is_empty(), true)
	for i in _era_btns.size():
		_style_toggle(_era_btns[i], _t_eras.has(i))
	for i in _avail_rows.size():
		var on_row := (i == 0) == _t_avail
		(_avail_rows[i].find_child("Dot", true, false) as PanelContainer).add_theme_stylebox_override("panel", _radio_dot_style(on_row))
		var fill := _avail_rows[i].find_child("Fill", true, false)
		if fill != null:
			fill.queue_free()
		if on_row:
			var inner := PanelContainer.new()
			inner.name = "Fill"
			var isb := StyleBoxFlat.new()
			isb.bg_color = SELECT_BLUE
			isb.set_corner_radius_all(9)
			inner.add_theme_stylebox_override("panel", isb)
			inner.custom_minimum_size = Vector2(18, 18)
			inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var dot := _avail_rows[i].find_child("Dot", true, false) as PanelContainer
			var cc := CenterContainer.new()
			cc.name = "Fill"
			cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cc.add_child(inner)
			dot.add_child(cc)
			# the CenterContainer is named Fill; the inner panel keeps its own name inside it
	if _caps_opt != null:
		_caps_opt.selected = _t_caps
		_goals_opt.selected = _t_goals
		_sync_range_edits()


func _filter_country_rows() -> void:
	var q := FootballerRepository.fold(_country_search.text.strip_edges())
	for nat in _country_rows.keys():
		(_country_rows[nat] as Button).visible = q == "" or FootballerRepository.fold(String(nat)).contains(q)


func _reset_temp() -> void:
	_t_nations.clear()
	_t_eras.clear()
	_t_avail = false
	_t_caps = 0
	_t_goals = 0
	_t_cr[0] = -1
	_t_cr[1] = -1
	_t_gr[0] = -1
	_t_gr[1] = -1
	_country_search.text = ""
	_filter_country_rows()
	_refresh_filter_widgets()


func _apply_filters() -> void:
	_sel_nations = _t_nations.duplicate()
	_sel_eras = _t_eras.duplicate()
	_avail = _t_avail
	_caps_band = _t_caps
	_goals_band = _t_goals
	_cr = _t_cr.duplicate()
	_gr = _t_gr.duplicate()
	_filter_panel.visible = false
	_main_panel.visible = true
	_rebuild()

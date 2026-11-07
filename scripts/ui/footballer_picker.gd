class_name FootballerPicker
extends Control
## Footballer selector: live search, sort, country chips with live counts, era filters,
## "available only", Random, section headers, paged results.
## Normal play: never shows or sorts/filters by caps/goals. TEST MODE (show_stats) additionally
## shows stats and unlocks stat sorting/filtering (a testing aid; see docs/DECISIONS.md).

signal picked(id: String)
signal closed

const PAGE := 50

## Remembered between openings (you reopen the picker every shot).
static var _saved := {"sort": "name_az", "nations": {}, "eras": {}, "avail": false,
	"caps_band": 0, "goals_band": 0, "filters_open": false}

var session: GameSession
var show_stats := false
var _search: LineEdit
var _sort: OptionButton
var _sort_keys: Array[String] = []
var _avail_btn: Button
var _filters_btn: Button
var _filters_box: VBoxContainer
var _clear_btn: Button
var _summary: Label
var _chips_row: HBoxContainer
var _chip_btns: Dictionary = {}     # nationality -> Button
var _codes: Dictionary = {}         # nationality -> country code
var _era_btns: Array[Button] = []
var _caps_opt: OptionButton
var _goals_opt: OptionButton
var _sc: ScrollContainer
var _list: VBoxContainer
var _press_scroll := 0
var _limit := PAGE
var _debounce: Timer


func setup(s: GameSession) -> void:
	session = s
	theme = UiKit.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiKit.overlay(0.6))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sm := UiKit.safe_margins(get_viewport()) if is_inside_tree() else [16.0, 16.0, 16.0, 16.0]
	m.add_theme_constant_override("margin_left", int(sm[0]) + 8)
	m.add_theme_constant_override("margin_right", int(sm[2]) + 8)
	m.add_theme_constant_override("margin_top", int(sm[1]) + 24)
	m.add_theme_constant_override("margin_bottom", int(sm[3]) + 16)
	add_child(m)
	var p := UiKit.panel(UiKit.C_PANEL_SOLID)
	m.add_child(p)
	var v := UiKit.vbox(10)
	p.add_child(v)
	# ---- header
	var head := UiKit.hbox()
	head.add_child(UiKit.expand(UiKit.label("Choose footballer", 32)))
	head.add_child(UiKit.button("Close", func() -> void: closed.emit(), 60, 22))
	v.add_child(head)
	if show_stats:
		v.add_child(UiKit.text("TEST MODE: caps & goals shown; stat sorting/filters unlocked (off in Settings)", 18, UiKit.C_WARN))
	# ---- search + random
	var srow := UiKit.hbox(8)
	_search = LineEdit.new()
	_search.placeholder_text = "Search %d players…" % session.repo.count()
	_search.custom_minimum_size = Vector2(0, 60)
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = 0.18
	_debounce.timeout.connect(_rebuild)
	add_child(_debounce)
	_search.text_changed.connect(func(_t: String) -> void: _debounce.start())
	srow.add_child(_search)
	var rnd := UiKit.button("Random", _on_random, 60, 20)
	rnd.custom_minimum_size.x = 130
	srow.add_child(rnd)
	v.add_child(srow)
	# ---- sort + available only + filters toggle
	var row2 := UiKit.hbox(8)
	_sort = OptionButton.new()
	_sort.custom_minimum_size = Vector2(0, 56)
	_sort.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sort.add_theme_font_size_override("font_size", 20)
	var labels: Array = FootballerRepository.SORT_LABELS.duplicate()
	if show_stats:
		labels.append_array(FootballerRepository.STAT_SORT_LABELS)
	for pair in labels:
		_sort_keys.append(String(pair[0]))
		_sort.add_item(String(pair[1]))
	_sort.selected = maxi(_sort_keys.find(String(_saved["sort"])), 0)
	_sort.item_selected.connect(func(_i: int) -> void: _rebuild())
	row2.add_child(_sort)
	_avail_btn = UiKit.button("Available only", func() -> void: _rebuild(), 56, 19)
	_avail_btn.toggle_mode = true
	_avail_btn.button_pressed = bool(_saved["avail"])
	_avail_btn.add_theme_stylebox_override("pressed", UiKit.box(UiKit.C_ACCENT_DARK, 14, 12))
	row2.add_child(_avail_btn)
	_filters_btn = UiKit.button("Filters", _toggle_filters, 56, 19)
	row2.add_child(_filters_btn)
	v.add_child(row2)
	# ---- country chips (horizontal scroll)
	var chips_sc := ScrollContainer.new()
	chips_sc.custom_minimum_size = Vector2(0, 68)
	chips_sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chips_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	chips_sc.scroll_deadzone = 12
	_chips_row = UiKit.hbox(8)
	chips_sc.add_child(_chips_row)
	v.add_child(chips_sc)
	for fb in session.repo.all_sorted():
		if not _codes.has(fb.nationality):
			_codes[fb.nationality] = fb.country_code if fb.country_code != "" else fb.nationality.substr(0, 3).to_upper()
	for nat in session.repo.nationalities():
		var b := UiKit.button(nat, func() -> void: _rebuild(), 56, 18)
		b.toggle_mode = true
		b.icon = Flags.texture(String(_codes[nat]))
		b.add_theme_constant_override("h_separation", 8)
		b.add_theme_stylebox_override("pressed", UiKit.box(UiKit.C_ACCENT_DARK, 14, 10))
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.button_pressed = (_saved["nations"] as Dictionary).has(nat)
		_chip_btns[nat] = b
		_chips_row.add_child(b)
	# ---- collapsible filters
	_filters_box = UiKit.vbox(8)
	_filters_box.visible = bool(_saved["filters_open"])
	v.add_child(_filters_box)
	_filters_box.add_child(UiKit.label("Born", 18, UiKit.C_MUTED))
	var eras := HFlowContainer.new()
	eras.add_theme_constant_override("h_separation", 8)
	eras.add_theme_constant_override("v_separation", 8)
	for i in FootballerRepository.ERAS.size():
		var eb := UiKit.button(String(FootballerRepository.ERAS[i][0]), func() -> void: _rebuild(), 52, 19)
		eb.toggle_mode = true
		eb.custom_minimum_size.x = 100
		eb.add_theme_stylebox_override("pressed", UiKit.box(UiKit.C_ACCENT_DARK, 14, 10))
		eb.button_pressed = (_saved["eras"] as Dictionary).has(i)
		_era_btns.append(eb)
		eras.add_child(eb)
	_filters_box.add_child(eras)
	if show_stats:
		_filters_box.add_child(UiKit.label("Test mode: stat filters", 18, UiKit.C_WARN))
		var stat_row := UiKit.hbox(8)
		_caps_opt = _band_option(FootballerRepository.CAPS_BANDS, int(_saved["caps_band"]))
		_goals_opt = _band_option(FootballerRepository.GOALS_BANDS, int(_saved["goals_band"]))
		stat_row.add_child(_caps_opt)
		stat_row.add_child(_goals_opt)
		_filters_box.add_child(stat_row)
	# ---- summary / clear
	var srow2 := UiKit.hbox(8)
	_summary = UiKit.label("", 19, UiKit.C_MUTED)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	srow2.add_child(_summary)
	_clear_btn = UiKit.button("Clear filters", _clear_filters, 48, 18)
	srow2.add_child(_clear_btn)
	v.add_child(srow2)
	# ---- results
	_sc = ScrollContainer.new()
	_sc.scroll_deadzone = 14
	_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_sc)
	_list = UiKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(_list)
	_rebuild()


func _band_option(bands: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(0, 54)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.add_theme_font_size_override("font_size", 20)
	for b in bands:
		o.add_item(String(b[0]))
	o.selected = selected
	o.item_selected.connect(func(_i: int) -> void: _rebuild())
	return o


func _toggle_filters() -> void:
	_filters_box.visible = not _filters_box.visible
	_saved["filters_open"] = _filters_box.visible
	_update_filter_labels()


func _options(limit: int) -> Dictionary:
	var nations := {}
	for nat in _chip_btns.keys():
		if (_chip_btns[nat] as Button).button_pressed:
			nations[nat] = true
	var eras := {}
	for i in _era_btns.size():
		if _era_btns[i].button_pressed:
			eras[i] = true
	return {
		"q": _search.text, "nations": nations, "eras": eras,
		"available_only": _avail_btn.button_pressed,
		"caps_band": _caps_opt.selected if _caps_opt != null else 0,
		"goals_band": _goals_opt.selected if _goals_opt != null else 0,
		"sort": _sort_keys[maxi(_sort.selected, 0)], "limit": limit,
	}


func _active_filter_count(o: Dictionary) -> int:
	var n := 0
	n += 1 if not (o["nations"] as Dictionary).is_empty() else 0
	n += 1 if not (o["eras"] as Dictionary).is_empty() else 0
	n += 1 if int(o["caps_band"]) > 0 else 0
	n += 1 if int(o["goals_band"]) > 0 else 0
	n += 1 if bool(o["available_only"]) else 0
	n += 1 if String(o["q"]).strip_edges() != "" else 0
	return n


func _clear_filters() -> void:
	_search.text = ""
	for b in _chip_btns.values():
		(b as Button).set_pressed_no_signal(false)
	for b in _era_btns:
		b.set_pressed_no_signal(false)
	_avail_btn.set_pressed_no_signal(false)
	if _caps_opt != null:
		_caps_opt.selected = 0
		_goals_opt.selected = 0
	_rebuild()


func _update_filter_labels(o: Dictionary = {}) -> void:
	if o.is_empty():
		o = _options(-1)
	var narrow := int(not (o["eras"] as Dictionary).is_empty()) + int(int(o["caps_band"]) > 0) + int(int(o["goals_band"]) > 0)
	_filters_btn.text = "Filters%s %s" % [(" (%d)" % narrow) if narrow > 0 else "", "▴" if _filters_box.visible else "▾"]


func _rebuild() -> void:
	_limit = PAGE
	var o := _options(-1)
	_saved["sort"] = o["sort"]
	_saved["nations"] = o["nations"]
	_saved["eras"] = o["eras"]
	_saved["avail"] = o["available_only"]
	_saved["caps_band"] = o["caps_band"]
	_saved["goals_band"] = o["goals_band"]
	_render()


## Only the first _limit matches become buttons (the real database has ~10k players).
func _render() -> void:
	UiKit.clear(_list)
	var o := _options(-1)
	var results := session.repo.query(o, session.pool)
	var total := results.size()
	# live counts on country chips: what each chip would give under the OTHER filters
	var counts := session.repo.facet_counts(o, session.pool)
	for nat in _chip_btns.keys():
		var b: Button = _chip_btns[nat]
		var n := int(counts.get(nat, 0))
		b.text = "%s  %d" % [_codes[nat], n]
		b.disabled = n == 0 and not b.button_pressed
	var key := String(o["sort"])
	var last_header := ""
	for i in mini(_limit, total):
		var fb: Footballer = results[i]
		var header := _header_for(fb, key)
		if header != "" and header != last_header:
			last_header = header
			_list.add_child(UiKit.label(header, 20, UiKit.C_ACCENT.lightened(0.25)))
		var used := session.pool.is_used(fb.id)
		var b := UiKit.player_button(fb, show_stats, used, fb.id == session.selected_id, func() -> void: _on_pick(fb.id))
		# Let drags reach the ScrollContainer (touch scrolling); a press only picks if the list didn't scroll.
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.button_down.connect(func() -> void: _press_scroll = _sc.scroll_vertical)
		_list.add_child(b)
	if total == 0:
		_list.add_child(UiKit.text("No players match. Try clearing a filter.", 24, UiKit.C_MUTED))
	if total > _limit:
		var more := UiKit.button("Show more (%d of %d shown)" % [_limit, total], func() -> void:
			_limit += PAGE
			var keep := _sc.scroll_vertical
			_render()
			_sc.set_deferred("scroll_vertical", keep), 64, 22)
		more.mouse_filter = Control.MOUSE_FILTER_PASS
		_list.add_child(more)
	var avail := 0
	for fb in results:
		if not session.pool.is_used(fb.id):
			avail += 1
	_summary.text = "%d match · %d available · %d used" % [total, avail, session.pool.used_count()]
	_clear_btn.visible = _active_filter_count(o) > 0
	_update_filter_labels(o)


func _header_for(fb: Footballer, key: String) -> String:
	match key:
		"name_az", "name_za":
			return fb.name.substr(0, 1).to_upper() if fb.name != "" else ""
		"country":
			return fb.nationality
		"born_old", "born_new":
			return ("%ds" % (fb.birth_year / 10 * 10)) if fb.birth_year > 0 else "Unknown birth year"
	return ""


## Random pick among the AVAILABLE players matching the current filters (stats stay hidden).
func _on_random() -> void:
	var o := _options(-1)
	o["available_only"] = true
	var candidates := session.repo.query(o, session.pool)
	if candidates.is_empty():
		return
	var fb: Footballer = candidates[randi() % candidates.size()]
	_on_pick(fb.id, true)


func _on_pick(id: String, force: bool = false) -> void:
	if not force and absi(_sc.scroll_vertical - _press_scroll) > 6:
		return
	if session.select_footballer(id):
		picked.emit(id)

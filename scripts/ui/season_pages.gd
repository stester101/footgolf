class_name SeasonPages
extends RefCounted
## Presentation of a mini season (data and rules live in Season): the page shown after every course
## (that course's result + the running season table) and the final page with the winner.
## Pure view: it only reads the Season it is given. Built from RoundController as a GameUI overlay.


static func _tag(text: String, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(text, size, color, align)
	l.add_theme_font_override("font", UiKit.font_caps())
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _cell(text: String, width: int, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_RIGHT) -> Label:
	var l := UiKit.label(text, size, color, align)
	l.custom_minimum_size.x = width
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _row(cells: Array) -> HBoxContainer:
	var h := UiKit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in cells:
		h.add_child(c)
	return h


static func _plate() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.skin("glass", 6, 18, 14))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


static func _name_cell(text: String) -> Label:
	var l := UiKit.label(text, 24, Color.WHITE)
	l.add_theme_font_override("font", UiKit.font_semi())
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _rel(v: int) -> String:
	return RoundState.fmt_relative(v)


## Result of the course at `at`: [{name, place, strokes, rel, points}] best first.
static func course_rows(season: Season, at: int) -> Array:
	var r: Dictionary = season.results[at]
	var places := Season.places_for(r.rel)
	var rows: Array = []
	for p in (r.names as Array).size():
		rows.append({"name": String(r.names[p]), "place": int(places[p]), "strokes": int(r.strokes[p]),
			"rel": int(r.rel[p]), "points": int(r.points[p]) if (r.points as Array).size() > p else 0, "seat": p})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.seat) < int(b.seat) if a.place == b.place else a.place < b.place)
	return rows


## The overlay. `at` = index of the course just finished. can_advance=false (online guest) shows a waiting note.
static func build(season: Season, at: int, can_advance: bool, on_next: Callable, on_menu: Callable) -> Control:
	var final := season.is_finished() and not season.has_next()
	var multi := season.player_count() > 1
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_meta("keep_hud", true)
	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.06, 0.12, 0.90)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(scrim)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.add_theme_constant_override("margin_top", 70)
	m.add_theme_constant_override("margin_bottom", 20)
	root.add_child(m)
	var col := UiKit.vbox(12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sc)
	var body := UiKit.vbox(12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc.add_child(body)

	# header plate
	var head := _plate()
	var hv := UiKit.vbox(2)
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(_tag("SEASON COMPLETE" if final else "COURSE %d OF %d COMPLETE" % [at + 1, season.courses.size()], 17, UiKit.C_CYAN))
	if final:
		var w := season.winners()
		var title := ("Winner: " + " & ".join(PackedStringArray(w))) if multi else "Season total %s" % _rel(int(season.standings()[0].rel))
		var tl := UiKit.label(title, 38, Color.WHITE)
		tl.add_theme_font_override("font", UiKit.font_semi())
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hv.add_child(tl)
	else:
		var cn := UiKit.label(String(season.results[at].name), 38, Color.WHITE)
		cn.add_theme_font_override("font", UiKit.font_semi())
		cn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hv.add_child(cn)
	head.add_child(hv)
	body.add_child(head)

	# this course
	var res := _plate()
	var rv := UiKit.vbox(6)
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r: Dictionary = season.results[at]
	rv.add_child(_tag("%s  ·  %d HOLES  ·  PAR %d" % [String(r.name).to_upper(), int(r.holes), int(r.par)], 16, UiKit.C_MUTED))
	rv.add_child(_row([_cell("#", 36, 16, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_LEFT), _name_cell("PLAYER"),
		_cell("SCORE", 96, 16, UiKit.C_MUTED)] + ([_cell("PTS", 64, 16, UiKit.C_MUTED)] if multi else [])))
	for row in course_rows(season, at):
		rv.add_child(_row([_cell(str(row.place) if multi else "", 36, 24, UiKit.C_WARN, HORIZONTAL_ALIGNMENT_LEFT),
			_name_cell(String(row.name)), _cell("%d (%s)" % [row.strokes, _rel(int(row.rel))], 96, 24, Color.WHITE)]
			+ ([_cell("+%d" % row.points, 64, 24, UiKit.C_ACCENT)] if multi else [])))
	res.add_child(rv)
	body.add_child(res)

	# season table
	var tab := _plate()
	var tv := UiKit.vbox(6)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(_tag("SEASON TABLE  ·  AFTER %d OF %d" % [season.results.size(), season.courses.size()], 16, UiKit.C_MUTED))
	tv.add_child(_row([_cell("#", 36, 16, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_LEFT), _name_cell("PLAYER"),
		_cell("TO PAR", 80, 16, UiKit.C_MUTED)] + ([_cell("POINTS", 80, 16, UiKit.C_MUTED)] if multi else [_cell("STROKES", 80, 16, UiKit.C_MUTED)])))
	for row in season.standings():
		var lead := int(row.place) == 1 and multi
		tv.add_child(_row([_cell(str(row.place) if multi else "", 36, 24, UiKit.C_WARN, HORIZONTAL_ALIGNMENT_LEFT),
			_name_cell(String(row.name)), _cell(_rel(int(row.rel)), 80, 24, Color.WHITE),
			_cell(str(row.points) if multi else str(row.strokes), 80, 28, UiKit.C_ACCENT if lead else Color.WHITE)]))
	if multi:
		tv.add_child(_tag("POINTS PER COURSE: 1ST 2 x HOLES, 2ND 1.2 x, 3RD 0.7 x, 4TH 0.4 x. TIES SHARE.", 13, UiKit.C_MUTED))
	tab.add_child(tv)
	body.add_child(tab)

	# actions
	var bottom := _plate()
	var bv := UiKit.vbox(10)
	if not final:
		if can_advance:
			var b := UiKit.primary(UiKit.button("NEXT COURSE  (%d of %d)" % [at + 2, season.courses.size()], on_next, 90, 30))
			b.set_meta("ui_id", "season_next")
			bv.add_child(b)
		else:
			bv.add_child(UiKit.label("Waiting for the host to start course %d of %d" % [at + 2, season.courses.size()],
				22, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER, true))
	var mb := UiKit.button("End season  ·  main menu" if not final else "Main menu", on_menu, 76, 26)
	mb.set_meta("ui_id", "season_menu")
	bv.add_child(mb)
	bottom.add_child(bv)
	col.add_child(bottom)
	return root

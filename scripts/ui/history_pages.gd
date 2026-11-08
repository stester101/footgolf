class_name HistoryPages
extends RefCounted
## Menu pages for saved rounds, Round History and Records. Presentation only: data comes from
## RoundSave / RoundHistory; the pages reuse MainMenu's page helpers so they look like the rest.


static func fmt_date(unix: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %02d:%02d" % [dt["day"], months[int(dt["month"]) - 1], dt["hour"], dt["minute"]]


static func _players_line(players: Array) -> String:
	var parts: Array[String] = []
	for p in players:
		parts.append("%s %s" % [p["name"], RoundState.fmt_relative(int(p["to_par"]))])
	return ", ".join(parts)


# ------------------------------------------------------------------ resume

static func open_resume(menu: MainMenu) -> void:
	var pg: Dictionary = menu._page("Resume round")
	var body: VBoxContainer = pg["body"]
	_fill_resume(menu, body)
	menu._push(pg["root"])


static func _fill_resume(menu: MainMenu, body: VBoxContainer) -> void:
	UiKit.clear(body)
	var saves := RoundSave.list_saves()
	if saves.is_empty():
		body.add_child(menu._note("No unfinished rounds. A round is saved automatically after every shot."))
		return
	for sv in saves:
		var id := String(sv["id"])
		var sub := "Hole %d of %d  ·  %d done  ·  %s\n%s" % [int(sv["hole_index"]) + 1, int(sv["holes_total"]), int(sv["holes_done"]),
			_players_line(sv["players"]), fmt_date(int(sv["saved_at"]))]
		body.add_child(menu._nav_row("flag", String(sv["course_name"]), sub, func() -> void: menu.resume_requested.emit(id), "resume_" + id))
		var del := UiKit.button("Delete this round", Callable(), 56, 20)
		del.add_theme_color_override("font_color", UiKit.C_WARN)
		del.set_meta("ui_id", "delete_" + id)
		del.pressed.connect(func() -> void:
			if not del.has_meta("armed"):
				del.set_meta("armed", true)
				del.text = "Tap again to delete"
				return
			RoundSave.delete(id)
			_fill_resume(menu, body))
		body.add_child(del)


# ------------------------------------------------------------------ history

static func open_history(menu: MainMenu) -> void:
	var pg: Dictionary = menu._page("Round History")
	var body: VBoxContainer = pg["body"]
	var recs := RoundHistory.recent()
	if recs.is_empty():
		body.add_child(menu._note("No finished rounds yet. Completed rounds appear here with their scorecards."))
	for r in recs:
		var rec: Dictionary = r
		var mine: Dictionary = rec["players"][0]
		var title := "%s  ·  %s" % [rec["course_name"], RoundState.fmt_relative(int(mine["to_par"]))] if (rec["players"] as Array).size() == 1 \
			else "%s  ·  %s" % [rec["course_name"], String(rec.get("winner", "")) if String(rec.get("winner", "")) != "" else "Tied"]
		var sub := "%s  ·  %s" % [fmt_date(int(rec["date"])), _players_line(rec["players"])]
		body.add_child(menu._nav_row("list", title, sub, func() -> void: open_detail(menu, rec), "history_" + String(rec["id"])))
	menu._push(pg["root"])


static func open_detail(menu: MainMenu, rec: Dictionary) -> void:
	var pg: Dictionary = menu._page(String(rec["course_name"]))
	var body: VBoxContainer = pg["body"]
	body.add_child(menu._note("%s  ·  %s" % [fmt_date(int(rec["date"])), RoundHistory.rules_label(rec.get("rules", {}))]))
	for p in rec["players"]:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 16, 12))
		var v := UiKit.vbox(6)
		panel.add_child(v)
		var head := UiKit.hbox(8)
		var nm := UiKit.label(String(p["name"]), 28, Color.WHITE)
		nm.add_theme_font_override("font", UiKit.font_semi())
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nm)
		var tot := UiKit.label("%d  (%s)" % [int(p["score"]), RoundState.fmt_relative(int(p["to_par"]))], 28, UiKit.C_ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
		tot.add_theme_font_override("font", UiKit.font_semi())
		head.add_child(tot)
		v.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 12)
		for c in ["HOLE", "PAR", "SCORE", "+/-"]:
			var hl := UiKit.label(c, 16, UiKit.C_CYAN, HORIZONTAL_ALIGNMENT_RIGHT if c != "HOLE" else HORIZONTAL_ALIGNMENT_LEFT)
			hl.add_theme_font_override("font", UiKit.font_caps())
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL if c == "HOLE" else Control.SIZE_SHRINK_END
			grid.add_child(hl)
		for h in p["holes"]:
			var pen := int(h.get("penalties", 0))
			grid.add_child(_cell(String(h["name"]), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, true))
			grid.add_child(_cell(str(int(h["par"])), 20, UiKit.C_MUTED))
			grid.add_child(_cell("%d%s" % [int(h["score"]), " (%d pen)" % pen if pen > 0 else ""], 20, Color.WHITE))
			var tp := int(h["to_par"])
			grid.add_child(_cell(RoundState.fmt_relative(tp), 20, UiKit.C_ACCENT if tp < 0 else (UiKit.C_WARN if tp > 0 else Color.WHITE)))
		v.add_child(grid)
		var bh: Dictionary = p.get("best_hole", {})
		var wh: Dictionary = p.get("worst_hole", {})
		if not bh.is_empty():
			v.add_child(menu._note("Best hole: %s (%s)    Worst hole: %s (%s)" % [bh["name"], RoundState.fmt_relative(int(bh["to_par"])),
				wh["name"], RoundState.fmt_relative(int(wh["to_par"]))]))
		body.add_child(panel)
	menu._push(pg["root"])


static func _cell(t: String, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_RIGHT, expand: bool = false) -> Label:
	var l := UiKit.label(t, size, col, align)
	if expand:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
	return l


# ------------------------------------------------------------------ records

static func open_records(menu: MainMenu) -> void:
	var pg: Dictionary = menu._page("Records")
	var body: VBoxContainer = pg["body"]
	var rec := RoundHistory.records(RoundHistory.load_records())
	if int(rec["rounds"]) == 0:
		body.add_child(menu._note("Personal bests appear here after your first finished round."))
		menu._push(pg["root"])
		return
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 10)
	for pair in [["ROUNDS", rec["rounds"]], ["HOLES-IN-ONE", rec["holes_in_one"]], ["BIRDIES+", rec["birdies_or_better"]]]:
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
	var bh: Dictionary = rec["best_hole"]
	if not bh.is_empty():
		body.add_child(menu._note("Best hole: %s on %s (%s, %s)" % [bh["name"], bh["course_name"], RoundState.fmt_relative(int(bh["to_par"])), bh["player"]]))
	for c in rec["courses"]:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 16, 12))
		var v := UiKit.vbox(2)
		var t := UiKit.label(String(c["course_name"]), 26, Color.WHITE)
		t.add_theme_font_override("font", UiKit.font_semi())
		v.add_child(t)
		v.add_child(UiKit.label("BEST %d (%s)  ·  %s  ·  %s" % [int(c["best_score"]), RoundState.fmt_relative(int(c["best_to_par"])),
			c["best_player"], fmt_date(int(c["best_date"]))], 19, UiKit.C_ACCENT))
		v.add_child(UiKit.label("%d rounds  ·  average %s" % [int(c["rounds"]), "%+.1f" % float(c["avg_to_par"])], 19, UiKit.C_MUTED))
		v.add_child(menu._note(String(c["rules_label"])))
		panel.add_child(v)
		body.add_child(panel)
	menu._push(pg["root"])

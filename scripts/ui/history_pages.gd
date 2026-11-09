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


# ------------------------------------------------------------------ profile scope

## Profile whose statistics are shown ("" = guests). null until first used: defaults to the first profile.
static var profile_id: Variant = null


static func _ensure_migrated() -> void:
	var all := App.profiles.all_profiles()
	HistoryMigration.ensure(App.telemetry, String(all[0]["id"]) if not all.is_empty() else "")


static func _scope_options(recs: Array) -> Array:
	var ids: Array = []
	for pr in App.profiles.all_profiles():
		ids.append(String(pr["id"]))
	if RoundHistory.profile_ids_in(recs).has(""):
		ids.append("")
	return ids


static func current_profile(recs: Array) -> String:
	var opts := _scope_options(recs)
	if profile_id == null or not opts.has(String(profile_id)):
		profile_id = String(opts[0]) if not opts.is_empty() else ""
	return String(profile_id)


static func profile_label(pid: String) -> String:
	return "Guests" if pid == "" else String(App.profiles.get_profile(pid).get("name", "Player"))


## Button cycling the shown profile; `refresh` rebuilds the page body. Hidden when there is only one choice.
static func _profile_bar(body: VBoxContainer, recs: Array, refresh: Callable) -> void:
	var opts := _scope_options(recs)
	if opts.size() < 2:
		return
	var b := UiKit.button("Profile: %s  (tap to change)" % profile_label(current_profile(recs)), Callable(), 56, 22)
	b.set_meta("ui_id", "stats_profile")
	b.pressed.connect(func() -> void:
		profile_id = opts[(opts.find(current_profile(recs)) + 1) % opts.size()]
		refresh.call())
	body.add_child(b)


static func _tiles(pairs: Array) -> HBoxContainer:
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 10)
	for pair in pairs:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 12, 14))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UiKit.vbox(0)
		var n := UiKit.label(str(pair[1]), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		n.add_theme_font_override("font", UiKit.font_semi())
		v.add_child(n)
		var c := UiKit.label(String(pair[0]), 16, UiKit.C_CYAN, HORIZONTAL_ALIGNMENT_CENTER)
		c.add_theme_font_override("font", UiKit.font_caps())
		v.add_child(c)
		p.add_child(v)
		grid.add_child(p)
	return grid


static func _kv_panel(title: String, rows: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 16, 12))
	var v := UiKit.vbox(4)
	var t := UiKit.label(title, 22, UiKit.C_CYAN)
	t.add_theme_font_override("font", UiKit.font_caps())
	v.add_child(t)
	for r in rows:
		var h := UiKit.hbox(8)
		var k := UiKit.label(String(r[0]), 20, UiKit.C_MUTED)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(k)
		h.add_child(UiKit.label(String(r[1]), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(h)
	panel.add_child(v)
	return panel


static func _fmt_to_par(v: Variant) -> String:
	return "N/A" if v == null else ("E" if absf(float(v)) < 0.05 else "%+.1f" % float(v))


static func _pair(acc: Dictionary, unit: String) -> String:
	return "%s / %s %s" % [StatsEngine.fmt_num(StatsEngine.acc_avg(acc)), StatsEngine.fmt_num(StatsEngine.acc_max(acc)), unit]


## Label/value rows for a lifetime aggregate (StatsEngine.lifetime); a single round is lifetime([stats]).
static func stat_rows(L: Dictionary) -> Dictionary:
	var acc: Dictionary = L["acc"]
	var rounds := int(L["rounds"])
	var full := int(L["full_rounds"])
	var scoring: Array = [
		["Avg to par / round", _fmt_to_par(null if rounds == 0 else float(L["to_par"]) / rounds)],
		["Birdies or better", str(L["birdies_or_better"])], ["Pars", str(L["pars"])], ["Bogeys or worse", str(L["bogeys_plus"])],
		["Holes-in-one", str(L["aces"])], ["Penalties", str(L["penalties"])]]
	var play: Array = [
		["Fairways hit (par 4/5 tee shots)", StatsEngine.fmt_pct(StatsEngine.ratio(int(L["fw_hit"]), int(L["fw_elig"])))],
		["Greens in regulation", StatsEngine.fmt_pct(StatsEngine.ratio(int(L["gir_hit"]), int(L["gir_holes"])))],
		["Putts per round", StatsEngine.fmt_num(null if full == 0 else float(L["putts"]) / full)],
		["Putts per hole", StatsEngine.fmt_num(null if int(L["full_holes"]) == 0 else float(L["putts"]) / int(L["full_holes"]), 2)]]
	var dist: Array = [
		["Approach carry avg / longest", _pair(acc["approach_carry_yd"], "yd")],
		["Approach total avg / longest", _pair(acc["approach_total_yd"], "yd")],
		["Putt travel avg / longest", _pair(acc["putt_total_ft"], "ft")]]
	var shots := int(L["shots"])
	var mode: Array = [
		["Caps shots", "%d  (%s)" % [L["caps_shots"], StatsEngine.fmt_pct(StatsEngine.ratio(int(L["caps_shots"]), shots))]],
		["Goals shots", "%d  (%s)" % [L["goals_shots"], StatsEngine.fmt_pct(StatsEngine.ratio(int(L["goals_shots"]), shots))]],
		["Caps: avg yd gained on pin", StatsEngine.fmt_num(StatsEngine.acc_avg(acc["caps_gain_yd"]))],
		["Goals: avg yd gained on pin", StatsEngine.fmt_num(StatsEngine.acc_avg(acc["goals_gain_yd"]))],
		["Caps: avg yd left to pin", StatsEngine.fmt_num(StatsEngine.acc_avg(acc["caps_remaining_yd"]))],
		["Goals: avg yd left to pin", StatsEngine.fmt_num(StatsEngine.acc_avg(acc["goals_remaining_yd"]))],
		["Holed with Caps / Goals", "N/A" if full == 0 else "%d / %d" % [L["caps_holed"], L["goals_holed"]]]]
	var tops: Array[String] = []
	for f in L["top_footballers"]:
		tops.append("%s x%d" % [f["name"], int(f["n"])])
	var fb: Array = [["Footballers used", str(L["footballers_used"])], ["Most used", ", ".join(tops) if not tops.is_empty() else "N/A"]]
	return {"scoring": scoring, "play": play, "dist": dist, "mode": mode, "fb": fb}


static func _stat_panels(body: VBoxContainer, L: Dictionary) -> void:
	var r := stat_rows(L)
	body.add_child(_kv_panel("SCORING", r["scoring"]))
	body.add_child(_kv_panel("TEE TO GREEN", r["play"]))
	body.add_child(_kv_panel("DISTANCES", r["dist"]))
	body.add_child(_kv_panel("CAPS VS GOALS", r["mode"]))
	body.add_child(_kv_panel("FOOTBALLERS", r["fb"]))


# ------------------------------------------------------------------ overview

static func open_overview(menu: MainMenu) -> void:
	_ensure_migrated()
	var pg: Dictionary = menu._page("Overview")
	var body: VBoxContainer = pg["body"]
	_fill_overview(menu, body)
	menu._push(pg["root"])


static func _fill_overview(menu: MainMenu, body: VBoxContainer) -> void:
	UiKit.clear(body)
	var recs := RoundHistory.load_records()
	_profile_bar(body, recs, func() -> void: _fill_overview(menu, body))
	var pid := current_profile(recs)
	var ents := RoundHistory.entries(recs, pid)
	var L := RoundHistory.lifetime(ents)
	body.add_child(_tiles([["ROUNDS", L["rounds"]], ["HOLES", L["holes"]], ["SHOTS", L["shots"]]]))
	if ents.is_empty():
		body.add_child(menu._note("No finished rounds for %s yet. Statistics appear after a round is completed." % profile_label(pid)))
	else:
		var to_par: Array = []
		for e in ents:
			to_par.append(int(e["player"]["to_par"]))
		var tr = StatsEngine.trend_to_par(to_par)
		body.add_child(menu._note("Trend (last 3 rounds vs the 3 before): %s" % ("needs 6 finished rounds" if tr == null else "%+.1f strokes to par per round (lower is better)" % float(tr))))
		_stat_panels(body, L)
		if int(L["full_rounds"]) < int(L["rounds"]):
			body.add_child(menu._note("Tee-to-green, distance and performance figures use %d of %d rounds; older rounds were recorded without shot detail (N/A)." % [L["full_rounds"], L["rounds"]]))
	body.add_child(menu._note("Stored on this device for this profile only. Definitions: docs/STATS_DEFINITIONS.md."))
	body.add_child(menu._nav_row("list", "Export data", "Copy a summary or save CSV / JSON files", func() -> void: menu._show_export()))


# ------------------------------------------------------------------ history

static func open_history(menu: MainMenu) -> void:
	_ensure_migrated()
	var pg: Dictionary = menu._page("Round History")
	var body: VBoxContainer = pg["body"]
	_fill_history(menu, body)
	menu._push(pg["root"])


static func _fill_history(menu: MainMenu, body: VBoxContainer) -> void:
	UiKit.clear(body)
	var allrecs := RoundHistory.load_records()
	_profile_bar(body, allrecs, func() -> void: _fill_history(menu, body))
	var pid := current_profile(allrecs)
	var ents := RoundHistory.entries(allrecs, pid)
	if ents.is_empty():
		body.add_child(menu._note("No finished rounds for %s yet. Completed rounds appear here with their scorecards." % profile_label(pid)))
	for e in ents:
		var rec: Dictionary = e["rec"]
		var mine: Dictionary = e["player"]
		var title := "%s  ·  %d (%s)" % [rec["course_name"], int(mine["score"]), RoundState.fmt_relative(int(mine["to_par"]))]
		var sub := "%s  ·  %s" % [fmt_date(int(rec["date"])), _players_line(rec["players"])]
		body.add_child(menu._nav_row("list", title, sub, func() -> void: open_detail(menu, rec), "history_" + String(rec["id"])))


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
		var rows: Array = []
		if typeof(p.get("stats")) == TYPE_DICTIONARY:
			rows = (p["stats"] as Dictionary).get("hole_rows", [])
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 12)
		for c in ["HOLE", "PAR", "SCORE", "+/-", "PUTTS"]:
			var hl := UiKit.label(c, 16, UiKit.C_CYAN, HORIZONTAL_ALIGNMENT_RIGHT if c != "HOLE" else HORIZONTAL_ALIGNMENT_LEFT)
			hl.add_theme_font_override("font", UiKit.font_caps())
			hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL if c == "HOLE" else Control.SIZE_SHRINK_END
			grid.add_child(hl)
		for i in (p["holes"] as Array).size():
			var h: Dictionary = p["holes"][i]
			var pen := int(h.get("penalties", 0))
			grid.add_child(_cell(String(h["name"]), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, true))
			grid.add_child(_cell(str(int(h["par"])), 20, UiKit.C_MUTED))
			grid.add_child(_cell("%d%s" % [int(h["score"]), " (%d pen)" % pen if pen > 0 else ""], 20, Color.WHITE))
			var tp := int(h["to_par"])
			grid.add_child(_cell(RoundState.fmt_relative(tp), 20, UiKit.C_ACCENT if tp < 0 else (UiKit.C_WARN if tp > 0 else Color.WHITE)))
			var putts = rows[i].get("putts") if i < rows.size() else null
			grid.add_child(_cell("-" if putts == null else str(int(putts)), 20, UiKit.C_MUTED))
		v.add_child(grid)
		var bh: Dictionary = p.get("best_hole", {})
		var wh: Dictionary = p.get("worst_hole", {})
		if not bh.is_empty():
			v.add_child(menu._note("Best hole: %s (%s)    Worst hole: %s (%s)" % [bh["name"], RoundState.fmt_relative(int(bh["to_par"])),
				wh["name"], RoundState.fmt_relative(int(wh["to_par"]))]))
		if typeof(p.get("stats")) == TYPE_DICTIONARY:
			var r := stat_rows(StatsEngine.lifetime([p["stats"]]))
			v.add_child(_kv_panel("ROUND STATS", (r["play"] as Array) + (r["mode"] as Array).slice(0, 2)))
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
	_ensure_migrated()
	var pg: Dictionary = menu._page("Records")
	var body: VBoxContainer = pg["body"]
	_fill_records(menu, body)
	menu._push(pg["root"])


## Personal bests across a profile's entries; null fields = N/A (no round with reliable shot detail).
static func personal_bests(ents: Array) -> Dictionary:
	var best_round: Variant = null
	var most_birdies := 0
	var fewest_putts: Variant = null
	var longest_carry: Variant = null
	var longest_putt: Variant = null
	for e in ents:
		var p: Dictionary = e["player"]
		if best_round == null or int(p["to_par"]) < int(best_round["to_par"]):
			best_round = {"to_par": int(p["to_par"]), "score": int(p["score"]), "course": String(e["rec"]["course_name"])}
		var st = p.get("stats")
		if typeof(st) != TYPE_DICTIONARY:
			continue
		most_birdies = maxi(most_birdies, int(st.get("birdies_or_better", 0)))
		if String(st.get("level", "")) != "full":
			continue
		if fewest_putts == null or int(st["putts"]) < int(fewest_putts):
			fewest_putts = int(st["putts"])
		var cm = StatsEngine.acc_max(st["approach_carry_yd"])
		if cm != null and (longest_carry == null or float(cm) > float(longest_carry)):
			longest_carry = cm
		var pm = StatsEngine.acc_max(st["putt_total_ft"])
		if pm != null and (longest_putt == null or float(pm) > float(longest_putt)):
			longest_putt = pm
	return {"best_round": best_round, "most_birdies": most_birdies, "fewest_putts": fewest_putts,
		"longest_carry_yd": longest_carry, "longest_putt_ft": longest_putt}


static func _fill_records(menu: MainMenu, body: VBoxContainer) -> void:
	UiKit.clear(body)
	var allrecs := RoundHistory.load_records()
	_profile_bar(body, allrecs, func() -> void: _fill_records(menu, body))
	var pid := current_profile(allrecs)
	var rec := RoundHistory.records(allrecs, pid)
	if int(rec["rounds"]) == 0:
		body.add_child(menu._note("Personal bests for %s appear here after the first finished round." % profile_label(pid)))
		return
	body.add_child(_tiles([["ROUNDS", rec["rounds"]], ["HOLES-IN-ONE", rec["holes_in_one"]], ["BIRDIES+", rec["birdies_or_better"]]]))
	var pb := personal_bests(RoundHistory.entries(allrecs, pid))
	var br = pb["best_round"]
	body.add_child(_kv_panel("PERSONAL BESTS", [
		["Best round", "N/A" if br == null else "%d (%s) · %s" % [br["score"], RoundState.fmt_relative(int(br["to_par"])), br["course"]]],
		["Most birdies in a round", str(pb["most_birdies"])],
		["Fewest putts in a round", "N/A" if pb["fewest_putts"] == null else str(pb["fewest_putts"])],
		["Longest approach carry", StatsEngine.fmt_num(pb["longest_carry_yd"], 1, " yd")],
		["Longest putt travel", StatsEngine.fmt_num(pb["longest_putt_ft"], 1, " ft")]]))
	var bh: Dictionary = rec["best_hole"]
	if not bh.is_empty():
		body.add_child(menu._note("Best hole: %s on %s (%s)" % [bh["name"], bh["course_name"], RoundState.fmt_relative(int(bh["to_par"]))]))
	for c in rec["courses"]:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 16, 12))
		var v := UiKit.vbox(2)
		var t := UiKit.label("%s  ·  course record" % c["course_name"], 26, Color.WHITE)
		t.add_theme_font_override("font", UiKit.font_semi())
		v.add_child(t)
		v.add_child(UiKit.label("BEST %d (%s)  ·  %s" % [int(c["best_score"]), RoundState.fmt_relative(int(c["best_to_par"])), fmt_date(int(c["best_date"]))], 19, UiKit.C_ACCENT))
		v.add_child(UiKit.label("%d rounds  ·  average %s" % [int(c["rounds"]), "%+.1f" % float(c["avg_to_par"])], 19, UiKit.C_MUTED))
		v.add_child(menu._note(String(c["rules_label"])))
		panel.add_child(v)
		body.add_child(panel)

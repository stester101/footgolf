class_name CareerPages
extends RefCounted
## Career Mode screens (design: docs/career/CAREER_UI_DESIGN.md; widgets: CareerKit; home tabs: CareerShell).
## Portrait, scrollable. Presentation only: all rules and state live in CareerManager / TournamentManager. Pages are
## pushed on the MainMenu page stack; the in-round overlays (Save Error, round done) are plain Controls on GameUI.

const TOURNAMENT_ROWS := 25


# ------------------------------------------------------------------ plumbing

static func manager() -> CareerManager:
	if CareerManager.active == null:
		var c := CareerManager.new()
		CareerManager.course_source = func(id: String) -> Dictionary: return CourseSource.load_course(id, App.settings.par_overrides)
		if c.store.exists() and bool(c.load_saved().ok):
			CareerManager.active = c
		else:
			return c  # not stored as active: no career yet (or unreadable)
	return CareerManager.active


static func _nations() -> Array:
	var seen := {}
	for g in CareerManager.load_roster():
		seen[String(g["nationality"])] = true
	var out: Array = seen.keys()
	out.sort()
	return out


static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return ("-" if n < 0 else "") + "£" + out


static func _replace(menu: MainMenu, builder: Callable) -> void:
	menu._pop()
	builder.call()


## Text card (kept for the other Career pages): caption title plus wrapped lines.
static func _card(title: String, lines: Array) -> PanelContainer:
	return CareerKit.info_card(title, lines)


## Option pills (wrap onto several lines): the selected one lime. 96 px tall (48 dp).
static func _choice_buttons(labels: Array, current: int, cb: Callable, id_prefix: String = "career_choice") -> Control:
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", 10)
	box.add_theme_constant_override("v_separation", 10)
	var btns: Array[Button] = []
	var refresh := func(cur: int) -> void:
		for i in btns.size():
			var on := i == cur
			var n: StyleBox = UiKit.skin("lime", 8, 22, 8) if on else CareerKit.flat(Color(0.10, 0.18, 0.32, 0.92), 18, 22.0, Color(0.7, 0.85, 1.0, 0.3), 1)
			CareerKit._btn_styles(btns[i], n, n if on else CareerKit.flat(CareerKit.C_CARD_HOVER, 18, 22.0, Color(0.8, 0.92, 1.0, 0.45), 1), n)
			for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
				btns[i].add_theme_color_override(c, CareerKit.C_LIME_TEXT if on else Color.WHITE)
	for i in labels.size():
		var b := Button.new()
		b.text = String(labels[i])
		b.custom_minimum_size = Vector2(0, CareerKit.TOUCH)
		b.focus_mode = Control.FOCUS_ALL
		b.add_theme_font_size_override("font_size", CareerKit.fs(22))
		b.add_theme_font_override("font", UiKit.font_semi())
		b.set_meta("ui_id", "%s_%d" % [id_prefix, i])
		var idx := i
		b.pressed.connect(func() -> void:
			refresh.call(idx)
			cb.call(idx))
		btns.append(b)
		box.add_child(b)
	refresh.call(current)
	return box


# ------------------------------------------------------------------ entry / create

## Main menu "Career Mode": the hub when a career exists, otherwise Create Career.
static func open_entry(menu: MainMenu) -> void:
	var c := manager()
	if CareerManager.active != null and c.has_career():
		open_hub(menu)
	else:
		open_create(menu, false)


static func open_create(menu: MainMenu, replacing: bool) -> void:
	var pg: Dictionary = CareerKit.page(menu, "New Career", "The LBT awaits", CareerKit.C_MAJOR)
	var body: VBoxContainer = pg["body"]
	var intro := UiKit.vbox(8)
	intro.add_child(CareerKit.caption("Your story starts here", CareerKit.C_MAJOR))
	intro.add_child(CareerKit.text("From world #%d to the LBT Championship" % CareerConfig.START_WORLD_RANK, 32, Color.WHITE, "display", true))
	intro.add_child(CareerKit.text("You start on the LBT with a tour card, no wins and %s. Opponents are simulated golfers; you play every shot yourself with your footballers." % money(CareerConfig.START_BALANCE), 20, CareerKit.C_MUTED, "", true))
	body.add_child(CareerKit.card(intro, CareerKit.glass(Color(0.34, 0.27, 0.10, 0.92), Color(0.08, 0.08, 0.10, 0.96), 22.0, 24.0)))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Golfer name"
	name_edit.max_length = 20
	name_edit.custom_minimum_size = Vector2(0, CareerKit.TOUCH)
	name_edit.add_theme_font_size_override("font_size", CareerKit.fs(28))
	name_edit.add_theme_stylebox_override("normal", CareerKit.flat(Color(0.03, 0.07, 0.14, 0.95), 16, 20.0, Color(0.6, 0.78, 1.0, 0.35), 1))
	name_edit.add_theme_stylebox_override("focus", CareerKit.flat(Color(0.03, 0.07, 0.14, 0.95), 16, 20.0, CareerKit.C_LIME, 2))
	name_edit.set_meta("ui_id", "career_name")
	var nations := _nations()
	var nat := OptionButton.new()
	nat.custom_minimum_size = Vector2(0, CareerKit.TOUCH)
	nat.add_theme_font_size_override("font_size", CareerKit.fs(24))
	for n in nations:
		nat.add_item(String(n))
	var gb := nations.find("England")
	nat.select(maxi(gb, 0))
	var state := {"length": 1}
	var form := UiKit.vbox(12)
	form.add_child(CareerKit.caption("Golfer name"))
	form.add_child(name_edit)
	form.add_child(CareerKit.caption("Nationality"))
	form.add_child(nat)
	form.add_child(CareerKit.caption("Season length"))
	var labels: Array = []
	for l in CareerConfig.SEASON_LENGTHS:
		labels.append("%s · %d events" % [CareerConfig.season_label(l), CareerConfig.total_events(l)])
	form.add_child(_choice_buttons(labels, 1, func(i: int) -> void: state["length"] = i, "career_length"))
	body.add_child(CareerKit.card(form))
	var status := CareerKit.text("", 21, UiKit.C_WARN, "", true)
	var confirm := {"armed": not replacing}
	if replacing:
		body.add_child(CareerKit.info_card("Replacing a career", ["A career already exists. Starting a new one replaces it permanently (export it first in Career Settings)."], UiKit.C_WARN))
	body.add_child(status)
	var go := CareerKit.cta("Start career" if not replacing else "Replace career", "", func() -> void:
		if name_edit.text.strip_edges() == "":
			status.text = "Enter a golfer name."
			return
		if replacing and not bool(confirm["armed"]):
			confirm["armed"] = true
			status.text = "Tap again to permanently replace your existing career."
			return
		var c := CareerManager.new()
		CareerManager.course_source = func(id: String) -> Dictionary: return CourseSource.load_course(id, App.settings.par_overrides)
		if not c.create(name_edit.text, nations[nat.selected], CareerConfig.SEASON_LENGTHS[int(state["length"])]):
			_present_save_error(menu, c.store, func() -> void:
				CareerManager.active = c
				_replace(menu, func() -> void: open_hub(menu)))
			return
		CareerManager.active = c
		_replace(menu, func() -> void: open_hub(menu)), "career_create")
	(pg["footer"] as VBoxContainer).add_child(go)
	menu._push(pg["root"])


# ------------------------------------------------------------------ hub (tabbed shell: see CareerShell)

static func open_hub(menu: MainMenu) -> void:
	CareerShell.open(menu, "hub")


static func _status_text(s: String) -> String:
	return {"setup": "ready to start the round", "in_round": "round in progress (resume)", "between_rounds": "between rounds",
		"complete": "finished", "missed_cut": "missed the cut"}.get(s, s)


# ------------------------------------------------------------------ calendar / event

static func open_calendar(menu: MainMenu) -> void:
	CareerShell.go(menu, "schedule")


static func _tier_skin(col: Color) -> UiSkin:
	var sk := CareerKit.glass(Color(col.r * 0.3 + 0.05, col.g * 0.3 + 0.08, col.b * 0.3 + 0.15, 0.95), Color(0.05, 0.09, 0.18, 0.97), 22.0, 24.0)
	sk.border = Color(col.r, col.g, col.b, 0.6)
	sk.rim = col
	return sk


static func open_event(menu: MainMenu, serial: int) -> void:
	var c := CareerManager.active
	var e := c.event_by_serial(serial)
	var cat := String(e["category"])
	var col := CareerKit.tier_color(cat)
	var pg: Dictionary = CareerKit.page(menu, String(e["name"]), "Event %d · %s" % [serial, CalendarManager.category_label(cat)], col)
	var body: VBoxContainer = pg["body"]
	var info := CourseSource.course_info(String(e["course_id"]))
	var active_here := c.has_active_tournament() and int(c.tournament()["event"]["serial"]) == serial
	var hv := UiKit.vbox(10)
	var hh := UiKit.hbox(10)
	hh.add_child(CareerKit.tier_chip(cat))
	var st := CareerShell.event_status(c, e, c.next_event())
	hh.add_child(CareerKit.trim(CareerKit.text(String(st["text"]).to_upper(), 18, st["color"], "caps", false, HORIZONTAL_ALIGNMENT_RIGHT)))
	hv.add_child(hh)
	hv.add_child(CareerKit.text(String(info.get("name", "")), 30, Color.WHITE, "display", true))
	hv.add_child(CareerKit.text("%d holes per round  ·  %s" % [(info.get("holes", []) as Array).size(), CalendarManager.cut_text(e["cut"])], 19, CareerKit.C_MUTED, "", true))
	var stats := UiKit.hbox(10)
	stats.add_child(CareerKit.stat("Rounds", str(int(e["rounds"])), "", Color.WHITE, 34))
	stats.add_child(CareerKit.stat("Field", str(int(e["field_size"])), "", Color.WHITE, 34))
	stats.add_child(CareerKit.stat("Purse", CareerKit.money_short(int(e["purse"])), "", CareerKit.C_UP, 34))
	stats.add_child(CareerKit.stat("Win pts", str(int((e["points"] as Dictionary)["winner"])), "", col, 34))
	hv.add_child(stats)
	if active_here:
		hv.add_child(CareerKit.text("Course and pars are frozen for this tournament.", 18, CareerKit.C_MUTED, "", true))
	body.add_child(CareerKit.card(hv, _tier_skin(col)))
	var el := c.eligibility(e)
	var frozen: Dictionary = (c.tournament().get("event", {}) as Dictionary).get("eligibility_frozen", {}) if active_here else {}
	var shown: Dictionary = frozen if not frozen.is_empty() else el
	var ok := bool(shown.get("eligible", true))
	var qv := UiKit.vbox(8)
	var qh := UiKit.hbox(10)
	qh.add_child(CareerKit.trim(CareerKit.caption("Qualification")))
	qh.add_child(CareerKit.chip("Eligible" if ok else "Not eligible", CareerKit.C_UP if ok else UiKit.C_WARN))
	qv.add_child(qh)
	qv.add_child(CareerKit.text(String(shown["requirement"]), 20, Color.WHITE, "", true))
	qv.add_child(CareerKit.text(String(shown["reason"]), 20, CareerKit.C_UP if ok else UiKit.C_WARN, "", true))
	if cat == "finale":
		qv.add_child(CareerKit.text("The finale field is the top %d of the Season Standings." % CareerConfig.FINALE_QUALIFIERS, 19, CareerKit.C_MUTED, "", true))
	body.add_child(CareerKit.card(qv))
	var status := String(e["status"])
	if status == "complete" or status == "skipped":
		var r: Dictionary = e["result"]
		var rv := UiKit.vbox(8)
		rv.add_child(CareerKit.caption("Result", CareerKit.C_MAJOR))
		var rh := UiKit.hbox(10)
		rh.add_child(CareerKit.stat("Winner", String(r.get("winner_name", "?")), "%d strokes" % int(r.get("winner_total", 0)), Color.WHITE, 26))
		if bool(r.get("human_played", false)):
			rh.add_child(CareerKit.stat("You", CareerWorldPages.place_text(String(r.get("human_place_label", "")), int(r.get("human_place", 0))), "missed cut" if bool(r.get("human_missed_cut", false)) else money(int(r.get("human_earnings", 0))),
				CareerKit.C_MAJOR if bool(r.get("human_won", false)) else CareerKit.C_LIME, 26))
		rv.add_child(rh)
		if not bool(r.get("human_played", false)):
			rv.add_child(CareerKit.text("You did not play this event.", 19, CareerKit.C_MUTED))
		body.add_child(CareerKit.card(rv))
		if r.has("report"):
			(pg["footer"] as VBoxContainer).add_child(CareerKit.ghost("Tournament report", func() -> void: CareerWorldPages.open_report(menu, e, false), "career_event_report"))
	elif active_here:
		(pg["footer"] as VBoxContainer).add_child(CareerKit.cta("Continue tournament", "", func() -> void: open_tournament(menu), "career_event_continue"))
	elif e == c.next_event() and not c.has_active_tournament():
		var enter := CareerKit.cta("Enter event", "%d rounds · purse %s" % [int(e["rounds"]), CareerKit.money_short(int(e["purse"]))], func() -> void:
			if c.enter_event(serial):
				_replace(menu, func() -> void: open_tournament(menu))
			elif c.store.is_blocked():
				_present_save_error(menu, c.store, Callable())
			, "career_enter")
		enter.disabled = not bool(el["eligible"])
		(pg["footer"] as VBoxContainer).add_child(enter)
		(pg["footer"] as VBoxContainer).add_child(CareerKit.link("Skip event (the world plays it without you)", func() -> void:
			if c.skip_event(serial):
				_replace(menu, func() -> void: open_event(menu, serial))
			elif c.store.is_blocked():
				_present_save_error(menu, c.store, Callable()), "career_skip"))
	else:
		body.add_child(CareerKit.text("Events are played in calendar order.", 19, CareerKit.C_MUTED, "", true))
	var past := _past_winners(c, e)
	body.add_child(CareerKit.info_card("Past winners", [past if past != "" else "None yet."]))
	menu._push(pg["root"])


# ------------------------------------------------------------------ tournament (leaderboard, between rounds, results)

static func open_tournament(menu: MainMenu) -> void:
	var c := CareerManager.active
	var t := c.tournament()
	if t.is_empty():
		return
	var ev: Dictionary = t["event"]
	var cat := String(ev["category"])
	var col := CareerKit.tier_color(cat)
	var pg: Dictionary = CareerKit.page(menu, String(ev["name"]), CalendarManager.category_label(cat), col)
	var body: VBoxContainer = pg["body"]
	var status := String(t["status"])
	var rounds_done := (t["human_rounds"] as Array).size()
	var total := int(ev["rounds"])
	var hv := UiKit.vbox(10)
	var hh := UiKit.hbox(10)
	hh.add_child(CareerKit.tier_chip(cat))
	hh.add_child(CareerKit.trim(CareerKit.text(_status_text(status).to_upper() + ("  ·  MISSED THE CUT" if bool(t.get("human_missed_cut", false)) else ""), 16, CareerKit.C_MUTED, "caps", false, HORIZONTAL_ALIGNMENT_RIGHT)))
	hv.add_child(hh)
	hv.add_child(CareerKit.text("%s  ·  par %d per round" % [(t["snapshot"] as Dictionary)["name"], TournamentManager.par_per_round(t)], 24, Color.WHITE, "semi", true))
	hv.add_child(CareerKit.text(CalendarManager.cut_text(ev["cut"]), 19, CareerKit.C_MUTED, "", true))
	var pips := UiKit.hbox(8)
	for i in total:
		var pv := UiKit.vbox(4)
		pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pv.add_child(CareerKit.progress(1.0 if i < rounds_done else 0.0, col, 10))
		var lbl := "R%d" % (i + 1)
		if i < rounds_done:
			var hr: Dictionary = (t["human_rounds"] as Array)[i]
			lbl += "  %s" % RoundState.fmt_relative(int(hr.get("strokes", 0)) - int(hr.get("par", 0)))
		pv.add_child(CareerKit.text(lbl, 16, Color.WHITE if i < rounds_done else (CareerKit.C_LIME if i == rounds_done else CareerKit.C_FAINT), "caps"))
		pips.add_child(pv)
	hv.add_child(pips)
	body.add_child(CareerKit.card(hv, _tier_skin(col)))
	if rounds_done > 0:
		var lb := UiKit.vbox(2)
		lb.add_child(CareerKit.section("Leaderboard", "To par"))
		lb.add_child(_leaderboard(c, t))
		body.add_child(CareerKit.card(lb))
	else:
		body.add_child(CareerKit.info_card("Before you tee off", ["The leaderboard appears after your first round. The field plays alongside you, simulated."]))
	var footer: VBoxContainer = pg["footer"]
	match status:
		"setup", "between_rounds":
			footer.add_child(CareerKit.cta("Set up round %d" % (int(t["round_index"]) + 1), "", func() -> void: open_round_setup(menu), "career_setup_round"))
		"in_round":
			footer.add_child(CareerKit.cta("Resume round %d" % (int(t["round_index"]) + 1), "", func() -> void: menu.career_round_requested.emit(), "career_resume_round"))
		"complete":
			footer.add_child(CareerKit.cta("Finish and see results", "", func() -> void:
				var res := c.finalize_tournament()
				if res.is_empty() and c.store.is_blocked():
					_present_save_error(menu, c.store, Callable())
					return
				_replace(menu, func() -> void: open_results(menu, res)), "career_finish"))
	menu._push(pg["root"])


static func _leaderboard(c: CareerManager, t: Dictionary) -> Control:
	var rows := c.leaderboard()
	var box := UiKit.vbox(2)
	var shown := 0
	var line_drawn := false
	var cs: Dictionary = t["cut"]
	for r in rows:
		var is_me: bool = r["is_human"]
		if shown >= TOURNAMENT_ROWS and not is_me:
			continue
		if bool(cs["applied"]) and bool(r["cut"]) and not line_drawn:
			line_drawn = true
			box.add_child(CareerKit.line_marker("Cut line %d" % int(cs["line_total"])))
		var rs := " ".join(PackedStringArray((r["rounds"] as Array).map(func(x) -> String: return str(int(x)))))
		box.add_child(CareerKit.rank_row(("T%d" if r["tied"] else "%d") % int(r["place"]), String(r["name"]), RoundState.fmt_relative(int(r["rel"])), 0, is_me, rs, false))
		shown += 1
	return box


## The Tournament Report after finishing an event (winner, your finish, money, ranking movement, rivals).
static func open_results(menu: MainMenu, res: Dictionary) -> void:
	var c := CareerManager.active
	var ev := {}
	for e in c.data["calendar"]:
		if (e["result"] as Dictionary) == res:
			ev = e
	if ev.is_empty():
		ev = {"name": "Event", "category": "regular", "id": "", "result": res}
	CareerWorldPages.open_report(menu, ev, true)


static func _past_winners(c: CareerManager, e: Dictionary) -> String:
	var out: Array = []
	for g in c.data["golfers"]:
		for h in g.get("honours", []):
			if String(h.get("event_id", "")).get_slice("_e", 1) == String(e["id"]).get_slice("_e", 1) and String(h.get("event_id", "")) != String(e["id"]):
				out.append("%s (season %d)" % [g.get("name", "?"), int(h["season"])])
	return ", ".join(PackedStringArray(out))


# ------------------------------------------------------------------ pre-round setup (Round Setup rules, frozen per round)

static func open_round_setup(menu: MainMenu) -> void:
	var c := CareerManager.active
	var t := c.tournament()
	var rc := RoundConfig.from_settings(App.settings)  # defaults; frozen once the round starts
	var ev: Dictionary = t["event"]
	var pg: Dictionary = CareerKit.page(menu, "Round %d Setup" % (int(t["round_index"]) + 1), String(ev["name"]), CareerKit.tier_color(String(ev["category"])))
	var body: VBoxContainer = pg["body"]
	var hv := UiKit.vbox(6)
	hv.add_child(CareerKit.caption("Course"))
	hv.add_child(CareerKit.text(String((t["snapshot"] as Dictionary)["name"]), 28, Color.WHITE, "display", true))
	hv.add_child(CareerKit.text("%d holes  ·  par %d (frozen for this tournament)" % [((t["snapshot"] as Dictionary)["holes"] as Array).size(), TournamentManager.par_per_round(t)], 19, CareerKit.C_MUTED, "", true))
	if c.footballer_rule_on():
		hv.add_child(CareerKit.text("Career rule: each footballer can be used once per season (%d used so far)." % c.season_used_footballers().size(), 19, UiKit.C_CYAN, "", true))
	body.add_child(CareerKit.card(hv))
	var mv := UiKit.vbox(10)
	menu._mulligan_choices(mv)
	mv.add_child(CareerKit.text("Redo the last shot from its result screen. Fixed for this round.", 18, CareerKit.C_MUTED, "", true))
	body.add_child(CareerKit.card(mv))
	var dv := UiKit.vbox(10)
	dv.add_child(CareerKit.caption("Difficulty"))
	menu._difficulty_controls(dv, rc, Callable())
	dv.add_child(CareerKit.text("These values are fixed for the whole round.", 18, CareerKit.C_MUTED, "", true))
	body.add_child(CareerKit.card(dv))
	(pg["footer"] as VBoxContainer).add_child(CareerKit.cta("Start round", "", func() -> void:
		var start := func() -> void: menu.career_round_requested.emit()
		if c.begin_round(rc.to_dict(), MainMenu._last_mulligans):
			start.call()
		elif c.store.is_blocked():
			_present_save_error(menu, c.store, start), "career_start_round"))
	menu._push(pg["root"])


# ------------------------------------------------------------------ settings

static func open_settings(menu: MainMenu) -> void:
	var c := CareerManager.active
	var pg: Dictionary = CareerKit.page(menu, "Career Settings", c.player_name(), CareerKit.C_REGULAR)
	var body: VBoxContainer = pg["body"]
	var meta: Dictionary = c.data["save_metadata"]
	var sv := UiKit.vbox(8)
	var sh := UiKit.hbox(10)
	sh.add_child(CareerKit.trim(CareerKit.caption("Save status")))
	sh.add_child(CareerKit.chip("Save failed" if c.store.is_blocked() else "Saved", UiKit.C_WARN if c.store.is_blocked() else CareerKit.C_UP))
	sv.add_child(sh)
	sv.add_child(CareerKit.text("Career: %s (season %d)" % [c.player_name(), int((c.data["season"] as Dictionary)["number"])], 21, Color.WHITE, "", true))
	sv.add_child(CareerKit.text("Saved after every shot  ·  %s" % (("SAVE FAILED: " + c.store.last_error) if c.store.is_blocked() else "last save OK"), 19, CareerKit.C_MUTED, "", true))
	sv.add_child(CareerKit.text("Created: %s" % Time.get_datetime_string_from_unix_time(int(meta.get("created_at", 0))).replace("T", " "), 19, CareerKit.C_MUTED, "", true))
	body.add_child(CareerKit.card(sv))
	var fv := UiKit.vbox(10)
	fv.add_child(CareerKit.caption("Footballers"))
	fv.add_child(menu._toggle("Each footballer once per season", c.footballer_rule_on(), func(on: bool) -> void:
		c.set_footballer_rule(on)))
	fv.add_child(CareerKit.text("Footballers used in any career round stay used until the next season starts. Mulliganed shots still count.", 18, CareerKit.C_MUTED, "", true))
	body.add_child(CareerKit.card(fv))
	var av := UiKit.vbox(10)
	av.add_child(CareerKit.caption("Rivals' form (opponents only)"))
	var modes := CareerConfig.ADAPTIVE_MODES
	av.add_child(CareerKit.segmented(["Off", "Balanced", "Hard-lock"], maxi(0, modes.find(AdaptiveDifficulty.mode(c.data))), func(i: int) -> void:
		c.set_adaptive_mode(String(modes[i]))
		_replace(menu, func() -> void: open_settings(menu)), "career_adaptive"))
	av.add_child(CareerKit.text("Balanced nudges the opponents' ratings by a few points after each event you play, based on how you did against expectation. Hard-lock keeps rivals permanently tougher. It never changes your shots, physics or footballers. %s." % AdaptiveDifficulty.hint_text(c.data), 18, CareerKit.C_MUTED, "", true))
	body.add_child(CareerKit.card(av))
	var path := "user://exports/career_export.json"
	var status := CareerKit.text("", 20, UiKit.C_WARN, "", true)
	var dv := UiKit.vbox(10)
	dv.add_child(CareerKit.caption("Data"))
	dv.add_child(CareerKit.ghost("Export career", func() -> void:
		status.text = "Exported to %s" % ProjectSettings.globalize_path(path) if c.store.export_to(path) else "Export failed.", "career_export"))
	var imp_armed := {"v": false}
	dv.add_child(CareerKit.ghost("Import career from the export file", func() -> void:
		if not bool(imp_armed["v"]):
			imp_armed["v"] = true
			status.text = "Importing replaces the current career (a backup is kept). Tap again to confirm."
			return
		var r := c.store.import_from(path)
		if bool(r.ok):
			CareerManager.active.data = r.data
			status.text = "Imported. Your previous career was backed up."
		else:
			status.text = "Import refused: %s Your current career is unchanged." % String(r.get("error", "")), "career_import"))
	var reset_armed := {"v": false}
	dv.add_child(CareerKit.ghost("Reset career (deletes everything)", func() -> void:
		if not bool(reset_armed["v"]):
			reset_armed["v"] = true
			status.text = "This permanently deletes the career. Tap again to confirm."
			return
		c.store.delete_career()
		CareerManager.active = null
		while menu._stack.size() > 1:
			menu._pop()
		open_create(menu, false), "career_reset", CareerKit.C_DOWN))
	dv.add_child(status)
	body.add_child(CareerKit.card(dv))
	menu._push(pg["root"])


# ------------------------------------------------------------------ overlays

static func _overlay_base() -> Dictionary:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_meta("keep_hud", true)
	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.06, 0.12, 0.92)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(scrim)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 16)
	m.add_theme_constant_override("margin_top", 90)
	m.add_theme_constant_override("margin_bottom", 40)
	root.add_child(m)
	var col := UiKit.vbox(14)
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	m.add_child(col)
	return {"root": root, "col": col}


## Save Error screen: Retry Save. `on_ok` runs after a successful retry (the overlay closes itself via the
## store's save_recovered handler in CareerRoundRun, or by itself when `on_ok` is given).
static func save_error_overlay(store: CareerSaveManager, on_ok: Callable) -> Control:
	var b := _overlay_base()
	var col: VBoxContainer = b["col"]
	var root: Control = b["root"]
	root.set_meta("save_error", true)
	var v := UiKit.vbox(12)
	v.add_child(CareerKit.caption("Career save", UiKit.C_WARN))
	v.add_child(CareerKit.text(CareerRoundRun.SAVE_ERROR_TEXT, 36, UiKit.C_WARN, "display", true))
	v.add_child(CareerKit.text("Play is paused and shots are blocked until the save succeeds. Your latest progress is kept in memory. Free some storage space or check that the device storage is available, then tap Retry Save.", 22, Color.WHITE, "", true))
	var why := CareerKit.text(store.last_error, 19, CareerKit.C_MUTED, "", true)
	v.add_child(why)
	col.add_child(CareerKit.card(v, CareerKit.striped(Color(0.20, 0.11, 0.05, 0.97), UiKit.C_WARN, 18, 24.0)))
	col.add_child(CareerKit.cta("Retry Save", "", func() -> void:
		if store.retry():
			if on_ok.is_valid():
				on_ok.call()
				root.queue_free()
		else:
			why.text = store.last_error, "career_retry_save"))
	return root


static func round_done_overlay(text: String, sub: String, on_continue: Callable) -> Control:
	var b := _overlay_base()
	var col: VBoxContainer = b["col"]
	var v := UiKit.vbox(10)
	v.add_child(CareerKit.caption("Round complete", CareerKit.C_LIME))
	v.add_child(CareerKit.text(text, 32, Color.WHITE, "display", true))
	if sub != "":
		v.add_child(CareerKit.text(sub, 22, CareerKit.C_MUTED, "", true))
	col.add_child(CareerKit.card(v, CareerKit.glass(Color(0.13, 0.28, 0.52, 0.95), Color(0.05, 0.11, 0.23, 0.97), 22.0, 24.0)))
	col.add_child(CareerKit.cta("Continue", "", on_continue, "career_round_continue"))
	return b["root"]


## Save Error shown on a menu page (create / start round / finish): Retry Save, then `on_ok`.
static func _present_save_error(menu: MainMenu, store: CareerSaveManager, on_ok: Callable) -> void:
	var ov := save_error_overlay(store, func() -> void:
		if on_ok.is_valid():
			on_ok.call())
	menu._present(ov)


## Subtitle of the main-menu "Career Mode" row.
static func menu_subtitle() -> String:
	var c := manager()
	if CareerManager.active != null and c.has_career():
		return "%s · season %d" % [c.player_name(), int((c.data["season"] as Dictionary)["number"])]
	return "Start a new career"

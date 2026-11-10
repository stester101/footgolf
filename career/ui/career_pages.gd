class_name CareerPages
extends RefCounted
## Career Mode screens in the existing glass UI (UiKit), portrait, scrollable. Presentation only: all rules and
## state live in CareerManager / TournamentManager. Pages are built on the MainMenu page stack (menu._page etc.);
## the in-round overlays (Save Error, round done) are plain Controls pushed onto GameUI.

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


static func _card(title: String, lines: Array) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 20, 14))
	var v := UiKit.vbox(4)
	var t := UiKit.label(title, 20, UiKit.C_CYAN)
	t.add_theme_font_override("font", UiKit.font_caps())
	v.add_child(t)
	for l in lines:
		var lab := UiKit.text(String(l), 23, Color.WHITE)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(lab)
	p.add_child(v)
	return p


static func _choice_buttons(labels: Array, current: int, cb: Callable) -> Control:
	var box := HFlowContainer.new()
	box.add_theme_constant_override("h_separation", 10)
	box.add_theme_constant_override("v_separation", 10)
	var btns: Array[Button] = []
	var refresh := func(cur: int) -> void:
		for i in btns.size():
			var on := i == cur
			btns[i].add_theme_stylebox_override("normal", UiKit.skin("lime" if on else "recess", 6, 16, 8))
			btns[i].add_theme_stylebox_override("hover", UiKit.skin("lime" if on else "btn", 6, 16, 8))
			btns[i].add_theme_color_override("font_color", Color("#0E2A07") if on else Color.WHITE)
			btns[i].add_theme_color_override("font_hover_color", Color("#0E2A07") if on else Color.WHITE)
	for i in labels.size():
		var b := Button.new()
		b.text = String(labels[i])
		b.custom_minimum_size = Vector2(0, 66)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 22)
		b.add_theme_font_override("font", UiKit.font_semi())
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
	var pg: Dictionary = menu._page("Create Career")
	var body: VBoxContainer = pg["body"]
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Golfer name"
	name_edit.max_length = 20
	name_edit.custom_minimum_size = Vector2(0, 64)
	name_edit.add_theme_font_size_override("font_size", 26)
	name_edit.set_meta("ui_id", "career_name")
	var nations := _nations()
	var nat := OptionButton.new()
	nat.custom_minimum_size = Vector2(0, 64)
	nat.add_theme_font_size_override("font_size", 24)
	for n in nations:
		nat.add_item(String(n))
	var gb := nations.find("England")
	nat.select(maxi(gb, 0))
	var state := {"length": 1}
	body.add_child(menu._caption("GOLFER NAME"))
	body.add_child(name_edit)
	body.add_child(menu._caption("NATIONALITY"))
	body.add_child(nat)
	body.add_child(menu._caption("SEASON LENGTH"))
	var labels: Array = []
	for l in CareerConfig.SEASON_LENGTHS:
		labels.append("%s · %d events" % [CareerConfig.season_label(l), CareerConfig.total_events(l)])
	body.add_child(_choice_buttons(labels, 1, func(i: int) -> void: state["length"] = i))
	body.add_child(menu._note("You start on the Main Tour with a tour card, ranked %d in the world, with no wins and %s. Opponents are simulated golfers; you play every shot yourself with your footballers." % [CareerConfig.START_WORLD_RANK, money(CareerConfig.START_BALANCE)]))
	var status := UiKit.label("", 22, UiKit.C_WARN)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var confirm := {"armed": not replacing}
	if replacing:
		body.add_child(UiKit.text("A career already exists. Starting a new one replaces it permanently (export it first in Career Settings).", 21, UiKit.C_WARN))
	body.add_child(status)
	var go: Button = menu._primary_button("Start career" if not replacing else "Replace career", func() -> void:
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


# ------------------------------------------------------------------ hub

static func open_hub(menu: MainMenu) -> void:
	var c := CareerManager.active
	var pg: Dictionary = menu._page("Career Hub")
	var body: VBoxContainer = pg["body"]
	var p: Dictionary = c.data["player"]
	var eco: Dictionary = c.data["economy"]
	var sr := c.season_rank()
	body.add_child(_card(String(p["name"]).to_upper(), [
		"%s  ·  Season %d (%s)" % [p["nationality"], int((c.data["season"] as Dictionary)["number"]), CareerConfig.season_label(String((c.data["season"] as Dictionary)["length"]))],
		"World ranking: %d (of %d)" % [c.world_rank(), c.world_table().size()],
		"Season standing: %s  ·  %d pts" % [(QualificationManager._ord(sr)) if sr > 0 else "no results yet", c.season_points()],
		"Earnings: %s this season  ·  %s career" % [money(int(eco["season_earnings"])), money(int(eco["career_earnings"]))],
	]))
	# next event / active tournament
	if c.has_active_tournament():
		var t := c.tournament()
		var ev: Dictionary = t["event"]
		body.add_child(_card("TOURNAMENT IN PROGRESS", ["%s  (%s)" % [ev["name"], CalendarManager.category_label(String(ev["category"]))],
			"Round %d of %d  ·  %s" % [mini(int(t["round_index"]) + 1, int(ev["rounds"])), int(ev["rounds"]), _status_text(String(t["status"]))]]))
		body.add_child(menu._primary_button("Continue tournament", func() -> void: open_tournament(menu), "career_continue"))
	else:
		var e := c.next_event()
		if e.is_empty():
			body.add_child(_card("SEASON COMPLETE", ["All events are done. Golfers age, some retire and new ones arrive when the next season starts (the full off-season is a later phase)."]))
			body.add_child(menu._primary_button("Start next season", func() -> void:
				if c.start_next_season():
					_replace(menu, func() -> void: open_hub(menu))
				else:
					_present_save_error(menu, c.store, Callable()), "career_next_season"))
		else:
			var el := c.eligibility(e)
			body.add_child(_card("NEXT EVENT", ["%s  (%s)" % [e["name"], CalendarManager.category_label(String(e["category"]))],
				"%s  ·  %d rounds  ·  purse %s" % [CourseSource.course_info(String(e["course_id"])).get("name", e["course_id"]), int(e["rounds"]), money(int(e["purse"]))],
				String(el["reason"])]))
			body.add_child(menu._primary_button("View event", func() -> void: open_event(menu, int(e["serial"])), "career_next_event"))
	body.add_child(CareerWorldPages.ledger_card(c))
	body.add_child(CareerWorldPages.rivals_card(c))
	body.add_child(menu._nav_row("course", "Calendar", "%d events this season" % (c.data["calendar"] as Array).size(), func() -> void: open_calendar(menu), "career_calendar"))
	body.add_child(menu._nav_row("bars", "World Ranking", "You are %d" % c.world_rank(), func() -> void: CareerWorldPages.open_world_ranking(menu), "career_world_ranking"))
	body.add_child(menu._nav_row("list", "Season Standings", "Top %d reach the finale" % CareerConfig.FINALE_QUALIFIERS, func() -> void: CareerWorldPages.open_standings(menu), "career_standings"))
	body.add_child(menu._nav_row("people", "Rivals", "Head-to-head records", func() -> void: CareerWorldPages.open_rivals(menu), "career_rivals"))
	body.add_child(menu._nav_row("star", "Trophy Cabinet", "%d trophies" % (c.data["trophies"] as Array).size(), func() -> void: CareerWorldPages.open_trophies(menu), "career_trophies"))
	CareerSponsorPages.hub_refresh(c)
	body.add_child(menu._nav_row("trophy", "Sponsors", CareerSponsorPages.hub_subtitle(c), func() -> void: CareerSponsorPages.open_sponsor_review(menu), "career_sponsors"))
	body.add_child(menu._nav_row("flag", "Shop", CareerShopPages.hub_subtitle(c), func() -> void: CareerShopPages.open_shop(menu), "career_shop"))
	body.add_child(menu._nav_row("gear", "Career Settings", "Footballer rule, export, import, reset", func() -> void: open_settings(menu), "career_settings"))
	body.add_child(menu._note("The full off-season arrives in a later phase."))
	if c.store.is_blocked():
		body.add_child(UiKit.text("Last save failed: " + c.store.last_error, 21, UiKit.C_WARN))
		body.add_child(menu._secondary_button("Retry Save", func() -> void:
			if c.store.retry():
				_replace(menu, func() -> void: open_hub(menu)), "career_retry"))
	menu._push(pg["root"])


static func _status_text(s: String) -> String:
	return {"setup": "ready to start the round", "in_round": "round in progress (resume)", "between_rounds": "between rounds",
		"complete": "finished", "missed_cut": "missed the cut"}.get(s, s)


# ------------------------------------------------------------------ calendar / event

static func open_calendar(menu: MainMenu) -> void:
	var c := CareerManager.active
	var pg: Dictionary = menu._page("Calendar")
	var body: VBoxContainer = pg["body"]
	var nxt := c.next_event()
	var ctx := c.qual_ctx()
	for e in c.data["calendar"]:
		var status := String(e["status"])
		var sub := ""
		match status:
			"complete":
				var r: Dictionary = e["result"]
				sub = "Played: %s · %s" % [("won" if bool(r.get("human_won", false)) else "T/P%d" % int(r.get("human_place", 0))), money(int(r.get("human_earnings", 0)))]
			"skipped":
				sub = "Skipped · won by %s" % String((e["result"] as Dictionary).get("winner_name", "?"))
			"in_progress":
				sub = "In progress"
			_:
				var el := c.eligibility(e, ctx)
				sub = ("NEXT · " if e == nxt else "") + ("Eligible" if bool(el["eligible"]) else "Not eligible")
		var title := "%d. %s" % [int(e["serial"]), e["name"]]
		body.add_child(menu._nav_row("flag" if String(e["category"]) != "regular" else "course", title,
			"%s · %s · %d rounds · %s" % [CalendarManager.category_label(String(e["category"])), CourseSource.course_info(String(e["course_id"])).get("name", ""), int(e["rounds"]), sub],
			func() -> void: open_event(menu, int(e["serial"])), "career_event_%d" % int(e["serial"])))
	menu._push(pg["root"])


static func open_event(menu: MainMenu, serial: int) -> void:
	var c := CareerManager.active
	var e := c.event_by_serial(serial)
	var pg: Dictionary = menu._page(String(e["name"]))
	var body: VBoxContainer = pg["body"]
	var info := CourseSource.course_info(String(e["course_id"]))
	var snap_note := ""
	if c.has_active_tournament() and int(c.tournament()["event"]["serial"]) == serial:
		snap_note = "Course and pars are frozen for this tournament."
	body.add_child(_card(CalendarManager.category_label(String(e["category"])).to_upper(), [
		"Course: %s (%d holes per round)" % [info.get("name", ""), (info.get("holes", []) as Array).size()],
		"Rounds: %d  ·  %s" % [int(e["rounds"]), CalendarManager.cut_text(e["cut"])],
		"Field: %d players  ·  purse %s" % [int(e["field_size"]), money(int(e["purse"]))],
		"Winner earns %d season points" % int((e["points"] as Dictionary)["winner"]),
		snap_note]))
	var el := c.eligibility(e)
	var frozen: Dictionary = (c.tournament().get("event", {}) as Dictionary).get("eligibility_frozen", {}) if snap_note != "" else {}
	var shown: Dictionary = frozen if not frozen.is_empty() else el
	var qlines: Array = [String(shown["requirement"]), String(shown["reason"])]
	if String(e["category"]) == "finale":
		qlines.append("The finale field is the top %d of the Season Standings." % CareerConfig.FINALE_QUALIFIERS)
	body.add_child(_card("QUALIFICATION", qlines))
	var past := _past_winners(c, e)
	body.add_child(menu._note("Past winners: %s" % (past if past != "" else "none yet.")))
	var status := String(e["status"])
	if status == "complete" or status == "skipped":
		var r: Dictionary = e["result"]
		body.add_child(_card("RESULT", ["Winner: %s (%d)" % [r.get("winner_name", "?"), int(r.get("winner_total", 0))],
			("Your finish: %s%s · %s" % [r.get("human_place_label", str(int(r.get("human_place", 0)))), " (missed cut)" if bool(r.get("human_missed_cut", false)) else "", money(int(r.get("human_earnings", 0)))]) if bool(r.get("human_played", false)) else "You did not play this event."]))
		if r.has("report"):
			(pg["footer"] as VBoxContainer).add_child(menu._secondary_button("Tournament report", func() -> void: CareerWorldPages.open_report(menu, e, false), "career_event_report"))
	elif c.has_active_tournament() and int(c.tournament()["event"]["serial"]) == serial:
		(pg["footer"] as VBoxContainer).add_child(menu._primary_button("Continue tournament", func() -> void: open_tournament(menu), "career_event_continue"))
	elif e == c.next_event() and not c.has_active_tournament():
		var enter: Button = menu._primary_button("Enter event", func() -> void:
			if c.enter_event(serial):
				_replace(menu, func() -> void: open_tournament(menu))
			elif c.store.is_blocked():
				_present_save_error(menu, c.store, Callable())
			, "career_enter")
		enter.disabled = not bool(el["eligible"])
		(pg["footer"] as VBoxContainer).add_child(enter)
		(pg["footer"] as VBoxContainer).add_child(menu._secondary_button("Skip event (the world plays on without you)", func() -> void:
			if c.skip_event(serial):
				_replace(menu, func() -> void: open_event(menu, serial))
			elif c.store.is_blocked():
				_present_save_error(menu, c.store, Callable()), "career_skip"))
	else:
		body.add_child(menu._note("Events are played in calendar order."))
	menu._push(pg["root"])


# ------------------------------------------------------------------ tournament (leaderboard, between rounds, results)

static func open_tournament(menu: MainMenu) -> void:
	var c := CareerManager.active
	var t := c.tournament()
	if t.is_empty():
		return
	var ev: Dictionary = t["event"]
	var pg: Dictionary = menu._page(String(ev["name"]))
	var body: VBoxContainer = pg["body"]
	var status := String(t["status"])
	var rounds_done := (t["human_rounds"] as Array).size()
	body.add_child(_card(CalendarManager.category_label(String(ev["category"])).to_upper(), [
		"%s  ·  par %d per round" % [(t["snapshot"] as Dictionary)["name"], TournamentManager.par_per_round(t)],
		"%s" % CalendarManager.cut_text(ev["cut"]),
		"Rounds played: %d of %d" % [rounds_done, int(ev["rounds"])],
		"Status: %s" % _status_text(status) + ("  (missed the cut)" if bool(t.get("human_missed_cut", false)) else "")]))
	if rounds_done > 0:
		body.add_child(menu._caption("LEADERBOARD"))
		body.add_child(_leaderboard(c, t))
	var footer: VBoxContainer = pg["footer"]
	match status:
		"setup", "between_rounds":
			footer.add_child(menu._primary_button("Set up round %d" % (int(t["round_index"]) + 1), func() -> void: open_round_setup(menu), "career_setup_round"))
		"in_round":
			footer.add_child(menu._primary_button("Resume round %d" % (int(t["round_index"]) + 1), func() -> void: menu.career_round_requested.emit(), "career_resume_round"))
		"complete":
			footer.add_child(menu._primary_button("Finish and see results", func() -> void:
				var res := c.finalize_tournament()
				if res.is_empty() and c.store.is_blocked():
					_present_save_error(menu, c.store, Callable())
					return
				_replace(menu, func() -> void: open_results(menu, res)), "career_finish"))
	menu._push(pg["root"])


static func _leaderboard(c: CareerManager, t: Dictionary) -> Control:
	var rows := c.leaderboard()
	var box := UiKit.vbox(4)
	var shown := 0
	var line_drawn := false
	var cs: Dictionary = t["cut"]
	for r in rows:
		var is_me: bool = r["is_human"]
		if shown >= TOURNAMENT_ROWS and not is_me:
			continue
		if bool(cs["applied"]) and bool(r["cut"]) and not line_drawn:
			line_drawn = true
			box.add_child(UiKit.label("— cut line (%d) —" % int(cs["line_total"]), 19, UiKit.C_WARN, HORIZONTAL_ALIGNMENT_CENTER))
		var h := UiKit.hbox(8)
		var col := UiKit.C_ACCENT if is_me else Color.WHITE
		var pl := UiKit.label(("T%d" if r["tied"] else "%d") % int(r["place"]), 22, col)
		pl.custom_minimum_size.x = 56
		h.add_child(pl)
		var nm := UiKit.label(String(r["name"]), 22, col)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(nm)
		var rs := UiKit.label(" ".join(PackedStringArray((r["rounds"] as Array).map(func(x) -> String: return str(int(x))))), 20, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		h.add_child(rs)
		var tot := UiKit.label(RoundState.fmt_relative(int(r["rel"])), 22, col, HORIZONTAL_ALIGNMENT_RIGHT)
		tot.custom_minimum_size.x = 64
		h.add_child(tot)
		box.add_child(h)
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
	var rc := RoundConfig.from_settings(App.settings)  # defaults (hole 12 in unless Settings says otherwise); frozen once the round starts
	var pg: Dictionary = menu._page("Round %d Setup" % (int(t["round_index"]) + 1))
	var body: VBoxContainer = pg["body"]
	body.add_child(_card(String((t["snapshot"] as Dictionary)["name"]).to_upper(), [
		"%d holes · par %d (frozen for this tournament)" % [((t["snapshot"] as Dictionary)["holes"] as Array).size(), TournamentManager.par_per_round(t)]]))
	if c.footballer_rule_on():
		body.add_child(UiKit.text("Career rule: each footballer can be used once per season (%d used so far)." % c.season_used_footballers().size(), 21, UiKit.C_CYAN))
	menu._mulligan_choices(body)
	body.add_child(menu._note("Redo the last shot from its result screen. Fixed for this round."))
	body.add_child(menu._caption("DIFFICULTY"))
	menu._difficulty_controls(body, rc, Callable())
	body.add_child(menu._note("These values are fixed for the whole round."))
	(pg["footer"] as VBoxContainer).add_child(menu._primary_button("Start round", func() -> void:
		var start := func() -> void: menu.career_round_requested.emit()
		if c.begin_round(rc.to_dict(), MainMenu._last_mulligans):
			start.call()
		elif c.store.is_blocked():
			_present_save_error(menu, c.store, start), "career_start_round"))
	menu._push(pg["root"])


# ------------------------------------------------------------------ settings

static func open_settings(menu: MainMenu) -> void:
	var c := CareerManager.active
	var pg: Dictionary = menu._page("Career Settings")
	var body: VBoxContainer = pg["body"]
	var meta: Dictionary = c.data["save_metadata"]
	body.add_child(_card("SAVE STATUS", [
		"Career: %s (season %d)" % [c.player_name(), int((c.data["season"] as Dictionary)["number"])],
		"Saved after every shot · %s" % ("SAVE FAILED: " + c.store.last_error if c.store.is_blocked() else "last save OK"),
		"Created: %s" % Time.get_datetime_string_from_unix_time(int(meta.get("created_at", 0))).replace("T", " ")]))
	body.add_child(menu._toggle("Each footballer once per season (career rule)", c.footballer_rule_on(), func(on: bool) -> void:
		c.set_footballer_rule(on)))
	body.add_child(menu._note("Footballers used in any career round stay used until the next season starts. Mulliganed shots still count."))
	var path := "user://exports/career_export.json"
	var status := UiKit.label("", 21, UiKit.C_WARN)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(menu._secondary_button("Export career", func() -> void:
		status.text = "Exported to %s" % ProjectSettings.globalize_path(path) if c.store.export_to(path) else "Export failed.", "career_export"))
	var imp_armed := {"v": false}
	body.add_child(menu._secondary_button("Import career from the export file", func() -> void:
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
	body.add_child(menu._secondary_button("Reset career (deletes everything)", func() -> void:
		if not bool(reset_armed["v"]):
			reset_armed["v"] = true
			status.text = "This permanently deletes the career. Tap again to confirm."
			return
		c.store.delete_career()
		CareerManager.active = null
		menu._pop()
		menu._pop()
		open_create(menu, false), "career_reset"))
	body.add_child(status)
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
	var t := UiKit.label(CareerRoundRun.SAVE_ERROR_TEXT, 40, UiKit.C_WARN)
	t.add_theme_font_override("font", UiKit.font_semi())
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(t)
	col.add_child(UiKit.text("Play is paused and shots are blocked until the save succeeds. Your latest progress is kept in memory. Free some storage space or check that the device storage is available, then tap Retry Save.", 24, Color.WHITE))
	var why := UiKit.label(store.last_error, 20, UiKit.C_MUTED)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(why)
	var btn := UiKit.button("Retry Save", func() -> void:
		if store.retry():
			if on_ok.is_valid():
				on_ok.call()
				root.queue_free()
		else:
			why.text = store.last_error, 88, 32)
	UiKit.primary(btn)
	btn.set_meta("ui_id", "career_retry_save")
	col.add_child(btn)
	return root


static func round_done_overlay(text: String, sub: String, on_continue: Callable) -> Control:
	var b := _overlay_base()
	var col: VBoxContainer = b["col"]
	var t := UiKit.label("Round complete", 40, Color.WHITE)
	t.add_theme_font_override("font", UiKit.font_semi())
	col.add_child(t)
	col.add_child(UiKit.text(text, 30, UiKit.C_ACCENT))
	if sub != "":
		col.add_child(UiKit.text(sub, 24, Color.WHITE))
	var btn := UiKit.button("Continue", on_continue, 88, 32)
	UiKit.primary(btn)
	btn.set_meta("ui_id", "career_round_continue")
	col.add_child(btn)
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

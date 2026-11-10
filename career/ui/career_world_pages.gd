class_name CareerWorldPages
extends RefCounted
## Career screens about the wider world and your record (Appendix A screens 10-11 and the step-5 extras):
## World Ranking, Season Standings, Tournament Report, Trophy Cabinet, Rivals and the ledger card. Presentation
## only: every number is read from CareerManager / the stored event results. Same glass style as CareerPages.

const PAGE_STEP := 30


# ------------------------------------------------------------------ shared bits

static func _h(text: String, size: int, color: Color, width: float = 0.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(text, size, color, align)
	if width > 0.0:
		l.custom_minimum_size.x = width
	return l


static func _line(left: String, mid: String, right: String, color: Color, sub: String = "", highlight: bool = false) -> Control:
	var h := UiKit.hbox(8)
	h.add_child(_h(left, 22, color, 58))
	var nm := UiKit.label(mid, 22, color)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	h.add_child(nm)
	if sub != "":
		h.add_child(_h(sub, 19, UiKit.C_MUTED, 0.0, HORIZONTAL_ALIGNMENT_RIGHT))
	h.add_child(_h(right, 22, color, 86, HORIZONTAL_ALIGNMENT_RIGHT))
	if not highlight:
		return h
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(Color(0.35, 0.8, 0.3, 0.22), 6, 6))
	p.add_child(h)
	return p


static func _divider(text: String) -> Control:
	return UiKit.label("— %s —" % text, 18, UiKit.C_WARN, HORIZONTAL_ALIGNMENT_CENTER)


static func _delta(d: int) -> String:
	if d > 0:
		return "up %d" % d
	if d < 0:
		return "down %d" % -d
	return "no change"


static func _ord(n: int) -> String:
	return QualificationManager._ord(n)


static func _home(menu: MainMenu) -> Control:
	return menu._primary_button("Back to Career Hub", func() -> void:
		while menu._stack.size() > 1:
			menu._pop()
		CareerPages.open_hub(menu), "career_back_hub")


# ------------------------------------------------------------------ rankings (World Ranking / Season Standings)

## Shared list page. rows = table rows (rank, name, is_human, ...); value_of(row) -> String; sub_of(row) -> String;
## lines = [{after_rank:int, text:String}] divider labels drawn after that rank.
static func _ranking_page(menu: MainMenu, title: String, header: Control, rows: Array, value_of: Callable, sub_of: Callable, lines: Array, ui_prefix: String) -> void:
	var pg: Dictionary = menu._page(title)
	var body: VBoxContainer = pg["body"]
	body.add_child(header)
	var state := {"limit": PAGE_STEP, "query": ""}
	var search := LineEdit.new()
	search.placeholder_text = "Search a golfer"
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(0, 60)
	search.add_theme_font_size_override("font_size", 24)
	search.set_meta("ui_id", ui_prefix + "_search")
	body.add_child(search)
	var list := UiKit.vbox(4)
	body.add_child(list)
	var me_idx := 0
	for i in rows.size():
		if bool(rows[i]["is_human"]):
			me_idx = i
	var rebuild := Callable()
	var add_row := func(i: int) -> void:
		var r: Dictionary = rows[i]
		list.add_child(_line(str(int(r["rank"])), String(r["name"]), String(value_of.call(r)), UiKit.C_ACCENT if bool(r["is_human"]) else Color.WHITE,
			String(sub_of.call(r)), bool(r["is_human"])))
		for ln in lines:
			if int(ln["after_rank"]) == int(r["rank"]):
				list.add_child(_divider(String(ln["text"])))
	rebuild = func() -> void:
		UiKit.clear(list)
		var q := String(state["query"]).strip_edges().to_lower()
		if q != "":
			var shown := 0
			for i in rows.size():
				if String(rows[i]["name"]).to_lower().contains(q):
					add_row.call(i)
					shown += 1
					if shown >= 40:
						break
			if shown == 0:
				list.add_child(UiKit.text("No golfer matches.", 22, UiKit.C_MUTED))
			return
		var limit := mini(int(state["limit"]), rows.size())
		for i in limit:
			add_row.call(i)
		if me_idx >= limit:
			list.add_child(UiKit.label("…", 22, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
			for i in range(maxi(limit, me_idx - 3), mini(rows.size(), me_idx + 4)):
				add_row.call(i)
		if limit < rows.size():
			var more: Button = menu._secondary_button("Show %d more" % mini(PAGE_STEP, rows.size() - limit), func() -> void:
				state["limit"] = int(state["limit"]) + PAGE_STEP
				rebuild.call(), ui_prefix + "_more")
			list.add_child(more)
	search.text_changed.connect(func(t: String) -> void:
		state["query"] = t
		rebuild.call())
	rebuild.call()
	menu._push(pg["root"])


static func open_world_ranking(menu: MainMenu) -> void:
	var c := CareerManager.active
	var rows := c.world_table()
	var me: Dictionary = {}
	for r in rows:
		if bool(r["is_human"]):
			me = r
	var res_last := _last_result(c)
	var lines: Array = [
		{"after_rank": CareerConfig.MAJOR_MAX_WORLD_RANK, "text": "majors: top %d" % CareerConfig.MAJOR_MAX_WORLD_RANK},
		{"after_rank": CareerConfig.FLAGSHIP_MAX_WORLD_RANK, "text": "flagships: top %d" % CareerConfig.FLAGSHIP_MAX_WORLD_RANK},
	]
	var head := CareerPages._card("YOUR WORLD RANKING", [
		"Rank %d of %d  ·  %d points" % [int(me.get("rank", 0)), rows.size(), int(round(float(me.get("points", 0.0))))],
		("Last event: %s -> %d (%s)" % [("%d" % int(res_last["world_rank_before"])), int(res_last["world_rank_after"]),
			_delta(int(res_last["world_rank_before"]) - int(res_last["world_rank_after"]))]) if not res_last.is_empty() else "No events played yet.",
		"Points from this season count in full, last season at half (two-season window)."])
	_ranking_page(menu, "World Ranking", head, rows,
		func(r: Dictionary) -> String: return str(int(round(float(r["points"])))),
		func(r: Dictionary) -> String: return "",
		lines, "career_wr")


static func open_standings(menu: MainMenu) -> void:
	var c := CareerManager.active
	var rows := c.standings_table()
	var me: Dictionary = {}
	for r in rows:
		if bool(r["is_human"]):
			me = r
	var started := not (c.standings()["applied"] as Dictionary).is_empty()
	var lines: Array = [
		{"after_rank": CareerConfig.FINALE_QUALIFIERS, "text": "finale line: top %d qualify for the Tour Championship" % CareerConfig.FINALE_QUALIFIERS},
		{"after_rank": CareerConfig.TOUR_CARD_RETENTION_RANK, "text": "tour card line: top %d keep their card" % CareerConfig.TOUR_CARD_RETENTION_RANK},
	]
	var status := "Not ranked until the season has results." if not started else \
		("You are %s: %s the finale line." % [_ord(int(me.get("rank", 0))), "inside" if int(me.get("rank", 0)) <= CareerConfig.FINALE_QUALIFIERS else "outside"])
	var head := CareerPages._card("SEASON STANDINGS", [
		"Season %d  ·  %d points  ·  %d wins  ·  %d starts" % [c.season_number(), int(round(float(me.get("points", 0.0)))), int(me.get("wins", 0)), int(me.get("starts", 0))],
		status,
		"The Tour Championship does not add season points. Tour card retention is a later phase."])
	_ranking_page(menu, "Season Standings", head, rows,
		func(r: Dictionary) -> String: return str(int(round(float(r["points"])))),
		func(r: Dictionary) -> String: return ("%dW" % int(r["wins"])) if int(r["wins"]) > 0 else "",
		lines, "career_ss")


static func _last_result(c: CareerManager) -> Dictionary:
	var last := {}
	for e in c.data["calendar"]:
		var r: Dictionary = e["result"]
		if String(e["status"]) in ["complete", "skipped"] and r.has("world_rank_after"):
			last = r
	return last


# ------------------------------------------------------------------ tournament report

## Winner, your finish, money (ledger), ranking movement, the leaderboard top and your rivals' results.
static func open_report(menu: MainMenu, ev: Dictionary, back_to_hub: bool) -> void:
	var c := CareerManager.active
	var res: Dictionary = ev["result"]
	var pg: Dictionary = menu._page("Tournament Report")
	var body: VBoxContainer = pg["body"]
	var winner_lines := ["%s  (%d strokes, %s)" % [res.get("winner_name", "?"), int(res.get("winner_total", 0)), RoundState.fmt_relative(int(res.get("winner_to_par", 0)))],
		"%s  ·  %s" % [ev["name"], CalendarManager.category_label(String(ev["category"]))]]
	var po: Dictionary = res.get("playoff", {})
	if bool(po.get("needed", false)):
		winner_lines.append("Decided by a sudden-death playoff.")
	body.add_child(CareerPages._card("WINNER", winner_lines))
	if bool(res.get("human_played", false)):
		var lines: Array = []
		if bool(res.get("human_won", false)):
			lines.append("You won the tournament!")
		lines.append("Finish: %s%s  ·  %d strokes (%s)" % [res.get("human_place_label", str(int(res["human_place"]))),
			"  (missed the cut)" if bool(res.get("human_missed_cut", false)) else "", int(res["human_total"]), RoundState.fmt_relative(int(res["human_rel"]))])
		lines.append("Rounds: %s" % ", ".join(PackedStringArray((res.get("rounds", []) as Array).map(func(x) -> String: return str(int(x))))))
		lines.append("Season points: %d  ·  World points: %d" % [int(res["human_points"]), int(round(float(res.get("human_world_points", 0.0))))])
		body.add_child(CareerPages._card("YOUR RESULT", lines))
	else:
		body.add_child(CareerPages._card("YOUR RESULT", ["You did not play this event."]))
	# money (ledger)
	var money_lines: Array = []
	for t in CareerRecords.ledger_for_event(c.data, String(ev["id"])):
		money_lines.append("%s  %s" % [CareerPages.money(int(t["amount"])), t["label"]])
	if money_lines.is_empty():
		money_lines.append("No prize money from this event.")
	money_lines.append("Balance: %s  ·  this season %s" % [CareerPages.money(int((c.data["economy"] as Dictionary)["balance"])), CareerPages.money(int((c.data["economy"] as Dictionary)["season_earnings"]))])
	body.add_child(CareerPages._card("MONEY", money_lines))
	# ranking movement
	var mv := ["World Ranking: %d -> %d (%s)" % [int(res.get("world_rank_before", 0)), int(res.get("world_rank_after", 0)), _delta(int(res.get("world_rank_before", 0)) - int(res.get("world_rank_after", 0)))]]
	var sb := int(res.get("season_rank_before", 0))
	var sa := int(res.get("season_rank_after", 0))
	mv.append("Season Standings: %s -> %s (%s)" % [_ord(sb), _ord(sa), _delta(sb - sa)])
	for m in res.get("movers", []):
		mv.append("Biggest climber: %s up %d to %d" % [m["name"], int(m["delta"]), int(m["rank"])])
		break
	body.add_child(CareerPages._card("RANKING MOVEMENT", mv))
	# rivals
	var rivals: Array = res.get("rivals", [])
	if not rivals.is_empty():
		var rl: Array = []
		for r in rivals:
			var who := "finished ahead of you" if int(r["rival_ahead"]) > 0 else ("finished behind you" if int(r["rival_ahead"]) < 0 else "tied with you")
			rl.append("%s: %s (%s), %s" % [r["name"], r["pos"], RoundState.fmt_relative(int(r["to_par"])), who])
		body.add_child(CareerPages._card("YOUR RIVALS", rl))
	# leaderboard
	body.add_child(menu._caption("LEADERBOARD (TOP %d, YOU AND YOUR RIVALS)" % CareerConfig.REPORT_TOP_ROWS))
	var box := UiKit.vbox(4)
	var cut_drawn := false
	var cut: Dictionary = res.get("cut", {})
	for r in res.get("report", []):
		if String(r["status"]) == "cut" and not cut_drawn and not cut.is_empty():
			cut_drawn = true
			box.add_child(_divider("cut line %d" % int(cut.get("line_total", 0))))
		var me := bool(r["is_human"])
		var rounds := " ".join(PackedStringArray((r["rounds"] as Array).map(func(x) -> String: return str(int(x)))))
		box.add_child(_line(String(r["pos"]), String(r["name"]), RoundState.fmt_relative(int(r["to_par"])), UiKit.C_ACCENT if me else Color.WHITE, rounds, me))
	body.add_child(box)
	if back_to_hub:
		(pg["footer"] as VBoxContainer).add_child(menu._primary_button("Back to Career Hub", func() -> void:
			while menu._stack.size() > 1:
				menu._pop()
			CareerPages.open_hub(menu), "career_results_done"))
	menu._push(pg["root"])


# ------------------------------------------------------------------ trophy cabinet

static func open_trophies(menu: MainMenu) -> void:
	var c := CareerManager.active
	var rec: Dictionary = c.data["records"]
	var pg: Dictionary = menu._page("Trophy Cabinet")
	var body: VBoxContainer = pg["body"]
	var best: Dictionary = rec["best_finish"]
	var cheque: Dictionary = rec["biggest_cheque"]
	body.add_child(CareerPages._card("CAREER RECORDS", [
		"Wins: %d  ·  Majors: %d" % [int(rec["wins"]), int(rec["majors"])],
		"Starts: %d  ·  Cuts made: %d  ·  Top 10s: %d" % [int(rec["starts"]), int(rec["cuts_made"]), int(rec["top10s"])],
		("Best finish: %s at %s (season %d)" % [_ord(int(best["place"])), best["event"], int(best["season"])]) if not best.is_empty() else "Best finish: none yet",
		("Best world ranking: %d" % int(rec["best_world_rank"])) if int(rec["best_world_rank"]) > 0 else "Best world ranking: none yet",
		("Biggest cheque: %s (%s)" % [CareerPages.money(int(cheque["amount"])), cheque["event"]]) if not cheque.is_empty() else "Biggest cheque: none yet",
		"Career earnings: %s" % CareerPages.money(int((c.data["economy"] as Dictionary)["career_earnings"]))]))
	var groups := [["major", "MAJOR CHAMPIONSHIPS"], ["tour_championship", "TOUR CHAMPIONSHIPS"], ["season_title", "SEASON TITLES"],
		["flagship", "FLAGSHIP WINS"], ["event_win", "TOUR EVENT WINS"]]
	var any := false
	for g in groups:
		var list := CareerRecords.trophies_of(c.data, String(g[0]))
		if list.is_empty():
			continue
		any = true
		var lines: Array = []
		for t in list:
			lines.append("%s  (season %d)" % [t["name"], int(t["season"])])
		body.add_child(CareerPages._card("%s  ·  %d" % [g[1], list.size()], lines))
	if not any:
		body.add_child(menu._note("The cabinet is empty. Win a tournament, a major or the Tour Championship, or finish a season top of the Season Standings, to fill it."))
	menu._push(pg["root"])


# ------------------------------------------------------------------ rivals

static func open_rivals(menu: MainMenu) -> void:
	var c := CareerManager.active
	var pg: Dictionary = menu._page("Rivals")
	var body: VBoxContainer = pg["body"]
	var list: Array = c.data["rivalries"]
	if list.is_empty():
		body.add_child(menu._note("No rivals yet. A golfer becomes a rival after you finish within %d strokes of each other in %d events." % [CareerConfig.RIVAL_CLOSE_STROKES, CareerConfig.RIVAL_MIN_CLOSE]))
	var by := c.golfers_by_id()
	var rank_of := RankingManager.rank_map(c.world_table())
	for i in list.size():
		var r: Dictionary = list[i]
		var g: Dictionary = by.get(String(r["id"]), {})
		body.add_child(CareerPages._card(("%s%s" % [String(r["name"]).to_upper(), "  ·  FEATURED" if i < CareerConfig.RIVAL_MAX_FEATURED else ""]), [
			"%s  ·  world rank %s" % [g.get("nationality", ""), str(rank_of.get(String(r["id"]), "-"))],
			"Head to head: you %d - %d them (%d tied)" % [int(r["wins"]), int(r["losses"]), int(r["ties"])],
			"%d meetings  ·  %d close finishes" % [int(r["meetings"]), int(r["close"])]]))
	body.add_child(menu._note("Head to head compares finishing positions in events you both played (a missed cut counts as behind everyone who made it)."))
	menu._push(pg["root"])


# ------------------------------------------------------------------ hub pieces

static func ledger_card(c: CareerManager) -> Control:
	var rows := CareerRecords.ledger_recent(c.data, CareerConfig.LEDGER_HUB_ROWS)
	var lines: Array = ["Balance: %s" % CareerPages.money(int((c.data["economy"] as Dictionary)["balance"]))]
	if rows.is_empty():
		lines.append("No transactions yet. Prize money appears here.")
	rows.reverse()
	for t in rows:
		lines.append("%s  %s" % [CareerPages.money(int(t["amount"])), t["label"]])
	return CareerPages._card("LEDGER", lines)


static func rivals_card(c: CareerManager) -> Control:
	var rivals := CareerRecords.featured_rivals(c.data)
	var lines: Array = []
	if rivals.is_empty():
		lines.append("None yet. Finish within %d strokes of the same golfer %d times." % [CareerConfig.RIVAL_CLOSE_STROKES, CareerConfig.RIVAL_MIN_CLOSE])
	for r in rivals:
		lines.append("%s  (you %d - %d)" % [r["name"], int(r["wins"]), int(r["losses"])])
	return CareerPages._card("RIVALS", lines)

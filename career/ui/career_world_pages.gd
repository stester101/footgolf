class_name CareerWorldPages
extends RefCounted
## Career screens about the wider world and your record: World Ranking, Season Standings (full tables), Tournament
## Report, Trophy Cabinet and Rivals. Presentation only: every number is read from CareerManager / the stored event
## results. Built with CareerKit (see docs/career/CAREER_UI_DESIGN.md).

const PAGE_STEP := 30


static func _delta(d: int) -> String:
	if d > 0:
		return "up %d" % d
	if d < 0:
		return "down %d" % -d
	return "no change"


static func _ord(n: int) -> String:
	return QualificationManager._ord(n)


## "1" -> "1st", "T5" stays "T5".
static func place_text(label: String, place: int) -> String:
	if label == "" or label.is_valid_int():
		return _ord(place if place > 0 else int(label))
	return label


static func _home(menu: MainMenu) -> Control:
	return CareerKit.cta("Back to Career Hub", "", func() -> void:
		while menu._stack.size() > 1:
			menu._pop()
		CareerPages.open_hub(menu), "career_back_hub")


# ------------------------------------------------------------------ rankings (World Ranking / Season Standings)

## Full table page with search and paging. rows = table rows (rank, name, is_human, id, ...); value_of(row) -> String;
## sub_of(row) -> String; lines = {rank: label} markers drawn after that rank; moves = {id: delta}.
static func _ranking_page(menu: MainMenu, title: String, header: Control, rows: Array, value_of: Callable, sub_of: Callable, lines: Dictionary, moves: Dictionary, ui_prefix: String) -> void:
	var pg: Dictionary = CareerKit.page(menu, title, "LBT · Season %d" % CareerManager.active.season_number(), CareerKit.C_REGULAR)
	var body: VBoxContainer = pg["body"]
	body.add_child(header)
	var state := {"limit": PAGE_STEP, "query": ""}
	var search := LineEdit.new()
	search.placeholder_text = "Search a golfer"
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(0, CareerKit.TOUCH)
	search.add_theme_font_size_override("font_size", CareerKit.fs(24))
	search.add_theme_stylebox_override("normal", CareerKit.flat(Color(0.03, 0.07, 0.14, 0.95), 16, 20.0, Color(0.6, 0.78, 1.0, 0.3), 1))
	search.add_theme_stylebox_override("focus", CareerKit.flat(Color(0.03, 0.07, 0.14, 0.95), 16, 20.0, CareerKit.C_LIME, 2))
	search.set_meta("ui_id", ui_prefix + "_search")
	body.add_child(search)
	var list := UiKit.vbox(2)
	body.add_child(CareerKit.card(list))
	var me_idx := 0
	for i in rows.size():
		if bool(rows[i]["is_human"]):
			me_idx = i
	var fn := {}
	fn["add_row"] = func(i: int) -> void:
		var r: Dictionary = rows[i]
		list.add_child(CareerKit.rank_row(str(int(r["rank"])), String(r["name"]), String(value_of.call(r)), int(moves.get(String(r["id"]), 0)), bool(r["is_human"]), String(sub_of.call(r))))
		if lines.has(int(r["rank"])):
			list.add_child(CareerKit.line_marker(String(lines[int(r["rank"])])))
	fn["rebuild"] = func() -> void:
		UiKit.clear(list)
		var add_row: Callable = fn["add_row"]
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
				list.add_child(CareerKit.text("No golfer matches.", 22, CareerKit.C_MUTED))
			return
		var limit := mini(int(state["limit"]), rows.size())
		for i in limit:
			add_row.call(i)
		if me_idx >= limit:
			list.add_child(CareerKit.text("· · ·", 20, CareerKit.C_FAINT, "caps", false, HORIZONTAL_ALIGNMENT_CENTER))
			for i in range(maxi(limit, me_idx - 3), mini(rows.size(), me_idx + 4)):
				add_row.call(i)
		if limit < rows.size():
			list.add_child(CareerKit.ghost("Show %d more" % mini(PAGE_STEP, rows.size() - limit), func() -> void:
				state["limit"] = int(state["limit"]) + PAGE_STEP
				(fn["rebuild"] as Callable).call(), ui_prefix + "_more"))
	search.text_changed.connect(func(t: String) -> void:
		state["query"] = t
		(fn["rebuild"] as Callable).call())
	(fn["rebuild"] as Callable).call()
	menu._push(pg["root"])


static func _summary(rank_text: String, of_text: String, delta: int, has_delta: bool, stats: Array, note: String) -> Control:
	var v := UiKit.vbox(8)
	var h := UiKit.hbox(14)
	h.add_child(CareerKit.stat("Your rank", rank_text, of_text, CareerKit.C_LIME, 56))
	for s in stats:
		h.add_child(CareerKit.stat(String(s[0]), String(s[1]), String(s[2]), Color.WHITE, 36))
	if has_delta:
		var mv := UiKit.vbox(0)
		mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mv.add_child(CareerKit.caption("Move", CareerKit.C_MUTED))
		mv.add_child(CareerKit.move_arrow(delta, true, 32))
		h.add_child(mv)
	v.add_child(h)
	v.add_child(CareerKit.text(note, 19, CareerKit.C_MUTED, "", true))
	return CareerKit.card(v, CareerKit.glass(Color(0.12, 0.25, 0.46, 0.92), Color(0.05, 0.10, 0.21, 0.96), 20.0, 22.0))


static func open_world_ranking(menu: MainMenu) -> void:
	var c := CareerManager.active
	var rows := c.world_table()
	var me: Dictionary = {}
	for r in rows:
		if bool(r["is_human"]):
			me = r
	var moves: Dictionary = CareerKit.note_ranks(c)["world"]
	var res_last := _last_result(c)
	var last := ("Last event: %d -> %d (%s). " % [int(res_last["world_rank_before"]), int(res_last["world_rank_after"]),
		_delta(int(res_last["world_rank_before"]) - int(res_last["world_rank_after"]))]) if not res_last.is_empty() else "No events played yet. "
	var head := _summary("#%d" % int(me.get("rank", 0)), "of %d" % rows.size(), int(moves.get(CareerManager.PLAYER, 0)), true,
		[["Points", str(int(round(float(me.get("points", 0.0))))), "two seasons"]],
		last + "This season's points count in full, last season's at half.")
	_ranking_page(menu, "World Ranking", head, rows,
		func(r: Dictionary) -> String: return str(int(round(float(r["points"])))),
		func(r: Dictionary) -> String: return "",
		{CareerConfig.MAJOR_MAX_WORLD_RANK: "Majors: top %d" % CareerConfig.MAJOR_MAX_WORLD_RANK, CareerConfig.FLAGSHIP_MAX_WORLD_RANK: "Flagships: top %d" % CareerConfig.FLAGSHIP_MAX_WORLD_RANK},
		moves, "career_wr")


static func open_standings(menu: MainMenu) -> void:
	var c := CareerManager.active
	var rows := c.standings_table()
	var me: Dictionary = {}
	for r in rows:
		if bool(r["is_human"]):
			me = r
	var moves: Dictionary = CareerKit.note_ranks(c)["ss"]
	var started := not (c.standings()["applied"] as Dictionary).is_empty()
	var rk := int(me.get("rank", 0))
	var status := "Not ranked until the season has results." if not started else \
		("You are %s: %s the finale line. The LBT Championship adds no season points; finish inside the card line to keep your LBT card." % [_ord(rk), "inside" if rk <= CareerConfig.FINALE_QUALIFIERS else "outside"])
	var head := _summary(_ord(rk) if started else "-", "of %d" % rows.size(), int(moves.get(CareerManager.PLAYER, 0)), started,
		[["Points", str(int(round(float(me.get("points", 0.0))))), "%d wins · %d starts" % [int(me.get("wins", 0)), int(me.get("starts", 0))]]], status)
	_ranking_page(menu, "Season Standings", head, rows,
		func(r: Dictionary) -> String: return str(int(round(float(r["points"])))),
		func(r: Dictionary) -> String: return ("%dW" % int(r["wins"])) if int(r["wins"]) > 0 else "",
		{CareerConfig.FINALE_QUALIFIERS: "Finale line: top %d" % CareerConfig.FINALE_QUALIFIERS, CareerConfig.TOUR_CARD_RETENTION_RANK: "LBT card line: top %d" % CareerConfig.TOUR_CARD_RETENTION_RANK},
		moves, "career_ss")


static func _last_result(c: CareerManager) -> Dictionary:
	var last := {}
	for e in c.data["calendar"]:
		var r: Dictionary = e["result"]
		if String(e["status"]) in ["complete", "skipped"] and r.has("world_rank_after"):
			last = r
	return last


# ------------------------------------------------------------------ tournament report

static func _move_line(title: String, before: String, after: String, d: int) -> Control:
	var h := UiKit.hbox(12)
	h.add_child(CareerKit.trim(CareerKit.text(title, 21, Color.WHITE)))
	h.add_child(CareerKit.text("%s  →  %s" % [before, after], 21, CareerKit.C_MUTED, "num"))
	var a := CareerKit.move_arrow(d, true, 18)
	a.custom_minimum_size.x = 64
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(a)
	return h


## Winner, your finish, money (ledger), ranking movement, the leaderboard top and your rivals' results.
static func open_report(menu: MainMenu, ev: Dictionary, back_to_hub: bool) -> void:
	var c := CareerManager.active
	var res: Dictionary = ev["result"]
	var cat := String(ev.get("category", "regular"))
	var col := CareerKit.tier_color(cat)
	var pg: Dictionary = CareerKit.page(menu, "Tournament Report", "%s · %s" % [ev["name"], CalendarManager.category_label(cat)], col)
	var body: VBoxContainer = pg["body"]
	# hero: your finish
	var hv := UiKit.vbox(10)
	var played := bool(res.get("human_played", false))
	var won := played and bool(res.get("human_won", false))
	if played:
		hv.add_child(CareerKit.caption("Champion" if won else ("Missed the cut" if bool(res.get("human_missed_cut", false)) else "Your finish"), CareerKit.C_MAJOR if won else col))
		var big := UiKit.hbox(16)
		big.add_child(CareerKit.text("WINNER" if won else place_text(String(res.get("human_place_label", "")), int(res.get("human_place", 0))), 64, CareerKit.C_MAJOR if won else Color.WHITE, "display"))
		var bv := UiKit.vbox(0)
		bv.alignment = BoxContainer.ALIGNMENT_CENTER
		bv.add_child(CareerKit.text("%d strokes (%s)" % [int(res["human_total"]), RoundState.fmt_relative(int(res["human_rel"]))], 22, Color.WHITE, "semi"))
		bv.add_child(CareerKit.text("Rounds: %s" % ", ".join(PackedStringArray((res.get("rounds", []) as Array).map(func(x) -> String: return str(int(x))))), 18, CareerKit.C_MUTED))
		big.add_child(bv)
		hv.add_child(big)
		var st := UiKit.hbox(10)
		st.add_child(CareerKit.stat("Earnings", "", "", CareerKit.C_UP, 32, float(res.get("human_earnings", 0)), func(x: float) -> String: return CareerKit.money_short(int(round(x)))))
		st.add_child(CareerKit.stat("Season pts", "", "", Color.WHITE, 32, float(res.get("human_points", 0)), func(x: float) -> String: return str(int(round(x)))))
		st.add_child(CareerKit.stat("World pts", "", "", Color.WHITE, 32, float(round(float(res.get("human_world_points", 0.0)))), func(x: float) -> String: return str(int(round(x)))))
		hv.add_child(st)
	else:
		hv.add_child(CareerKit.caption("Your result", col))
		hv.add_child(CareerKit.text("You did not play this event.", 28, Color.WHITE, "display", true))
	var sk := CareerKit.glass(Color(col.r * 0.3 + 0.05, col.g * 0.3 + 0.08, col.b * 0.3 + 0.15, 0.95), Color(0.05, 0.09, 0.18, 0.97), 22.0, 24.0)
	sk.border = Color(col.r, col.g, col.b, 0.6)
	sk.rim = col
	body.add_child(CareerKit.card(hv, sk))
	# winner
	var wh := UiKit.hbox(16)
	wh.add_child(CareerKit.icon_disc("trophy", CareerKit.C_MAJOR, 64))
	var wv := UiKit.vbox(2)
	wv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wv.add_child(CareerKit.caption("Winner", CareerKit.C_MAJOR))
	wv.add_child(CareerKit.trim(CareerKit.text(String(res.get("winner_name", "?")), 26, Color.WHITE, "semi")))
	var po: Dictionary = res.get("playoff", {})
	wv.add_child(CareerKit.text("%d strokes (%s)%s" % [int(res.get("winner_total", 0)), RoundState.fmt_relative(int(res.get("winner_to_par", 0))),
		"  ·  won a sudden-death playoff" if bool(po.get("needed", false)) else ""], 18, CareerKit.C_MUTED, "", true))
	wh.add_child(wv)
	if not won:
		body.add_child(CareerKit.card(wh))
	# ranking movement
	var mv := UiKit.vbox(10)
	mv.add_child(CareerKit.caption("Ranking movement"))
	var wb := int(res.get("world_rank_before", 0))
	var wa := int(res.get("world_rank_after", 0))
	mv.add_child(_move_line("World Ranking", "#%d" % wb, "#%d" % wa, wb - wa))
	var sb := int(res.get("season_rank_before", 0))
	var sa := int(res.get("season_rank_after", 0))
	mv.add_child(_move_line("Season Standings", _ord(sb), _ord(sa), sb - sa))
	for m in res.get("movers", []):
		mv.add_child(CareerKit.text("Biggest climber: %s, up %d to #%d" % [m["name"], int(m["delta"]), int(m["rank"])], 18, CareerKit.C_MUTED, "", true))
		break
	body.add_child(CareerKit.card(mv))
	# money (ledger)
	var mon := UiKit.vbox(8)
	mon.add_child(CareerKit.caption("Money"))
	var any := false
	for t in CareerRecords.ledger_for_event(c.data, String(ev.get("id", ""))):
		any = true
		var lh := UiKit.hbox(10)
		lh.add_child(CareerKit.trim(CareerKit.text(String(t["label"]), 20, Color.WHITE)))
		lh.add_child(CareerKit.text(("+" if int(t["amount"]) > 0 else "") + CareerPages.money(int(t["amount"])), 20, CareerKit.C_UP if int(t["amount"]) > 0 else CareerKit.C_DOWN, "num"))
		mon.add_child(lh)
	if not any:
		mon.add_child(CareerKit.text("No prize money from this event.", 20, CareerKit.C_MUTED))
	mon.add_child(CareerKit.text("Balance %s  ·  this season %s" % [CareerPages.money(int((c.data["economy"] as Dictionary)["balance"])), CareerPages.money(int((c.data["economy"] as Dictionary)["season_earnings"]))], 18, CareerKit.C_MUTED, "", true))
	body.add_child(CareerKit.card(mon))
	# rivals
	var rivals: Array = res.get("rivals", [])
	if not rivals.is_empty():
		var rv := UiKit.vbox(8)
		rv.add_child(CareerKit.caption("Your rivals"))
		for r in rivals:
			var ahead := int(r["rival_ahead"])
			var rh := UiKit.hbox(10)
			rh.add_child(CareerKit.trim(CareerKit.text("%s  %s (%s)" % [r["name"], r["pos"], RoundState.fmt_relative(int(r["to_par"]))], 20, Color.WHITE)))
			rh.add_child(CareerKit.chip("Beat you" if ahead > 0 else ("You beat them" if ahead < 0 else "Tied"), CareerKit.C_DOWN if ahead > 0 else (CareerKit.C_UP if ahead < 0 else CareerKit.C_MUTED)))
			rv.add_child(rh)
		body.add_child(CareerKit.card(rv))
	# leaderboard
	var box := UiKit.vbox(2)
	box.add_child(CareerKit.section("Leaderboard", "Top %d, you and rivals" % CareerConfig.REPORT_TOP_ROWS))
	var cut_drawn := false
	var cut: Dictionary = res.get("cut", {})
	for r in res.get("report", []):
		if String(r["status"]) == "cut" and not cut_drawn and not cut.is_empty():
			cut_drawn = true
			box.add_child(CareerKit.line_marker("Cut line %d" % int(cut.get("line_total", 0))))
		var rounds := " ".join(PackedStringArray((r["rounds"] as Array).map(func(x) -> String: return str(int(x)))))
		box.add_child(CareerKit.rank_row(String(r["pos"]), String(r["name"]), RoundState.fmt_relative(int(r["to_par"])), 0, bool(r["is_human"]), rounds, false))
	body.add_child(CareerKit.card(box))
	if back_to_hub:
		(pg["footer"] as VBoxContainer).add_child(CareerKit.cta("Back to Career Hub", "", func() -> void:
			while menu._stack.size() > 1:
				menu._pop()
			CareerPages.open_hub(menu), "career_results_done"))
	menu._push(pg["root"])


# ------------------------------------------------------------------ trophy cabinet

const TROPHY_GROUPS := [["major", "Major championships", Color("#FFC845")], ["tour_championship", "LBT Championships", Color("#FF7A59")],
	["season_title", "Season titles", Color("#8FD8FF")], ["flagship", "Flagship wins", Color("#B98CFF")], ["event_win", "LBT event wins", Color("#4FA3FF")]]


static func open_trophies(menu: MainMenu) -> void:
	var c := CareerManager.active
	var rec: Dictionary = c.data["records"]
	var pg: Dictionary = CareerKit.page(menu, "Trophy Cabinet", c.player_name(), CareerKit.C_MAJOR)
	var body: VBoxContainer = pg["body"]
	var shelf := UiKit.hbox(6)
	for g in TROPHY_GROUPS:
		shelf.add_child(CareerKit.trophy(String(g[1]).get_slice(" ", 0), CareerRecords.trophies_of(c.data, String(g[0])).size(), g[2]))
	var sv := UiKit.vbox(12)
	sv.add_child(CareerKit.section("Shelf", "%d trophies" % (c.data["trophies"] as Array).size()))
	sv.add_child(shelf)
	body.add_child(CareerKit.card(sv, CareerKit.glass(Color(0.30, 0.24, 0.10, 0.92), Color(0.07, 0.07, 0.10, 0.96), 22.0, 22.0)))
	var best: Dictionary = rec["best_finish"]
	var cheque: Dictionary = rec["biggest_cheque"]
	var rv := UiKit.vbox(10)
	rv.add_child(CareerKit.caption("Career records"))
	var g1 := GridContainer.new()
	g1.columns = 3
	g1.add_theme_constant_override("h_separation", 12)
	g1.add_theme_constant_override("v_separation", 14)
	g1.add_child(CareerKit.stat("Wins", str(int(rec["wins"])), "", CareerKit.C_MAJOR, 36))
	g1.add_child(CareerKit.stat("Majors", str(int(rec["majors"])), "", CareerKit.C_MAJOR, 36))
	g1.add_child(CareerKit.stat("Top 10s", str(int(rec["top10s"])), "", Color.WHITE, 36))
	g1.add_child(CareerKit.stat("Starts", str(int(rec["starts"])), "", Color.WHITE, 36))
	g1.add_child(CareerKit.stat("Cuts made", str(int(rec["cuts_made"])), "", Color.WHITE, 36))
	g1.add_child(CareerKit.stat("Best rank", ("#%d" % int(rec["best_world_rank"])) if int(rec["best_world_rank"]) > 0 else "-", "", CareerKit.C_LIME, 36))
	rv.add_child(g1)
	rv.add_child(CareerKit.text(("Best finish: %s at %s (season %d)" % [_ord(int(best["place"])), best["event"], int(best["season"])]) if not best.is_empty() else "Best finish: none yet", 19, Color.WHITE, "", true))
	rv.add_child(CareerKit.text(("Biggest cheque: %s (%s)" % [CareerPages.money(int(cheque["amount"])), cheque["event"]]) if not cheque.is_empty() else "Biggest cheque: none yet", 19, Color.WHITE, "", true))
	rv.add_child(CareerKit.text("Career earnings: %s" % CareerPages.money(int((c.data["economy"] as Dictionary)["career_earnings"])), 19, CareerKit.C_UP, "", true))
	body.add_child(CareerKit.card(rv))
	var any := false
	for g in TROPHY_GROUPS:
		var list := CareerRecords.trophies_of(c.data, String(g[0]))
		if list.is_empty():
			continue
		any = true
		var v := UiKit.vbox(8)
		v.add_child(CareerKit.section(String(g[1]), str(list.size())))
		for t in list:
			var h := UiKit.hbox(12)
			var ic := LineIcon.make("trophy", 30, g[2])
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			h.add_child(ic)
			h.add_child(CareerKit.trim(CareerKit.text(String(t["name"]), 22, Color.WHITE, "semi")))
			h.add_child(CareerKit.chip("Season %d" % int(t["season"]), g[2]))
			v.add_child(h)
		body.add_child(CareerKit.card(v, CareerKit.striped(CareerKit.C_CARD, g[2])))
	if not any:
		body.add_child(CareerKit.info_card("Empty cabinet", ["Win a tournament, a major or the LBT Championship, or finish a season top of the Season Standings, to fill it."]))
	menu._push(pg["root"])


# ------------------------------------------------------------------ rivals

static func _h2h_bar(w: int, l: int, t: int) -> Control:
	var h := UiKit.hbox(3)
	h.custom_minimum_size.y = 12
	var total := maxi(1, w + l + t)
	for part in [[w, CareerKit.C_UP], [t, CareerKit.C_FAINT], [l, CareerKit.C_DOWN]]:
		if int(part[0]) <= 0:
			continue
		var r := ColorRect.new()
		r.color = part[1]
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.size_flags_stretch_ratio = float(part[0]) / float(total)
		r.custom_minimum_size.y = 12
		h.add_child(r)
	if w + l + t == 0:
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.1)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(r)
	return h


static func open_rivals(menu: MainMenu) -> void:
	var c := CareerManager.active
	var pg: Dictionary = CareerKit.page(menu, "Rivals", "Head to head", CareerKit.C_DOWN)
	var body: VBoxContainer = pg["body"]
	var list: Array = c.data["rivalries"]
	if list.is_empty():
		body.add_child(CareerKit.info_card("No rivals yet", ["A golfer becomes a rival after you finish within %d strokes of each other in %d events." % [CareerConfig.RIVAL_CLOSE_STROKES, CareerConfig.RIVAL_MIN_CLOSE]]))
	var by := c.golfers_by_id()
	var rank_of := RankingManager.rank_map(c.world_table())
	for i in list.size():
		var r: Dictionary = list[i]
		var g: Dictionary = by.get(String(r["id"]), {})
		var v := UiKit.vbox(10)
		var h := UiKit.hbox(12)
		h.add_child(CareerKit.nation_chip(String(g.get("nationality", "")), 28))
		h.add_child(CareerKit.trim(CareerKit.text(String(r["name"]), 26, Color.WHITE, "semi")))
		if i < CareerConfig.RIVAL_MAX_FEATURED:
			h.add_child(CareerKit.chip("Featured", CareerKit.C_DOWN))
		v.add_child(h)
		var sh := UiKit.hbox(10)
		sh.add_child(CareerKit.stat("You", str(int(r["wins"])), "wins", CareerKit.C_UP, 36))
		sh.add_child(CareerKit.stat("Them", str(int(r["losses"])), "wins", CareerKit.C_DOWN, 36))
		sh.add_child(CareerKit.stat("Tied", str(int(r["ties"])), "", Color.WHITE, 36))
		sh.add_child(CareerKit.stat("World", "#%s" % str(rank_of.get(String(r["id"]), "-")), "", Color.WHITE, 36))
		v.add_child(sh)
		v.add_child(_h2h_bar(int(r["wins"]), int(r["losses"]), int(r["ties"])))
		v.add_child(CareerKit.text("%d meetings  ·  %d close finishes" % [int(r["meetings"]), int(r["close"])], 18, CareerKit.C_MUTED))
		body.add_child(CareerKit.card(v, CareerKit.striped(CareerKit.C_CARD, CareerKit.C_DOWN if i < CareerConfig.RIVAL_MAX_FEATURED else CareerKit.C_FAINT)))
	body.add_child(CareerKit.text("Head to head compares finishing positions in events you both played (a missed cut counts as behind everyone who made it).", 18, CareerKit.C_MUTED, "", true))
	menu._push(pg["root"])


# ------------------------------------------------------------------ small cards (kept for callers outside the shell)

static func ledger_card(c: CareerManager) -> Control:
	var rows := CareerRecords.ledger_recent(c.data, CareerConfig.LEDGER_HUB_ROWS)
	var lines: Array = ["Balance: %s" % CareerPages.money(int((c.data["economy"] as Dictionary)["balance"]))]
	if rows.is_empty():
		lines.append("No transactions yet. Prize money appears here.")
	rows.reverse()
	for t in rows:
		lines.append("%s  %s" % [CareerPages.money(int(t["amount"])), t["label"]])
	return CareerKit.info_card("Ledger", lines)


static func rivals_card(c: CareerManager) -> Control:
	var rivals := CareerRecords.featured_rivals(c.data)
	var lines: Array = []
	if rivals.is_empty():
		lines.append("None yet. Finish within %d strokes of the same golfer %d times." % [CareerConfig.RIVAL_CLOSE_STROKES, CareerConfig.RIVAL_MIN_CLOSE])
	for r in rivals:
		lines.append("%s  (you %d - %d)" % [r["name"], int(r["wins"]), int(r["losses"])])
	return CareerKit.info_card("Rivals", lines)

class_name CareerOffSeasonPages
extends RefCounted
## Off-season screens (guided, resumable: the step lives in the save, see OffSeason) and the LBT status card.
## Presentation only. Back always returns to the Hub, which offers 'Continue off-season' at the same step.

const STEP_TITLES := {"review": "Season review", "sponsors": "Sponsors", "shop": "Shop", "news": "World news", "start": "Next season"}


## LBT card status, sponsor wildcards, rivals' form.
static func status_card(c: CareerManager) -> Control:
	return CareerShell._status_card(c)


static func _tracker(idx: int) -> Control:
	var h := UiKit.hbox(8)
	for i in OffSeason.STEPS.size():
		var v := UiKit.vbox(6)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var on := i <= idx
		var bar := ColorRect.new()
		bar.color = CareerKit.C_MAJOR if i < idx else (CareerKit.C_LIME if i == idx else Color(1, 1, 1, 0.12))
		bar.custom_minimum_size.y = 8
		v.add_child(bar)
		v.add_child(CareerKit.text(String(STEP_TITLES.get(OffSeason.STEPS[i], "")).to_upper(), 13, Color.WHITE if on else CareerKit.C_FAINT, "caps", true))
		h.add_child(v)
	return h


static func open(menu: MainMenu) -> void:
	var c := CareerManager.active
	if not c.begin_off_season() and not c.off_season_active():
		return
	var step := OffSeason.step(c)
	var idx := OffSeason.STEPS.find(step)
	var os := OffSeason.state(c)
	var pg: Dictionary = CareerKit.page(menu, String(STEP_TITLES.get(step, step)), "Off-season · step %d of %d" % [idx + 1, OffSeason.STEPS.size()], CareerKit.C_MAJOR)
	var body: VBoxContainer = pg["body"]
	body.add_child(_tracker(idx))
	var next_label := "Continue"
	match step:
		"review":
			_review(menu, body, c, os)
		"sponsors":
			_hook(menu, body, "Sponsors", c.off_season_hook_sponsors())
		"shop":
			_hook(menu, body, "Shop", c.off_season_hook_shop())
		"news":
			_news(menu, body, os)
		"start":
			_start(menu, body, c, os)
			next_label = "Start season %d" % (int(os["season"]) + 1)
	body.add_child(CareerKit.text("You can leave at any time; the Hub resumes here.", 17, CareerKit.C_FAINT, "", true))
	var footer: VBoxContainer = pg["footer"]
	footer.add_child(CareerKit.cta(next_label, "", func() -> void: _next(menu, c, step), "career_offseason_next"))
	menu._push(pg["root"])


static func _next(menu: MainMenu, c: CareerManager, step: String) -> void:
	if step == "start":
		var ok := c.start_next_season()
		var done := func() -> void:
			while menu._stack.size() > 1:
				menu._pop()
			CareerPages.open_hub(menu)
		if ok:
			done.call()
		else:
			CareerPages._present_save_error(menu, c.store, done)
		return
	var again := func() -> void: CareerPages._replace(menu, func() -> void: open(menu))
	if c.advance_off_season():
		again.call()
	elif c.store.is_blocked():
		CareerPages._present_save_error(menu, c.store, again)


static func _review(menu: MainMenu, body: VBoxContainer, c: CareerManager, os: Dictionary) -> void:
	var r: Dictionary = os["review"]
	var hv := UiKit.vbox(10)
	hv.add_child(CareerKit.caption("Season %d review" % int(r["season"]), CareerKit.C_MAJOR))
	var hr := int(r["human_rank"])
	hv.add_child(CareerKit.text(("%s in the Standings" % QualificationManager._ord(hr)) if hr > 0 else "Unranked", 40, Color.WHITE, "display", true))
	var st := UiKit.hbox(10)
	st.add_child(CareerKit.stat("Points", str(int(r["human_points"])), "", Color.WHITE, 32))
	st.add_child(CareerKit.stat("Played", str(int(r["events_played"])), "%d skipped" % int(r["events_skipped"]), Color.WHITE, 32))
	st.add_child(CareerKit.stat("Earned", "", "", CareerKit.C_UP, 32, float(r["earnings"]), func(x: float) -> String: return CareerKit.money_short(int(round(x)))))
	var ws := int(r["world_rank_start"])
	var we := int(r["world_rank_end"])
	st.add_child(CareerKit.stat("World", "#%d" % we, ("from #%d" % ws) if ws > 0 else "", CareerKit.C_LIME, 32))
	hv.add_child(st)
	body.add_child(CareerKit.card(hv, CareerKit.glass(Color(0.34, 0.27, 0.10, 0.92), Color(0.08, 0.08, 0.10, 0.96), 22.0, 24.0)))
	body.add_child(CareerKit.info_card("Champions", ["Season Standings: %s" % String(r["champion"]), "LBT Championship: %s" % String(r["lbt_champion"]),
		"Career earnings: %s" % CareerPages.money(int(r["career_earnings"]))]))
	var titles: Array = r["titles"]
	body.add_child(CareerKit.info_card("Your titles", titles if not titles.is_empty() else ["No titles this season. Next year."], CareerKit.C_MAJOR))
	var card: Dictionary = os["card"]
	var text := ""
	var ok := true
	match String(card["status"]):
		"kept":
			text = "You finished %s, inside the top %d: you keep your LBT card." % [QualificationManager._ord(int(card["standings_rank"])), int(card["line"])]
		"regained":
			text = "You finished %s, inside the top %d: your LBT card is back." % [QualificationManager._ord(int(card["standings_rank"])), int(card["line"])]
		_:
			ok = false
			text = "You finished outside the top %d, so you start next season without your LBT card. You receive %d sponsor wildcard entries to regular events. Finish top %d on a wildcard, or reach the card line, to earn it back. There is no dead end: wildcards renew every season." % [int(card["line"]), int(card["wildcards_next"]), CareerConfig.WILDCARD_CARD_PLACE]
	body.add_child(CareerKit.info_card("LBT card", [text], CareerKit.C_UP if ok else UiKit.C_WARN))


static func _hook(menu: MainMenu, body: VBoxContainer, title: String, h: Dictionary) -> void:
	body.add_child(CareerKit.info_card(title, (h.get("lines", []) as Array), CareerKit.C_MAJOR))
	if not bool(h.get("available", false)):
		body.add_child(CareerKit.text("Nothing to do here. Continue.", 19, CareerKit.C_MUTED))
	elif String(h.get("kind", "")) == "sponsors":
		body.add_child(CareerKit.row("trophy", "Open sponsors", "Review offers and sign for next season", "", func() -> void: CareerSponsorPages.open_sponsor_review(menu), "career_os_sponsors", CareerKit.C_MAJOR))
	elif String(h.get("kind", "")) == "shop":
		body.add_child(CareerKit.row("star", "Open shop", "Spend your winnings on cosmetics", "", func() -> void: CareerShopPages.open_shop(menu), "career_os_shop", CareerKit.C_FLAGSHIP))


static func _news(menu: MainMenu, body: VBoxContainer, os: Dictionary) -> void:
	var n: Dictionary = os["news"]
	body.add_child(CareerKit.info_card("Ageing", ["Every active golfer is a year older (%d). Ratings drift with age." % int(n.get("aged", 0))]))
	var ret: Array = (n.get("retired", []) as Array).duplicate()
	ret.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["rating"]) > float(b["rating"]))
	var rl: Array = []
	for g in ret.slice(0, 8):
		rl.append("%s (%d) retires" % [g["name"], int(g["age"])])
	if ret.size() > 8:
		rl.append("... and %d more" % (ret.size() - 8))
	body.add_child(CareerKit.info_card("Retirements", rl if not rl.is_empty() else ["Nobody retires this year."], CareerKit.C_FAINT))
	var ent: Array = n.get("entrants", [])
	var el: Array = []
	for g in ent.slice(0, 8):
		el.append("%s (%d, %s) joins the pro ranks" % [g["name"], int(g["age"]), g["nationality"]])
	if ent.size() > 8:
		el.append("... and %d more" % (ent.size() - 8))
	body.add_child(CareerKit.info_card("New entrants", el if not el.is_empty() else ["No new entrants."], CareerKit.C_UP))


static func _start(menu: MainMenu, body: VBoxContainer, c: CareerManager, os: Dictionary) -> void:
	var card: Dictionary = os["card"]
	var hv := UiKit.vbox(8)
	hv.add_child(CareerKit.caption("Ready", CareerKit.C_LIME))
	hv.add_child(CareerKit.text("Season %d starts now" % (int(os["season"]) + 1), 40, Color.WHITE, "display", true))
	body.add_child(CareerKit.card(hv, CareerKit.glass(Color(0.15, 0.33, 0.16, 0.92), Color(0.05, 0.10, 0.08, 0.96), 22.0, 24.0)))
	var lines: Array = ["A new calendar and fresh Season Standings begin.",
		"Every footballer can be used again (the once-per-season pool resets)."]
	if int(card.get("wildcards_next", 0)) > 0:
		lines.append("LBT card: lost. You start with %d sponsor wildcards." % int(card["wildcards_next"]))
	else:
		lines.append("LBT card: held.")
	lines.append(AdaptiveDifficulty.hint_text(c.data))
	body.add_child(CareerKit.info_card("What happens next", lines))

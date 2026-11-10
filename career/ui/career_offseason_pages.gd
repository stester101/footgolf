class_name CareerOffSeasonPages
extends RefCounted
## Off-season screens (guided, resumable: the step lives in the save, see OffSeason) and the Hub's LBT status card.
## Presentation only. Back always returns to the Hub, which offers 'Continue off-season' at the same step.

const STEP_TITLES := {"review": "Season review", "sponsors": "Sponsors", "shop": "Shop", "news": "World news", "start": "Next season"}


## Hub card: LBT card status, sponsor wildcards, rivals' form.
static func status_card(c: CareerManager) -> Control:
	return CareerPages._card("LBT STATUS", [OffSeason.card_status_text(c), AdaptiveDifficulty.hint_text(c.data)])


static func open(menu: MainMenu) -> void:
	var c := CareerManager.active
	if not c.begin_off_season() and not c.off_season_active():
		return
	var step := OffSeason.step(c)
	var idx := OffSeason.STEPS.find(step)
	var os := OffSeason.state(c)
	var pg: Dictionary = menu._page("Off-season: %s" % String(STEP_TITLES.get(step, step)))
	var body: VBoxContainer = pg["body"]
	body.add_child(menu._note("Step %d of %d. You can leave at any time; the Hub resumes here." % [idx + 1, OffSeason.STEPS.size()]))
	var next_label := "Continue"
	match step:
		"review":
			_review(menu, body, c, os)
		"sponsors":
			_hook(menu, body, "SPONSORS", c.off_season_hook_sponsors())
		"shop":
			_hook(menu, body, "SHOP", c.off_season_hook_shop())
		"news":
			_news(menu, body, os)
		"start":
			_start(menu, body, c, os)
			next_label = "Start season %d" % (int(os["season"]) + 1)
	var footer: VBoxContainer = pg["footer"]
	footer.add_child(menu._primary_button(next_label, func() -> void: _next(menu, c, step), "career_offseason_next"))
	menu._push(pg["root"])


static func _next(menu: MainMenu, c: CareerManager, step: String) -> void:
	if step == "start":
		var ok := c.start_next_season()
		var done := func() -> void:
			menu._pop()
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
	var lines: Array = [
		"Standings finish: %s  ·  %d pts" % [QualificationManager._ord(int(r["human_rank"])) if int(r["human_rank"]) > 0 else "unranked", int(r["human_points"])],
		"Standings champion: %s" % String(r["champion"]),
		"LBT Championship winner: %s" % String(r["lbt_champion"]),
		"Events played: %d  ·  skipped: %d" % [int(r["events_played"]), int(r["events_skipped"])],
		"Money: %s this season  ·  %s career" % [CareerPages.money(int(r["earnings"])), CareerPages.money(int(r["career_earnings"]))],
		"World ranking: %s -> %d" % [str(int(r["world_rank_start"])) if int(r["world_rank_start"]) > 0 else "-", int(r["world_rank_end"])],
	]
	body.add_child(CareerPages._card("SEASON %d REVIEW" % int(r["season"]), lines))
	var titles: Array = r["titles"]
	body.add_child(CareerPages._card("TITLES", titles if not titles.is_empty() else ["No titles this season. Next year."]))
	var card: Dictionary = os["card"]
	var text := ""
	match String(card["status"]):
		"kept":
			text = "You finished %s, inside the top %d: you keep your LBT card." % [QualificationManager._ord(int(card["standings_rank"])), int(card["line"])]
		"regained":
			text = "You finished %s, inside the top %d: your LBT card is back." % [QualificationManager._ord(int(card["standings_rank"])), int(card["line"])]
		_:
			text = "You finished outside the top %d, so you start next season without your LBT card. You receive %d sponsor wildcard entries to regular events. Finish top %d on a wildcard, or reach the card line, to earn it back. There is no dead end: wildcards renew every season." % [int(card["line"]), int(card["wildcards_next"]), CareerConfig.WILDCARD_CARD_PLACE]
	body.add_child(CareerPages._card("LBT CARD", [text]))


static func _hook(menu: MainMenu, body: VBoxContainer, title: String, h: Dictionary) -> void:
	body.add_child(CareerPages._card(title, (h.get("lines", []) as Array)))
	if not bool(h.get("available", false)):
		body.add_child(menu._note("Nothing to do here yet. Continue."))


static func _news(menu: MainMenu, body: VBoxContainer, os: Dictionary) -> void:
	var n: Dictionary = os["news"]
	body.add_child(CareerPages._card("AGEING", ["Every active golfer is a year older (%d). Ratings drift with age." % int(n.get("aged", 0))]))
	var ret: Array = (n.get("retired", []) as Array).duplicate()
	ret.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["rating"]) > float(b["rating"]))
	var rl: Array = []
	for g in ret.slice(0, 8):
		rl.append("%s (%d) retires" % [g["name"], int(g["age"])])
	if ret.size() > 8:
		rl.append("... and %d more" % (ret.size() - 8))
	body.add_child(CareerPages._card("RETIREMENTS", rl if not rl.is_empty() else ["Nobody retires this year."]))
	var ent: Array = n.get("entrants", [])
	var el: Array = []
	for g in ent.slice(0, 8):
		el.append("%s (%d, %s) joins the pro ranks" % [g["name"], int(g["age"]), g["nationality"]])
	if ent.size() > 8:
		el.append("... and %d more" % (ent.size() - 8))
	body.add_child(CareerPages._card("NEW ENTRANTS", el if not el.is_empty() else ["No new entrants."]))


static func _start(menu: MainMenu, body: VBoxContainer, c: CareerManager, os: Dictionary) -> void:
	var card: Dictionary = os["card"]
	var lines: Array = ["A new calendar and fresh Season Standings begin.",
		"Every footballer can be used again (the once-per-season pool resets)."]
	if int(card.get("wildcards_next", 0)) > 0:
		lines.append("LBT card: lost. You start with %d sponsor wildcards." % int(card["wildcards_next"]))
	else:
		lines.append("LBT card: held.")
	lines.append(AdaptiveDifficulty.hint_text(c.data))
	body.add_child(CareerPages._card("READY FOR SEASON %d" % (int(os["season"]) + 1), lines))

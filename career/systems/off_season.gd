class_name OffSeason
extends RefCounted
## LBT tour card / sponsor wildcards and the guided, resumable OFF-SEASON (owner decisions 2026-11-10).
## All state lives in the career save so a reload resumes at the same step:
##   data.off_season = {active, season, step, review{}, card{}, news{}, evolved, archived, prev_rank{}}
##   data.tour_status = {wildcards_left, wildcards_used[event ids], history[{season, text}]}
## The human golfer entity's `tour_card` flag is the single source of truth for the card (QualificationManager reads it).
## Steps: review -> sponsors -> shop -> news -> start. The sponsors and shop steps are hooks
## (CareerManager.off_season_hook_sponsors / off_season_hook_shop) owned by the sponsors/shop work.
## Numbers: CareerConfig (PROPOSED DEFAULT - OWNER APPROVAL REQUIRED).

const STEPS := ["review", "sponsors", "shop", "news", "start"]


static func default_state() -> Dictionary:
	return {"active": false, "season": 0, "step": "", "review": {}, "card": {}, "news": {}, "evolved": false, "archived": false, "prev_rank": {}}


static func default_tour_status() -> Dictionary:
	return {"wildcards_left": 0, "wildcards_used": [], "history": []}


static func is_active(c: CareerManager) -> bool:
	return bool((c.data.get("off_season", {}) as Dictionary).get("active", false))


static func state(c: CareerManager) -> Dictionary:
	return c.data["off_season"]


static func step(c: CareerManager) -> String:
	return String(state(c).get("step", ""))


# ------------------------------------------------------------------ tour card and wildcards

static func has_card(c: CareerManager) -> bool:
	return bool(c.human().get("tour_card", true))


static func wildcards_left(c: CareerManager) -> int:
	return int((c.data.get("tour_status", {}) as Dictionary).get("wildcards_left", 0))


## Eligibility with the sponsor wildcard applied: a player without the card may enter REGULAR events on a wildcard.
static func apply_wildcard(c: CareerManager, event: Dictionary, chk: Dictionary, ctx: Dictionary) -> Dictionary:
	if bool(chk["eligible"]) or has_card(c) or String(event["category"]) != "regular":
		return chk
	var h := c.human().duplicate()
	h["tour_card"] = true
	var alt := QualificationManager.check(h, c.sim_event(event), ctx)
	if not bool(alt["eligible"]):
		return chk  # injured etc.: a wildcard does not help
	if wildcards_left(c) <= 0:
		chk["reason"] = "Not eligible: no LBT card and no sponsor wildcards left this season. Finish inside the card line (top %d) or top %d in a wildcard event to earn the card back." % [CareerConfig.TOUR_CARD_RETENTION_RANK, CareerConfig.WILDCARD_CARD_PLACE]
		return chk
	alt["via"] = "wildcard"
	alt["reason"] = "Eligible on a sponsor wildcard (%d left this season). Finish top %d to earn your LBT card back." % [wildcards_left(c), CareerConfig.WILDCARD_CARD_PLACE]
	return alt


## Wildcard use at event entry (the caller commits). Idempotent per event id.
static func consume_wildcard(c: CareerManager, event_id: String) -> void:
	var ts: Dictionary = c.data["tour_status"]
	var used: Array = ts["wildcards_used"]
	if used.has(event_id):
		return
	used.append(event_id)
	ts["wildcards_left"] = maxi(0, int(ts["wildcards_left"]) - 1)


## After a PLAYED event: earns the card back (top-N in a wildcard event, or a Standings rank inside the line).
## Returns "" or a message for the result. Idempotent (only acts while the card is missing).
static func review_card_after_event(c: CareerManager, ev: Dictionary, result: Dictionary, wildcard_event: bool) -> String:
	if has_card(c) or not bool(result.get("human_played", false)):
		return ""
	var place := int(result.get("human_place", 0))
	var why := ""
	if wildcard_event and place > 0 and place <= CareerConfig.WILDCARD_CARD_PLACE and not bool(result.get("human_missed_cut", false)):
		why = "Top %d on a sponsor wildcard" % CareerConfig.WILDCARD_CARD_PLACE
	else:
		var sr := c.season_rank()
		if sr > 0 and sr <= CareerConfig.TOUR_CARD_RETENTION_RANK:
			why = "Season Standings rank %d is inside the card line (%d)" % [sr, CareerConfig.TOUR_CARD_RETENTION_RANK]
	if why == "":
		return ""
	c.human()["tour_card"] = true
	var msg := "LBT card earned back: %s." % why
	(c.data["tour_status"]["history"] as Array).append({"season": c.season_number(), "event_id": String(ev["id"]), "text": msg})
	return msg


## Plain-language card status for the Hub / season summary.
static func card_status_text(c: CareerManager) -> String:
	if has_card(c):
		return "LBT card: held. Finish the season inside the top %d of the Season Standings to keep it." % CareerConfig.TOUR_CARD_RETENTION_RANK
	return "LBT card: lost. Sponsor wildcards left this season: %d. Top %d on a wildcard, or a Season Standings rank inside %d, earns it back." % [wildcards_left(c), CareerConfig.WILDCARD_CARD_PLACE, CareerConfig.TOUR_CARD_RETENTION_RANK]


# ------------------------------------------------------------------ off-season

## Starts the off-season (or returns true when it is already active = resume). Archives the finished season once.
## Does not commit; the caller does. False if the season is not finished or a tournament is open.
static func begin(c: CareerManager) -> bool:
	if is_active(c):
		return true
	if not c.season_finished() or c.has_active_tournament():
		return false
	var os := default_state()
	c.data["off_season"] = os
	os["active"] = true
	os["season"] = c.season_number()
	os["step"] = "review"
	_archive(c, os)
	return true


static func _archive(c: CareerManager, os: Dictionary) -> void:
	var old_n := c.season_number()
	var st := c.standings_table()
	var champion: Dictionary = st[0] if not st.is_empty() else {}
	var me := {}
	for r in st:
		if bool(r["is_human"]):
			me = r
	var finale := {}
	var first_rank := 0
	for e in c.data["calendar"]:
		var res: Dictionary = e["result"]
		if first_rank == 0 and int(res.get("world_rank_before", 0)) > 0:
			first_rank = int(res["world_rank_before"])
		if String(e["category"]) == "finale" and String(e["status"]) in ["complete", "skipped"]:
			finale = res
	var earnings := int((c.data["economy"] as Dictionary)["season_earnings"])
	var hist: Array = c.data["season_history"]
	if not hist.any(func(h: Dictionary) -> bool: return int(h["season"]) == old_n):
		hist.append({"season": old_n, "standings_champion": String(champion.get("name", "")),
			"standings_champion_id": String(champion.get("id", "")), "human_rank": int(me.get("rank", 0)), "human_points": float(me.get("points", 0.0)),
			"tour_champion": String(finale.get("winner_name", "")), "earnings": earnings})
	var title := not me.is_empty() and int(me["rank"]) == 1 and float(me["points"]) > 0.0
	if title:
		CareerRecords.trophy_add(c.data, "title:season_%d" % old_n, "season_title", "Season %d Standings champion" % old_n, old_n, "")
	var prev := {}
	for r in st:
		if int(r["rank"]) <= CareerConfig.PREV_STANDINGS_KEEP:
			prev[String(r["id"])] = int(r["rank"])
	os["prev_rank"] = prev
	os["archived"] = true
	# tour card review (decided now, applies to next season)
	var sr := int(me.get("rank", 0)) if int(me.get("points", 0.0)) > 0 else 0
	var had := has_card(c)
	var safe := sr > 0 and sr <= CareerConfig.TOUR_CARD_RETENTION_RANK
	var status := "kept" if (safe and had) else ("regained" if safe else ("lost" if had else "still_lost"))
	c.human()["tour_card"] = safe
	os["card"] = {"status": status, "standings_rank": sr, "line": CareerConfig.TOUR_CARD_RETENTION_RANK,
		"wildcards_next": 0 if safe else CareerConfig.WILDCARDS_PER_SEASON}
	var wins: Array = []
	for t in c.data["trophies"]:
		if int(t.get("season", 0)) == old_n:
			wins.append(String(t["name"]))
	os["review"] = {"season": old_n, "human_rank": int(me.get("rank", 0)), "human_points": int(round(float(me.get("points", 0.0)))),
		"champion": String(champion.get("name", "")), "lbt_champion": String(finale.get("winner_name", "")), "earnings": earnings,
		"career_earnings": int((c.data["economy"] as Dictionary)["career_earnings"]),
		"world_rank_start": first_rank, "world_rank_end": c.world_rank(), "titles": wins, "season_title": title,
		"events_played": (c.data["calendar"] as Array).filter(func(e: Dictionary) -> bool: return String(e["status"]) == "complete").size(),
		"events_skipped": (c.data["calendar"] as Array).filter(func(e: Dictionary) -> bool: return String(e["status"]) == "skipped").size()}


## Ageing / retirement / new entrants (WorldEvolution), run ONCE (flag persisted in the same state change).
static func evolve(c: CareerManager) -> void:
	var os := state(c)
	if bool(os["evolved"]):
		return
	var n := c.season_number() + 1
	var res := WorldEvolution.advance_season(c.data["golfers"], n, c.career_seed(), c.world())
	var by := c.golfers_by_id()
	var retired: Array = []
	for id in res["retired"]:
		var g: Dictionary = by.get(String(id), {})
		retired.append({"id": String(id), "name": String(g.get("name", id)), "age": int(g.get("age", 0)), "rating": float(g.get("rating", 0.0))})
	var entrants: Array = []
	for id in res["entrants"]:
		var g: Dictionary = by.get(String(id), {})
		entrants.append({"id": String(id), "name": String(g.get("name", id)), "age": int(g.get("age", 0)), "nationality": String(g.get("nationality", ""))})
	os["news"] = {"season": n, "aged": int(res["aged"]), "retired": retired, "entrants": entrants, "active": int(res["active"])}
	os["evolved"] = true


## Moves to the next step (in order; never skips the hooks' steps). The caller commits.
static func advance(c: CareerManager) -> bool:
	if not is_active(c):
		return false
	var os := state(c)
	var i := STEPS.find(String(os["step"]))
	if i < 0 or i >= STEPS.size() - 1:
		return false
	var nxt: String = STEPS[i + 1]
	if nxt == "news":
		evolve(c)
	os["step"] = nxt
	return true


## Sets up the next season from the off-season state (called by CareerManager.start_next_season).
static func finish(c: CareerManager) -> void:
	var os := state(c)
	evolve(c)
	var s: Dictionary = c.data["season"]
	var n := int(s["number"]) + 1
	c.data["prev_standings_rank"] = os["prev_rank"]
	s["number"] = n
	s["id"] = "season_%d" % n
	RankingManager.prune_world(c.world(), n)
	c.data["calendar"] = CalendarManager.build(String(s["length"]), n)
	c.data["season_standings"] = RankingManager.new_season_standings(n)
	(c.data["economy"] as Dictionary)["season_earnings"] = 0
	(c.data["season_footballers"] as Dictionary)[String(s["id"])] = []
	var ts: Dictionary = c.data["tour_status"]
	ts["wildcards_left"] = int((os["card"] as Dictionary).get("wildcards_next", 0))
	ts["wildcards_used"] = []
	CareerRecords.refresh_rivalries(c.data)
	(c.data["world_rankings"] as Dictionary)["player_rank"] = c.world_rank()
	c.data["off_season"] = default_state()

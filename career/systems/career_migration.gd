class_name CareerMigration
extends RefCounted
## Explicit save migrations (each step upgrades exactly one version, never recomputes past results, and only
## fills what is missing, so running it on already-upgraded data changes nothing).
## v1 -> v2: human golfer entity, World Ranking state, Season Standings table shape, event order counters,
## ledger / trophies / records / rivals defaults (ledger and trophies are rebuilt from the v1 career_history).


static func season_number_of(d: Dictionary) -> int:
	return int((d["season"] as Dictionary).get("number", 1))


static func v1_to_v2(src: Dictionary) -> Dictionary:
	var d := src.duplicate(true)
	var sn := season_number_of(d)
	# calendar: event order counters
	for e in d["calendar"]:
		if not (e as Dictionary).has("order"):
			e["order"] = CalendarManager.order_of(sn, int(e["serial"]))
	# human golfer entity (ranking tables and field building treat the player like any other golfer)
	var golfers: Array = d["golfers"]
	var has_human := false
	for g in golfers:
		if bool(g.get("is_human", false)):
			has_human = true
	if not has_human:
		golfers.append(new_human(d["player"] as Dictionary))
	for g in golfers:
		if not (g as Dictionary).has("honours"):
			g["honours"] = []
	# world ranking: baseline points from the roster; v1 results (simulated by the old stand-in) are not replayed
	var played: Dictionary = {}
	for e in d["calendar"]:
		if String(e["status"]) in ["complete", "skipped"]:
			played[String(e["id"])] = true
	var wr: Dictionary = d.get("world_rankings", {})
	if not wr.has("world"):
		var w := RankingManager.init_world(golfers, sn)
		w["applied"] = played.duplicate()
		wr["world"] = w
	if not wr.has("player_rank"):
		wr["player_rank"] = CareerConfig.START_WORLD_RANK
	d["world_rankings"] = wr
	# season standings: v1 was a flat {id: points}
	var ss: Dictionary = d.get("season_standings", {})
	if not (ss.has("points") and ss.has("applied")):
		var pts := {}
		for k in ss:
			pts[String(k)] = float(ss[k])
		d["season_standings"] = {"season": sn, "points": pts, "wins": {}, "starts": {}, "applied": played.duplicate()}
	# extras
	if not d.has("ledger"):
		d["ledger"] = []
	if not d.has("trophies"):
		d["trophies"] = []
	if not d.has("records"):
		d["records"] = CareerRecords.default_records()
	if not d.has("head_to_head"):
		d["head_to_head"] = {"applied": {}, "records": {}}
	if typeof(d.get("rivalries")) != TYPE_ARRAY:
		d["rivalries"] = []
	if not d.has("prev_standings_rank"):
		d["prev_standings_rank"] = {}
	if not d.has("season_history"):
		d["season_history"] = []
	# rebuild ledger and trophies from the v1 history (balances are already correct: no extra payment)
	var cat_of := {}
	for e in d["calendar"]:
		cat_of[String(e["id"])] = String(e["category"])
	var eco: Dictionary = d["economy"]
	for h in d.get("career_history", []):
		var eid := String(h["event_id"])
		var season := int(String(h.get("season", "season_%d" % sn)).get_slice("_", 1))
		var amount := int(h.get("earnings", 0))
		var has_entry := false
		for t in d["ledger"]:
			if String(t["id"]) == "prize:%s" % eid:
				has_entry = true
		if not has_entry:
			d["ledger"].append({"id": "prize:%s" % eid, "kind": "prize", "label": "%s prize money" % String(h.get("name", eid)),
				"amount": amount, "event_id": eid, "season": season, "balance_after": int(eco.get("balance", 0))})
		if int(h.get("human_place", 0)) == 1:
			CareerRecords.trophy_add(d, "win:%s" % eid, CareerRecords.win_kind(String(cat_of.get(eid, "regular"))), String(h.get("name", eid)), season, eid)
	d["schema_version"] = 2
	return d


static func new_human(player: Dictionary) -> Dictionary:
	return {"id": CareerRecords.PLAYER, "name": String(player.get("name", "Player")), "nationality": String(player.get("nationality", "")),
		"is_human": true, "age": 22, "form": 0.0, "injured_until": 0, "status": "active", "initial_rank": CareerConfig.START_WORLD_RANK,
		"tour_card": true, "honours": [], "kind": "human"}

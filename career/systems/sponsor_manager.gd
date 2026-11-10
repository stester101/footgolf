class_name SponsorManager
extends RefCounted
## Career sponsors: 12 FICTIONAL brands in 3 tiers (data/sponsors.json). Each season the player sees up to
## OFFERS_PER_SEASON offers and signs ONE primary sponsor. A contract pays a signing bonus, a fee for every event
## played and a bonus per objective reached. Failing an objective costs nothing except sponsor patience.
## Pure helpers on the career save Dictionary (the caller commits). Every payment is a CareerRecords ledger entry
## with a stable id, so nothing ever pays twice (failed-save retries, repeated hooks).
## Ids: sponsor_sign:<season_id>:<sponsor>, sponsor_fee:<event_id>, sponsor_bonus:<season_id>:<objective>.
## Save shape: see CareerDefaultsSponsorsShop.

const PATH := "res://career/data/sponsors.json"

# ---- PROPOSED DEFAULT - OWNER APPROVAL REQUIRED (all [INVENTED]; sponsor money figures live in sponsors.json)
const OFFERS_PER_SEASON := 3
const TIER_ORDER := ["local", "regional", "global"]
const TIER_WEIGHT := {"local": 1.0, "regional": 1.5, "global": 2.0}   # higher unlocked tiers are offered more often
const PATIENCE_MAX := 2          # a sponsor that saw this many missed seasons in a row stops offering
## A season counts as "missed" when the contract reached none of its objectives.

static var _cache: Array = []


static func all() -> Array:
	if _cache.is_empty():
		var d = CourseSource.read_json(PATH)
		if typeof(d) == TYPE_DICTIONARY:
			_cache = d.get("sponsors", [])
	return _cache


static func by_id(id: String) -> Dictionary:
	for s in all():
		if String(s["id"]) == id:
			return s
	return {}


static func tier_label(tier: String) -> String:
	return {"local": "Local", "regional": "Regional", "global": "Global"}.get(tier, tier)


static func is_unlocked(s: Dictionary, world_rank: int) -> bool:
	return world_rank <= int(s["unlock_rank"])


# ------------------------------------------------------------------ offers

static func contract_for(data: Dictionary, season_id: String) -> Dictionary:
	CareerDefaultsSponsorsShop.ensure_defaults(data)
	return (data["sponsorships"]["contracts"] as Dictionary).get(season_id, {})


## Generates (once per season, deterministic from the career seed) and returns the offered sponsor ids.
## Also settles the contracts of earlier seasons (patience bookkeeping).
static func ensure_offers(data: Dictionary, season_id: String, world_rank: int, career_seed: int) -> Array:
	CareerDefaultsSponsorsShop.ensure_defaults(data)
	settle_past(data, season_id)
	var sp: Dictionary = data["sponsorships"]
	var offers: Dictionary = sp["offers"]
	if offers.has(season_id):
		return offers[season_id]
	var cand: Array = []
	for s in all():
		var pat := int((sp["patience"] as Dictionary).get(String(s["id"]), 0))
		if is_unlocked(s, world_rank) and pat < PATIENCE_MAX:
			cand.append(s)
	cand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
	var rng := SimRng.make(career_seed, season_id, 0, "sponsors", "offers")
	var picked: Array = []
	while picked.size() < OFFERS_PER_SEASON and not cand.is_empty():
		var weights: Array = []
		var total := 0.0
		for s in cand:
			var w := float(TIER_WEIGHT.get(String(s["tier"]), 1.0)) / float(1 + int((sp["patience"] as Dictionary).get(String(s["id"]), 0)))
			weights.append(w)
			total += w
		var r := rng.randf() * total
		var idx := 0
		for i in weights.size():
			r -= float(weights[i])
			if r <= 0.0:
				idx = i
				break
			idx = i
		picked.append(String((cand[idx] as Dictionary)["id"]))
		cand.remove_at(idx)
	offers[season_id] = picked
	return picked


# ------------------------------------------------------------------ signing

## Signs one of this season's offers. {ok, reason}. Idempotent: signing the same sponsor again changes nothing.
static func sign(data: Dictionary, sponsor_id: String, season_id: String, season: int) -> Dictionary:
	CareerDefaultsSponsorsShop.ensure_defaults(data)
	var sp: Dictionary = data["sponsorships"]
	var existing := contract_for(data, season_id)
	if not existing.is_empty():
		return {"ok": String(existing["sponsor_id"]) == sponsor_id, "reason": "Already signed with a sponsor this season."}
	if not (sp["offers"] as Dictionary).get(season_id, []).has(sponsor_id):
		return {"ok": false, "reason": "That sponsor has not offered you a deal this season."}
	var s := by_id(sponsor_id)
	if s.is_empty():
		return {"ok": false, "reason": "Unknown sponsor."}
	var progress := {}
	for o in s["objectives"]:
		progress[String(o["id"])] = {"value": 0, "done": false, "failed": false, "paid": false}
	(sp["contracts"] as Dictionary)[season_id] = {"sponsor_id": sponsor_id, "season": season, "season_id": season_id,
		"status": "active", "progress": progress, "events": 0, "fees": 0, "bonuses": 0}
	if not (sp["history"] as Array).has(sponsor_id):
		(sp["history"] as Array).append(sponsor_id)
	var bonus := int(s["signing_bonus"])
	if CareerRecords.ledger_add(data, "sponsor_sign:%s:%s" % [season_id, sponsor_id], "sponsor",
			"%s signing bonus" % String(s["name"]), bonus, "", season):
		(data["sponsorships"]["contracts"][season_id] as Dictionary)["bonuses"] = bonus
	return {"ok": true, "reason": ""}


# ------------------------------------------------------------------ progress (hook: CareerManager._settle)

## Applies a finished event's compact result once per event id. `result` = the dict CareerManager._settle builds.
static func apply_event(data: Dictionary, ev: Dictionary, result: Dictionary, season_id: String, season: int) -> void:
	CareerDefaultsSponsorsShop.ensure_defaults(data)
	var applied: Dictionary = data["sponsorships"]["applied"]
	var eid := String(ev["id"])
	if applied.has(eid):
		return
	applied[eid] = true
	if not bool(result.get("human_played", false)):
		return
	var c := contract_for(data, season_id)
	if c.is_empty() or String(c["status"]) != "active":
		return
	var s := by_id(String(c["sponsor_id"]))
	if s.is_empty():
		return
	var fee := int(s["appearance_fee"])
	if CareerRecords.ledger_add(data, "sponsor_fee:%s" % eid, "sponsor", "%s appearance fee" % String(s["name"]), fee, eid, season):
		c["fees"] = int(c["fees"]) + fee
	c["events"] = int(c["events"]) + 1
	var place := int(result.get("human_place", 0))
	var field := int(result.get("field", 0))
	var made := not bool(result.get("human_missed_cut", false))
	for o in s["objectives"]:
		var st: Dictionary = c["progress"][String(o["id"])]
		match String(o["type"]):
			"cuts":
				if made:
					st["value"] = int(st["value"]) + 1
			"top10":
				if made and place > 0 and place <= 10:
					st["value"] = int(st["value"]) + 1
			"win":
				if bool(result.get("human_won", false)):
					st["value"] = int(st["value"]) + 1
			"rank":
				var rk := int(result.get("world_rank_after", 0))
				if rk > 0 and rk <= int(o["x"]):
					st["value"] = rk
					st["done"] = true
			"no_last":
				if field > 1 and place >= field:
					st["failed"] = true
		if String(o["type"]) in ["cuts", "top10", "win"] and int(st["value"]) >= int(o["n"]):
			st["done"] = true
		_pay_objective(data, c, s, o, st, eid, season)


static func _pay_objective(data: Dictionary, c: Dictionary, s: Dictionary, o: Dictionary, st: Dictionary, event_id: String, season: int) -> void:
	if not bool(st["done"]) or bool(st["paid"]) or bool(st["failed"]):
		return
	if String(o["type"]) == "no_last" and String(c["status"]) == "active":
		return  # paid when the season is settled
	st["paid"] = true
	var amt := int(o["bonus"])
	if CareerRecords.ledger_add(data, "sponsor_bonus:%s:%s" % [String(c["season_id"]), String(o["id"])], "sponsor",
			"%s bonus: %s" % [String(s["name"]), String(o["label"])], amt, event_id, season):
		c["bonuses"] = int(c["bonuses"]) + amt


# ------------------------------------------------------------------ season end

## Settles every contract of a season other than `current_season_id` (patience bookkeeping). Idempotent.
static func settle_past(data: Dictionary, current_season_id: String) -> void:
	for sid in (data["sponsorships"]["contracts"] as Dictionary).keys():
		if String(sid) != current_season_id:
			settle(data, String(sid))


## Ends a contract: "never finish last" pays now when it was kept (and at least one event was played); the sponsor's
## patience goes up by one when no objective was reached, and resets otherwise. Idempotent.
static func settle(data: Dictionary, season_id: String) -> void:
	var c := contract_for(data, season_id)
	if c.is_empty() or String(c["status"]) != "active":
		return
	var s := by_id(String(c["sponsor_id"]))
	c["status"] = "settled"
	var any := false
	for o in s.get("objectives", []):
		var st: Dictionary = c["progress"][String(o["id"])]
		if String(o["type"]) == "no_last" and int(c["events"]) > 0 and not bool(st["failed"]):
			st["done"] = true
		_pay_objective(data, c, s, o, st, "", int(c["season"]))
		if bool(st["done"]) and not bool(st["failed"]):
			any = true
	var pat: Dictionary = data["sponsorships"]["patience"]
	var sid := String(c["sponsor_id"])
	pat[sid] = 0 if any else int(pat.get(sid, 0)) + 1


## Convenience for the UI: objective rows [{label, bonus, text, done, failed}] of a contract.
static func objective_rows(c: Dictionary) -> Array:
	var out: Array = []
	var s := by_id(String(c.get("sponsor_id", "")))
	for o in s.get("objectives", []):
		var st: Dictionary = (c["progress"] as Dictionary).get(String(o["id"]), {})
		var text := ""
		match String(o["type"]):
			"cuts", "top10", "win":
				text = "%d / %d" % [mini(int(st.get("value", 0)), int(o["n"])), int(o["n"])]
			"rank":
				text = "best %d" % int(st["value"]) if int(st.get("value", 0)) > 0 else "rank %d needed" % int(o["x"])
			"no_last":
				text = "failed" if bool(st.get("failed", false)) else ("kept" if bool(st.get("done", false)) else "on track")
		out.append({"label": String(o["label"]), "bonus": int(o["bonus"]), "text": text, "done": bool(st.get("done", false)),
			"failed": bool(st.get("failed", false))})
	return out

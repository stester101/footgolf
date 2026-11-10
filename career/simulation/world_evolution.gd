class_name WorldEvolution
extends RefCounted
## World changes: form after events, bounded rare injuries, honours, and season-boundary ageing,
## retirements and new fictional entrants. Mutates the golfer dictionaries in the Array in place
## (golfer state is the save's `golfers` array). Retired golfers are NEVER removed: status = "retired".
## Every draw uses SimRng, so re-running a step with the same inputs gives identical changes.

const GIVEN := ["Aldric", "Bram", "Caspian", "Dorian", "Eamon", "Fenwick", "Gareth", "Hollis", "Ignatius", "Jarek", "Kieran", "Lucan",
	"Merrick", "Niall", "Osric", "Percival", "Quillon", "Rafferty", "Soren", "Tobias", "Ulric", "Vance", "Wystan", "Yorick", "Zane",
	"Anselm", "Bastian", "Corwin", "Declan", "Emrys", "Florian", "Gideon", "Hadrian", "Idris", "Jasper", "Kellan", "Lorcan", "Magnus"]
const FAMILY := ["Ashgrove", "Brackenridge", "Cawley", "Dunmore", "Eastwick", "Fairbourne", "Garrity", "Halloran", "Ironside", "Jessop",
	"Kingsley", "Lockhart", "Marlowe", "Northcott", "Oakhurst", "Pemberton", "Quarrell", "Radcliffe", "Stanhope", "Thornbury",
	"Underhill", "Vandermeer", "Whitlock", "Yarrow", "Zeller", "Abernathy", "Blackwood", "Calloway", "Draycott", "Ellerby"]


static func _by_id(golfers: Array) -> Dictionary:
	var m := {}
	for g in golfers:
		m[str(g["id"])] = g
	return m


## After an event: update form, roll injuries, record honours for the winner. Idempotent per event
## (a golfer already processed for event.id is skipped).
static func update_after_event(golfers: Array, result: Dictionary, event: Dictionary, career_seed: int, season: int = 0) -> void:
	var by_id := _by_id(golfers)
	var eid := str(event.get("id", result.get("event_id", "")))
	var n_paid := 0
	for e in result["leaderboard"]:
		if e["status"] == "made_cut" and not e["incomplete"]:
			n_paid += 1
	for e in result["leaderboard"]:
		var g: Dictionary = by_id.get(e["id"], {})
		if g.is_empty() or bool(g.get("is_human", false)) or e["status"] == "incomplete":
			continue
		if str(g.get("last_event_id", "")) == eid:
			continue
		g["last_event_id"] = eid
		var perf: float
		if e["status"] == "cut":
			perf = CareerConfig.CUT_PLAYER_PERFORMANCE
		else:
			perf = 1.0 - 2.0 * float(int(e["position"]) - 1) / maxf(1.0, float(n_paid - 1))
		var f: float = float(g.get("form", 0.0))
		g["form"] = snappedf(clampf(CareerConfig.FORM_RETAIN * f + (1.0 - CareerConfig.FORM_RETAIN) * perf, -1.0, 1.0), 0.001)
		var rng := SimRng.make(career_seed, eid, 0, str(g["id"]), "injury")
		if rng.randf() < CareerConfig.INJURY_CHANCE_PER_START:
			var dur: int = rng.randi_range(CareerConfig.INJURY_MIN_EVENTS, CareerConfig.INJURY_MAX_EVENTS)
			g["injured_until"] = int(event.get("order", 0)) + 1 + dur
	record_honours(golfers, result, event, season)


## Winner honours: {season, category, event_id}. Skipped when already recorded or the winner is unresolved.
static func record_honours(golfers: Array, result: Dictionary, event: Dictionary, season: int) -> void:
	var wid := str(result.get("winner_id", ""))
	if wid == "":
		return
	var g: Dictionary = _by_id(golfers).get(wid, {})
	if g.is_empty():
		return
	var eid := str(event.get("id", result.get("event_id", "")))
	if not g.has("honours"):
		g["honours"] = []
	for h in g["honours"]:
		if str(h.get("event_id", "")) == eid:
			return
	g["honours"].append({"season": season, "category": str(result.get("category", "regular")), "event_id": eid})


## Season boundary: age, rating drift, form regression, retirement, new entrants. `world` (optional) gets
## baseline points for entrants. Returns {season, retired:[ids], entrants:[ids], aged:int, active:int}.
static func advance_season(golfers: Array, new_season: int, career_seed: int, world: Dictionary = {}, target_active: int = -1) -> Dictionary:
	if target_active < 0:
		target_active = CareerConfig.WORLD_ACTIVE_TARGET
	var sid := "season_%d" % new_season
	var retired: Array = []
	var aged := 0
	for g in golfers:
		if str(g.get("status", "active")) == "retired" or bool(g.get("is_human", false)):
			continue
		var id := str(g["id"])
		var rng := SimRng.make(career_seed, sid, 0, id, "age")
		g["age"] = int(g.get("age", 25)) + 1
		aged += 1
		var age: int = g["age"]
		var drift := 0.0
		if age <= CareerConfig.AGE_GROWTH_MAX:
			drift = CareerConfig.RATING_GROWTH_MEAN
		elif age >= CareerConfig.AGE_DECLINE_FROM:
			drift = -(CareerConfig.RATING_DECLINE_MEAN + CareerConfig.RATING_DECLINE_PER_YEAR_OVER * float(age - CareerConfig.AGE_DECLINE_FROM))
		drift += rng.randfn(0.0, CareerConfig.RATING_SEASON_NOISE)
		g["rating"] = snappedf(clampf(float(g["rating"]) + drift, CareerConfig.RATING_MIN, CareerConfig.RATING_MAX), 0.1)
		g["consistency"] = snappedf(clampf(float(g.get("consistency", 0.6)) + rng.randfn(0.0, 0.02), CareerConfig.CONSISTENCY_MIN, CareerConfig.CONSISTENCY_MAX), 0.01)
		g["form"] = snappedf(float(g.get("form", 0.0)) * CareerConfig.FORM_SEASON_REGRESSION, 0.001)
		var rrng := SimRng.make(career_seed, sid, 0, id, "retire")
		var p := 0.0
		if age >= CareerConfig.RETIRE_FROM_AGE:
			p = CareerConfig.RETIRE_BASE + CareerConfig.RETIRE_PER_YEAR * float(age - CareerConfig.RETIRE_FROM_AGE)
			if float(g["rating"]) < CareerConfig.RETIRE_LOW_RATING:
				p *= CareerConfig.RETIRE_LOW_RATING_FACTOR
		if age >= CareerConfig.RETIRE_MAX_AGE or rrng.randf() < p:
			g["status"] = "retired"
			g["retired_season"] = new_season
			_note(g, new_season, "retired")
			retired.append(id)
	# new entrants top the active population back up
	var active := 0
	for g in golfers:
		if str(g.get("status", "active")) != "retired" and not bool(g.get("is_human", false)):
			active += 1
	var want: int = clampi(target_active - active, 0, CareerConfig.MAX_ENTRANTS_PER_SEASON)
	var entrants: Array = []
	var names := {}
	var nats: Array = []
	var max_n := 0
	for g in golfers:
		names[str(g.get("name", ""))] = true
		var nat := str(g.get("nationality", ""))
		if nat != "" and not nats.has(nat):
			nats.append(nat)
		var gid := str(g["id"])
		if gid.begins_with("gx%d_" % new_season):
			max_n = maxi(max_n, int(gid.get_slice("_", 1)))
	nats.sort()
	for k in range(want):
		var n := max_n + k + 1
		var id := "gx%d_%d" % [new_season, n]
		var rng := SimRng.make(career_seed, sid, 0, id, "entrant")
		var gname := ""
		for _t in range(30):
			gname = "%s %s" % [GIVEN[rng.randi_range(0, GIVEN.size() - 1)], FAMILY[rng.randi_range(0, FAMILY.size() - 1)]]
			if not names.has(gname):
				break
		var suffix := 2
		var base := gname
		while names.has(gname):
			gname = "%s %s" % [base, "I".repeat(suffix)]
			suffix += 1
		names[gname] = true
		var start_rank := active + k + 1
		var g := {
			"id": id, "name": gname,
			"nationality": nats[rng.randi_range(0, nats.size() - 1)] if not nats.is_empty() else "England",
			"age": rng.randi_range(CareerConfig.ENTRANT_AGE_MIN, CareerConfig.ENTRANT_AGE_MAX),
			"rating": snappedf(clampf(rng.randfn(CareerConfig.ENTRANT_RATING_MEAN, CareerConfig.ENTRANT_RATING_SD), CareerConfig.ENTRANT_RATING_MIN, CareerConfig.ENTRANT_RATING_MAX), 0.1),
			"consistency": snappedf(rng.randf_range(0.4, 0.8), 0.01),
			"form": 0.0, "injured_until": 0, "status": "active", "initial_rank": start_rank,
			"kind": "generated", "entered_season": new_season, "honours": [], "status_history": [],
		}
		_note(g, new_season, "entered")
		golfers.append(g)
		entrants.append(id)
		if not world.is_empty():
			RankingManager.add_baseline(world, id, start_rank, new_season)
	return {"season": new_season, "retired": retired, "entrants": entrants, "aged": aged, "active": active + entrants.size()}


static func _note(g: Dictionary, season: int, what: String) -> void:
	if not g.has("status_history"):
		g["status_history"] = []
	g["status_history"].append({"season": season, "status": what})

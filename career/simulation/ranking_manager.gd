class_name RankingManager
extends RefCounted
## World Ranking (rolling two-season window, age-weighted) and Season Standings (reset each season).
## State is plain JSON-friendly Dictionaries; season keys are strings.
##   world     = {season_points: {"<season>": {golfer_id: points}}, applied: {event_id: true}}
##   standings = {season: int, points: {id: pts}, wins: {id: n}, starts: {id: n}, applied: {event_id: true}}
## Applying the same event twice is a no-op (restart safety).


# ---------------------------------------------------------------- world ranking
static func new_world() -> Dictionary:
	return {"season_points": {}, "applied": {}}


## Baseline points for the initial roster (from initial_rank), stored in `season` (weight 1.0 that season).
static func init_world(golfers: Array, season: int) -> Dictionary:
	var w := new_world()
	for g in golfers:
		add_baseline(w, str(g["id"]), int(g.get("initial_rank", 999)), season)
	return w


static func add_baseline(world: Dictionary, golfer_id: String, rank: int, season: int) -> void:
	_bucket(world, season)[golfer_id] = snappedf(CareerConfig.baseline_points(rank), 0.01)


static func world_points(world: Dictionary, golfer_id: String, current_season: int) -> float:
	var total := 0.0
	var weights: Array = CareerConfig.WORLD_AGE_WEIGHTS
	for key in world["season_points"]:
		var age: int = current_season - int(key)
		if age < 0 or age >= CareerConfig.WORLD_WINDOW_SEASONS:
			continue
		total += float(weights[age]) * float(world["season_points"][key].get(golfer_id, 0.0))
	return total


## Table of non-retired entities, best first. Tie-breaks: points, this season's points, initial_rank,
## human first, id. Each row: {id, name, rank, points, season_points, is_human}.
static func world_table(world: Dictionary, golfers: Array, current_season: int) -> Array:
	var rows: Array = []
	var cur: Dictionary = world["season_points"].get(str(current_season), {})
	for g in golfers:
		if str(g.get("status", "active")) == "retired":
			continue
		var id := str(g["id"])
		rows.append({"id": id, "name": str(g.get("name", "")), "points": snappedf(world_points(world, id, current_season), 0.01),
			"season_points": float(cur.get(id, 0.0)), "initial_rank": int(g.get("initial_rank", 9999)),
			"is_human": bool(g.get("is_human", false)), "rank": 0})
	rows.sort_custom(_world_less)
	for i in range(rows.size()):
		rows[i]["rank"] = i + 1
	return rows


static func rank_map(table: Array) -> Dictionary:
	var m := {}
	for r in table:
		m[r["id"]] = int(r["rank"])
	return m


## Add an event result's world points. Idempotent per event id.
static func apply_event_to_world(world: Dictionary, result: Dictionary, season: int) -> bool:
	var eid := str(result.get("event_id", ""))
	if world["applied"].has(eid):
		return false
	world["applied"][eid] = true
	var b := _bucket(world, season)
	for e in result["leaderboard"]:
		var p: float = float(e.get("world_points", 0.0))
		if p > 0.0:
			b[e["id"]] = snappedf(float(b.get(e["id"], 0.0)) + p, 0.01)
	return true


## Drop seasons outside the window (call at a season boundary, after advancing the season).
static func prune_world(world: Dictionary, current_season: int) -> void:
	for key in world["season_points"].keys():
		if current_season - int(key) >= CareerConfig.WORLD_WINDOW_SEASONS:
			world["season_points"].erase(key)


## Movement between two tables: {id: previous_rank - new_rank} (positive = moved up).
static func movement(before: Array, after: Array) -> Dictionary:
	var b := rank_map(before)
	var m := {}
	for r in after:
		if b.has(r["id"]):
			m[r["id"]] = int(b[r["id"]]) - int(r["rank"])
	return m


# ---------------------------------------------------------------- season standings
static func new_standings(season: int) -> Dictionary:
	return {"season": season, "points": {}, "wins": {}, "starts": {}, "applied": {}}


static func apply_event_to_standings(standings: Dictionary, result: Dictionary) -> bool:
	var eid := str(result.get("event_id", ""))
	if standings["applied"].has(eid):
		return false
	standings["applied"][eid] = true
	for e in result["leaderboard"]:
		var id: String = e["id"]
		if e["status"] == "incomplete":
			continue
		standings["starts"][id] = int(standings["starts"].get(id, 0)) + 1
		var p: float = float(e.get("season_points", 0.0))
		if p > 0.0:
			standings["points"][id] = snappedf(float(standings["points"].get(id, 0.0)) + p, 0.01)
		if id == str(result.get("winner_id", "")) and str(result.get("category", "")) != "finale":
			standings["wins"][id] = int(standings["wins"].get(id, 0)) + 1
	return true


## Everyone not retired, best first. Tie-break: points, wins, world rank (rank_by_id, optional), id.
static func standings_table(standings: Dictionary, golfers: Array, rank_by_id: Dictionary = {}) -> Array:
	var rows: Array = []
	for g in golfers:
		if str(g.get("status", "active")) == "retired":
			continue
		var id := str(g["id"])
		rows.append({"id": id, "name": str(g.get("name", "")), "points": float(standings["points"].get(id, 0.0)),
			"wins": int(standings["wins"].get(id, 0)), "starts": int(standings["starts"].get(id, 0)),
			"world_rank": int(rank_by_id.get(id, 99999)), "is_human": bool(g.get("is_human", false)), "rank": 0,
			"in_finale": false, "tour_card_safe": false})
	rows.sort_custom(_standings_less)
	for i in range(rows.size()):
		rows[i]["rank"] = i + 1
		rows[i]["in_finale"] = i + 1 <= CareerConfig.FINALE_QUALIFIERS
		rows[i]["tour_card_safe"] = i + 1 <= CareerConfig.TOUR_CARD_RETENTION_RANK
	return rows


## Start a fresh standings for `season`. Archive standings_table(old, ...) before calling if you want history.
static func new_season_standings(season: int) -> Dictionary:
	return new_standings(season)


# ---------------------------------------------------------------- helpers
static func _bucket(world: Dictionary, season: int) -> Dictionary:
	var key := str(season)
	if not world["season_points"].has(key):
		world["season_points"][key] = {}
	return world["season_points"][key]


static func _world_less(a: Dictionary, b: Dictionary) -> bool:
	if a["points"] != b["points"]:
		return a["points"] > b["points"]
	if a["season_points"] != b["season_points"]:
		return a["season_points"] > b["season_points"]
	if a["initial_rank"] != b["initial_rank"]:
		return a["initial_rank"] < b["initial_rank"]
	if a["is_human"] != b["is_human"]:
		return a["is_human"]
	return a["id"] < b["id"]


static func _standings_less(a: Dictionary, b: Dictionary) -> bool:
	if a["points"] != b["points"]:
		return a["points"] > b["points"]
	if a["wins"] != b["wins"]:
		return a["wins"] > b["wins"]
	if a["world_rank"] != b["world_rank"]:
		return a["world_rank"] < b["world_rank"]
	return a["id"] < b["id"]

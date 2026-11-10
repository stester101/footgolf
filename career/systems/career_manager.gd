class_name CareerManager
extends RefCounted
## The single career in memory: `data` (the save, see career/models/README.md) + its CareerSaveManager.
## Every mutator changes `data` then commit()s; a failed commit leaves the new state in memory (fail-closed,
## store.is_blocked()) and returns false. Pure logic: the course source and the simulation are injectable.
## TODO (later phases, documented only): rivals, sponsors/economy/shop, trophies and report ceremonies,
## off-season, Q-School (uses the same season footballer pool: season_id key), adaptive difficulty, ageing/injury,
## proper World Ranking (RankingManager) - player_rank stays at the start value for now.

const ROSTER_PATH := "res://career/data/golfer_roster.json"
const PLAYER := TournamentManager.PLAYER

## The one place the opponent simulation is chosen (master swaps CareerSimStub for the real module).
static var sim: Object = CareerSimStub
## Course loader: Callable(course_id) -> CourseSource.load_course() shape. UI sets it to include Settings par edits.
static var course_source: Callable = Callable()
static var active: CareerManager

var data: Dictionary = {}
var store: CareerSaveManager


func _init(p_store: CareerSaveManager = null) -> void:
	store = p_store if p_store != null else CareerSaveManager.new()


static func load_course(course_id: String) -> Dictionary:
	if course_source.is_valid():
		return course_source.call(course_id)
	return CourseSource.load_course(course_id)


# ------------------------------------------------------------------ create / load

static func load_roster() -> Array:
	var d = CourseSource.read_json(ROSTER_PATH)
	var out: Array = []
	if typeof(d) == TYPE_DICTIONARY:
		for g in d.get("golfers", []):
			var c: Dictionary = (g as Dictionary).duplicate(true)
			c["form"] = 0.0
			c["injured_until"] = 0
			c["status"] = "active"
			out.append(c)
	return out


static func new_data(p_name: String, nationality: String, length: String, p_seed: int) -> Dictionary:
	var career_id := "career_%d_%d" % [int(Time.get_unix_time_from_system()), p_seed & 0xffff]
	return {
		"schema_version": CareerConfig.SCHEMA_VERSION, "career_id": career_id,
		"player": {"name": p_name.strip_edges(), "nationality": nationality},
		"options": {"footballer_once_per_season": true},
		"season": {"number": 1, "id": "season_1", "length": length},
		"calendar": CalendarManager.build(length, 1),
		"active_tournament": {},
		"world_rankings": {"player_rank": CareerConfig.START_WORLD_RANK},
		"season_standings": {},
		"golfers": load_roster(),
		"rivalries": [], "sponsorships": {}, "cosmetics": {}, "achievements": [],
		"career_history": [],
		"economy": {"balance": CareerConfig.START_BALANCE, "currency": CareerConfig.CURRENCY, "season_earnings": 0, "career_earnings": 0},
		"simulation_state": {"seed": p_seed},
		"season_footballers": {"season_1": []},
		"save_metadata": {"created_at": int(Time.get_unix_time_from_system())},
	}


## Starts a brand new career (replaces `data`; the caller warns about overwriting first).
func create(p_name: String, nationality: String, length: String, p_seed: int = -1) -> bool:
	if p_name.strip_edges() == "" or not length in CareerConfig.SEASON_LENGTHS:
		return false
	if p_seed < 0:
		p_seed = int(Time.get_ticks_usec()) & 0x7fffffff
	data = new_data(p_name, nationality, length, p_seed)
	return store.commit(data)


## Loads the saved career. Returns {ok, error}.
func load_saved() -> Dictionary:
	var r := store.load_career()
	if bool(r.ok):
		data = r.data
	return r


# ------------------------------------------------------------------ read helpers

func has_career() -> bool:
	return not data.is_empty()


func player_name() -> String:
	return String((data["player"] as Dictionary)["name"])


func season_id() -> String:
	return String((data["season"] as Dictionary)["id"])


func golfers_by_id() -> Dictionary:
	var m := {}
	for g in data["golfers"]:
		m[String(g["id"])] = g
	return m


func tournament() -> Dictionary:
	return data.get("active_tournament", {})


func has_active_tournament() -> bool:
	return not tournament().is_empty()


func season_points() -> int:
	return int((data["season_standings"] as Dictionary).get(PLAYER, 0))


## 1-based rank of the player by season points among everyone with points (ties share), 0 when no points.
func season_rank() -> int:
	var mine := season_points()
	if mine <= 0:
		return 0
	var better := 0
	for k in data["season_standings"]:
		if int(data["season_standings"][k]) > mine:
			better += 1
	return better + 1


func season_wins() -> Array:
	var wins: Array = []
	for e in data["calendar"]:
		if String(e["status"]) == "complete" and bool((e["result"] as Dictionary).get("human_won", false)):
			wins.append(String(e["category"]))
	return wins


func eligibility(event: Dictionary) -> Dictionary:
	return CalendarManager.eligibility(event, {"world_rank": int((data["world_rankings"] as Dictionary)["player_rank"]),
		"season_rank": season_rank() if season_rank() > 0 else 9999, "season_wins": season_wins()})


## The first event not yet played or skipped (the only one that can be entered), or {}.
func next_event() -> Dictionary:
	for e in data["calendar"]:
		if String(e["status"]) in ["upcoming", "in_progress"]:
			return e
	return {}


func event_by_serial(serial: int) -> Dictionary:
	for e in data["calendar"]:
		if int(e["serial"]) == serial:
			return e
	return {}


func season_finished() -> bool:
	return next_event().is_empty()


# ------------------------------------------------------------------ footballer once per season

func footballer_rule_on() -> bool:
	return bool((data["options"] as Dictionary).get("footballer_once_per_season", true))


## Used footballer ids of the CURRENT season (the pool is keyed by season id and resets with a new season).
func season_used_footballers() -> Array:
	return ((data["season_footballers"] as Dictionary).get(season_id(), []) as Array).duplicate()


func note_footballer_used(id: String) -> void:
	var sf: Dictionary = data["season_footballers"]
	var arr: Array = sf.get(season_id(), [])
	if not arr.has(id):
		arr.append(id)
	sf[season_id()] = arr


## Applies (or clears, when the option is off) the season lock to a round's pool.
func apply_season_lock(pool: FootballerPool) -> void:
	if footballer_rule_on():
		pool.set_season_lock(season_id(), season_used_footballers())
	else:
		pool.set_season_lock("", [])


func set_footballer_rule(on: bool) -> bool:
	(data["options"] as Dictionary)["footballer_once_per_season"] = on
	return store.commit(data)


# ------------------------------------------------------------------ tournament flow

## Enter the next event: freezes eligibility + the course snapshot + the field. False if not allowed.
func enter_event(serial: int) -> bool:
	if has_active_tournament():
		return false
	var e := event_by_serial(serial)
	if e.is_empty() or e != next_event() or not bool(eligibility(e)["eligible"]):
		return false
	var snap := CourseSnapshot.capture(load_course(String(e["course_id"])))
	if snap.is_empty():
		return false
	var t := TournamentManager.create(e, snap, _field_for(e), int((data["simulation_state"] as Dictionary)["seed"]) + int(e["serial"]) * 7919)
	t["event"]["eligibility_frozen"] = eligibility(e)
	e["status"] = "in_progress"
	data["active_tournament"] = t
	return store.commit(data)


func _field_for(e: Dictionary) -> Array:
	var list: Array = (data["golfers"] as Array).filter(func(g: Dictionary) -> bool: return String(g.get("status", "active")) == "active")
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["initial_rank"]) < int(b["initial_rank"]))
	var ids: Array = []
	for g in list:
		if ids.size() >= int(e["field_size"]) - 1:
			break
		ids.append(String(g["id"]))
	return ids


## Freezes this round's rules and mulligans (the player's Round Setup) and marks the round in progress.
func begin_round(rules: Dictionary, mulligans: int) -> bool:
	var t := tournament()
	if t.is_empty() or not String(t["status"]) in ["setup", "between_rounds"]:
		return false
	t["rules"] = rules.duplicate(true)
	t["mulligans"] = mulligans
	t["round_save"] = {}
	t["status"] = "in_round"
	return store.commit(data)


## Autosave of the in-progress round (RoundSave.capture dict) inside the career save. False = save failed.
func store_round_progress(round_save: Dictionary) -> bool:
	var t := tournament()
	if t.is_empty():
		return false
	t["round_save"] = round_save
	return store.commit(data)


## The human finished the round: records it, simulates the opponents, applies the cut. Returns the new status
## ("" if there is no round in progress). A failed commit still leaves the new state in memory.
func complete_round(strokes: int, par: int, holes: int) -> String:
	var t := tournament()
	if t.is_empty() or String(t["status"]) != "in_round":
		return ""
	var st := TournamentManager.record_human_round(t, golfers_by_id(), strokes, par, holes, sim)
	store.commit(data)
	return st


func leaderboard() -> Array:
	var t := tournament()
	if t.is_empty():
		return []
	return TournamentManager.leaderboard(t, golfers_by_id(), player_name(), String((data["player"] as Dictionary)["nationality"]))


## Idempotent: pays the prize money, awards season points, records the result in the calendar and closes the
## tournament. Returns the result Dictionary ({} if nothing to finalize). Safe to call again after a failed save.
func finalize_tournament() -> Dictionary:
	var t := tournament()
	if t.is_empty() or String(t["status"]) != "complete":
		return {}
	var ev: Dictionary = event_by_serial(int(t["event"]["serial"]))
	if not bool(t.get("finalized", false)):
		var rows := leaderboard()
		var result := _apply_results(ev, t, rows)
		t["finalized"] = true
		ev["result"] = result
		ev["status"] = "complete"
		(data["career_history"] as Array).append({"event_id": String(ev["id"]), "name": String(ev["name"]), "season": season_id(),
			"human_place": int(result["human_place"]), "earnings": int(result["human_earnings"])})
	var res: Dictionary = ev["result"]
	data["active_tournament"] = {}
	store.commit(data)
	return res


func _apply_results(ev: Dictionary, t: Dictionary, rows: Array) -> Dictionary:
	var pay := TournamentManager.payouts(int(ev["purse"]), rows)
	var pts := TournamentManager.season_points(int((ev["points"] as Dictionary)["winner"]), rows)
	var sd: Dictionary = data["season_standings"]
	for id in pts:
		sd[id] = int(sd.get(id, 0)) + int(pts[id])
	var winner: Dictionary = rows[0]
	var me := {}
	for r in rows:
		if r["is_human"]:
			me = r
	var earned := int(pay.get(PLAYER, 0))
	var eco: Dictionary = data["economy"]
	eco["balance"] = int(eco["balance"]) + earned
	eco["season_earnings"] = int(eco["season_earnings"]) + earned
	eco["career_earnings"] = int(eco["career_earnings"]) + earned
	return {
		"winner_id": String(winner["id"]), "winner_name": String(winner["name"]), "winner_total": int(winner["total"]),
		"human_played": not me.is_empty(), "human_place": int(me.get("place", 0)), "human_total": int(me.get("total", 0)),
		"human_rel": int(me.get("rel", 0)), "human_missed_cut": bool(me.get("cut", false)),
		"human_won": not me.is_empty() and int(me["place"]) == 1, "human_earnings": earned,
		"human_points": int(pts.get(PLAYER, 0)), "field": rows.size(),
		"rounds": me.get("rounds", []),
	}


## Skip the next event: the world still plays it (simulated), standings update.
func skip_event(serial: int) -> bool:
	if has_active_tournament():
		return false
	var e := event_by_serial(serial)
	if e.is_empty() or e != next_event():
		return false
	var snap := CourseSnapshot.capture(load_course(String(e["course_id"])))
	if snap.is_empty():
		return false
	var t := TournamentManager.create(e, snap, _field_for(e), int((data["simulation_state"] as Dictionary)["seed"]) + int(e["serial"]) * 7919)
	TournamentManager.simulate_all(t, golfers_by_id(), sim)
	var rows := TournamentManager.leaderboard(t, golfers_by_id(), player_name(), "")
	var pts := TournamentManager.season_points(int((e["points"] as Dictionary)["winner"]), rows)
	var sd: Dictionary = data["season_standings"]
	for id in pts:
		sd[id] = int(sd.get(id, 0)) + int(pts[id])
	e["status"] = "skipped"
	e["result"] = {"winner_id": String(rows[0]["id"]), "winner_name": String(rows[0]["name"]), "winner_total": int(rows[0]["total"]),
		"human_played": false, "human_place": 0, "human_earnings": 0, "human_won": false}
	return store.commit(data)


## Starts the next season: new calendar, standings reset, a fresh season footballer pool (new season id).
## (The proper off-season sequence is a later phase.)
func start_next_season() -> bool:
	if not season_finished() or has_active_tournament():
		return false
	var s: Dictionary = data["season"]
	var n := int(s["number"]) + 1
	s["number"] = n
	s["id"] = "season_%d" % n
	data["calendar"] = CalendarManager.build(String(s["length"]), n)
	data["season_standings"] = {}
	(data["economy"] as Dictionary)["season_earnings"] = 0
	(data["season_footballers"] as Dictionary)[String(s["id"])] = []
	return store.commit(data)

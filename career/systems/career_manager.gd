class_name CareerManager
extends RefCounted
## The single career in memory: `data` (the save, see career/models/README.md) + its CareerSaveManager.
## Every mutator changes `data` then commit()s; a failed commit leaves the new state in memory (fail-closed,
## store.is_blocked()) and returns false. Pure logic: the course source and the simulation are injectable.
##
## The opponent world is the real simulation (career/simulation/*): fields come from QualificationManager, scores
## from OpponentSimulation, World Ranking / Season Standings from RankingManager, form / injuries / ageing from
## WorldEvolution. Extras (ledger, trophies, rivals) live in CareerRecords.
## The tour is the "LBT" (Q-School is dropped): tour card + sponsor wildcards + the resumable off-season live in
## OffSeason; opponent-only adaptive difficulty in AdaptiveDifficulty (see docs/DECISIONS.md).
## TODO (later phases, documented only, NOT approved by the owner): sponsors / shop / wider economy (hooks:
## off_season_hook_sponsors / off_season_hook_shop), an interactive sudden-death playoff (ties for first are settled by a seeded simulated
## playoff in which the human plays as an average member of the tied group; see docs/DECISIONS.md).

const ROSTER_PATH := "res://career/data/golfer_roster.json"
const PLAYER := TournamentManager.PLAYER

## The simulation used for the opponents' round-by-round scores (CareerSim = OpponentSimulation adapter;
## tests may swap in CareerSimStub). The final result of every event always comes from OpponentSimulation.
static var sim: Object = CareerSim
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
			c["honours"] = []
			out.append(c)
	return out


static func new_data(p_name: String, nationality: String, length: String, p_seed: int) -> Dictionary:
	var career_id := "career_%d_%d" % [int(Time.get_unix_time_from_system()), p_seed & 0xffff]
	var golfers := load_roster()
	golfers.append(CareerMigration.new_human({"name": p_name.strip_edges(), "nationality": nationality}))
	var world := RankingManager.init_world(golfers, 1)
	return CareerMigration.ensure_defaults({
		"schema_version": CareerConfig.SCHEMA_VERSION, "career_id": career_id,
		"player": {"name": p_name.strip_edges(), "nationality": nationality},
		"options": {"footballer_once_per_season": true},
		"season": {"number": 1, "id": "season_1", "length": length},
		"calendar": CalendarManager.build(length, 1),
		"active_tournament": {},
		"world_rankings": {"player_rank": CareerConfig.START_WORLD_RANK, "world": world},
		"season_standings": RankingManager.new_standings(1),
		"prev_standings_rank": {}, "season_history": [],
		"golfers": golfers,
		"rivalries": [], "head_to_head": {"applied": {}, "records": {}},
		"ledger": [], "trophies": [], "records": CareerRecords.default_records(),
		"sponsorships": {}, "cosmetics": {}, "achievements": [],
		"career_history": [],
		"economy": {"balance": CareerConfig.START_BALANCE, "currency": CareerConfig.CURRENCY, "season_earnings": 0, "career_earnings": 0},
		"simulation_state": {"seed": p_seed},
		"season_footballers": {"season_1": []},
		"save_metadata": {"created_at": int(Time.get_unix_time_from_system())},
	})


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
		CareerDefaultsSponsorsShop.ensure_defaults(data)
	return r


# ------------------------------------------------------------------ read helpers

func has_career() -> bool:
	return not data.is_empty()


func player_name() -> String:
	return String((data["player"] as Dictionary)["name"])


func season_id() -> String:
	return String((data["season"] as Dictionary)["id"])


func season_number() -> int:
	return int((data["season"] as Dictionary)["number"])


func career_seed() -> int:
	return int((data["simulation_state"] as Dictionary)["seed"])


func golfers_by_id() -> Dictionary:
	var m := {}
	for g in data["golfers"]:
		m[String(g["id"])] = g
	return m


func human() -> Dictionary:
	for g in data["golfers"]:
		if bool(g.get("is_human", false)):
			return g
	return {}


func tournament() -> Dictionary:
	return data.get("active_tournament", {})


func has_active_tournament() -> bool:
	return not tournament().is_empty()


func world() -> Dictionary:
	return (data["world_rankings"] as Dictionary)["world"]


func standings() -> Dictionary:
	return data["season_standings"]


## World Ranking table, best first (non-retired golfers incl. the player): rows {id,name,rank,points,season_points,is_human}.
func world_table() -> Array:
	return RankingManager.world_table(world(), data["golfers"], season_number())


## Season Standings table, best first: rows add {wins, starts, in_finale, tour_card_safe}.
func standings_table(wtable: Array = []) -> Array:
	if wtable.is_empty():
		wtable = world_table()
	return RankingManager.standings_table(standings(), data["golfers"], RankingManager.rank_map(wtable))


func world_rank() -> int:
	for r in world_table():
		if bool(r["is_human"]):
			return int(r["rank"])
	return 0


func season_points() -> int:
	return int(round(float((standings()["points"] as Dictionary).get(PLAYER, 0.0))))


## 1-based Season Standings rank of the player; 0 while the season has no results yet.
func season_rank() -> int:
	if (standings()["applied"] as Dictionary).is_empty():
		return 0
	for r in standings_table():
		if bool(r["is_human"]):
			return int(r["rank"])
	return 0


func season_wins() -> Array:
	var wins: Array = []
	for e in data["calendar"]:
		if String(e["status"]) == "complete" and bool((e["result"] as Dictionary).get("human_won", false)):
			wins.append(String(e["category"]))
	return wins


## The calendar event as the simulation modules want it: order counter, {world, season} winner points.
func sim_event(e: Dictionary) -> Dictionary:
	var se := e.duplicate(true)
	if not se.has("order"):
		se["order"] = CalendarManager.order_of(season_number(), int(e["serial"]))
	se["points"] = {"world": float((e.get("world_points", {}) as Dictionary).get("winner", CareerConfig.WINNER_POINTS.get(String(e["category"]), 0))),
		"season": float((e["points"] as Dictionary).get("winner", 0))}
	se.erase("result")
	return se


func event_seed(e: Dictionary) -> int:
	return career_seed() + int(e["serial"]) * 7919


func qual_ctx() -> Dictionary:
	return QualificationManager.build_context(world(), standings(), data["golfers"], season_number(), _prev_standings())


func _prev_standings() -> Dictionary:
	var m := {}
	var src: Dictionary = data.get("prev_standings_rank", {})
	for k in src:
		m[String(k)] = int(src[k])
	return m


## {eligible, via, reason, requirement, exemptions, world_rank, standings_rank} for the player.
func eligibility(event: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	if ctx.is_empty():
		ctx = qual_ctx()
	return OffSeason.apply_wildcard(self, event, QualificationManager.check(human(), sim_event(event), ctx), ctx)


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

## Enter the next event: freezes eligibility + the course snapshot + the field (built by QualificationManager).
## False if the event is not the next one or the player is not eligible.
func enter_event(serial: int) -> bool:
	if has_active_tournament():
		return false
	var e := event_by_serial(serial)
	if e.is_empty() or e != next_event():
		return false
	var ctx := qual_ctx()
	var se := sim_event(e)
	var chk := eligibility(e, ctx)
	if not bool(chk["eligible"]):
		return false
	var snap := CourseSnapshot.capture(load_course(String(e["course_id"])))
	if snap.is_empty():
		return false
	var wildcard := String(chk.get("via", "")) == "wildcard"
	var card_before := OffSeason.has_card(self)
	if wildcard:
		human()["tour_card"] = true  # only for building the field below; restored right after
	var bf := QualificationManager.build_field(se, data["golfers"], ctx)
	human()["tour_card"] = card_before
	var ids: Array = (bf["ids"] as Array).filter(func(id) -> bool: return String(id) != PLAYER)
	# adaptive difficulty: the opponents' rating offset is frozen for this event when it is entered
	var offset := AdaptiveDifficulty.current_offset(data)
	var shifted_field: Array = (bf["field"] as Array).map(func(g: Dictionary) -> Dictionary: return AdaptiveDifficulty.shifted({"x": g}, offset)["x"])
	se["field_strength"] = OpponentSimulation.field_strength(shifted_field)
	var t := TournamentManager.create(se, snap, ids, event_seed(e))
	t["event"]["eligibility_frozen"] = chk
	t["invited"] = bf["invited"]
	t["adaptive_offset"] = offset
	if wildcard:
		t["event"]["wildcard"] = true
		OffSeason.consume_wildcard(self, String(e["id"]))
	e["status"] = "in_progress"
	data["active_tournament"] = t
	return store.commit(data)


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
	var st := TournamentManager.record_human_round(t, tournament_golfers(), strokes, par, holes, sim)
	store.commit(data)
	return st


## golfer id -> golfer for the active tournament: AI ratings carry the adaptive offset frozen at entry.
func tournament_golfers() -> Dictionary:
	return AdaptiveDifficulty.shifted(golfers_by_id(), float(tournament().get("adaptive_offset", 0.0)))


func leaderboard() -> Array:
	var t := tournament()
	if t.is_empty():
		return []
	return TournamentManager.leaderboard(t, tournament_golfers(), player_name(), String((data["player"] as Dictionary)["nationality"]))


## Idempotent: settles the event (official result, prize money into the ledger, Season Standings + World Ranking,
## form / injuries, trophies, records, rivals), records it in the calendar and closes the tournament. Returns the
## result Dictionary ({} if nothing to finalize). Safe to call again after a failed save.
func finalize_tournament() -> Dictionary:
	var t := tournament()
	if t.is_empty() or String(t["status"]) != "complete":
		return {}
	var ev: Dictionary = event_by_serial(int(t["event"]["serial"]))
	if not bool(t.get("finalized", false)):
		var res := _official_result(t)
		var expected := _expected_percentile(t)
		var result := _settle(ev, res, true)
		if bool(result["human_played"]):
			AdaptiveDifficulty.record(data, String(ev["id"]), AdaptiveDifficulty.score_of(expected, int(result["human_place"]), int(result["field"])))
			var msg := OffSeason.review_card_after_event(self, ev, result, bool(t["event"].get("wildcard", false)))
			if msg != "":
				result["card_message"] = msg
		t["finalized"] = true
		ev["result"] = result
		ev["status"] = "complete"
		var hist: Array = data["career_history"]
		if not hist.any(func(h: Dictionary) -> bool: return String(h["event_id"]) == String(ev["id"])):
			hist.append({"event_id": String(ev["id"]), "name": String(ev["name"]), "season": season_id(),
				"human_place": int(result["human_place"]), "earnings": int(result["human_earnings"])})
	var res_out: Dictionary = ev["result"]
	data["active_tournament"] = {}
	store.commit(data)
	return res_out


## Finish percentile expected from the player's world rank (before the event settles) against the opponents entered.
func _expected_percentile(t: Dictionary) -> float:
	var rm := RankingManager.rank_map(world_table())
	var ranks: Array = []
	for id in t["field"]:
		ranks.append(int(rm.get(String(id), 9999)))
	return AdaptiveDifficulty.expected_percentile(int(rm.get(PLAYER, 9999)), ranks)


## The official event result for a finished tournament: the same OpponentSimulation scores the leaderboard showed,
## with the cut, positions, payouts and points. A tie for first that includes the player is settled by a seeded
## sudden-death playoff (the player counts as an average member of the tied group).
func _official_result(t: Dictionary) -> Dictionary:
	var ev: Dictionary = t["event"]
	var by := tournament_golfers()
	var field: Array = []
	for id in t["field"]:
		field.append(by[String(id)])
	var hr: Array = []
	if bool(t["has_human"]):
		field.append(human())
		for h in t["human_rounds"]:
			hr.append(int((h as Dictionary)["strokes"]))
	var ci := TournamentManager.course_info(t)
	var seed_v := int(t["sim_seed"])
	var res := OpponentSimulation.simulate_event_field(field, ev, ci, seed_v, hr)
	var po: Dictionary = res["playoff"]
	if bool(po["needed"]) and bool(po["human_involved"]) and not bool(po["resolved"]):
		var tied: Array = []
		var sum := 0.0
		var n := 0
		for g in field:
			if (po["tied_ids"] as Array).has(String(g["id"])):
				if bool(g.get("is_human", false)):
					continue
				sum += float(g.get("rating", 70.0))
				n += 1
		for g in field:
			if (po["tied_ids"] as Array).has(String(g["id"])):
				if bool(g.get("is_human", false)):
					tied.append({"id": PLAYER, "rating": sum / float(maxi(1, n)), "consistency": 0.6, "form": 0.0})
				else:
					tied.append(g)
		var sd := OpponentSimulation.sudden_death(tied, ev, ci, seed_v)
		OpponentSimulation.apply_playoff_result(res, sd["groups"], ev, ci)
		res["playoff"]["holes"] = sd["holes"]
	return res


## Applies an official event result to the world (once per event id) and builds the compact result stored in the
## calendar. `human_played` false = the player skipped the event.
func _settle(e: Dictionary, res: Dictionary, human_played: bool) -> Dictionary:
	var season := season_number()
	var se := sim_event(e)
	var golfers: Array = data["golfers"]
	var bw := world_table()
	var bs := standings_table(bw)
	RankingManager.apply_event_to_world(world(), res, season)
	RankingManager.apply_event_to_standings(standings(), res)
	WorldEvolution.update_after_event(golfers, res, se, career_seed(), season)
	var aw := world_table()
	var as_ := standings_table(aw)
	var rank_b := RankingManager.rank_map(bw)
	var rank_a := RankingManager.rank_map(aw)
	var srank_b := RankingManager.rank_map(bs)
	var srank_a := RankingManager.rank_map(as_)
	(data["world_rankings"] as Dictionary)["player_rank"] = int(rank_a.get(PLAYER, 0))
	var lb: Array = res["leaderboard"]
	var winner := {}
	var me := {}
	for r in lb:
		if String(r["id"]) == String(res["winner_id"]):
			winner = r
		if bool(r["is_human"]):
			me = r
	if winner.is_empty() and not lb.is_empty():
		winner = lb[0]
	if human_played and not me.is_empty():
		CareerRecords.apply_human_event(data, e, me, season, int(rank_a.get(PLAYER, 0)))
		CareerRecords.update_head_to_head(data, e, lb)
		var pay := int(me.get("payout", 0))
		if pay > 0:
			CareerRecords.ledger_add(data, "prize:%s" % String(e["id"]), "prize", "%s prize money" % String(e["name"]), pay, String(e["id"]), season)
	else:
		CareerRecords.note_world_rank(data, int(rank_a.get(PLAYER, 0)))
	# the biggest climbers in the world ranking this event
	var movers: Array = []
	for id in rank_a:
		if rank_b.has(id) and id != PLAYER:
			var d := int(rank_b[id]) - int(rank_a[id])
			if d > 0:
				movers.append({"id": id, "delta": d})
	movers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["delta"] > b["delta"] or (a["delta"] == b["delta"] and String(a["id"]) < String(b["id"])))
	var by := golfers_by_id()
	var mover_rows: Array = []
	for m in movers.slice(0, 3):
		mover_rows.append({"id": m["id"], "name": String((by.get(m["id"], {}) as Dictionary).get("name", m["id"])), "delta": m["delta"],
			"rank": int(rank_a[m["id"]])})
	var ids_keep := {}
	var report: Array = []
	var rivals_ids: Array = []
	for rv in CareerRecords.featured_rivals(data):
		rivals_ids.append(String(rv["id"]))
	for i in lb.size():
		var r: Dictionary = lb[i]
		var keep: bool = i < CareerConfig.REPORT_TOP_ROWS or bool(r["is_human"]) or rivals_ids.has(String(r["id"]))
		if keep and not ids_keep.has(String(r["id"])):
			ids_keep[String(r["id"])] = true
			report.append({"id": String(r["id"]), "name": String(r["name"]), "pos": String(r["position_label"]), "position": int(r["position"]),
				"status": String(r["status"]), "total": int(r["total"]), "to_par": int(r["to_par"]), "payout": int(r["payout"]),
				"rounds": (r["rounds"] as Array).duplicate(), "is_human": bool(r["is_human"])})
	var rival_lines: Array = []
	if human_played:
		for rid in rivals_ids:
			for r in lb:
				if String(r["id"]) == rid:
					var ahead := 0
					if not me.is_empty():
						ahead = signi(int(me["position"]) - int(r["position"]))  # +1 = the rival finished ahead of you
					rival_lines.append({"id": rid, "name": String(r["name"]), "pos": String(r["position_label"]), "total": int(r["total"]),
						"to_par": int(r["to_par"]), "status": String(r["status"]), "rival_ahead": ahead})
	var po: Dictionary = res["playoff"]
	var out := {
		"winner_id": String(winner.get("id", "")), "winner_name": String(winner.get("name", "?")), "winner_total": int(winner.get("total", 0)),
		"winner_to_par": int(winner.get("to_par", 0)),
		"human_played": human_played and not me.is_empty(), "human_place": int(me.get("position", 0)), "human_place_label": String(me.get("position_label", "")),
		"human_total": int(me.get("total", 0)), "human_rel": int(me.get("to_par", 0)),
		"human_missed_cut": not me.is_empty() and String(me.get("status", "")) == "cut",
		"human_won": human_played and not me.is_empty() and String(winner.get("id", "")) == PLAYER,
		"human_earnings": int(me.get("payout", 0)), "human_points": int(round(float(me.get("season_points", 0.0)))),
		"human_world_points": float(me.get("world_points", 0.0)), "field": lb.size(), "rounds": (me.get("rounds", []) as Array).duplicate(),
		"world_rank_before": int(rank_b.get(PLAYER, 0)), "world_rank_after": int(rank_a.get(PLAYER, 0)),
		"season_rank_before": int(srank_b.get(PLAYER, 0)), "season_rank_after": int(srank_a.get(PLAYER, 0)),
		"playoff": {"needed": bool(po["needed"]), "human_involved": bool(po["human_involved"]), "holes": (po.get("holes", []) as Array).size()},
		"cut": (res["cut"] as Dictionary).duplicate(), "par_per_round": int(res.get("par_per_round", 0)),
		"movers": mover_rows, "report": report, "rivals": rival_lines,
	}
	SponsorManager.apply_event(data, e, out, season_id(), season)  # sponsor fee + objectives, once per event id
	return out


## Skip the next event: the world still plays it (simulated), World Ranking and Season Standings update.
func skip_event(serial: int) -> bool:
	if has_active_tournament():
		return false
	var e := event_by_serial(serial)
	if e.is_empty() or e != next_event():
		return false
	var snap := CourseSnapshot.capture(load_course(String(e["course_id"])))
	if snap.is_empty():
		return false
	var ctx := qual_ctx()
	var se := sim_event(e)
	var ais: Array = (data["golfers"] as Array).filter(func(g: Dictionary) -> bool: return not bool(g.get("is_human", false)))
	var bf := QualificationManager.build_field(se, ais, ctx)
	var ci := {"holes": (snap["holes"] as Array).size(), "par": CourseSnapshot.total_par(snap), "difficulty": 0.0}
	var res := OpponentSimulation.simulate_event_field(bf["field"], se, ci, event_seed(e))
	var result := _settle(e, res, false)
	e["status"] = "skipped"
	e["result"] = result
	return store.commit(data)


## Starts the next season via the off-season state (begun implicitly when it was not): archives the finished
## standings, applies the tour card review, ages / retires golfers and adds entrants (once), new calendar and
## standings, a fresh season footballer pool (new season id), sponsor wildcards if the card was lost.
func start_next_season() -> bool:
	if not season_finished() or has_active_tournament():
		return false
	if not OffSeason.begin(self):
		return false
	OffSeason.finish(self)
	return store.commit(data)


# ------------------------------------------------------------------ off-season (resumable; state in data.off_season)

func off_season_active() -> bool:
	return OffSeason.is_active(self)


## Begins (or resumes) the off-season. False if the season is not finished. Commits; a failed save keeps the state in memory.
func begin_off_season() -> bool:
	if not OffSeason.begin(self):
		return false
	return store.commit(data)


## Next off-season step (review -> sponsors -> shop -> news -> start).
func advance_off_season() -> bool:
	if not OffSeason.advance(self):
		return false
	return store.commit(data)


## HOOK for the sponsors work: called by the off-season 'sponsors' step page. Return {available: bool, lines: Array[String]}.
## The stub reports nothing; the sponsors implementation replaces the body (keep the name and signature).
func off_season_hook_sponsors() -> Dictionary:
	return {"available": true, "kind": "sponsors", "lines": ["Review your sponsor and sign next season's contract.", "Offers depend on your world rank."]}


## HOOK for the shop work: called by the off-season 'shop' step page. Same contract as off_season_hook_sponsors().
func off_season_hook_shop() -> Dictionary:
	return {"available": true, "kind": "shop", "lines": ["Spend your prize money on cosmetics. No gameplay effect."]}


func set_adaptive_mode(m: String) -> bool:
	if not AdaptiveDifficulty.set_mode(data, m):
		return false
	return store.commit(data)


## Skip whatever event is next (the Hub's 'Skip to next event').
func skip_next_event() -> bool:
	var e := next_event()
	return not e.is_empty() and skip_event(int(e["serial"]))


# ------------------------------------------------------------------ live leaderboard (read-only; LiveProgress)
# Kept as ONE block at the end of the file. Nothing here writes the save or changes a result.

## Live progress of the round being played in the active tournament (null when there is none).
## Opponent per-hole scores come from the same frozen simulation as the official result and sum exactly to it.
func live_progress() -> LiveProgress:
	var t := tournament()
	if t.is_empty() or not String(t.get("status", "")) in ["in_round", "between_rounds", "setup"]:
		return null
	return LiveProgress.new(t, tournament_golfers(), player_name(), sim)


## Live board after the player has completed `holes_done` holes at `round_rel` to par this round ({} when none).
func live_board(holes_done: int, round_rel: int) -> Dictionary:
	var lp := live_progress()
	return {} if lp == null else lp.board(holes_done, round_rel)

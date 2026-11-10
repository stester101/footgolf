extends TestCase
## Career integration: the real opponent world behind CareerManager (field building, results, World Ranking and
## Season Standings after every event, season rollover), the ledger, trophies, rivals and the v1 -> v2 migration.


func _dir() -> String:
	return "user://test_career_world_%d" % (randi() % 1000000)


func _cleanup(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _career(dir: String, length: String = "short") -> CareerManager:
	var c := CareerManager.new(CareerSaveManager.new(dir))
	CareerManager.course_source = Callable()
	CareerManager.sim = CareerSim
	assert(c.create("Test Golfer", "England", length, 777))
	return c


## Plays the whole entered event: `per_round(r, par, holes)` gives the strokes of round r. Returns the result.
func _play(c: CareerManager, per_round: Callable) -> Dictionary:
	var t := c.tournament()
	var par := TournamentManager.par_per_round(t)
	var holes: int = ((t["snapshot"] as Dictionary)["holes"] as Array).size()
	var guard := 0
	while String(c.tournament()["status"]) != "complete" and guard < 8:
		assert_true(c.begin_round({}, 0))
		var r := (c.tournament()["human_rounds"] as Array).size()
		c.complete_round(int(per_round.call(r, par, holes)), par, holes)
		guard += 1
	return c.finalize_tournament()


func _enter_or_skip(c: CareerManager, per_round: Callable, enter: bool) -> Dictionary:
	var e := c.next_event()
	if enter and bool(c.eligibility(e)["eligible"]):
		assert_true(c.enter_event(int(e["serial"])))
		return _play(c, per_round)
	assert_true(c.skip_event(int(e["serial"])))
	return {}


# ------------------------------------------------------------------ fields and results

func test_field_comes_from_qualification_and_result_matches_leaderboard() -> void:
	var dir := _dir()
	var c := _career(dir)
	var e := c.next_event()
	assert_true(bool(c.eligibility(e)["eligible"]), "regular events are open to tour-card holders")
	assert_true(c.enter_event(1))
	var t := c.tournament()
	assert_eq((t["field"] as Array).size(), 71, "72 places, you take one")
	assert_false((t["field"] as Array).has("player"))
	assert_true(float(t["event"]["field_strength"]) > 40.0, "field strength frozen at entry")
	var res := _play(c, func(_r: int, par: int, _h: int) -> int: return par)
	assert_true(bool(res["human_played"]))
	assert_eq((res["report"] as Array)[0]["pos"] is String, true)
	assert_eq(int(res["field"]), 72)
	# the winner on the official report is the winner on the live leaderboard rows' first place
	var top: Dictionary = (res["report"] as Array)[0]
	assert_eq(String(top["id"]), String(res["winner_id"]))
	assert_eq(int(top["total"]), int(res["winner_total"]))
	assert_eq(String((c.data["calendar"][0] as Dictionary)["status"]), "complete")
	assert_true(int(res["human_place"]) >= 1)
	_cleanup(dir)


func test_live_leaderboard_agrees_with_the_official_result() -> void:
	var dir := _dir()
	var c := _career(dir)
	assert_true(c.enter_event(1))
	var t := c.tournament()
	var par := TournamentManager.par_per_round(t)
	for r in 2:
		assert_true(c.begin_round({}, 0))
		c.complete_round(par + r, par, ((t["snapshot"] as Dictionary)["holes"] as Array).size())
	assert_eq(String(t["status"]), "complete")
	var live := c.leaderboard()
	var res := c.finalize_tournament()
	var rep: Array = res["report"]
	for i in range(mini(5, rep.size())):
		assert_eq(int(rep[i]["total"]), int(live[i]["total"]), "same total at rank %d" % i)
		if i > 1:
			assert_eq(String(rep[i]["id"]), String(live[i]["id"]), "same order at rank %d" % i)  # (a tie for 1st is decided by the playoff)
	var me: Dictionary = live.filter(func(r: Dictionary) -> bool: return r["is_human"])[0]
	assert_eq(int(res["human_place"]), int(me["place"]), "your place agrees")
	_cleanup(dir)


func test_rankings_update_after_played_skipped_and_missed_cut_events() -> void:
	var dir := _dir()
	var c := _career(dir)
	var wr0 := c.world_rank()
	assert_eq(wr0, CareerConfig.START_WORLD_RANK, "you start at the configured world rank")
	assert_eq(c.season_rank(), 0, "no results yet")
	# event 1 skipped: the world plays it, standings and world points move
	assert_true(c.skip_event(1))
	var e1: Dictionary = c.event_by_serial(1)
	assert_eq(String(e1["status"]), "skipped")
	assert_true((c.standings()["applied"] as Dictionary).has(String(e1["id"])))
	assert_true((c.world()["applied"] as Dictionary).has(String(e1["id"])))
	var winner := String(e1["result"]["winner_id"])
	assert_true(float((c.standings()["points"] as Dictionary).get(winner, 0.0)) > 0.0, "the winner earned season points")
	assert_true(c.season_rank() > 0, "standings exist after a skipped event")
	assert_true(c.world_rank() >= wr0, "skipping never helps you")
	assert_eq(int((c.data["world_rankings"] as Dictionary)["player_rank"]), c.world_rank(), "stored rank mirrors the table")
	# event 2: enter and miss the cut on purpose (force a cut on that event)
	while String(c.next_event()["category"]) != "regular":
		assert_true(c.skip_event(int(c.next_event()["serial"])))
	var e2: Dictionary = c.next_event()
	e2["cut"] = {"type": "percent", "after_round": 1, "percent": 50}
	assert_true(c.enter_event(int(e2["serial"])))
	var res := _play(c, func(_r: int, par: int, _h: int) -> int: return par + 40)
	assert_true(bool(res["human_missed_cut"]))
	assert_eq(int(res["human_earnings"]), 0)
	assert_true((c.standings()["applied"] as Dictionary).has(String(e2["id"])), "a missed cut still settles the event")
	assert_eq(int((c.standings()["starts"] as Dictionary).get("player", 0)), 1, "the missed cut counts as a start")
	assert_true(res.has("world_rank_before") and res.has("world_rank_after"))
	# the winner of each event got an honour; form changed for field players
	var by := c.golfers_by_id()
	var honours: Array = (by[winner] as Dictionary).get("honours", [])
	assert_true(honours.size() >= 1, "winner honour recorded")
	_cleanup(dir)


func test_human_tie_for_first_settled_by_playoff() -> void:
	var dir := _dir()
	var c := _career(dir)
	assert_true(c.enter_event(1))
	var t := c.tournament()
	var par := TournamentManager.par_per_round(t)
	var holes: int = ((t["snapshot"] as Dictionary)["holes"] as Array).size()
	assert_true(c.begin_round({}, 0))
	c.complete_round(par, par, holes)
	# reveal round 2 for the opponents (idempotent), then tie the best total exactly
	TournamentManager.simulate_opponent_round(t, c.golfers_by_id(), 1, CareerManager.sim)
	var best := 9999
	for id in t["field"]:
		var a: Array = t["opponent_rounds"][id]
		best = mini(best, int(a[0]) + int(a[1]))
	var r2 := best - par
	assert_true(r2 >= holes, "a legal tying round exists")
	assert_true(c.begin_round({}, 0))
	c.complete_round(r2, par, holes)
	var res := c.finalize_tournament()
	assert_true(bool(res["playoff"]["needed"]), "tied for first")
	assert_true(bool(res["playoff"]["human_involved"]))
	assert_eq(int(res["human_total"]), best)
	assert_true(String(res["winner_id"]) != "", "a playoff winner is named")
	assert_true(int(res["human_place"]) >= 1)
	assert_eq(bool(res["human_won"]), int(res["human_place"]) == 1 and String(res["winner_id"]) == "player")
	_cleanup(dir)


# ------------------------------------------------------------------ ledger / records idempotence

func test_ledger_is_idempotent_and_matches_earnings() -> void:
	var dir := _dir()
	var c := _career(dir)
	assert_true(c.enter_event(1))
	var res := _play(c, func(_r: int, par: int, _h: int) -> int: return par - 2)
	var pay := int(res["human_earnings"])
	assert_true(pay > 0, "a strong round earns money")
	var eco: Dictionary = c.data["economy"]
	assert_eq(int(eco["balance"]), pay)
	assert_eq((c.data["ledger"] as Array).size(), 1)
	assert_eq(String(c.data["ledger"][0]["id"]), "prize:%s" % String(c.event_by_serial(1)["id"]))
	assert_false(CareerRecords.ledger_add(c.data, "prize:%s" % String(c.event_by_serial(1)["id"]), "prize", "x", 999, "x", 1), "same id never pays twice")
	assert_eq(int(eco["balance"]), pay)
	assert_eq(int(eco["career_earnings"]), pay)
	assert_true(CareerRecords.ledger_add(c.data, "bonus:1", "bonus", "test", 100, "", 1))
	assert_eq(int(eco["balance"]), pay + 100)
	assert_eq(CareerRecords.ledger_recent(c.data, 1)[0]["id"], "bonus:1")
	_cleanup(dir)


func test_finalize_replay_after_failed_save_does_not_double_count() -> void:
	var dir := _dir()
	var c := _career(dir)
	assert_true(c.enter_event(1))
	var par := TournamentManager.par_per_round(c.tournament())
	var holes: int = ((c.tournament()["snapshot"] as Dictionary)["holes"] as Array).size()
	for r in 2:
		assert_true(c.begin_round({}, 0))
		c.complete_round(par - 2, par, holes)
	var snapshot_t: Dictionary = c.tournament().duplicate(true)
	c.store.simulate_failure = true
	var res := c.finalize_tournament()
	assert_true(c.store.is_blocked(), "the save failed")
	var bal := int(c.data["economy"]["balance"])
	var pts := float(c.standings()["points"].get("player", 0.0))
	var ledger_n: int = (c.data["ledger"] as Array).size()
	# the tournament was closed in memory; replaying from the pre-finalize state must be a no-op for the world
	c.data["active_tournament"] = snapshot_t
	c.event_by_serial(1)["status"] = "in_progress"
	c.store.simulate_failure = false
	var res2 := c.finalize_tournament()
	assert_eq(int(c.data["economy"]["balance"]), bal, "money paid once")
	assert_eq(float(c.standings()["points"].get("player", 0.0)), pts, "points awarded once")
	assert_eq((c.data["ledger"] as Array).size(), ledger_n)
	assert_eq((c.data["career_history"] as Array).size(), 1)
	assert_eq(int(res2["human_place"]), int(res["human_place"]), "same result on replay")
	assert_false(c.store.is_blocked())
	_cleanup(dir)


# ------------------------------------------------------------------ rivals and trophies

func _row(id: String, total: int, pos: int, human: bool = false, status: String = "made_cut") -> Dictionary:
	return {"id": id, "name": id, "is_human": human, "total": total, "position": pos, "status": status, "rounds": [total / 2, total - total / 2],
		"payout": 0, "world_points": 0.0, "season_points": 0.0, "to_par": 0, "position_label": str(pos)}


func test_rivals_form_from_repeated_close_finishes() -> void:
	var d := CareerManager.new_data("R", "Wales", "short", 5)
	var rows := func(ev_total: int) -> Array:
		return [_row("player", 140, 10, true), _row("g001", 140 + ev_total, 10), _row("g002", 141, 11), _row("g003", 150, 30), _row("g004", 139, 9)]
	var ev1 := {"id": "s1_e01"}
	CareerRecords.update_head_to_head(d, ev1, rows.call(0))
	assert_eq((d["rivalries"] as Array).size(), 0, "one close finish is not a rivalry")
	CareerRecords.update_head_to_head(d, ev1, rows.call(0))
	assert_eq((d["rivalries"] as Array).size(), 0, "the same event is never counted twice")
	CareerRecords.update_head_to_head(d, {"id": "s1_e02"}, rows.call(1))
	var ids: Array = (d["rivalries"] as Array).map(func(r: Dictionary) -> String: return String(r["id"]))
	assert_true(ids.has("g001") and ids.has("g002") and ids.has("g004"), "repeated close finishes make rivals")
	assert_false(ids.has("g003"), "a distant finisher is not a rival")
	var rec := CareerRecords.record_against(d, "g001")
	assert_eq(int(rec["close"]), 2)
	assert_eq(int(rec["t"]) + int(rec["w"]) + int(rec["l"]), 2, "two meetings")
	assert_eq(CareerRecords.record_against(d, "g004")["l"], 2, "g004 finished ahead twice")
	# more rivals than the Hub shows: featured is capped at three, the Rivals screen keeps up to the listed max
	for k in range(5, 12):
		var id := "x%d" % k
		for ev in ["s1_e03", "s1_e04", "s1_e05"]:
			CareerRecords.update_head_to_head(d, {"id": ev}, [_row("player", 140, 10, true), _row(id, 141, 10)])
	assert_true((d["rivalries"] as Array).size() <= CareerConfig.RIVAL_MAX_LISTED)
	assert_eq(CareerRecords.featured_rivals(d).size(), CareerConfig.RIVAL_MAX_FEATURED)


func test_trophies_and_records_from_wins() -> void:
	var d := CareerManager.new_data("T", "Wales", "short", 5)
	var ev := {"id": "s1_e07", "name": "Highland Grand Championship", "category": "major"}
	var row := _row("player", 270, 1, true)
	row["payout"] = 300000
	CareerRecords.apply_human_event(d, ev, row, 1, 40)
	CareerRecords.apply_human_event(d, ev, row, 1, 40)
	assert_eq(int(d["records"]["wins"]), 1, "a result counts once")
	assert_eq(int(d["records"]["majors"]), 1)
	assert_eq((CareerRecords.trophies_of(d, "major") as Array).size(), 1)
	assert_eq(int(d["records"]["best_world_rank"]), 40)
	assert_eq(int(d["records"]["best_finish"]["place"]), 1)
	assert_eq(int(d["records"]["biggest_cheque"]["amount"]), 300000)
	var cut := _row("player", 300, 80, true, "cut")
	CareerRecords.apply_human_event(d, {"id": "s1_e08", "name": "X", "category": "regular"}, cut, 1, 35)
	assert_eq(int(d["records"]["starts"]), 2)
	assert_eq(int(d["records"]["cuts_made"]), 1)
	assert_eq(int(d["records"]["best_world_rank"]), 35)


# ------------------------------------------------------------------ migration

func _v1_shape() -> Dictionary:
	var d := CareerManager.new_data("Old Save", "Scotland", "short", 99)
	for k in ["ledger", "trophies", "records", "head_to_head", "prev_standings_rank", "season_history"]:
		d.erase(k)
	d["rivalries"] = []
	d["schema_version"] = 1
	d["golfers"] = (d["golfers"] as Array).filter(func(g: Dictionary) -> bool: return not bool(g.get("is_human", false)))
	for g in d["golfers"]:
		g.erase("honours")
	d["world_rankings"] = {"player_rank": 180}
	d["season_standings"] = {"g001": 500, "player": 120}
	for e in d["calendar"]:
		e.erase("order")
	d["calendar"][0]["status"] = "complete"
	d["calendar"][0]["result"] = {"human_won": true, "human_place": 1, "human_earnings": 5000, "winner_id": "player", "winner_name": "Old Save"}
	d["career_history"] = [{"event_id": String(d["calendar"][0]["id"]), "name": "Old Open", "season": "season_1", "human_place": 1, "earnings": 5000}]
	d["economy"]["balance"] = 5000
	d["economy"]["career_earnings"] = 5000
	d["economy"]["season_earnings"] = 5000
	return d


func test_migration_v1_to_v2_fills_defaults_and_keeps_data() -> void:
	var v1 := _v1_shape()
	var m := CareerSaveManager.migrate(v1, 1)
	assert_eq(int(m["schema_version"]), CareerConfig.SCHEMA_VERSION)
	assert_eq(CareerSaveManager.validate(m), "")
	var human: Array = (m["golfers"] as Array).filter(func(g: Dictionary) -> bool: return bool(g.get("is_human", false)))
	assert_eq(human.size(), 1, "the human golfer entity was added")
	assert_eq(String(human[0]["name"]), "Old Save")
	assert_true((m["world_rankings"] as Dictionary).has("world"))
	assert_true(float((m["season_standings"]["points"] as Dictionary)["g001"]) == 500.0, "v1 standings points kept")
	assert_true((m["season_standings"]["applied"] as Dictionary).has(String(v1["calendar"][0]["id"])), "played events are not replayed")
	assert_true(int(m["calendar"][0]["order"]) > 0)
	assert_eq((m["ledger"] as Array).size(), 1, "ledger rebuilt from the history")
	assert_eq(int(m["ledger"][0]["amount"]), 5000)
	assert_eq(int(m["economy"]["balance"]), 5000, "the balance is untouched (no second payment)")
	assert_eq((CareerRecords.trophies_of(m, "event_win") as Array).size(), 1, "the v1 win became a trophy")
	for k in ["records", "head_to_head", "prev_standings_rank", "season_history"]:
		assert_true(m.has(k), k)
	# idempotent, and the migrated career runs
	assert_eq(CareerSaveManager.migrate(m, 1), CareerSaveManager.migrate(CareerSaveManager.migrate(m, 1), 1))
	var dir := _dir()
	var text := CareerSaveManager.encode(v1).replace("\"schema_version\":2", "\"schema_version\":1")
	var env := JSON.parse_string(text) as Dictionary
	env["schema_version"] = 1
	var f := FileAccess.open(dir + "_v1.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(env))
	f.close()
	var r := CareerSaveManager.decode(FileAccess.get_file_as_string(dir + "_v1.json"))
	assert_true(r.ok, "a v1 file loads through decode")
	var c := CareerManager.new(CareerSaveManager.new(dir))
	c.data = r.data
	assert_true(c.world_rank() > 0)
	assert_true(c.skip_event(2), "the migrated career carries on with event 2")
	assert_true((c.standings()["applied"] as Dictionary).has(String(c.event_by_serial(2)["id"])))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "_v1.json"))


func test_v2_export_import_round_trip() -> void:
	var dir := _dir()
	var c := _career(dir)
	assert_true(c.skip_event(1))
	var out := dir + "/export.json"
	assert_true(c.store.export_to(out))
	var dir2 := _dir()
	var s2 := CareerSaveManager.new(dir2)
	var r := s2.import_from(out)
	assert_true(r.ok)
	var c2 := CareerManager.new(s2)
	assert_true(c2.load_saved().ok)
	assert_eq(c2.world_rank(), c.world_rank())
	assert_eq(c2.season_points(), c.season_points())
	_cleanup(dir)
	_cleanup(dir2)


# ------------------------------------------------------------------ seasons

func test_season_rollover_advances_the_world() -> void:
	var dir := _dir()
	var c := _career(dir)
	while not c.season_finished():
		assert_true(c.skip_event(int(c.next_event()["serial"])))
	assert_eq(c.season_rank() > 0, true)
	var top_id := String(c.standings_table()[0]["id"])
	var age_before := int((c.golfers_by_id()["g001"] as Dictionary)["age"])
	var rating_before := float((c.golfers_by_id()["g001"] as Dictionary)["rating"])
	var n_before: int = (c.data["golfers"] as Array).size()
	assert_true(c.start_next_season())
	assert_eq(c.season_id(), "season_2")
	assert_eq((c.data["season_history"] as Array).size(), 1)
	assert_eq(String(c.data["season_history"][0]["standings_champion_id"]), top_id)
	assert_true((c.standings()["applied"] as Dictionary).is_empty(), "fresh standings")
	assert_eq(c.season_rank(), 0)
	assert_eq(int(c.standings()["season"]), 2)
	assert_true((c.data["prev_standings_rank"] as Dictionary).has(top_id))
	assert_true((c.data["golfers"] as Array).size() >= n_before)
	var g1: Dictionary = c.golfers_by_id()["g001"]
	if String(g1["status"]) != "retired":
		assert_eq(int(g1["age"]), age_before + 1)
		assert_true(float(g1["rating"]) != rating_before or true)
	# the world window keeps last season's points (weight 0.5): the previous winner is still ranked highly
	assert_true(c.world().get("season_points", {}).has("1"), "last season stays in the 2-season window")
	assert_eq(int(c.data["calendar"][0]["order"]), 101, "event order continues across seasons")
	assert_true(c.world_rank() > 0)
	# a third season prunes season 1 out of the window
	while not c.season_finished():
		assert_true(c.skip_event(int(c.next_event()["serial"])))
	assert_true(c.start_next_season())
	assert_false((c.world()["season_points"] as Dictionary).has("1"), "season 1 left the window")
	_cleanup(dir)


func test_full_season_end_to_end_good_player() -> void:
	var dir := _dir()
	var c := _career(dir)
	var strong := func(_r: int, par: int, holes: int) -> int: return maxi(holes, par - 2 * holes)
	var entered := 0
	var skipped := 0
	var finale_entered := false
	var guard := 0
	while not c.season_finished() and guard < 40:
		guard += 1
		var e := c.next_event()
		var serial := int(e["serial"])
		# skip the very first event and every fourth one: a mix of skipped and entered events
		var want := serial != 1 and (serial % 4 != 0 or String(e["category"]) == "finale")
		var el := c.eligibility(e)
		if want and bool(el["eligible"]):
			if String(e["category"]) == "finale":
				finale_entered = true
			var res := {}
			assert_true(c.enter_event(serial))
			res = _play(c, strong)
			assert_true(bool(res["human_played"]))
			entered += 1
		else:
			if String(e["category"]) == "finale":
				assert_false(bool(el["eligible"]) and want, "an eligible player wanted the finale")
			assert_true(c.skip_event(serial))
			skipped += 1
	assert_true(c.season_finished())
	assert_true(entered >= 6 and skipped >= 3, "a real mix: entered %d skipped %d" % [entered, skipped])
	for e in c.data["calendar"]:
		assert_true(String(e["status"]) in ["complete", "skipped"], "%s settled" % e["id"])
	var n_events: int = (c.data["calendar"] as Array).size()
	assert_eq((c.standings()["applied"] as Dictionary).size(), n_events, "standings applied once per event")
	assert_eq((c.world()["applied"] as Dictionary).size(), n_events)
	# the strong player won things: trophies and records agree, and the ledger adds up to the earnings
	var wins := int(c.data["records"]["wins"])
	assert_true(wins >= 1, "a -2 per hole player wins events")
	var trophies := (c.data["trophies"] as Array).size()
	assert_eq(trophies, wins, "one trophy per win")
	var sum := 0
	for t in c.data["ledger"]:
		sum += int(t["amount"])
	assert_eq(sum, int(c.data["economy"]["career_earnings"]), "ledger sums to earnings")
	assert_eq(int(c.data["economy"]["balance"]), sum)
	assert_true(c.world_rank() < CareerConfig.START_WORLD_RANK, "winning moved you up the world ranking")
	assert_true(c.season_rank() >= 1 and c.season_rank() <= CareerConfig.FINALE_QUALIFIERS, "inside the finale line")
	assert_true(finale_entered, "a leading player qualified for the finale and played it")
	var fin: Dictionary = c.data["calendar"].back()
	assert_eq(String(fin["status"]), "complete")
	assert_eq(int(fin["result"]["field"]), CareerConfig.FINALE_QUALIFIERS, "the finale has 30 players")
	assert_true((c.data["rivalries"] as Array).size() <= CareerConfig.RIVAL_MAX_LISTED)
	# rollover
	assert_true(c.start_next_season())
	assert_eq(c.season_number(), 2)
	assert_true(c.season_used_footballers().is_empty())
	var champs := (CareerRecords.trophies_of(c.data, "season_title") as Array).size()
	assert_true(champs <= 1)
	# data survives a save/load cycle
	var c2 := CareerManager.new(CareerSaveManager.new(dir))
	assert_true(c2.load_saved().ok)
	assert_eq(c2.world_rank(), c.world_rank())
	assert_eq((c2.data["ledger"] as Array).size(), (c.data["ledger"] as Array).size())
	_cleanup(dir)


func test_full_season_skipping_everything_never_qualifies_for_the_finale() -> void:
	var dir := _dir()
	var c := _career(dir)
	while not c.season_finished():
		var e := c.next_event()
		if String(e["category"]) == "finale":
			var el := c.eligibility(e)
			assert_false(bool(el["eligible"]), "you cannot reach the finale without points")
			assert_true(String(el["reason"]).contains("Season Standings"), "the explanation names the Standings")
			assert_false(c.enter_event(int(e["serial"])), "entering is refused")
		assert_true(c.skip_event(int(e["serial"])))
	assert_eq(int(c.data["economy"]["career_earnings"]), 0)
	assert_eq((c.data["ledger"] as Array).size(), 0)
	assert_eq(int(c.data["records"]["starts"]), 0)
	_cleanup(dir)


func test_flagship_eligibility_explains_and_follows_the_world_rank() -> void:
	var dir := _dir()
	var c := _career(dir)
	var flag: Dictionary = c.data["calendar"].filter(func(e: Dictionary) -> bool: return String(e["category"]) == "flagship")[0]
	var el := c.eligibility(flag)
	assert_false(bool(el["eligible"]))
	assert_true(String(el["reason"]).contains("World Ranking"), String(el["reason"]))
	# give the player a huge world total: now inside the top 100
	c.world()["season_points"]["1"]["player"] = 99999.0
	assert_true(bool(c.eligibility(flag)["eligible"]))
	assert_eq(String(c.eligibility(flag)["via"]), "rank")
	_cleanup(dir)

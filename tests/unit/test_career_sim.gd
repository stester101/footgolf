extends TestCase
## Career opponent world: simulation, cuts, rankings, qualification, evolution. Pure logic, seeded.

const SEED := 424242


func _roster() -> Array:
	var f := FileAccess.open("res://career/data/golfer_roster.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var out: Array = []
	for g in d["golfers"]:
		var c: Dictionary = g.duplicate(true)
		c["form"] = 0.0
		c["injured_until"] = 0
		c["status"] = "active"
		c["honours"] = []
		out.append(c)
	return out


func _event(id: String = "e1", cat: String = "regular", rounds: int = 2, cut: Dictionary = {"type": "none"}, size: int = 72) -> Dictionary:
	return {"id": id, "category": cat, "name": id, "course_id": "starter", "rounds": rounds, "cut": cut,
		"purse": CareerConfig.PURSE[cat], "field_size": size, "order": 1}


func _course() -> Dictionary:
	return {"par": 34, "holes": 9, "difficulty": 0.0}


# ---------------------------------------------------------------- simulation
func test_round_deterministic_and_event_specific() -> void:
	var golfers := _roster()
	var a := OpponentSimulation.simulate_round(golfers[10], _course(), _event("e1"), 0, SEED)
	var b := OpponentSimulation.simulate_round(golfers[10], _course(), _event("e1"), 0, SEED)
	assert_eq(a, b, "same inputs same score")
	var differing := 0
	for i in range(40):
		var x := OpponentSimulation.simulate_round(golfers[i], _course(), _event("e1"), 0, SEED)
		var y := OpponentSimulation.simulate_round(golfers[i], _course(), _event("e2"), 0, SEED)
		var z := OpponentSimulation.simulate_round(golfers[i], _course(), _event("e1"), 1, SEED)
		if x["strokes"] != y["strokes"] or x["strokes"] != z["strokes"]:
			differing += 1
	assert_true(differing > 25, "other event/round gives different draws (%d)" % differing)


func test_restart_safe_event() -> void:
	var golfers := _roster().slice(0, 72)
	var ev := _event("restart", "regular", 2)
	var r1 := OpponentSimulation.simulate_event_field(golfers, ev, _course(), SEED)
	var r2 := OpponentSimulation.simulate_event_field(golfers.duplicate(true), ev, _course(), SEED)
	assert_eq(r1, r2, "re-simulation identical")
	var partial := OpponentSimulation.simulate_event_field(golfers, ev, _course(), SEED, [], 1)
	var after_r1 := {}
	for e in partial["leaderboard"]:
		assert_eq(e["rounds"].size(), 1, "only round 1 revealed")
		after_r1[e["id"]] = e["rounds"][0]
	for e in r1["leaderboard"]:
		assert_eq(e["rounds"][0], after_r1[e["id"]], "round 1 score never rerolls")


func test_ratings_form_difficulty_adaptive() -> void:
	var strong := {"id": "s", "rating": 95.0, "consistency": 0.6, "form": 0.0}
	var weak := {"id": "w", "rating": 45.0, "consistency": 0.6, "form": 0.0}
	var tot_s := 0
	var tot_w := 0
	for i in range(60):
		tot_s += OpponentSimulation.simulate_round(strong, _course(), _event("x%d" % i), 0, SEED)["strokes"]
		tot_w += OpponentSimulation.simulate_round(weak, _course(), _event("x%d" % i), 0, SEED)["strokes"]
	assert_true(tot_s < tot_w - 60, "strong golfer scores clearly lower")
	var hot := strong.duplicate()
	hot["form"] = 1.0
	var base := OpponentSimulation.mean_per_hole(strong, "regular", _course(), 70.0, 0.0)
	assert_true(OpponentSimulation.mean_per_hole(hot, "regular", _course(), 70.0, 0.0) < base, "form lowers score")
	assert_true(OpponentSimulation.mean_per_hole(strong, "major", _course(), 70.0, 0.0) > base, "major harder")
	assert_true(OpponentSimulation.mean_per_hole(strong, "regular", _course(), 90.0, 0.0) > base, "stronger field harder")
	var capped := OpponentSimulation.mean_per_hole(strong, "regular", _course(), 70.0, 5.0) - base
	assert_true(absf(capped - CareerConfig.ADAPTIVE_MAX_ADJUST_PER_HOLE) < 0.0001, "adaptive hook capped")
	assert_eq(OpponentSimulation.mean_per_hole(strong, "regular", _course(), 70.0, 0.0), base, "adaptive default is 0")


func test_calibration_winning_score() -> void:
	var golfers := _roster()
	var wins: Array = []
	for i in range(30):
		var r := OpponentSimulation.simulate_event_field(golfers.slice(0, 72), _event("cal%d" % i, "regular", 2), _course(), SEED)
		wins.append(r["leaderboard"][0]["to_par"])
	var avg := 0.0
	for w in wins:
		avg += float(w)
	avg /= wins.size()
	note("2-round regular winner to par (par 34 x 9 holes, roster top 72): avg %.1f min %d max %d" % [avg, wins.min(), wins.max()])
	assert_true(avg < 0.0 and avg > -25.0, "winning score plausible (%.1f)" % avg)


# ---------------------------------------------------------------- cuts, positions, awards
func test_no_cut_event() -> void:
	var golfers := _roster().slice(0, 72)
	var r := OpponentSimulation.simulate_event_field(golfers, _event("nc", "regular", 2), _course(), SEED)
	assert_true(r["cut"].is_empty(), "no cut info")
	assert_eq(r["leaderboard"].size(), 72)
	for e in r["leaderboard"]:
		assert_eq(e["status"], "made_cut")
		assert_eq(e["rounds"].size(), 2)


func test_percent_cut_with_ties() -> void:
	var golfers := _roster().slice(0, 60)
	var ev := _event("cut1", "flagship", 3, {"type": "percent", "after_round": 2, "percent": 50}, 60)
	var r := OpponentSimulation.simulate_event_field(golfers, ev, _course(), SEED)
	var made := 0
	var line: int = r["cut"]["line_total"]
	var seen_cut := false
	for e in r["leaderboard"]:
		var after2 := int(e["rounds"][0]) + int(e["rounds"][1])
		if e["status"] == "made_cut":
			made += 1
			assert_false(seen_cut, "no made-cut golfer below a cut golfer")
			assert_eq(e["rounds"].size(), 3)
			assert_true(after2 <= line, "made cut at or inside the line")
		else:
			seen_cut = true
			assert_eq(e["rounds"].size(), 2, "cut golfers have 2 rounds only")
			assert_true(after2 > line, "missed cut is outside the line")
	assert_true(made >= 30, "at least 50%% make it incl. ties (%d)" % made)
	assert_eq(r["cut"]["made_cut"], made)


func test_top_n_cut_ties_exact() -> void:
	var ev := _event("tn", "major", 4, {"type": "top_n", "after_round": 2, "n": 3}, 50)
	var r := OpponentSimulation.simulate_event_field(_roster().slice(0, 50), ev, _course(), SEED)
	var line: int = r["cut"]["line_total"]
	var better := 0
	var at_line := 0
	var made := 0
	for e in r["leaderboard"]:
		var t := int(e["rounds"][0]) + int(e["rounds"][1])
		if t < line:
			better += 1
		elif t == line:
			at_line += 1
		if e["status"] == "made_cut":
			made += 1
	assert_true(better < 3 and better + at_line >= 3, "line is the 3rd best total")
	assert_eq(made, better + at_line, "all golfers tied on the line survive")


func test_positions_ties_and_payouts() -> void:
	var ev := _event("pay", "regular", 2)
	var r := OpponentSimulation.simulate_event_field(_roster().slice(0, 72), ev, _course(), SEED)
	var lb: Array = r["leaderboard"]
	for i in range(lb.size()):
		var better := 0
		for e in lb:
			if int(e["total"]) < int(lb[i]["total"]):
				better += 1
		assert_eq(int(lb[i]["position"]), better + 1, "position = 1 + strictly better (ties share)")
	var paid := 0
	for e in lb:
		paid += int(e["payout"])
	assert_true(paid <= int(ev["purse"]) and paid > int(ev["purse"]) - 2 * lb.size(), "purse paid out (%d of %d)" % [paid, ev["purse"]])
	var prev_pos := 0
	var prev_pay := 1 << 60
	for e in lb:
		if int(e["position"]) > prev_pos:
			assert_true(int(e["payout"]) <= prev_pay, "payout never increases with worse position")
		prev_pos = int(e["position"])
		prev_pay = int(e["payout"])
	assert_true(float(lb[0]["world_points"]) > float(lb[lb.size() - 1]["world_points"]))
	assert_true(float(lb[0]["season_points"]) <= float(CareerConfig.SEASON_WINNER_POINTS["regular"]) + 0.01)
	assert_true(r["winner_id"] != "", "winner determined (playoff for ties)")


func test_cut_players_get_no_money() -> void:
	var ev := _event("cm", "flagship", 3, {"type": "percent", "after_round": 2, "percent": 50}, 60)
	var r := OpponentSimulation.simulate_event_field(_roster().slice(0, 60), ev, _course(), SEED)
	for e in r["leaderboard"]:
		if e["status"] == "cut":
			assert_eq(int(e["payout"]), 0)
			assert_eq(float(e["world_points"]), 0.0)


func test_human_rounds_incomplete_and_extremes() -> void:
	var golfers := _roster().slice(0, 20)
	golfers.append({"id": "player", "name": "Me", "nationality": "England", "is_human": true})
	var ev := _event("hum", "regular", 2)
	var partial := OpponentSimulation.simulate_event_field(golfers, ev, _course(), SEED, [34])
	assert_false(partial["complete"], "human has not finished")
	assert_eq(partial["leaderboard"][partial["leaderboard"].size() - 1]["id"], "player", "incomplete listed last")
	var full := OpponentSimulation.simulate_event_field(golfers, ev, _course(), SEED, [20, 20])
	assert_true(full["complete"])
	assert_eq(full["winner_id"], "player")
	var bad := OpponentSimulation.simulate_event_field(golfers, ev, _course(), SEED, [60, 60])
	assert_eq(bad["leaderboard"][bad["leaderboard"].size() - 1]["id"], "player")


func test_human_cut_exits_but_event_completes() -> void:
	var golfers := _roster().slice(0, 40)
	golfers.append({"id": "player", "name": "Me", "nationality": "England", "is_human": true})
	var ev := _event("hcut", "major", 4, {"type": "percent", "after_round": 2, "percent": 50}, 41)
	var r := OpponentSimulation.simulate_event_field(golfers, ev, _course(), SEED, [55, 55])
	var me := {}
	for e in r["leaderboard"]:
		if e["id"] == "player":
			me = e
	assert_eq(me["status"], "cut")
	assert_eq(me["rounds"].size(), 2)
	assert_true(r["complete"], "the AI event completes for the report")
	assert_true(r["winner_id"] != "" or r["playoff"]["needed"])


func test_sudden_death() -> void:
	var golfers := _roster().slice(0, 4)
	var ev := _event("po")
	var a := OpponentSimulation.sudden_death(golfers, ev, _course(), SEED)
	assert_eq(a, OpponentSimulation.sudden_death(golfers, ev, _course(), SEED), "playoff deterministic")
	var total := 0
	for grp in a["groups"]:
		total += grp.size()
	assert_eq(total, 4, "everyone ranked")
	assert_eq(a["groups"][0].size(), 1, "single winner")
	assert_eq(a["winner_id"], a["groups"][0][0])
	var found := false
	for i in range(80):
		var r := OpponentSimulation.simulate_event_field(_roster().slice(0, 30), _event("pt%d" % i, "regular", 1), {"par": 4, "holes": 1, "difficulty": 0.0}, SEED)
		if r["playoff"]["needed"]:
			found = true
			assert_true(r["playoff"]["resolved"], "AI-only tie resolved automatically")
			assert_true(r["winner_id"] != "")
			assert_eq(int(r["leaderboard"][0]["position"]), 1)
			assert_true(int(r["leaderboard"][1]["position"]) > 1, "playoff losers no longer share 1st")
			break
	assert_true(found, "a 1-hole event produced an AI tie for first")


# ---------------------------------------------------------------- rankings
func test_world_window_and_age_weights() -> void:
	var golfers := _roster().slice(0, 5)
	var w := RankingManager.new_world()
	RankingManager.add_baseline(w, "g001", 1, 1)
	var b := snappedf(CareerConfig.baseline_points(1), 0.01)
	assert_eq(RankingManager.world_points(w, "g001", 1), b)
	assert_eq(RankingManager.world_points(w, "g001", 2), b * 0.5, "half weight next season")
	assert_eq(RankingManager.world_points(w, "g001", 3), 0.0, "outside the two-season window")
	var res := {"event_id": "ev1", "category": "major", "leaderboard": [{"id": "g002", "world_points": 1000.0, "season_points": 1000.0, "status": "made_cut"}]}
	assert_true(RankingManager.apply_event_to_world(w, res, 2))
	assert_false(RankingManager.apply_event_to_world(w, res, 2), "applying twice is a no-op")
	assert_eq(RankingManager.world_points(w, "g002", 2), 1000.0)
	assert_eq(RankingManager.world_points(w, "g002", 3), 500.0)
	assert_eq(RankingManager.world_points(w, "g002", 4), 0.0)
	assert_eq(RankingManager.world_table(w, golfers, 2).size(), 5)
	RankingManager.prune_world(w, 3)
	assert_false(w["season_points"].has("1"), "season 1 pruned")


func test_world_table_ties_deterministic_and_baseline() -> void:
	var golfers := _roster()
	var w := RankingManager.init_world(golfers, 1)
	var t1 := RankingManager.world_table(w, golfers, 1)
	assert_eq(t1, RankingManager.world_table(w, golfers.duplicate(true), 1))
	for i in range(20):
		assert_eq(t1[i]["id"], golfers[i]["id"], "baseline order follows initial_rank")
	golfers.append({"id": "player", "name": "Me", "is_human": true, "initial_rank": 180, "status": "active"})
	RankingManager.add_baseline(w, "player", 180, 1)
	var pr: int = RankingManager.rank_map(RankingManager.world_table(w, golfers, 1))["player"]
	assert_eq(pr, 180, "human wins an exact baseline tie so the start rank is 180")


func test_season_standings_reset_and_top30() -> void:
	var golfers := _roster()
	var st := RankingManager.new_standings(1)
	var r := OpponentSimulation.simulate_event_field(golfers.slice(0, 72), _event("s1", "regular", 2), _course(), SEED)
	assert_true(RankingManager.apply_event_to_standings(st, r))
	assert_false(RankingManager.apply_event_to_standings(st, r), "idempotent")
	var tab := RankingManager.standings_table(st, golfers)
	assert_eq(tab[0]["id"], r["winner_id"], "winner leads the standings")
	assert_eq(tab[0]["wins"], 1)
	assert_eq(QualificationManager.finale_qualifiers(tab).size(), 30)
	assert_true(tab[29]["in_finale"] and not tab[30]["in_finale"])
	for row in RankingManager.standings_table(RankingManager.new_season_standings(2), golfers):
		assert_eq(row["points"], 0.0, "standings reset")
	assert_true(float(tab[0]["points"]) > 0.0)


func test_finale_not_in_season_points() -> void:
	var ev := _event("fin", "finale", 3, {"type": "none"}, 30)
	var r := OpponentSimulation.simulate_event_field(_roster().slice(0, 30), ev, _course(), SEED)
	assert_eq(float(r["leaderboard"][0]["season_points"]), 0.0)
	assert_true(float(r["leaderboard"][0]["world_points"]) > 0.0)
	assert_eq(r["field_size"], 30)


# ---------------------------------------------------------------- qualification
func _ctx(golfers: Array, season: int = 2, prev: Dictionary = {}) -> Dictionary:
	var w := RankingManager.init_world(golfers, season)
	return QualificationManager.build_context(w, RankingManager.new_standings(season), golfers, season, prev)


func test_qualification_explanations() -> void:
	var golfers := _roster()
	var ctx := _ctx(golfers)
	var flag := _event("f1", "flagship", 3, {"type": "none"}, 60)
	var major := _event("m1", "major", 4, {"type": "none"}, 96)
	var c1 := QualificationManager.check(golfers[49], flag, ctx)
	assert_true(c1["eligible"] and c1["via"] == "rank")
	assert_true(str(c1["reason"]).contains("World Ranking 50"), c1["reason"])
	var c2 := QualificationManager.check(golfers[119], flag, ctx)
	assert_false(c2["eligible"])
	assert_true(str(c2["reason"]).contains("World Ranking 120") and str(c2["reason"]).contains("Top 100"), c2["reason"])
	var c3 := QualificationManager.check(golfers[79], major, ctx)
	assert_false(c3["eligible"], "rank 80 outside top 75")
	assert_true(str(c3["requirement"]).contains("Top 75"))
	golfers[79]["honours"].append({"season": 1, "category": "major", "event_id": "old"})
	var c4 := QualificationManager.check(golfers[79], major, _ctx(golfers))
	assert_true(c4["eligible"] and c4["via"] == "exemption", c4["reason"])
	assert_true(str(c4["reason"]).contains("major champion"))
	golfers[79]["honours"][0]["season"] = -10
	assert_false(QualificationManager.check(golfers[79], major, _ctx(golfers))["eligible"], "old major win expired")
	var c5 := QualificationManager.check(golfers[79], major, _ctx(golfers, 2, {"g080": 12}))
	assert_true(c5["eligible"] and str(c5["reason"]).contains("12th"), c5["reason"])
	golfers[200]["tour_card"] = false
	assert_false(QualificationManager.check(golfers[200], _event("r1"), ctx)["eligible"], "needs a tour card")
	golfers[3]["injured_until"] = 5
	var inj := QualificationManager.check(golfers[3], flag, _ctx(golfers))
	assert_false(inj["eligible"])
	assert_true(str(inj["reason"]).contains("injured"))


func test_finale_eligibility_top30() -> void:
	var golfers := _roster()
	var w := RankingManager.init_world(golfers, 1)
	var st := RankingManager.new_standings(1)
	st["points"]["g100"] = 500.0
	var ctx := QualificationManager.build_context(w, st, golfers, 1)
	var fin := _event("fin", "finale", 3, {"type": "none"}, 30)
	var c := QualificationManager.check(golfers[99], fin, ctx)
	assert_true(c["eligible"] and str(c["reason"]).contains("1st"), c["reason"])
	var c2 := QualificationManager.check(golfers[200], fin, ctx)
	assert_false(c2["eligible"])
	assert_true(str(c2["reason"]).contains("Requires top 30"), c2["reason"])
	var field := QualificationManager.build_field(fin, golfers, ctx)
	assert_eq(field["field"].size(), 30)
	assert_true(field["ids"].has("g100"))


func test_field_construction() -> void:
	var golfers := _roster()
	golfers.append({"id": "player", "name": "Me", "nationality": "England", "is_human": true, "initial_rank": 180, "status": "active"})
	var w := RankingManager.init_world(golfers, 1)
	RankingManager.add_baseline(w, "player", 180, 1)
	var ctx := QualificationManager.build_context(w, RankingManager.new_standings(1), golfers, 1)
	for cat in ["regular", "flagship", "major", "finale"]:
		var ev := _event("fc_" + cat, cat, CareerConfig.ROUNDS[cat], {"type": "none"}, int(CareerConfig.FIELD_SIZE[cat]))
		var f := QualificationManager.build_field(ev, golfers, ctx)
		assert_eq(f["field"].size(), int(CareerConfig.FIELD_SIZE[cat]), "%s field fills to size" % cat)
		var seen := {}
		for id in f["ids"]:
			assert_false(seen.has(id), "no duplicate entries")
			seen[id] = true
	assert_true(QualificationManager.build_field(_event("fr", "regular", 2), golfers, ctx)["player_in"], "tour-card player is in a regular field")
	var flag := QualificationManager.build_field(_event("ff", "flagship", 3, {"type": "none"}, 60), golfers, ctx)
	assert_false(flag["player_in"], "rank 180 player is not in a flagship")
	assert_false(str(flag["player_check"]["reason"]).is_empty())
	assert_true(flag["ids"].has("g001") and not flag["ids"].has("g090"))
	var maj := QualificationManager.build_field(_event("fm", "major", 4, {"type": "none"}, 96), golfers, ctx)
	assert_true(maj["invited"].size() > 0, "majors top up with invitations beyond the top 75")


# ---------------------------------------------------------------- evolution
func test_form_updates_and_honours() -> void:
	var golfers := _roster().slice(0, 72)
	var ev := _event("fm1", "regular", 2)
	ev["order"] = 3
	var r := OpponentSimulation.simulate_event_field(golfers, ev, _course(), SEED)
	WorldEvolution.update_after_event(golfers, r, ev, SEED, 1)
	var by_id := {}
	for g in golfers:
		by_id[g["id"]] = g
	assert_true(float(by_id[r["winner_id"]]["form"]) > 0.25, "winner's form rises")
	assert_true(float(by_id[r["leaderboard"][71]["id"]]["form"]) < 0.0, "last place form falls")
	assert_eq(by_id[r["winner_id"]]["honours"].size(), 1)
	var snap := golfers.duplicate(true)
	WorldEvolution.update_after_event(golfers, r, ev, SEED, 1)
	assert_eq(golfers, snap, "second application is a no-op (restart safety)")
	for g in golfers:
		assert_true(absf(float(g["form"])) <= 1.0)
		assert_true(int(g["injured_until"]) == 0 or int(g["injured_until"]) <= 3 + 1 + CareerConfig.INJURY_MAX_EVENTS, "injury bounded")


func test_multi_season_evolution() -> void:
	var golfers := _roster()
	var world := RankingManager.init_world(golfers, 1)
	var initial_ids: Array = golfers.map(func(g): return g["id"])
	var ever_retired := {}
	var entrants_total := 0
	for season in range(2, 22):
		var rep := WorldEvolution.advance_season(golfers, season, SEED, world)
		for id in rep["retired"]:
			ever_retired[id] = true
		entrants_total += rep["entrants"].size()
		RankingManager.prune_world(world, season)
		var active := 0
		for g in golfers:
			assert_true(float(g["rating"]) >= 40.0 and float(g["rating"]) <= 100.0, "rating in bounds")
			assert_true(int(g["age"]) >= 17 and int(g["age"]) <= CareerConfig.RETIRE_MAX_AGE + 1, "age sane: %d" % int(g["age"]))
			assert_true(float(g["consistency"]) >= 0.2999 and float(g["consistency"]) <= 0.9501, "consistency bounds")
			if g["status"] != "retired":
				active += 1
		assert_true(active >= 255 and active <= 262, "active pool stays full (%d)" % active)
		var ctx := QualificationManager.build_context(world, RankingManager.new_standings(season), golfers, season)
		var f := QualificationManager.build_field(_event("ms%d" % season, "major", 4, {"type": "none"}, 96), golfers, ctx)
		assert_eq(f["field"].size(), 96, "major field fills in season %d" % season)
	assert_true(ever_retired.size() > 40, "retirements happen (%d)" % ever_retired.size())
	for id in initial_ids:
		var found := false
		for g in golfers:
			if g["id"] == id:
				found = true
		assert_true(found, "golfer %s is never deleted" % id)
	for g in golfers:
		if ever_retired.has(g["id"]):
			assert_eq(g["status"], "retired")
			assert_true(g["status_history"].size() >= 1 and g["status_history"][-1]["status"] == "retired", "history keeps retirement")
	var gen := 0
	var ids := {}
	var names := {}
	for g in golfers:
		assert_false(ids.has(g["id"]), "unique id")
		ids[g["id"]] = true
		assert_false(names.has(g["name"]), "unique name %s" % g["name"])
		names[g["name"]] = true
		if g["kind"] == "generated":
			gen += 1
	assert_eq(gen, entrants_total)
	assert_true(gen > 0)
	var tab := RankingManager.world_table(world, golfers, 21)
	assert_true(tab.size() >= 255 and tab.size() < golfers.size(), "retired golfers are not ranked but stay in records")


func test_evolution_deterministic() -> void:
	var a := _roster()
	var b := _roster()
	WorldEvolution.advance_season(a, 2, SEED)
	WorldEvolution.advance_season(b, 2, SEED)
	assert_eq(a, b)
	var c := _roster()
	WorldEvolution.advance_season(c, 2, SEED + 7)
	assert_true(c != a)

extends TestCase
## StatsEngine metric definitions (docs/STATS_DEFINITIONS.md), the v2 shot record, mulligan/undo handling,
## per-profile history isolation, legacy migration and save->resume equality with a non-default RoundConfig.


func _dir() -> String:
	return "user://test_stats_%d" % (randi() % 1000000)


func _cleanup_dir(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


## A v2 shot record with only what the definitions read.
func _shot(hole: String, mode: String, style_type: String, start: String, end: String, o: Dictionary = {}) -> Dictionary:
	var d := {"type": "shot", "v": 2, "hole_id": hole, "mode": mode, "shot_type": style_type, "footballer_id": "f_" + hole + mode,
		"footballer_name": "F", "start_lie": start, "final_lie": end, "on_green_end": end == "Green", "penalty": 0, "holed": false,
		"stroke_delta": 1, "total_m": 100.0, "carry_m": 90.0, "carry_yd": 98.4, "pin_before_m": 150.0, "pin_after_m": 50.0}
	d.merge(o, true)
	return d


func _hole(id: String, par: int, strokes: int, pens: int) -> Dictionary:
	return {"id": id, "name": id, "par": par, "strokes": strokes, "penalties": pens, "score": strokes + pens,
		"to_par": strokes + pens - par, "completion": "HOLED"}


func test_fairway_gir_putts_penalty_holed() -> void:
	# h1 par 4: tee on fairway, approach onto green (GIR in 2), 2 putts (second holes out)
	# h2 par 3: tee shot into water (penalty), relief on fairway, chip on green, putt holed
	# h3 par 5: tee in rough (fairway missed), 3rd shot reaches green in 3 = par-2 -> GIR, 1 putt
	var shots: Array = [
		_shot("h1", "CAPS", "Approach", "Tee", "Fairway"),
		_shot("h1", "CAPS", "Approach", "Fairway", "Green"),
		_shot("h1", "GOALS", "Putt", "Green", "Green", {"total_m": 6.0, "carry_m": null, "carry_yd": null}),
		_shot("h1", "GOALS", "Putt", "Green", "Green", {"holed": true, "pin_after_m": 0.0}),
		_shot("h2", "CAPS", "Approach", "Tee", "Fairway", {"penalty": 1, "hazard": "Water"}),
		_shot("h2", "CAPS", "Approach", "Fairway", "Green"),
		_shot("h2", "GOALS", "Putt", "Green", "Green", {"holed": true, "pin_after_m": 0.0}),
		_shot("h3", "CAPS", "Approach", "Tee", "Rough"),
		_shot("h3", "CAPS", "Approach", "Rough", "Fairway"),
		_shot("h3", "CAPS", "Approach", "Fairway", "Green"),
		_shot("h3", "GOALS", "Putt", "Green", "Green", {"holed": true, "pin_after_m": 0.0}),
	]
	var holes: Array = [_hole("h1", 4, 4, 0), _hole("h2", 3, 3, 1), _hole("h3", 5, 4, 0)]
	var st := StatsEngine.round_stats(shots, holes)
	assert_eq(st["level"], "full")
	assert_eq(st["strokes"], 11)
	assert_eq(st["penalties"], 1)
	assert_eq(st["score"], 12)
	assert_eq(st["to_par"], 0)
	assert_eq(st["fairways"], {"hit": 1, "eligible": 2}, "par 3 excluded; penalty tee shot is not a hit")
	assert_eq(st["gir"], {"hit": 2, "holes": 3}, "h2 reached green in 2 strokes + 1 penalty = 3 > par-2")
	assert_eq(st["putts"], 4, "shots started from the green")
	assert_eq(st["birdies_or_better"], 1)
	assert_eq(st["pars"], 1)
	assert_eq(st["bogeys_plus"], 1)
	assert_eq(st["caps_holed"], 0)
	assert_eq(st["goals_holed"], 3)
	assert_eq(st["caps_shots"], 7)
	assert_eq(st["goals_shots"], 4)
	assert_eq(StatsEngine.acc_max(st["putt_total_ft"]), Units.m_to_feet(100.0))
	assert_eq(int((st["approach_carry_yd"] as Dictionary)["n"]), 7, "putts have no carry; null carries are skipped")
	# reconciles with the scorecard
	var n := 0
	var pen := 0
	for s in shots:
		n += int(s["stroke_delta"])
		pen += int(s["penalty"])
	assert_eq(n, st["strokes"])
	assert_eq(pen, st["penalties"])


func test_null_measurements_are_not_nominal() -> void:
	var r := ShotResult.new()
	r.style = ShotTypes.Style.FLIGHT
	r.had_contact = false
	r.hole_id = "h1"
	var d := TelemetryLog.shot_record({}, r, null, Vector3(0, 0, 100), 1, 0, {"seq": 1})
	assert_eq(d["carry_m"], null, "no first contact -> no measured carry")
	assert_eq(d["roll_m"], null)
	assert_eq(d["shot_type"], "Approach")
	assert_eq(d["v"], TelemetryLog.FORMAT_VERSION)
	r.style = ShotTypes.Style.ROLL
	var p := TelemetryLog.shot_record({}, r, null, Vector3(0, 0, 100), 1, 0)
	assert_eq(p["shot_type"], "Putt")
	assert_eq(p["carry_m"], null, "a putt has no carry")
	assert_true(p["roll_m"] != null, "putt travel is the roll")
	var rec := {"type": "shot", "v": 2, "carry_yd": null}
	var f := StatsEngine.round_stats([_shot("h1", "CAPS", "Approach", "Tee", "Fairway", rec)], [_hole("h1", 4, 1, 0)])
	assert_eq(int((f["approach_carry_yd"] as Dictionary)["n"]), 0)
	assert_eq(StatsEngine.acc_avg(f["approach_carry_yd"]), null)


func test_legacy_and_mismatch_are_limited_with_na() -> void:
	var legacy := {"type": "shot", "v": 1, "hole_id": "h1", "mode": "CAPS", "footballer_id": "a", "footballer_name": "A", "final_lie": "Fairway"}
	var st := StatsEngine.round_stats([legacy], [_hole("h1", 3, 1, 0)])
	assert_eq(st["level"], "limited")
	assert_eq(st["fairways"], null)
	assert_eq(st["gir"], null)
	assert_eq(st["putts"], null)
	assert_eq(st["strokes"], 1, "scorecard metrics stay exact")
	assert_eq(st["caps_shots"], 1, "usage is still known")
	# v2 shots that do not add up to the scorecard are not trusted either
	var bad := StatsEngine.round_stats([_shot("h1", "CAPS", "Approach", "Tee", "Green")], [_hole("h1", 3, 2, 0)])
	assert_eq(bad["level"], "limited")
	var L := StatsEngine.lifetime([st, bad])
	assert_eq(L["full_rounds"], 0)
	assert_eq(StatsEngine.ratio(int(L["gir_hit"]), int(L["gir_holes"])), null, "N/A, not 0%")


func test_lifetime_reconciles_with_round_totals() -> void:
	var a := StatsEngine.round_stats([_shot("h1", "CAPS", "Approach", "Tee", "Green", {"holed": true})], [_hole("h1", 3, 1, 0)])
	var b := StatsEngine.round_stats([_shot("h1", "CAPS", "Approach", "Tee", "Rough", {"penalty": 1}),
		_shot("h1", "CAPS", "Approach", "Rough", "Green", {"holed": true})], [_hole("h1", 3, 2, 1)])
	var L := StatsEngine.lifetime([a, b])
	assert_eq(L["rounds"], 2)
	assert_eq(L["strokes"], 3)
	assert_eq(L["penalties"], 1)
	assert_eq(L["score"], 4)
	assert_eq(L["to_par"], -2)
	assert_eq(L["aces"], 1)
	assert_eq(L["gir_hit"], 1, "the penalty round took 3 strokes to reach the green")
	assert_eq(StatsEngine.trend_to_par([1, 1, 1], 3), null)
	assert_near(float(StatsEngine.trend_to_par([0, 0, 0, 3, 3, 3], 3)), -3.0, 1e-9)


## Mulligan: the replaced shot is in the log (audit) but marked replaced and never counted.
func test_mulligan_replaced_not_double_counted() -> void:
	var dir := _dir()
	var s := TestHelpers.make_session()
	s.round_state.mulligans_allowed = 1
	var tl := TelemetryLog.new(dir)
	tl.attach(s, "starter", "Starter Links")
	s.hole_started.emit(0)
	s.set_aim(5.0)
	assert_true(s.select_footballer(TestHelpers.add_player(s.repo, 60, 0)))
	assert_true(s.take_shot())
	s.skip_motion()
	assert_true(s.use_mulligan())
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 40, 0, 5.0)
	var recs := tl.load_records()
	assert_eq(TelemetryLog.of_type(recs, "shot").size(), 2, "both attempts are in the audit log")
	var mull := TelemetryLog.of_type(recs, "mulligan")
	assert_eq(mull.size(), 1)
	assert_eq(int(mull[0]["replaces_seq"]), 1)
	var played := TelemetryLog.played_shots(recs)
	assert_eq(played.size(), 1)
	assert_true(bool(played[0]["replacement"]), "the retake is flagged as a replacement")
	assert_eq(int(played[0]["seq"]), 2)
	# the log-based and the session-based record sets agree (one authoritative shot)
	var live := StatsEngine.shot_records_of(s, 0)
	assert_eq(live.size(), 1)
	assert_eq(live[0]["footballer_id"], played[0]["footballer_id"])
	assert_eq(s.current_hole_state().strokes, 1)
	_cleanup_dir(dir)
	TestHelpers.cleanup_repo(s.repo)


func test_dev_undo_marks_shot_undone() -> void:
	var dir := _dir()
	var s := TestHelpers.make_session()
	var tl := TelemetryLog.new(dir)
	tl.attach(s, "starter", "Starter Links")
	s.hole_started.emit(0)
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 60, 0, 5.0)
	s.acknowledge_result()
	assert_true(s.dev_undo())
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 50, 0, 5.0)  # reuses shot id 1; seq keeps them apart
	var recs := tl.load_records()
	assert_eq(TelemetryLog.of_type(recs, "undo").size(), 1)
	var played := TelemetryLog.played_shots(recs)
	assert_eq(played.size(), 1)
	assert_eq(int(played[0]["seq"]), 2)
	_cleanup_dir(dir)
	TestHelpers.cleanup_repo(s.repo)


func _rec(id: String, course: String, pid: String, to_par: int, date: int) -> Dictionary:
	var rows := [_hole("h1", 3, 3 + to_par, 0)]
	var st := StatsEngine.round_stats([], rows)
	return {"v": 2, "id": id, "course_id": course, "course_name": course, "date": date, "rules": {}, "winner": "",
		"players": [{"profile_id": pid, "name": pid, "score": 3 + to_par, "par": 3, "to_par": to_par, "strokes": 3 + to_par,
		"penalties": 0, "holes": rows, "stats": st}]}


func test_history_isolated_per_profile() -> void:
	var dir := _dir()
	var path := dir + "/history.json"
	assert_true(RoundHistory.append(_rec("r1", "starter", "pA", -1, 100), path))
	assert_true(RoundHistory.append(_rec("r2", "starter", "pB", 2, 200), path))
	assert_true(RoundHistory.append(_rec("r3", "starter", "pA", 0, 300), path))
	var recs := RoundHistory.load_records(path)
	var a := RoundHistory.entries(recs, "pA")
	var b := RoundHistory.entries(recs, "pB")
	assert_eq(a.size(), 2)
	assert_eq(b.size(), 1)
	assert_eq(RoundHistory.entries(recs, "").size(), 0, "guests see nobody else's rounds")
	assert_eq(RoundHistory.lifetime(a)["rounds"], 2)
	assert_eq(RoundHistory.lifetime(b)["to_par"], 2)
	assert_eq(RoundHistory.records(recs, "pA")["courses"][0]["best_to_par"], -1)
	assert_eq(RoundHistory.records(recs, "pB")["courses"][0]["best_to_par"], 2)
	assert_eq(HistoryPages.personal_bests(a)["best_round"]["to_par"], -1)
	_cleanup_dir(dir)


func test_migration_imports_legacy_telemetry_idempotently() -> void:
	var dir := _dir()
	var tl := TelemetryLog.new(dir + "/tel")
	var rid := "20250101-120000-0001"
	tl.append(rid, {"type": "round_start", "v": 1, "round_id": rid, "course_id": "starter", "course_name": "Starter Links", "round_seed": 1, "mulligans_allowed": 0})
	tl.append(rid, {"type": "shot", "v": 1, "round_id": rid, "hole_id": "h1", "shot_id": 1, "mode": "CAPS", "footballer_id": "a", "footballer_name": "A", "final_lie": "Green", "holed": true})
	tl.append(rid, {"type": "hole", "v": 1, "round_id": rid, "hole_id": "h1", "hole_name": "One", "hole_index": 0, "par": 3, "strokes": 1, "penalties": 0, "score": 1, "to_par": -2, "completion": "HOLED"})
	tl.append(rid, {"type": "round", "v": 1, "round_id": rid, "time": "2025-01-01T12:10:00", "course_id": "starter", "holes": 1, "holes_completed": 1, "strokes": 1, "penalties": 0, "score": 1, "par_played": 3, "to_par": -2, "shots": 1})
	tl.append("unfinished", {"type": "round_start", "v": 1, "round_id": "unfinished", "course_id": "starter"})
	var path := dir + "/history.json"
	var n1 := HistoryMigration.run(tl, "pA", path)
	assert_eq(n1, 1, "only the completed round is imported")
	assert_eq(HistoryMigration.run(tl, "pA", path), 0, "idempotent")
	var recs := RoundHistory.load_records(path)
	assert_eq(recs.size(), 1)
	var p: Dictionary = recs[0]["players"][0]
	assert_eq(p["profile_id"], "pA")
	assert_eq(p["stats"]["level"], "limited")
	assert_eq(p["stats"]["aces"], 1)
	assert_eq(p["stats"]["fairways"], null, "legacy: N/A not 0")
	# a version-1 history file (no profile ids) is adopted by the default profile
	RoundSave.write_json_atomic(dir + "/old.json", {"history_version": 1, "records": [{"id": "x", "course_id": "c", "course_name": "C", "date": 5, "rules": {},
		"players": [{"name": "n", "score": 3, "to_par": 0, "holes": []}]}]})
	HistoryMigration.run(TelemetryLog.new(dir + "/none"), "pB", dir + "/old.json")
	assert_eq(RoundHistory.entries(RoundHistory.load_records(dir + "/old.json"), "pB").size(), 1)
	_cleanup_dir(dir + "/tel")
	_cleanup_dir(dir)


func test_save_resume_equality_with_non_default_round_config() -> void:
	var rc := RoundConfig.new()
	rc.cup_diameter_ft = 2.0
	rc.gimme_ft = 3.0
	rc.reuse_per_mode = true
	rc.wind_mode = RoundConfig.WindMode.SCALED
	rc.wind_scale = 1.5
	rc.max_score_mode = RoundConfig.MaxScore.CUSTOM
	rc.max_over_par_custom = 4
	rc.show_aim_arrow = false
	rc.tee_color = "blue"
	rc.pin_varied = true
	rc.order_by_stats = true
	var s := GameSession.new(PhysicsConfig.new(), TestHelpers.make_repo())
	s.apply_rules(rc)
	var defs := TestHelpers.load_holes()
	s.start_round(defs, 4321, rc.pool_rule(), 1, 2)
	s.player_names[0] = "Ann"
	s.player_names[1] = "Bo"
	s.profile_ids.append("pA")
	s.profile_ids.append("pB")
	s.begin_play()
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 60, 0, 5.0)
	var data: Dictionary = JSON.parse_string(JSON.stringify(RoundSave.capture(s, {"id": "q1", "course_id": "starter", "course_name": "S"})))
	var tees: Array = []
	var pins: Array = []
	for d in s.hole_defs:
		tees.append((d as HoleDefinition).tee)
		pins.append((d as HoleDefinition).pin)
	var s2 := GameSession.new(PhysicsConfig.new(), s.repo)
	var fresh := TestHelpers.load_holes()
	assert_true(RoundSave.restore(s2, data, fresh))
	assert_eq(s2.rules.to_dict(), rc.to_dict(), "the full frozen RoundConfig is restored")
	assert_eq(RoundSave.rules_of(data).to_dict(), rc.to_dict())
	assert_eq(RoundSave.players_of(data), 2)
	assert_eq(RoundSave.mulligans_of(data), 1)
	assert_near(s2.wind_scale, 1.5, 1e-9)
	assert_near(s2.holeout_radius_ft, 3.0, 1e-9)
	assert_near(s2.cfg.cup_radius, s.cfg.cup_radius, 1e-9)
	assert_eq(s2.profile_ids, s.profile_ids)
	for i in fresh.size():
		assert_eq((fresh[i] as HoleDefinition).tee, tees[i], "same tee box")
		assert_eq((fresh[i] as HoleDefinition).pin, pins[i], "same pin")
		assert_eq((fresh[i] as HoleDefinition).tee_color, (s.hole_defs[i] as HoleDefinition).tee_color)
	assert_eq(s2.current_hole_state().max_score, s.current_hole_state().max_score)
	TestHelpers.cleanup_repo(s.repo)

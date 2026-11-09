extends TestCase
## Save & resume (RoundSave), RoundAutosave, History records and personal bests.


func _dir() -> String:
	return "user://test_saves_%d" % (randi() % 1000000)


func _cleanup_dir(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _fresh_like(s: GameSession) -> GameSession:
	return GameSession.new(PhysicsConfig.new(), s.repo)


## Everything that matters for "resume restores exactly", in comparable form.
func _fp(s: GameSession) -> Dictionary:
	var slots: Array = []
	for i in s.slots.size():
		var rs: RoundState = s.slot_round_state(i)
		var holes: Array = []
		for h in rs.holes:
			var hs: HoleState = h
			var ids: Array = []
			for r in hs.shots:
				ids.append([(r as ShotResult).shot_id, (r as ShotResult).footballer_id, snappedf((r as ShotResult).total_m, 0.0001), (r as ShotResult).final_pos])
			holes.append([hs.hole_id, hs.par, hs.strokes, hs.penalties, hs.complete, hs.completion, hs.used_footballer_ids.duplicate(), ids])
		var sl: GameSession.PlayerSlot = s.slots[i]
		slots.append({"holes": holes, "ball": sl.ball_pos, "safe": sl.last_safe_pos, "seed": rs.round_seed,
			"mull": [rs.mulligans_allowed, rs.mulligans_used], "idx": rs.current_index})
	return {"slots": slots, "turn": s.turn, "names": s.player_names.duplicate(), "pool": s.pool.snapshot(),
		"shot_counter": s.shot_counter, "history": s.history.size(), "holeout": s.holeout_radius_ft,
		"wind": [s.wind_custom, s.wind_custom_speed, s.wind_custom_bearing],
		"ball": s.ball_pos, "hole": s.hole.id}


func _json_roundtrip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func _two_player_session(mulligans: int = 2) -> GameSession:
	var s := GameSession.new(PhysicsConfig.new(), TestHelpers.make_repo())
	s.holeout_radius_ft = 5.0  # the bot needs the 5 ft auto hole-out to finish rounds
	s.cfg.cup_radius = 0.3
	s.holeout_radius_ft = 3.5
	s.wind_custom = true
	s.wind_custom_speed = 4.5
	s.wind_custom_bearing = 70.0
	s.start_round(TestHelpers.load_holes(), 777, FootballerPool.ReuseRule.ONCE_PER_MODE, mulligans, 2)
	s.player_names[0] = "Ann"
	s.player_names[1] = "Bo"
	s.begin_play()
	return s


func _meta() -> Dictionary:
	return {"id": "t1", "course_id": "starter", "course_name": "Starter Links", "telemetry_round_id": "rid-1"}


func test_solo_mid_hole_round_trip() -> void:
	var s := TestHelpers.make_session()
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 60, 0, 5.0)
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 40, 0)
	assert_eq(s.state, ShotTypes.State.AIMING)
	var data := RoundSave.capture(s, _meta())  # also syncs the active slot
	var before := _fp(s)
	assert_false(data.is_empty())
	assert_eq(String(data["resume"]), "play")
	var s2 := _fresh_like(s)
	assert_true(RoundSave.restore(s2, _json_roundtrip(data), TestHelpers.load_holes()))
	assert_eq(_fp(s2), before, "restored state equals the original")
	assert_near(s2.cfg.cup_radius, s.cfg.cup_radius, 1e-9)
	assert_eq(s2.state, ShotTypes.State.HOLE_INTRO)
	s2.begin_play()
	assert_eq(s2.state, ShotTypes.State.AIMING)
	# nothing is consumed twice; a used footballer stays used, strokes continue
	var used_id := s.current_hole_state().used_footballer_ids[0]
	assert_false(s2.pool.is_available(used_id), "used footballer stays used after resume")
	assert_eq(s2.pool.used_count(), 2)
	var strokes := s2.current_hole_state().strokes
	TestHelpers.shoot(s2, ShotTypes.Mode.CAPS, 30, 0)
	assert_eq(s2.current_hole_state().strokes, strokes + 1)
	assert_eq(s2.pool.used_count(), 3)
	assert_eq(s2.shot_counter, 3, "shot ids continue without repeating")
	TestHelpers.cleanup_repo(s.repo)


func test_pass_and_play_mid_hole_keeps_turn_settings_and_pool() -> void:
	var s := _two_player_session()
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 80, 0, 0.0)
	assert_eq(s.turn, 1)
	var before := _fp(s)
	var data := _json_roundtrip(RoundSave.capture(s, _meta()))
	var s2 := _fresh_like(s)
	assert_true(RoundSave.restore(s2, data, TestHelpers.load_holes()))
	assert_eq(_fp(s2), before)
	assert_eq(s2.turn, 1, "player 2 is still to play")
	assert_eq(s2.active_name(), "Bo")
	assert_near(s2.cfg.cup_radius, 0.3, 1e-6, "cup size in force is restored")
	assert_near(s2.holeout_radius_ft, 3.5, 1e-6)
	assert_eq(s2.pool.reuse_rule, FootballerPool.ReuseRule.ONCE_PER_MODE)
	assert_eq(s2.round_state.mulligans_allowed, 2)
	assert_near(s2.wind_speed(), 4.5, 1e-6)
	assert_eq(s2.slot_round_state(0).round_seed, 777)
	TestHelpers.cleanup_repo(s.repo)


func test_pass_and_play_mid_round_resumes_at_next_hole() -> void:
	var s := _two_player_session()
	var guard := 400
	while s.state != ShotTypes.State.HOLE_COMPLETE and guard > 0:
		guard -= 1
		if s.state == ShotTypes.State.AIMING:
			TestHelpers.bot_shot(s, 0)
		elif s.state == ShotTypes.State.SHOT_RESULT:
			s.acknowledge_result()
	assert_eq(s.state, ShotTypes.State.HOLE_COMPLETE)
	var done := [s.slot_round_state(0).holes_completed(), s.slot_round_state(1).holes_completed()]
	var strokes := [s.slot_round_state(0).holes[0].strokes, s.slot_round_state(1).holes[0].strokes]
	var data := _json_roundtrip(RoundSave.capture(s, _meta()))
	assert_eq(String(data["resume"]), "hole_complete")
	var s2 := _fresh_like(s)
	assert_true(RoundSave.restore(s2, data, TestHelpers.load_holes()))
	assert_eq(s2.round_state.current_index, 1, "continues on the next hole")
	assert_eq(s2.state, ShotTypes.State.HOLE_INTRO)
	assert_eq(s2.turn, 0)
	assert_eq([s2.slot_round_state(0).holes_completed(), s2.slot_round_state(1).holes_completed()], done)
	assert_eq([s2.slot_round_state(0).holes[0].strokes, s2.slot_round_state(1).holes[0].strokes], strokes)
	s2.begin_play()
	TestHelpers.shoot(s2, ShotTypes.Mode.CAPS, 50, 0)
	assert_eq(s2.turn, 1)
	TestHelpers.cleanup_repo(s.repo)


func test_capture_during_result_resumes_with_next_player_and_does_not_mutate() -> void:
	var s := _two_player_session()
	var id := TestHelpers.add_player(s.repo, 70, 0)
	s.select_footballer(id)
	assert_true(s.take_shot())
	assert_true(RoundSave.capture(s, _meta()).is_empty(), "no save while the ball is moving")
	s.skip_motion()
	assert_eq(s.state, ShotTypes.State.SHOT_RESULT)
	var data := _json_roundtrip(RoundSave.capture(s, _meta()))
	assert_eq(s.state, ShotTypes.State.SHOT_RESULT, "capture does not change the session")
	assert_eq(s.turn, 0)
	assert_eq(int(data["turn"]), 1, "the other player is up after the result")
	var s2 := _fresh_like(s)
	assert_true(RoundSave.restore(s2, data, TestHelpers.load_holes()))
	assert_eq(s2.turn, 1)
	assert_false(s2.pool.is_available(id, ShotTypes.Mode.CAPS))
	TestHelpers.cleanup_repo(s.repo)


func test_corrupt_and_old_version_files_are_ignored() -> void:
	var dir := _dir()
	var s := TestHelpers.make_session()
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 60, 0, 5.0)
	var good := RoundSave.capture(s, _meta())
	assert_true(RoundSave.write(good, dir))
	assert_eq(RoundSave.list_saves(dir).size(), 1)
	assert_false(FileAccess.file_exists(RoundSave.path_for("t1", dir) + ".tmp"), "atomic write leaves no temp file")
	# corrupt text
	var f := FileAccess.open(RoundSave.path_for("bad1", dir), FileAccess.WRITE)
	f.store_string("{ not json [")
	f.close()
	# old version
	var old := good.duplicate(true)
	old["id"] = "old2"
	old["save_version"] = 0
	RoundSave.write(old, dir)
	# missing keys
	RoundSave.write({"id": "thin3", "save_version": RoundSave.VERSION}, dir)
	# not a dictionary
	f = FileAccess.open(RoundSave.path_for("arr4", dir), FileAccess.WRITE)
	f.store_string("[1,2,3]")
	f.close()
	var listed := RoundSave.list_saves(dir)
	assert_eq(listed.size(), 1, "only the valid save is listed")
	assert_eq(String(listed[0]["id"]), "t1")
	for bad in ["bad1", "old2", "thin3", "arr4", "../x", "nonexistent"]:
		assert_true(RoundSave.load_save(bad, dir).is_empty(), "ignored: " + bad)
	# a save that does not fit the course is refused and leaves the session untouched
	var s2 := _fresh_like(s)
	var wrong := TestHelpers.load_ridge_holes()
	assert_false(RoundSave.restore(s2, _json_roundtrip(good), wrong))
	assert_true(s2.hole_defs.is_empty() and s2.slots.is_empty(), "failed restore changes nothing")
	RoundSave.delete("t1", dir)
	assert_eq(RoundSave.list_saves(dir).size(), 0)
	_cleanup_dir(dir)
	TestHelpers.cleanup_repo(s.repo)


func test_several_saves_listed_newest_first() -> void:
	var dir := _dir()
	var s := TestHelpers.make_session()
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 60, 0, 5.0)
	for i in 3:
		var d := RoundSave.capture(s, {"id": "r%d" % i, "course_id": "starter", "course_name": "C%d" % i})
		d["saved_at"] = 1000 + i
		RoundSave.write(d, dir)
	var l := RoundSave.list_saves(dir)
	assert_eq(l.size(), 3)
	assert_eq(String(l[0]["id"]), "r2")
	assert_eq(int(l[0]["holes_total"]), 3)
	_cleanup_dir(dir)
	TestHelpers.cleanup_repo(s.repo)


func test_autosave_writes_after_shots_and_completion_writes_history() -> void:
	var dir := _dir()
	var hist := dir + "/history.json"
	var s := GameSession.new(PhysicsConfig.new(), TestHelpers.make_repo())
	s.holeout_radius_ft = 5.0  # the bot needs the 5 ft auto hole-out to finish rounds
	var a := RoundAutosave.new()
	a.save_dir = dir
	a.history_path = hist
	a.attach(s, "starter", "Starter Links")
	s.start_round(TestHelpers.load_holes(), 4242)
	assert_eq(RoundSave.list_saves(dir).size(), 0, "nothing saved before the first shot")
	s.begin_play()
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 60, 0, 5.0)
	var l := RoundSave.list_saves(dir)
	assert_eq(l.size(), 1, "autosaved after the first shot")
	var id := String(l[0]["id"])
	assert_true(TestHelpers.bot_round(s))
	assert_eq(RoundSave.list_saves(dir).size(), 0, "save removed when the round completes")
	var recs := RoundHistory.load_records(hist)
	assert_eq(recs.size(), 1, "history record written")
	assert_eq(String(recs[0]["id"]), id)
	# completing again with the same id is ignored (no duplicates)
	assert_false(RoundHistory.append(recs[0], hist))
	assert_eq(RoundHistory.load_records(hist).size(), 1)
	_cleanup_dir(dir)
	TestHelpers.cleanup_repo(s.repo)


func test_resumed_autosave_keeps_id_and_telemetry_not_duplicated() -> void:
	var dir := _dir()
	var s := TestHelpers.make_session()
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 60, 0, 5.0)
	var data := _json_roundtrip(RoundSave.capture(s, _meta()))
	RoundSave.write(data, dir)
	var s2 := _fresh_like(s)
	assert_true(RoundSave.restore(s2, data, TestHelpers.load_holes()))
	var tl := TelemetryLog.new(dir + "/tel")
	tl.attach(s2, "starter", "Starter Links", "rid-1")
	var a := RoundAutosave.new()
	a.save_dir = dir
	a.history_path = dir + "/history.json"
	a.attach(s2, "starter", "Starter Links", tl, data)
	s2.begin_play()
	TestHelpers.shoot(s2, ShotTypes.Mode.CAPS, 30, 0)
	var recs := tl.load_records()
	assert_eq(TelemetryLog.of_type(recs, "round_start").size(), 0, "no second round_start after resume")
	assert_eq(TelemetryLog.of_type(recs, "shot").size(), 1, "only the new shot is logged")
	var l := RoundSave.list_saves(dir)
	assert_eq(l.size(), 1, "same save file is updated, not duplicated")
	assert_eq(String(l[0]["id"]), "t1")
	_cleanup_dir(dir + "/tel")
	_cleanup_dir(dir)
	TestHelpers.cleanup_repo(s.repo)


func test_history_record_content() -> void:
	var s := GameSession.new(PhysicsConfig.new(), TestHelpers.make_repo())
	s.holeout_radius_ft = 5.0  # the bot needs the 5 ft auto hole-out to finish rounds
	s.start_round(TestHelpers.load_holes(), 99, FootballerPool.ReuseRule.ONCE_PER_ROUND, 1, 1)
	s.player_names[0] = "Kit"
	s.begin_play()
	assert_true(TestHelpers.bot_round(s))
	var rec := RoundHistory.build_record(s, {"id": "x1", "course_id": "starter", "course_name": "Starter Links", "date": 1700000000})
	assert_eq(rec["course_name"], "Starter Links")
	assert_eq(int(rec["date"]), 1700000000)
	var p: Dictionary = rec["players"][0]
	assert_eq(p["name"], "Kit")
	assert_eq((p["holes"] as Array).size(), 3)
	assert_eq(int(p["score"]), s.round_state.total_score())
	assert_eq(int(p["to_par"]), s.round_state.relative_to_par())
	var sum := 0
	var low := 999
	var high := -999
	for h in p["holes"]:
		sum += int(h["score"])
		low = mini(low, int(h["to_par"]))
		high = maxi(high, int(h["to_par"]))
		assert_eq(int(h["to_par"]), int(h["score"]) - int(h["par"]))
	assert_eq(sum, int(p["score"]))
	assert_eq(int(p["best_hole"]["to_par"]), low)
	assert_eq(int(p["worst_hole"]["to_par"]), high)
	assert_eq(int(rec["rules"]["mulligans"]), 1)
	assert_eq(rec["winner"], "", "no winner label for a solo round")
	var rec2 := _json_roundtrip(rec)
	var all := RoundHistory.records([rec2, rec2])
	assert_eq(int(all["rounds"]), 2)
	assert_eq((all["courses"] as Array).size(), 1, "same course and rules group together")
	assert_eq(int(all["courses"][0]["best_score"]), int(p["score"]))
	TestHelpers.cleanup_repo(s.repo)


func test_history_file_corrupt_or_old_is_empty() -> void:
	var dir := _dir()
	var path := dir + "/history.json"
	assert_eq(RoundHistory.load_records(path).size(), 0, "missing file")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("garbage{")
	f.close()
	assert_eq(RoundHistory.load_records(path).size(), 0, "corrupt file")
	RoundSave.write_json_atomic(path, {"history_version": 0, "records": [{"id": "a"}]})
	assert_eq(RoundHistory.load_records(path).size(), 0, "old version")
	RoundSave.write_json_atomic(path, {"history_version": RoundHistory.VERSION, "records": [{"id": "a"}, 5]})
	assert_eq(RoundHistory.load_records(path).size(), 0, "malformed records dropped")
	_cleanup_dir(dir)

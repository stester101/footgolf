extends TestCase
## TelemetryLog: record serialisation, JSONL round trip, CSV/summary export, session hook.


func _tmp_log() -> TelemetryLog:
	var tl := TelemetryLog.new("user://test_telemetry_%d" % (randi() % 1000000))
	tl.clear()
	return tl


func _cleanup(tl: TelemetryLog) -> void:
	tl.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tl.dir))


func _sample_result() -> ShotResult:
	var r := ShotResult.new()
	r.shot_id = 7
	r.hole_id = "hole_01"
	r.footballer_id = "fb_1"
	r.footballer_name = "Test, \"Player\""
	r.nationality = "Testland"
	r.mode = ShotTypes.Mode.CAPS
	r.stat_value = 100
	r.caps = 100
	r.goals = 12
	r.spin = -0.5
	r.launch_angle_deg = 42.0
	r.start_pos = Vector3(0, 0.02, 0)
	r.final_pos = Vector3(3, 0.02, 100)
	r.carry_m = Units.caps_to_carry_m(100)
	r.had_contact = true
	r.total_m = 100.04
	r.start_lie = Surface.Type.TEE
	r.final_lie = Surface.Type.FAIRWAY
	r.remaining_m = 50.0
	r.penalty = 0
	return r


func test_shot_record_fields() -> void:
	var ctx := {"round_id": "r1", "course_id": "starter"}
	var r := _sample_result()
	var d := TelemetryLog.shot_record(ctx, r, ShotRequest.new(), Vector3(0, 0, 150), 2, 0)
	assert_eq(d["type"], "shot")
	assert_eq(d["round_id"], "r1")
	assert_eq(d["course_id"], "starter")
	assert_eq(d["hole_id"], "hole_01")
	assert_eq(d["shot_no"], 2)
	assert_eq(d["footballer_name"], "Test, \"Player\"")
	assert_eq(d["mode"], "CAPS")
	assert_eq(d["style"], "FLIGHT")
	assert_eq(d["stat"], 100)
	assert_near(float(d["spin"]), -0.5, 1e-9)
	assert_near(float(d["carry_yd"]), 100.0, 0.01, "carry in yards")
	assert_near(float(d["pin_before_m"]), 150.0, 0.001, "distance to pin before")
	assert_near(float(d["pin_after_m"]), 50.0, 0.001, "distance to pin after")
	assert_eq(d["start_lie"], "Tee")
	assert_eq(d["trajectory"], "STANDARD", "trajectory recorded by name")
	assert_eq((d["end_pos"] as Array).size(), 3)
	r.holed = true
	var h := TelemetryLog.shot_record(ctx, r, null, Vector3(0, 0, 150), 2, 0)
	assert_near(float(h["pin_after_m"]), 0.0, 1e-9, "holed = 0 after")


func test_mulligan_log_keeps_audit_but_exports_only_played_shots() -> void:
	var a := {"type": "shot", "round_id": "r1", "hole_id": "h1", "shot_id": 1, "stat": 10}
	var undone := {"type": "mulligan", "round_id": "r1", "hole_id": "h1", "shot_id": 1}
	var retake := {"type": "shot", "round_id": "r1", "hole_id": "h1", "shot_id": 1, "stat": 20}
	var kept := TelemetryLog.played_shots([a, undone, retake])
	assert_eq(kept.size(), 1)
	assert_eq(kept[0]["stat"], 20)
	assert_true(TelemetryLog.shots_csv([a, undone, retake]).contains(",20,"))


func test_hole_and_round_records() -> void:
	var rs := RoundState.new()
	rs.round_seed = 42
	for i in 2:
		var hs := HoleState.new()
		hs.hole_id = "h%d" % i
		hs.hole_name = "Hole %d" % i
		hs.par = 3
		hs.strokes = 4
		hs.penalties = i
		hs.complete = i == 0
		hs.completion = ShotTypes.COMPLETION_HOLED if i == 0 else ""
		rs.holes.append(hs)
		rs.hole_ids.append(hs.hole_id)
	var ctx := {"round_id": "r9", "course_id": "c", "course_name": "Course"}
	var h := TelemetryLog.hole_record(ctx, rs.holes[1], 1)
	assert_eq(h["score"], 5)
	assert_eq(h["to_par"], 2)
	assert_eq(h["penalties"], 1)
	var r := TelemetryLog.round_record(ctx, rs, 12.5)
	assert_eq(r["holes_completed"], 1)
	assert_eq(r["score"], 4, "only completed holes count")
	assert_eq(r["strokes"], 8)
	assert_eq(r["penalties"], 1)
	var st := TelemetryLog.round_start_record(ctx, rs)
	assert_eq(st["holes"], ["h0", "h1"])
	assert_eq(st["pars"], [3, 3])


func test_jsonl_round_trip_and_clear() -> void:
	var tl := _tmp_log()
	assert_true(tl.append("r1", {"type": "round_start", "round_id": "r1"}))
	assert_true(tl.append("r1", TelemetryLog.shot_record({"round_id": "r1"}, _sample_result(), null, Vector3.ZERO, 1, 0)))
	assert_true(tl.append("r2", {"type": "round_start", "round_id": "r2"}))
	assert_false(tl.append("", {"type": "x"}), "no round id, nothing written")
	assert_eq(tl.files().size(), 2)
	var recs := tl.load_records()
	assert_eq(recs.size(), 3)
	assert_eq(recs[1]["type"], "shot")
	assert_eq(recs[1]["footballer_name"], "Test, \"Player\"")
	assert_eq(TelemetryLog.parse_lines("{bad json\n{\"type\":\"shot\"}\n\n").size(), 1, "corrupt lines skipped")
	assert_eq(tl.clear(), 2)
	assert_eq(tl.load_records().size(), 0)
	_cleanup(tl)


func test_csv_escaping_and_columns() -> void:
	assert_eq(TelemetryLog.csv_cell("a,b"), "\"a,b\"")
	assert_eq(TelemetryLog.csv_cell("say \"hi\""), "\"say \"\"hi\"\"\"")
	assert_eq(TelemetryLog.csv_cell(true), "1")
	assert_eq(TelemetryLog.csv_cell(null), "")
	assert_eq(TelemetryLog.csv_cell(3.0), "3")
	assert_eq(TelemetryLog.csv_cell(["a", "b"]), "a;b")
	var rec := TelemetryLog.shot_record({"round_id": "r1"}, _sample_result(), null, Vector3.ZERO, 1, 0)
	var parsed: Array = TelemetryLog.parse_lines(JSON.stringify(rec))  # as stored: numbers become floats
	var csv := TelemetryLog.shots_csv(parsed)
	var lines := csv.strip_edges().split("\n")
	assert_eq(lines.size(), 2, "header + 1 row")
	assert_eq(lines[0], ",".join(PackedStringArray(TelemetryLog.SHOT_COLUMNS)))
	assert_true(lines[1].contains("\"Test, \"\"Player\"\"\""), "name escaped")
	assert_true(lines[1].contains(",CAPS,FLIGHT,100,100,12,"), "mode/style/stat/caps/goals recorded")
	assert_true(lines[1].contains(",3,0.02,100,"), "end position flattened")


func test_summary_and_export_files() -> void:
	var tl := _tmp_log()
	assert_true(TelemetryLog.summary_text([]).contains("No data"))
	var ctx := {"round_id": "r1", "course_id": "starter", "course_name": "Starter Links"}
	tl.append("r1", {"type": "round_start", "round_id": "r1", "course_name": "Starter Links"})
	tl.append("r1", TelemetryLog.shot_record(ctx, _sample_result(), null, Vector3.ZERO, 1, 0))
	tl.append("r1", {"type": "hole", "round_id": "r1", "hole_name": "First", "par": 3, "score": 4, "to_par": 1,
		"strokes": 4, "penalties": 0, "completion": "holed"})
	tl.append("r1", {"type": "round", "round_id": "r1", "score": 4, "to_par": 1, "shots": 1})
	var txt := TelemetryLog.summary_text(tl.load_records())
	assert_true(txt.contains("Starter Links"), "course in summary")
	assert_true(txt.contains("First par 3: 4 (+1)"), "hole line")
	assert_true(txt.contains("Shots CSV"), "csv appended")
	var out_dir := tl.dir + "_export"
	var res := tl.export_files([out_dir])
	assert_true(bool(res["ok"]), "export ok")
	assert_eq((res["files"] as Array).size(), 4)
	var rounds_csv := ""
	for f in res["files"]:
		if String(f).ends_with("_rounds.csv"):
			rounds_csv = FileAccess.get_file_as_string(out_dir.path_join(String(f)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out_dir.path_join(String(f))))
	assert_eq(rounds_csv.strip_edges().split("\n").size(), 2, "rounds csv has one row")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(out_dir))
	_cleanup(tl)


func test_attached_session_logs_shots_holes_round() -> void:
	var tl := _tmp_log()
	var s := GameSession.new(PhysicsConfig.new(), TestHelpers.make_repo())
	s.holeout_radius_ft = 5.0
	tl.attach(s, "starter", "Starter Links")
	s.start_round(TestHelpers.load_holes(), 777)
	s.begin_play()
	var r := TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 60, 3)
	assert_true(r != null, "first shot")
	for i in s.round_state.holes.size():
		if s.state == ShotTypes.State.HOLE_INTRO:
			s.begin_play()
		var cup := s.hole.cup_position()
		assert_eq(s.dev_place_ball(cup.x + 0.3, cup.z), "", "place near cup")
		assert_true(TestHelpers.shoot(s, ShotTypes.Mode.GOALS, 0, 0) != null, "tap-in")
		assert_eq(s.state, ShotTypes.State.HOLE_COMPLETE, "hole %d complete" % i)
		s.next_hole()
	assert_true(s.is_round_complete(), "round complete")
	var recs := tl.load_records()
	assert_eq(TelemetryLog.of_type(recs, "round_start").size(), 1)
	assert_eq(TelemetryLog.of_type(recs, "shot").size(), 4)
	assert_eq(TelemetryLog.of_type(recs, "hole").size(), 3)
	var rounds := TelemetryLog.of_type(recs, "round")
	assert_eq(rounds.size(), 1)
	var first: Dictionary = TelemetryLog.of_type(recs, "shot")[0]
	assert_eq(first["course_id"], "starter")
	assert_eq(int(first["shot_no"]), 1)
	assert_eq(first["mode"], "CAPS")
	assert_eq(int(TelemetryLog.of_type(recs, "shot")[1]["shot_no"]), 2, "tap-in is shot 2 on hole 1")
	assert_eq(int(rounds[0]["strokes"]), 4)
	assert_eq(int(rounds[0]["holes_completed"]), 3)
	# restarting the same session logs a new round
	s.start_round(TestHelpers.load_holes(), 778)
	assert_eq(TelemetryLog.of_type(tl.load_records(), "round_start").size(), 2, "new round detected")
	TestHelpers.cleanup_repo(s.repo)
	_cleanup(tl)

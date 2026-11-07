extends TestCase
## Runs data-driven developer scenarios twice each and checks expectations + repeatability.


func test_developer_scenarios() -> void:
	var f := FileAccess.open("res://tests/scenarios/scenarios.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	for sc in data["scenarios"]:
		var first := _run(sc)
		var second := _run(sc)
		if first == null or second == null:
			fail("%s: shot did not run" % sc["id"])
			continue
		assert_eq(first.final_pos, second.final_pos, "%s repeatable" % sc["id"])
		var ex: Dictionary = sc["expect"]
		if ex.has("hazard"):
			assert_eq(first.hazard, String(ex["hazard"]), "%s hazard" % sc["id"])
		if ex.has("penalty"):
			assert_eq(first.penalty, int(ex["penalty"]), "%s penalty" % sc["id"])
		if ex.has("carry_yd_min"):
			assert_gt(Units.m_to_yards(first.carry_m), float(ex["carry_yd_min"]), "%s carry min" % sc["id"])
			assert_lt(Units.m_to_yards(first.carry_m), float(ex["carry_yd_max"]), "%s carry max" % sc["id"])
		if ex.has("total_m_max"):
			assert_true(first.total_m <= float(ex["total_m_max"]), "%s total" % sc["id"])
		if ex.has("collisions_min"):
			assert_true(first.collisions.size() >= int(ex["collisions_min"]), "%s collisions" % sc["id"])
		note("%s: hazard='%s' carry %.1f yd total %.1f yd pen %d collisions %d" % [sc["id"], first.hazard, Units.m_to_yards(first.carry_m), Units.m_to_yards(first.total_m), first.penalty, first.collisions.size()])


func _run(sc: Dictionary) -> ShotResult:
	var s := TestHelpers.make_session()
	var hi := int(sc["hole"])
	if hi != 0:
		s.dev_select_hole(hi)
		s.begin_play()
	var w: Array = sc["wind"]
	s.wind_custom = true
	s.wind_custom_speed = float(w[0])
	s.wind_custom_bearing = float(w[1])
	if sc["ball"] != null:
		var b: Array = sc["ball"]
		var err := s.dev_place_ball(float(b[0]), float(b[1]))
		if err != "":
			fail("%s: place failed: %s" % [sc["id"], err])
			return null
	var aim := -999.0
	if typeof(sc["aim"]) != TYPE_STRING:
		aim = float(sc["aim"])
	elif sc["aim"] == "nearest_tree":
		var best := INF
		for t in s.hole.trees:
			var tp := Vector3(float(t["x"]), 0.0, float(t["z"]))
			var d := Units.horizontal_distance(tp, s.ball_pos)
			if d < best:
				best = d
				aim = Units.dir_to_bearing(tp - s.ball_pos)
	var mode := ShotTypes.Mode.CAPS if sc["mode"] == "CAPS" else ShotTypes.Mode.GOALS
	var r := TestHelpers.shoot(s, mode, int(sc["caps"]), int(sc["goals"]), aim)
	var ex: Dictionary = sc["expect"]
	if r != null and ex.has("strokes"):
		assert_eq(s.current_hole_state().strokes, int(ex["strokes"]), "%s strokes" % sc["id"])
	if r != null and ex.has("score"):
		assert_eq(s.current_hole_state().score(), int(ex["score"]), "%s score" % sc["id"])
	TestHelpers.cleanup_repo(s.repo)
	return r

extends TestCase


func test_zero_goals_consumes_and_counts_stroke() -> void:
	var s := TestHelpers.make_session()
	var start := s.ball_pos
	var id := TestHelpers.add_player(s.repo, 10, 0)
	s.set_mode(ShotTypes.Mode.GOALS)
	assert_true(s.select_footballer(id))
	assert_true(s.take_shot())
	assert_false(s.pool.is_available(id), "consumed at commit")
	assert_eq(s.current_hole_state().strokes, 1)
	s.advance(0.1)
	assert_eq(s.state, ShotTypes.State.SHOT_RESULT)
	assert_eq(s.ball_pos, start, "ball unmoved")
	assert_eq(s.last_result.total_m, 0.0)
	TestHelpers.cleanup_repo(s.repo)


func test_zero_caps_consumes_and_counts_stroke() -> void:
	var s := TestHelpers.make_session()
	var start := s.ball_pos
	var r := TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 0, 5)
	assert_true(r != null)
	assert_eq(s.current_hole_state().strokes, 1)
	assert_eq(s.ball_pos, start)
	TestHelpers.cleanup_repo(s.repo)


func test_shot_commit_cannot_run_twice() -> void:
	var s := TestHelpers.make_session()
	var id := TestHelpers.add_player(s.repo, 100, 5)
	var id2 := TestHelpers.add_player(s.repo, 100, 5)
	s.select_footballer(id)
	assert_true(s.take_shot())
	assert_false(s.take_shot(), "second tap ignored during motion")
	s.select_footballer(id2)
	assert_false(s.take_shot(), "new selection still cannot shoot during motion")
	assert_eq(s.current_hole_state().strokes, 1)
	assert_true(s.pool.is_available(id2), "second player not consumed")
	s.skip_motion()
	s.skip_motion()
	assert_eq(s.current_hole_state().shots.size(), 1, "result handled once")
	assert_false(s.take_shot(), "cannot shoot while result shown")
	TestHelpers.cleanup_repo(s.repo)


func test_invalid_shot_consumes_nothing() -> void:
	var s := TestHelpers.make_session()
	assert_false(s.take_shot(), "no footballer selected")
	assert_eq(s.current_hole_state().strokes, 0)
	var id := TestHelpers.add_player(s.repo, 50, 5)
	s.pool.consume(id)
	assert_false(s.select_footballer(id), "used footballer not selectable")
	assert_false(s.select_footballer("does-not-exist"))
	assert_eq(s.current_hole_state().strokes, 0)
	assert_eq(s.pool.used_count(), 1)
	TestHelpers.cleanup_repo(s.repo)


func test_used_footballer_persists_across_holes_and_resets_on_new_round() -> void:
	var s2 := TestHelpers.make_session()
	var a := TestHelpers.add_player(s2.repo, 2, 0)
	s2.select_footballer(a)
	s2.take_shot()
	s2.skip_motion()
	s2.acknowledge_result()
	# play to max score on hole 1, then move to hole 2 normally
	while s2.state == ShotTypes.State.AIMING:
		TestHelpers.shoot(s2, ShotTypes.Mode.GOALS, 0, 0)
	assert_eq(s2.state, ShotTypes.State.HOLE_COMPLETE)
	assert_eq(s2.current_hole_state().completion, ShotTypes.COMPLETION_MAX_SCORE)
	assert_eq(s2.current_hole_state().score(), 8)
	s2.next_hole()
	assert_eq(s2.round_state.current_index, 1)
	assert_false(s2.pool.is_available(a), "still used on hole 2")
	assert_false(s2.select_footballer(a))
	s2.start_round(TestHelpers.load_holes(), 1)
	assert_true(s2.pool.is_available(a), "new match resets pool")
	assert_eq(s2.repo.get_by_id(a).caps, 2, "data retained")
	TestHelpers.cleanup_repo(s2.repo)


func test_par_plus_five_auto_completes() -> void:
	var s := TestHelpers.make_session()
	for i in 8:
		assert_eq(s.state, ShotTypes.State.AIMING, "shot %d allowed" % (i + 1))
		TestHelpers.shoot(s, ShotTypes.Mode.GOALS, 0, 0)
	assert_eq(s.state, ShotTypes.State.HOLE_COMPLETE)
	assert_eq(s.current_hole_state().strokes, 8)
	assert_false(s.take_shot(), "no shots after completion")
	TestHelpers.cleanup_repo(s.repo)


func test_holeout_requires_rest_inside_radius() -> void:
	var s := TestHelpers.make_session()
	var cup := s.hole.cup_position()
	# Place 8 m short of the cup on the green, then putt firmly THROUGH the radius.
	var dir := (Vector3(cup.x, 0, cup.z) - Vector3(s.hole.tee.x, 0, s.hole.tee.y)).normalized()
	var p := cup - dir * 8.0
	assert_eq(s.dev_place_ball(p.x, p.z), "")
	var b := Units.dir_to_bearing(cup - s.ball_pos) + 2.5  # miss the cup slightly
	var r := TestHelpers.shoot(s, ShotTypes.Mode.GOALS, 0, 80, b)
	assert_false(r.holed, "rolled through radius without stopping inside")
	assert_gt(Units.horizontal_distance(r.final_pos, cup), Units.feet_to_m(5.0))
	assert_eq(s.state, ShotTypes.State.AIMING)
	TestHelpers.cleanup_repo(s.repo)


func test_holeout_when_stopping_inside_radius() -> void:
	var s := TestHelpers.make_session()
	var cup := s.hole.cup_position()
	var p := cup + Vector3(0, 0, -6.0)
	assert_eq(s.dev_place_ball(p.x, p.z), "")
	# Aim beside the cup so physical capture cannot happen; rely on 5 ft rule.
	var b := Units.dir_to_bearing(cup - s.ball_pos) + 8.0
	var r := TestHelpers.shoot(s, ShotTypes.Mode.GOALS, 0, 19, b)
	var d := Units.horizontal_distance(r.final_pos, cup)
	note("stopped %.2f ft from cup, holed=%s" % [Units.m_to_feet(d), r.holed])
	assert_eq(r.holed, d <= Units.feet_to_m(5.0), "holed iff rest within 5 ft")
	TestHelpers.cleanup_repo(s.repo)


func test_zero_radius_physical_cup_entry() -> void:
	var s := TestHelpers.make_session()
	s.holeout_radius_ft = 0.0
	var cup := s.hole.cup_position()
	var p := cup + Vector3(0.0, 0, -3.0)
	s.dev_place_ball(p.x, p.z)
	var holed := false
	var base_b := Units.dir_to_bearing(cup - s.ball_pos)
	# The green is tilted, so read the break: search aim offset and strength.
	for goals in [8, 9, 10, 11, 12]:
		for off_i in range(-16, 17):
			var r := TestHelpers.shoot(s, ShotTypes.Mode.GOALS, 0, goals, base_b + off_i * 0.5)
			if r.holed:
				holed = true
				assert_eq(r.end_reason, "cup")
				assert_eq(s.state, ShotTypes.State.HOLE_COMPLETE)
				note("dropped with %d goals, aim offset %.1f deg" % [goals, off_i * 0.5])
				break
			assert_gt(Units.horizontal_distance(r.final_pos, cup), 0.0)
			s.dev_undo()
		if holed:
			break
	assert_true(holed, "ball can physically drop at 0 ft setting")
	TestHelpers.cleanup_repo(s.repo)


func test_water_gives_one_penalty_and_safe_relief() -> void:
	var defs := TestHelpers.load_holes()
	var s := TestHelpers.make_session(defs)
	s.dev_select_hole(2)
	s.begin_play()
	var lake: HoleDefinition.Ellipse = s.hole.waters[0]
	var start := Vector3(lake.cx, 0, lake.cz - 40.0)
	assert_eq(s.dev_place_ball(start.x, start.z), "")
	s.wind_custom = true
	s.wind_custom_speed = 0.0
	var r := TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 44, 0, 0.0)
	assert_eq(r.hazard, "WATER")
	assert_eq(r.penalty, 1)
	assert_eq(s.current_hole_state().strokes, 1)
	assert_eq(s.current_hole_state().penalties, 1)
	assert_eq(s.current_hole_state().score(), 2)
	assert_true(s.hole.is_safe_spot(s.ball_pos.x, s.ball_pos.z, 0.0), "relief is safe")
	assert_near(s.ball_pos.y, s.hole.terrain_height(s.ball_pos.x, s.ball_pos.z) + s.cfg.ball_radius, 1e-4, "on ground")
	note("relief via %s at %s" % [r.relief_method, str(r.relief_pos)])
	TestHelpers.cleanup_repo(s.repo)


func test_oob_gives_one_penalty_and_safe_relief() -> void:
	var s := TestHelpers.make_session()
	s.wind_custom = true
	s.wind_custom_speed = 0.0
	var r := TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 120, 0, 90.0)  # hard right: only the far map edge is OOB (play area ends 65 m right of the tee)
	assert_eq(r.hazard, "OOB")
	assert_eq(r.penalty, 1)
	assert_eq(s.current_hole_state().score(), 2)
	assert_true(s.hole.in_bounds(s.ball_pos.x, s.ball_pos.z))
	assert_true(s.hole.is_safe_spot(s.ball_pos.x, s.ball_pos.z, 0.0))
	TestHelpers.cleanup_repo(s.repo)


func test_dev_undo_restores_everything() -> void:
	var s := TestHelpers.make_session()
	var start := s.ball_pos
	var id := TestHelpers.add_player(s.repo, 120, 4)
	s.select_footballer(id)
	s.take_shot()
	s.skip_motion()
	assert_true(s.ball_pos != start)
	assert_true(s.dev_undo())
	assert_eq(s.ball_pos, start)
	assert_eq(s.current_hole_state().strokes, 0)
	assert_true(s.pool.is_available(id))
	assert_eq(s.history.size(), 0)
	TestHelpers.cleanup_repo(s.repo)


func test_dev_replay_no_duplicate_scoring_and_identical_result() -> void:
	var s := TestHelpers.make_session()
	var id := TestHelpers.add_player(s.repo, 140, 4)
	s.select_footballer(id)
	s.take_shot()
	s.skip_motion()
	var first := s.last_result
	assert_true(s.dev_replay())
	s.skip_motion()
	var second := s.last_result
	assert_eq(s.current_hole_state().strokes, 1, "still one stroke")
	assert_eq(s.pool.used_count(), 1, "consumed once")
	assert_eq(s.history.size(), 1)
	assert_eq(first.final_pos, second.final_pos, "deterministic replay")
	assert_true(second.developer_replay)
	TestHelpers.cleanup_repo(s.repo)


func test_stats_hidden_until_resolution() -> void:
	var s := TestHelpers.make_session()
	var id := TestHelpers.add_player(s.repo, 150, 4)
	s.select_footballer(id)
	s.take_shot()
	assert_true(s.last_result == null, "no result object while in motion")
	s.advance(0.5)
	assert_eq(s.state, ShotTypes.State.BALL_IN_MOTION)
	assert_true(s.last_result == null)
	s.skip_motion()
	assert_true(s.last_result != null and s.last_result.stat_value == 150)
	TestHelpers.cleanup_repo(s.repo)


func test_restart_hole_returns_hole_consumptions() -> void:
	var s := TestHelpers.make_session()
	var id := TestHelpers.add_player(s.repo, 100, 2)
	s.select_footballer(id)
	s.take_shot()
	s.skip_motion()
	s.acknowledge_result()
	s.dev_restart_hole()
	assert_eq(s.current_hole_state().strokes, 0)
	assert_true(s.pool.is_available(id))
	TestHelpers.cleanup_repo(s.repo)


func test_spin_recorded_and_replayed() -> void:
	var s := TestHelpers.make_session()
	s.set_spin(-0.73)
	assert_near(s.spin, -0.75, 1e-9, "spin snaps to 0.05")
	var id := TestHelpers.add_player(s.repo, 120, 3)
	s.select_footballer(id)
	s.take_shot()
	s.skip_motion()
	var first := s.last_result
	assert_near(first.spin, -0.75, 1e-9)
	assert_true(s.dev_replay())
	s.skip_motion()
	assert_eq(s.last_result.final_pos, first.final_pos, "replay with spin is deterministic")
	assert_near(s.last_result.spin, -0.75, 1e-9)
	TestHelpers.cleanup_repo(s.repo)


func test_no_caps_on_the_green_and_spin_resets() -> void:
	var s := TestHelpers.make_session()
	var cup := s.hole.cup_position()
	assert_eq(s.dev_place_ball(cup.x, cup.z - 5.0), "")
	assert_eq(s.current_lie(), Surface.Type.GREEN)
	s.set_mode(ShotTypes.Mode.CAPS)
	assert_eq(s.mode, ShotTypes.Mode.GOALS, "caps refused on the green")
	var id := TestHelpers.add_player(s.repo, 30, 3)
	s.select_footballer(id)
	s.mode = ShotTypes.Mode.CAPS  # bypass set_mode: take_shot must still refuse
	assert_true(s.can_take_shot() != "", "take_shot validates the green rule")
	assert_false(s.take_shot())
	assert_eq(s.current_hole_state().strokes, 0, "refused shot costs nothing")
	assert_true(s.pool.is_available(id))
	# ball lands on the green after a caps shot -> mode auto-switches to Goals
	var s2 := TestHelpers.make_session()
	var c2 := s2.hole.cup_position()
	s2.dev_place_ball(c2.x, c2.z - 30.0)
	s2.set_mode(ShotTypes.Mode.CAPS)
	s2.set_spin(0.5)
	var r := TestHelpers.shoot(s2, ShotTypes.Mode.CAPS, 33, 0)
	assert_eq(s2.spin, 0.0, "spin reset after the shot")
	if s2.current_lie() == Surface.Type.GREEN:
		assert_eq(s2.mode, ShotTypes.Mode.GOALS, "auto-switched to Goals on the green")
	assert_true(r != null)
	TestHelpers.cleanup_repo(s.repo)
	TestHelpers.cleanup_repo(s2.repo)


func test_bigger_cup_default_and_setting() -> void:
	var cfg := PhysicsConfig.new()
	assert_near(cfg.cup_diameter_in(), 12.0, 1e-6, "default 12 in")
	cfg.set_cup_diameter_in(4.25)
	assert_near(cfg.cup_radius, PhysicsConfig.REGULATION_CUP_RADIUS, 0.0005)
	assert_near(cfg.cup_capture_speed_eff(), cfg.cup_capture_speed, 0.01, "regulation cup: base capture speed")
	cfg.set_cup_diameter_in(100.0)
	assert_near(cfg.cup_diameter_in(), 40.0, 1e-6, "clamped to 40 in")

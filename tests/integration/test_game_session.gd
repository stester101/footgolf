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


func test_once_per_mode_session_reuses_only_other_mode() -> void:
	var s := TestHelpers.make_session()
	s.start_round(TestHelpers.load_holes(), 12345, FootballerPool.ReuseRule.ONCE_PER_MODE)
	s.begin_play()
	var id := TestHelpers.add_player(s.repo, 0, 0)
	assert_true(s.select_footballer(id))
	assert_true(s.take_shot())
	s.skip_motion()
	s.acknowledge_result()
	assert_false(s.pool.is_available(id, ShotTypes.Mode.CAPS))
	assert_false(s.select_footballer(id), "CAPS already consumed")
	s.set_mode(ShotTypes.Mode.GOALS)
	assert_true(s.select_footballer(id), "same footballer is available for GOALS")
	assert_true(s.take_shot())
	s.skip_motion()
	s.acknowledge_result()
	assert_eq(s.current_hole_state().strokes, 2)
	assert_eq(s.pool.used_count(), 2)
	assert_false(s.pool.is_available(id, ShotTypes.Mode.GOALS))
	s.start_round(TestHelpers.load_holes(), 6789)
	assert_eq(s.pool.reuse_rule, FootballerPool.ReuseRule.ONCE_PER_ROUND, "new round uses default rule")
	TestHelpers.cleanup_repo(s.repo)


func test_stat_source_and_shot_style_are_independent() -> void:
	var s := TestHelpers.make_session()
	var flat := HoleDefinition.make_flat(Surface.Type.FAIRWAY)
	flat.id = "neutral_shot"
	s.start_round([flat], 12345)
	s.begin_play()
	s.wind_custom = true
	s.wind_custom_speed = 0.0
	for source in [ShotTypes.Mode.CAPS, ShotTypes.Mode.GOALS]:
		for motion in [ShotTypes.Style.FLIGHT, ShotTypes.Style.ROLL]:
			s.dev_reset_ball()
			s.set_mode(source)
			s.set_style(motion)
			var id := TestHelpers.add_player(s.repo, 80, 40)
			assert_true(s.select_footballer(id))
			assert_true(s.take_shot())
			s.skip_motion()
			var r := s.last_result
			assert_eq(r.mode, source)
			assert_eq(r.style, motion)
			var target := Units.caps_to_carry_m(80) if source == ShotTypes.Mode.CAPS else Units.goals_to_roll_m(40)
			assert_near(r.base_distance_m, target, 0.001, "source always determines yard/foot distance")
			if motion == ShotTypes.Style.FLIGHT:
				assert_true(r.had_contact, "flight makes first contact")
				assert_near(r.carry_m, target, 0.4, "flight calibrates carry regardless of source")
			else:
				assert_eq(r.carry_m, 0.0, "roll has no airborne carry")
				assert_near(r.total_m, target, 1.0, "roll calibrates travel regardless of source")
			s.acknowledge_result()
			if s.state == ShotTypes.State.HOLE_COMPLETE:
				s.next_hole()
				s.begin_play()
	TestHelpers.cleanup_repo(s.repo)


func test_rough_lie_reduces_goals_flight_carry_slightly() -> void:
	var s := TestHelpers.make_session()
	var flat := HoleDefinition.make_flat(Surface.Type.FAIRWAY)
	flat.id = "neutral_lie"
	s.start_round([flat], 12345)
	s.begin_play()
	s.wind_custom = true
	s.wind_custom_speed = 0.0
	s.dev_set_lie_override(Surface.Type.ROUGH)
	s.set_mode(ShotTypes.Mode.GOALS)
	s.set_style(ShotTypes.Style.FLIGHT)
	var id := TestHelpers.add_player(s.repo, 0, 100)
	assert_true(s.select_footballer(id))
	assert_true(s.take_shot())
	s.skip_motion()
	var r := s.last_result
	assert_eq(r.mode, ShotTypes.Mode.GOALS)
	assert_eq(r.style, ShotTypes.Style.FLIGHT)
	assert_gt(r.lie_factor, 0.79)  # rough: 10-20% shorter (owner, 2026-11-08)
	assert_lt(r.lie_factor, 0.91)
	assert_near(r.carry_m, r.target_distance_m, 0.3, "calibrated flight includes lie factor")
	assert_lt(r.carry_m, Units.goals_to_roll_m(100), "rough costs distance even with GOALS")
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
	# hole out on hole 1 (drop next to the cup, putt it in), then move to hole 2 normally
	var cup := s2.hole.cup_position()
	s2.dev_place_ball(cup.x, cup.z - 1.0)
	TestHelpers.shoot(s2, ShotTypes.Mode.GOALS, 0, 1, Units.dir_to_bearing(cup - s2.ball_pos))
	assert_eq(s2.state, ShotTypes.State.HOLE_COMPLETE)
	assert_eq(s2.current_hole_state().completion, ShotTypes.COMPLETION_HOLED)
	s2.next_hole()
	assert_eq(s2.round_state.current_index, 1)
	assert_false(s2.pool.is_available(a), "still used on hole 2")
	assert_false(s2.select_footballer(a))
	s2.start_round(TestHelpers.load_holes(), 1)
	assert_true(s2.pool.is_available(a), "new match resets pool")
	assert_eq(s2.repo.get_by_id(a).caps, 2, "data retained")
	TestHelpers.cleanup_repo(s2.repo)


func test_no_maximum_score() -> void:
	var s := TestHelpers.make_session()
	for i in 14:
		assert_eq(s.state, ShotTypes.State.AIMING, "shot %d allowed (no par+5 cap)" % (i + 1))
		TestHelpers.shoot(s, ShotTypes.Mode.GOALS, 0, 0)
	assert_eq(s.current_hole_state().strokes, 14)
	assert_eq(s.current_hole_state().score(), 14, "score is not clamped")
	assert_false(s.current_hole_state().complete, "hole only ends when holed")
	TestHelpers.cleanup_repo(s.repo)


func test_holeout_requires_rest_inside_radius() -> void:
	var s := TestHelpers.make_session()
	s.cfg.set_cup_diameter_in(12.0)  # a deliberate near-miss: with the 6 ft default cup this ball would simply drop
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


func test_mulligan_is_round_locked_and_restores_the_entire_shot() -> void:
	var s := TestHelpers.make_session()
	s.start_round(TestHelpers.load_holes(), 12345, FootballerPool.ReuseRule.ONCE_PER_ROUND, 1)
	s.begin_play()
	var start := s.ball_pos
	var id := TestHelpers.add_player(s.repo, 120, 4)
	assert_true(s.select_footballer(id))
	assert_false(s.can_mulligan(), "cannot use one before shooting")
	assert_true(s.take_shot())
	assert_false(s.use_mulligan(), "cannot cancel a shot in motion")
	s.skip_motion()
	assert_true(s.can_mulligan())
	assert_true(s.use_mulligan())
	assert_eq(s.state, ShotTypes.State.AIMING)
	assert_eq(s.ball_pos, start)
	assert_eq(s.current_hole_state().strokes, 0, "original attempt does not score")
	assert_eq(s.history.size(), 0)
	assert_eq(s.round_state.mulligan_audit.size(), 1, "original attempt kept for audit")
	assert_false(s.pool.is_available(id), "original footballer stays consumed")
	assert_eq(s.round_state.mulligans_remaining(), 0)
	assert_false(s.use_mulligan(), "cannot spend the allowance twice")
	var id2 := TestHelpers.add_player(s.repo, 0, 0)
	assert_true(s.select_footballer(id2))
	assert_true(s.take_shot())
	s.skip_motion()
	assert_true(s.last_result.is_replacement)
	assert_false(s.can_mulligan(), "replacement cannot be mulliganed")
	s.acknowledge_result()
	assert_false(s.can_mulligan(), "result dismissed")
	s.start_round(TestHelpers.load_holes(), 12345)
	assert_eq(s.round_state.mulligans_allowed, 0, "next round defaults to off")
	TestHelpers.cleanup_repo(s.repo)


func test_unlimited_mulligans_one_per_shot_and_footballers_stay_spent() -> void:
	var s := TestHelpers.make_session()
	s.start_round(TestHelpers.load_holes(), 12345, FootballerPool.ReuseRule.ONCE_PER_ROUND, -1)
	s.begin_play()
	for i in 2:
		# original shot, mulliganed
		var id := TestHelpers.add_player(s.repo, 0, 0)
		assert_true(s.select_footballer(id))
		assert_true(s.take_shot())
		s.skip_motion()
		assert_true(s.use_mulligan())
		assert_eq(s.current_hole_state().strokes, i, "original attempt does not score")
		assert_false(s.pool.is_available(id), "original stays spent")
		# replacement: cannot be mulliganed itself
		var id2 := TestHelpers.add_player(s.repo, 0, 0)
		assert_true(s.select_footballer(id2))
		assert_true(s.take_shot())
		s.skip_motion()
		assert_true(s.last_result.is_replacement)
		assert_false(s.can_mulligan())
		s.acknowledge_result()
	assert_eq(s.round_state.mulligans_used, 2)
	assert_eq(s.round_state.mulligan_audit.size(), 2)
	assert_eq(s.current_hole_state().strokes, 2, "only the two replacement shots score")

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


func test_caps_allowed_on_the_green_and_spin_resets() -> void:
	var s := TestHelpers.make_session()
	var cup := s.hole.cup_position()
	assert_eq(s.dev_place_ball(cup.x, cup.z - 5.0), "")
	assert_eq(s.current_lie(), Surface.Type.GREEN)
	s.set_mode(ShotTypes.Mode.CAPS)
	assert_eq(s.mode, ShotTypes.Mode.CAPS, "caps allowed on the green")
	var id := TestHelpers.add_player(s.repo, 3, 3)
	s.select_footballer(id)
	assert_eq(s.can_take_shot(), "")
	s.set_spin(0.5)
	s.set_trajectory(ShotTypes.Trajectory.HIGH)
	assert_true(s.take_shot())
	s.skip_motion()
	assert_eq(s.current_hole_state().strokes, 1)
	assert_eq(s.last_result.trajectory, ShotTypes.Trajectory.HIGH)
	assert_eq(s.spin, 0.0, "spin reset after the shot")
	assert_eq(s.trajectory, ShotTypes.Trajectory.STANDARD, "trajectory reset after the shot")
	TestHelpers.cleanup_repo(s.repo)


func test_trajectory_keeps_neutral_carry_and_changes_flight() -> void:
	var cfg := PhysicsConfig.new()
	var apex := {}
	for t in [ShotTypes.Trajectory.PUNCH, ShotTypes.Trajectory.LOW, ShotTypes.Trajectory.STANDARD, ShotTypes.Trajectory.HIGH]:
		var ang := ShotTypes.trajectory_angle(t, cfg.launch_angle_deg)
		for yd in [5, 60, 150, 230]:
			var target := Units.caps_to_carry_m(yd)
			var v := ShotCalculator.solve_caps_speed(target, cfg, 0.0, ang)
			var carry := ShotCalculator.measure_neutral_carry(v, cfg, 0.0, ang)
			assert_near(Units.m_to_yards(carry), float(yd), maxf(0.25, yd * 0.005), "%s %d yd exact" % [ShotTypes.trajectory_name(t), yd])
		var sim := TestHelpers.flat_sim(Surface.Type.FAIRWAY)
		var v2 := ShotCalculator.solve_caps_speed(Units.caps_to_carry_m(120), cfg, 0.0, ang)
		sim.launch(Vector3(0, cfg.ball_radius, 0), ShotCalculator.launch_velocity(Vector3(0, 0, 1), v2, ang), true)
		sim.run_until_done()
		apex[t] = sim.max_height
		note("%s %.0f deg: 120-cap apex %.1f m, speed %.1f m/s, total %.1f m" % [ShotTypes.trajectory_name(t), ang, sim.max_height, v2, sim.pos.z])
	assert_lt(float(apex[ShotTypes.Trajectory.PUNCH]), float(apex[ShotTypes.Trajectory.LOW]))
	assert_lt(float(apex[ShotTypes.Trajectory.LOW]), float(apex[ShotTypes.Trajectory.STANDARD]))
	assert_lt(float(apex[ShotTypes.Trajectory.STANDARD]), float(apex[ShotTypes.Trajectory.HIGH]))
	assert_lt(float(apex[ShotTypes.Trajectory.PUNCH]), 8.0, "punch stays under a canopy")


func test_bigger_cup_default_and_setting() -> void:
	var cfg := PhysicsConfig.new()
	assert_near(cfg.cup_diameter_in(), 72.0, 1e-6, "default 6 ft")
	cfg.set_cup_diameter_in(4.25)
	assert_near(cfg.cup_radius, PhysicsConfig.REGULATION_CUP_RADIUS, 0.0005)
	assert_near(cfg.cup_capture_speed_eff(), cfg.cup_capture_speed, 0.01, "regulation cup: base capture speed")
	cfg.set_cup_diameter_in(100.0)
	assert_near(cfg.cup_diameter_in(), 72.0, 1e-6, "clamped to 72 in")


func test_lie_effect_preview_matches_the_real_shot() -> void:
	var s := TestHelpers.make_session()
	var flat := HoleDefinition.make_flat(Surface.Type.FAIRWAY)
	flat.id = "neutral_lie"
	s.start_round([flat], 12345)
	s.begin_play()
	s.wind_custom = true
	s.wind_custom_speed = 0.0
	s.dev_set_lie_override(Surface.Type.BUNKER)
	s.set_mode(ShotTypes.Mode.CAPS)
	s.set_style(ShotTypes.Style.FLIGHT)
	var pv := s.lie_effect_preview()
	assert_eq(int(pv["min_pct"]), 20)
	assert_eq(int(pv["max_pct"]), 40)
	var id := TestHelpers.add_player(s.repo, 100, 0)
	assert_true(s.select_footballer(id))
	assert_true(s.take_shot())
	s.skip_motion()
	assert_eq(int(round((1.0 - s.last_result.lie_factor) * 100.0)), int(pv["exact_pct"]), "exact preview equals the real penalty")
	TestHelpers.cleanup_repo(s.repo)


func test_pass_and_play_alternates_turns_with_separate_scores() -> void:
	var s := TestHelpers.make_session()
	s.start_round(TestHelpers.load_holes(), 12345, FootballerPool.ReuseRule.ONCE_PER_ROUND, 0, 2)
	s.begin_play()
	assert_eq(s.player_count(), 2)
	assert_eq(s.turn, 0)
	var p0 := s.round_state
	var first := TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 30, 0)
	assert_true(first != null)
	assert_eq(s.turn, 1, "turn passes straight to player 2 after acknowledge")
	assert_true(s.round_state != p0, "player 2 has their own round state")
	assert_eq(s.current_hole_state().strokes, 0, "player 2 has not shot yet")
	assert_eq(s.slot_round_state(0).current().strokes, 1, "player 1 keeps their stroke")
	var tee := s.hole.tee_position(s.cfg.ball_radius)
	assert_true(s.ball_pos.distance_to(tee) < 0.01, "player 2 plays from the tee, not player 1's ball")
	TestHelpers.shoot(s, ShotTypes.Mode.GOALS, 0, 1)
	assert_eq(s.turn, 1, "player 2 is still furthest from the cup (0-distance shot), so plays again")
	assert_eq(s.slot_round_state(1).current().strokes, 1)
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 60, 2)
	assert_eq(s.turn, 0, "after a 60-cap shot player 2 is nearer the cup than player 1 (still on the tee), so player 1 is furthest")
	TestHelpers.cleanup_repo(s.repo)

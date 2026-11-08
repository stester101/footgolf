extends TestCase
## Round Setup difficulty (RoundConfig), optional maximum score, frozen rules, once-per-mode wiring.


func _zero_shot(s: GameSession, mode: int = ShotTypes.Mode.GOALS) -> void:
	TestHelpers.shoot(s, mode, 0, 0)


func test_defaults_equal_previous_behaviour() -> void:
	var rc := RoundConfig.new()
	assert_eq(rc.max_over_par(), -1, "no maximum score")
	assert_near(rc.wind_multiplier(), 1.0, 1e-9)
	assert_false(rc.reuse_per_mode)
	assert_eq(rc.pool_rule(), FootballerPool.ReuseRule.ONCE_PER_ROUND)
	assert_near(rc.gimme_ft, ScoringService.DEFAULT_HOLEOUT_FT, 1e-9)
	assert_near(rc.cup_diameter_ft * 12.0, PhysicsConfig.new().cup_diameter_in(), 1e-6)
	assert_eq(ScoringService.max_score_for_par(4), 0, "0 = unlimited")


func test_from_settings_and_write_defaults_roundtrip() -> void:
	var st := SettingsStore.new()
	st.save_path = "user://test_rc_settings_%d.json" % randi()
	var rc := RoundConfig.from_settings(st)
	rc.reuse_per_mode = true
	rc.max_score_mode = RoundConfig.MaxScore.CUSTOM
	rc.max_over_par_custom = 3
	rc.wind_mode = RoundConfig.WindMode.SCALED
	rc.wind_scale = 0.5
	rc.cup_diameter_ft = 4.0
	rc.gimme_ft = 3.0
	rc.show_aim_arrow = false
	rc.write_defaults(st)
	var st2 := SettingsStore.new()
	st2.save_path = st.save_path
	st2.load_settings()
	var back := RoundConfig.from_settings(st2)
	assert_true(back.reuse_per_mode)
	assert_eq(back.max_over_par(), 3)
	assert_eq(back.wind_mode, RoundConfig.WindMode.SCALED)
	assert_near(back.wind_scale, 0.5, 1e-9)
	assert_near(back.cup_diameter_ft, 4.0, 1e-6)
	assert_near(back.gimme_ft, 3.0, 1e-9)
	assert_false(back.show_aim_arrow)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(st.save_path))


func test_max_score_labels_and_values() -> void:
	var rc := RoundConfig.new()
	rc.max_score_mode = RoundConfig.MaxScore.PAR_PLUS_5
	assert_eq(rc.max_over_par(), 5)
	assert_eq(ScoringService.max_score_for_par(4, rc.max_over_par()), 9)
	assert_eq(rc.max_score_label(), "Par + 5")


func test_scoring_cap_ends_hole_and_records_cap() -> void:
	var hs := HoleState.new()
	hs.par = 3
	hs.max_score = 5
	hs.strokes = 4
	assert_eq(ScoringService.apply_shot(hs, 0, false), "", "below cap: still in play")
	hs.strokes = 5
	assert_eq(ScoringService.apply_shot(hs, 0, false), ShotTypes.COMPLETION_MAX_SCORE)
	assert_true(hs.complete)
	assert_eq(hs.score(), 5)
	# a penalty can overshoot: the record is still the cap
	var h2 := HoleState.new()
	h2.par = 3
	h2.max_score = 5
	h2.strokes = 4
	ScoringService.apply_shot(h2, 2, false)
	assert_eq(h2.raw_total(), 6)
	assert_eq(h2.score(), 5, "recorded as the cap")
	assert_eq(h2.copy().max_score, 5, "copy keeps the cap")


func test_no_cap_by_default() -> void:
	var hs := HoleState.new()
	hs.par = 3
	hs.strokes = 40
	assert_eq(ScoringService.apply_shot(hs, 0, false), "")
	assert_false(hs.complete)
	assert_eq(hs.score(), 40)


func test_holing_at_cap_is_a_normal_score() -> void:
	var hs := HoleState.new()
	hs.par = 3
	hs.max_score = 4
	hs.strokes = 4
	assert_eq(ScoringService.apply_shot(hs, 0, true), ShotTypes.COMPLETION_HOLED)
	assert_eq(hs.score(), 4)


func test_session_hole_ends_at_cap() -> void:
	var s := GameSession.new(PhysicsConfig.new(), TestHelpers.make_repo())
	var rc := RoundConfig.new()
	rc.max_score_mode = RoundConfig.MaxScore.CUSTOM
	rc.max_over_par_custom = 1
	s.apply_rules(rc)
	s.start_round(TestHelpers.load_holes(), 12345)
	s.begin_play()
	var par := s.current_hole_state().par
	assert_eq(s.current_hole_state().max_score, par + 1)
	for i in par:
		_zero_shot(s)
		assert_false(s.current_hole_state().complete, "not yet at the cap (shot %d)" % (i + 1))
	_zero_shot(s)
	assert_true(s.current_hole_state().complete, "hole ends at the cap")
	assert_eq(s.current_hole_state().completion, ShotTypes.COMPLETION_MAX_SCORE)
	assert_eq(s.current_hole_state().score(), par + 1)
	assert_eq(s.state, ShotTypes.State.HOLE_COMPLETE)
	assert_eq(s.round_state.holes_completed(), 1)
	TestHelpers.cleanup_repo(s.repo)


func test_session_without_rules_has_no_cap() -> void:
	var s := TestHelpers.make_session()
	assert_eq(s.current_hole_state().max_score, 0)
	TestHelpers.cleanup_repo(s.repo)


func test_mulligan_of_cap_shot_reopens_hole() -> void:
	var s := GameSession.new(PhysicsConfig.new(), TestHelpers.make_repo())
	var rc := RoundConfig.new()
	rc.max_score_mode = RoundConfig.MaxScore.CUSTOM
	rc.max_over_par_custom = 1
	s.apply_rules(rc)
	s.start_round(TestHelpers.load_holes(), 12345, FootballerPool.ReuseRule.ONCE_PER_ROUND, 1)
	s.begin_play()
	var par := s.current_hole_state().par
	for i in par:
		_zero_shot(s)
	var id := TestHelpers.add_player(s.repo, 0, 0)
	s.set_mode(ShotTypes.Mode.GOALS)
	s.select_footballer(id)
	assert_true(s.take_shot())
	s.skip_motion()
	assert_true(s.current_hole_state().complete)
	assert_true(s.can_mulligan())
	assert_true(s.use_mulligan())
	assert_false(s.current_hole_state().complete, "mulligan undoes the capped ending")
	assert_eq(s.current_hole_state().strokes, par)
	TestHelpers.cleanup_repo(s.repo)


func test_apply_rules_freezes_gimme_wind_and_cup() -> void:
	var cfg := PhysicsConfig.new()
	var s := GameSession.new(cfg, TestHelpers.make_repo())
	var rc := RoundConfig.new()
	rc.gimme_ft = 3.0
	rc.cup_diameter_ft = 5.0
	rc.wind_mode = RoundConfig.WindMode.SCALED
	rc.wind_scale = 0.5
	s.apply_rules(rc)
	s.start_round(TestHelpers.load_holes(), 1)
	s.begin_play()
	assert_near(s.holeout_radius_ft, 3.0, 1e-9)
	assert_near(cfg.cup_diameter_in(), 60.0, 1e-6)
	assert_near(s.wind_speed(), s.hole.wind_speed * 0.5, 1e-9)
	rc.wind_mode = RoundConfig.WindMode.NONE
	var s2 := GameSession.new(PhysicsConfig.new(), TestHelpers.make_repo())
	s2.apply_rules(rc)
	s2.start_round(TestHelpers.load_holes(), 1)
	s2.begin_play()
	assert_near(s2.wind_speed(), 0.0, 1e-9)
	TestHelpers.cleanup_repo(s.repo)
	TestHelpers.cleanup_repo(s2.repo)


func test_once_per_mode_rule_wiring() -> void:
	var rc := RoundConfig.new()
	rc.reuse_per_mode = true
	var s := GameSession.new(PhysicsConfig.new(), TestHelpers.make_repo())
	s.apply_rules(rc)
	s.start_round(TestHelpers.load_holes(), 12345, rc.pool_rule())
	s.begin_play()
	assert_eq(s.pool.reuse_rule, FootballerPool.ReuseRule.ONCE_PER_MODE)
	var id := TestHelpers.add_player(s.repo, 50, 20)
	s.set_mode(ShotTypes.Mode.CAPS)
	assert_true(s.select_footballer(id))
	assert_true(s.take_shot())
	s.skip_motion()
	assert_false(s.pool.is_available(id, ShotTypes.Mode.CAPS), "used for Caps")
	assert_true(s.pool.is_available(id, ShotTypes.Mode.GOALS), "still free for Goals")
	TestHelpers.cleanup_repo(s.repo)
	var rc2 := RoundConfig.new()
	assert_eq(rc2.pool_rule(), FootballerPool.ReuseRule.ONCE_PER_ROUND)

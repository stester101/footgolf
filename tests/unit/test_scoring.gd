extends TestCase


func test_max_score_par_plus_five() -> void:
	assert_eq(ScoringService.max_score_for_par(3), 8)
	assert_eq(ScoringService.max_score_for_par(4), 9)
	assert_eq(ScoringService.max_score_for_par(5), 10)


func test_holeout_radius_semantics() -> void:
	var five := Units.feet_to_m(5.0)
	assert_true(ScoringService.is_holed(false, true, five - 0.001, 5.0), "inside 5 ft at rest")
	assert_false(ScoringService.is_holed(false, true, Units.feet_to_m(5.1), 5.0), "5.1 ft stays in play")
	assert_false(ScoringService.is_holed(false, false, 0.1, 5.0), "rolling through radius doesn't count")
	assert_false(ScoringService.is_holed(false, true, 0.01, 0.0), "0 ft requires cup")
	assert_true(ScoringService.is_holed(true, true, 0.0, 0.0), "cup entry at 0 ft")
	assert_true(ScoringService.is_holed(true, false, 0.0, 5.0), "cup entry always holes")
	assert_true(ScoringService.is_holed(false, true, Units.feet_to_m(9.9), 12.0), "radius clamped to 10 ft")
	assert_false(ScoringService.is_holed(false, true, Units.feet_to_m(10.1), 12.0), "radius clamped to 10 ft")


func test_penalty_clamps_to_max() -> void:
	var hs := HoleState.new()
	hs.par = 3
	hs.strokes = 8
	ScoringService.apply_shot(hs, 1, false)
	assert_true(hs.complete)
	assert_eq(hs.completion, ShotTypes.COMPLETION_MAX_SCORE)
	assert_eq(hs.score(), 8, "displayed clamped")
	assert_eq(hs.raw_total(), 9, "raw retained")


func test_round_relative() -> void:
	assert_eq(RoundState.fmt_relative(0), "E")
	assert_eq(RoundState.fmt_relative(2), "+2")
	assert_eq(RoundState.fmt_relative(-1), "-1")

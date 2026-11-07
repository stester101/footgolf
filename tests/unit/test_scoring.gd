extends TestCase


func test_no_score_cap() -> void:
	var hs := HoleState.new()
	hs.par = 3
	hs.strokes = 20
	ScoringService.apply_shot(hs, 1, false)
	assert_false(hs.complete, "never auto-completes")
	assert_eq(hs.score(), 21, "strokes + penalties, uncapped")


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


func test_holed_completes() -> void:
	var hs := HoleState.new()
	hs.par = 4
	hs.strokes = 3
	assert_eq(ScoringService.apply_shot(hs, 0, true), ShotTypes.COMPLETION_HOLED)
	assert_true(hs.complete)


func test_round_relative() -> void:
	assert_eq(RoundState.fmt_relative(0), "E")
	assert_eq(RoundState.fmt_relative(2), "+2")
	assert_eq(RoundState.fmt_relative(-1), "-1")

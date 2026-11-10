extends TestCase
## Polish round 2: feedback cues, accessibility settings, auto-pause rule, round text, hardened settings load.

const TMP := "user://test_polish2_settings.json"


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP + suffix))


func test_haptic_cues() -> void:
	assert_eq(Feedback.haptic_ms("shot"), 35, "shot keeps its old duration")
	assert_eq(Feedback.haptic_ms("holed"), 90, "hole-out keeps its old duration")
	assert_eq(Feedback.haptic_ms("nonsense"), 0)
	assert_eq(Feedback.haptic_for_result(false, 0, 0), "shot")
	assert_eq(Feedback.haptic_for_result(false, 1, 0), "penalty")
	assert_eq(Feedback.haptic_for_result(true, 0, 0), "holed")
	assert_eq(Feedback.haptic_for_result(true, 0, -2), "eagle")
	assert_eq(Feedback.haptic_for_result(true, 1, -3), "eagle")


func test_sfx_stub_respects_mute() -> void:
	Feedback.cue_log.clear()
	assert_false(Feedback.sfx("shot", true), "muted: nothing plays")
	assert_false(Feedback.sfx("bogus", false), "unknown cue ignored")
	assert_true(Feedback.sfx("holed", false))
	assert_eq(Feedback.cue_log, ["holed"])
	for i in 40:
		Feedback.sfx("tap", false)
	assert_true(Feedback.cue_log.size() <= Feedback.CUE_LOG_MAX, "log is bounded")
	Feedback.cue_log.clear()


func test_new_settings_round_trip_and_defaults() -> void:
	_cleanup()
	var a := SettingsStore.new()
	assert_false(a.reduced_motion)
	assert_false(a.large_text)
	assert_true(a.sound_muted, "sound is muted by default")
	assert_true(a.auto_pause)
	assert_near(a.text_scale(), 1.0, 0.0001)
	a.save_path = TMP
	a.reduced_motion = true
	a.large_text = true
	a.sound_muted = false
	a.auto_pause = false
	assert_true(a.save(), "save reports success")
	var b := SettingsStore.new()
	b.save_path = TMP
	b.load_settings()
	assert_true(b.reduced_motion)
	assert_true(b.large_text)
	assert_false(b.sound_muted)
	assert_false(b.auto_pause)
	assert_near(b.text_scale(), 1.25, 0.0001)
	_cleanup()


func test_save_failure_is_reported() -> void:
	var s := SettingsStore.new()
	s.save_path = "user://no_such_dir_polish2/x/settings.json"
	assert_false(s.save(), "unwritable path returns false instead of failing silently")


func test_wrong_types_fall_back_to_defaults() -> void:
	_cleanup()
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string('{"wind_speed": [1,2], "sim_speed": "fast", "max_fps": {"a":1}, "last_players": 99, "holeout_radius_ft": null}')
	f.close()
	var s := SettingsStore.new()
	s.save_path = TMP
	s.load_settings()
	assert_near(s.wind_speed, 0.0, 0.0001)
	assert_near(s.sim_speed, 1.0, 0.0001)
	assert_eq(s.max_fps, 0)
	assert_eq(s.last_players, 4, "out-of-range number is clamped")
	assert_near(s.holeout_radius_ft, ScoringService.DEFAULT_HOLEOUT_FT, 0.0001)
	_cleanup()


func test_auto_pause_rule() -> void:
	var aim := ShotTypes.State.AIMING
	assert_true(Feedback.should_auto_pause(true, false, aim, false, false))
	assert_false(Feedback.should_auto_pause(false, false, aim, false, false), "setting off")
	assert_false(Feedback.should_auto_pause(true, true, aim, false, false), "never online")
	assert_false(Feedback.should_auto_pause(true, false, aim, true, false), "already an overlay")
	assert_false(Feedback.should_auto_pause(true, false, aim, false, true), "developer panel open")
	assert_false(Feedback.should_auto_pause(true, false, ShotTypes.State.BALL_IN_MOTION, false, false), "mid-flight")


func test_round_text() -> void:
	assert_eq(RoundText.score_name(1, 3), "Hole-in-one")
	assert_eq(RoundText.score_name(2, 4), "Eagle")
	assert_eq(RoundText.score_name(3, 4), "Birdie")
	assert_eq(RoundText.score_name(4, 4), "Par")
	assert_eq(RoundText.score_name(5, 4), "Bogey")
	assert_eq(RoundText.score_name(7, 4), "+3")
	var rs := RoundState.new()
	var h := HoleState.new()
	h.hole_name = "First"
	h.par = 3
	h.strokes = 2
	h.penalties = 1
	h.complete = true
	var h2 := HoleState.new()
	h2.hole_name = "Second"
	h2.par = 4
	rs.holes = [h, h2]
	var t := RoundText.build(rs, "2-hole round", "Sam")
	assert_true(t.contains("Player: Sam"))
	assert_true(t.contains("Score 3 (E)"), t)
	assert_true(t.contains("First  par 3  3  Par (+1 pen)"), t)
	assert_false(t.contains("Second"), "unplayed holes are left out")


func test_reconnect_status_counts_down() -> void:
	assert_true(OnlineRoom.reconnect_status(0).contains("60 s"))
	assert_true(OnlineRoom.reconnect_status(30500).contains("30 s") or OnlineRoom.reconnect_status(30500).contains("29 s"))
	assert_true(OnlineRoom.reconnect_status(999999).contains("0 s"), "never negative")

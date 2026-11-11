extends TestCase
## Game feel: procedural SFX synthesis, Feedback routing/mute, outcome callout text.


func test_every_cue_synthesises() -> void:
	for cue in SfxSynth.BUILDERS.keys():
		var w := SfxSynth.stream(cue)
		assert_true(w != null, "cue %s builds" % cue)
		assert_eq(w.format, AudioStreamWAV.FORMAT_16_BITS)
		assert_gt(w.data.size(), 200, "cue %s has audio" % cue)
		assert_lt(w.get_length(), 3.0, "cue %s is short" % cue)
	for alias in SfxSynth.ALIASES.keys():
		assert_true(SfxSynth.has_cue(alias), "alias %s resolves" % alias)


func test_synth_is_deterministic_and_cached() -> void:
	var a := SfxSynth.stream("splash")
	assert_true(a == SfxSynth.stream("splash"), "cached")
	SfxSynth._cache.erase("splash")
	var b := SfxSynth.stream("splash")
	assert_eq(a.data, b.data, "same seed, same samples")


func test_feedback_names_all_synthesisable() -> void:
	for cue in Feedback.SFX_NAMES:
		assert_true(SfxSynth.has_cue(cue), "Feedback cue %s has a sound" % cue)


func test_sfx_respects_mute_with_player() -> void:
	var calls := []
	var fake := FakePlayer.new()
	fake.calls = calls
	Feedback.player = fake
	Feedback.cue_log.clear()
	assert_false(Feedback.sfx("kick", true), "muted: nothing plays")
	assert_eq(calls.size(), 0)
	assert_true(Feedback.sfx("kick", false, 0.5))
	assert_eq(calls.size(), 1)
	assert_near(float(calls[0][1]), 0.5 * Feedback.volume, 1e-6, "gain = strength x volume")
	Feedback.player = null
	Feedback.cue_log.clear()


func test_score_callouts() -> void:
	assert_eq(FxDirector.score_callout(1, 0, -2)[0], "Hole in one!")
	assert_eq(FxDirector.score_callout(2, 1, -2)[0], "Eagle!", "a penalty stroke is not an ace")
	assert_eq(FxDirector.score_callout(3, 0, -1)[0], "Birdie!")
	assert_eq(FxDirector.score_callout(4, 0, 0)[0], "Par")
	assert_eq(FxDirector.score_callout(5, 0, 1)[0], "Bogey")
	assert_eq(FxDirector.score_callout(9, 0, 5)[0], "+5")


class FakePlayer:
	extends RefCounted
	var calls: Array

	func play(cue: String, gain: float, pitch: float) -> void:
		calls.append([cue, gain, pitch])

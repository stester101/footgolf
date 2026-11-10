extends TestCase
## LBT start, tour card + sponsor wildcards, the resumable off-season, adaptive difficulty (opponents only),
## skip-everything seasons and the ensure_defaults migration step.


func _dir() -> String:
	return "user://test_career_off_%d" % (randi() % 1000000)


func _cleanup(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _career(dir: String) -> CareerManager:
	var c := CareerManager.new(CareerSaveManager.new(dir))
	CareerManager.course_source = Callable()
	CareerManager.sim = CareerSim
	assert(c.create("Test Golfer", "England", "short", 777))
	return c


func _reload(dir: String) -> CareerManager:
	var c := CareerManager.new(CareerSaveManager.new(dir))
	assert(bool(c.load_saved().ok))
	return c


func _skip_season(c: CareerManager) -> void:
	while not c.season_finished():
		assert_true(c.skip_event(int(c.next_event()["serial"])))


func _play(c: CareerManager, strokes_vs_par: int) -> Dictionary:
	var t := c.tournament()
	var par := TournamentManager.par_per_round(t)
	var holes: int = ((t["snapshot"] as Dictionary)["holes"] as Array).size()
	var guard := 0
	while String(c.tournament()["status"]) != "complete" and guard < 8:
		assert_true(c.begin_round({}, 0))
		c.complete_round(par + strokes_vs_par, par, holes)
		guard += 1
	return c.finalize_tournament()


func test_new_career_starts_on_the_lbt_with_a_card() -> void:
	var dir := _dir()
	var c := _career(dir)
	assert_true(OffSeason.has_card(c), "tour card from day one")
	assert_true(c.world_rank() > 150 and c.world_rank() < 220, "world rank around 180")
	assert_eq(OffSeason.wildcards_left(c), 0)
	assert_false(c.off_season_active())
	assert_eq(CareerConfig.TOUR_NAME, "LBT")
	assert_true(bool(c.eligibility(c.next_event())["eligible"]))
	assert_true(String(c.eligibility(c.next_event())["reason"]).contains("LBT"))
	assert_eq(AdaptiveDifficulty.mode(c.data), "balanced")
	assert_eq(AdaptiveDifficulty.current_offset(c.data), 0.0)
	assert_false(String(c.data["calendar"][c.data["calendar"].size() - 1]["name"]).contains("Tour Championship"))
	_cleanup(dir)


func test_off_season_resumes_at_the_same_step_and_evolves_once() -> void:
	var dir := _dir()
	var c := _career(dir)
	assert_false(c.begin_off_season(), "not while events remain")
	_skip_season(c)
	var age_before := int((c.golfers_by_id()["g001"] as Dictionary)["age"])
	var status_before := String((c.golfers_by_id()["g001"] as Dictionary)["status"])
	assert_true(c.begin_off_season())
	assert_eq(OffSeason.step(c), "review")
	assert_eq(c.season_id(), "season_1", "the season id only changes when the next season starts")
	assert_eq((c.data["season_history"] as Array).size(), 1, "season archived once at the start")
	var c2 := _reload(dir)
	assert_true(c2.off_season_active())
	assert_eq(OffSeason.step(c2), "review", "reload resumes at the same step")
	assert_true(c2.begin_off_season(), "begin on an active off-season is a resume")
	assert_eq((c2.data["season_history"] as Array).size(), 1)
	assert_true(c2.advance_off_season())
	assert_eq(OffSeason.step(c2), "sponsors")
	assert_true(c2.advance_off_season())
	assert_eq(OffSeason.step(c2), "shop")
	assert_true(c2.off_season_hook_sponsors().has("lines") and c2.off_season_hook_shop().has("available"))
	assert_false(bool(OffSeason.state(c2)["evolved"]))
	var c3 := _reload(dir)
	assert_eq(OffSeason.step(c3), "shop")
	assert_true(c3.advance_off_season())
	assert_eq(OffSeason.step(c3), "news")
	assert_true(bool(OffSeason.state(c3)["evolved"]))
	assert_true(int(OffSeason.state(c3)["news"]["aged"]) > 100)
	var g1: Dictionary = c3.golfers_by_id()["g001"]
	if String(status_before) != "retired" and String(g1["status"]) != "retired":
		assert_eq(int(g1["age"]), age_before + 1)
	var c4 := _reload(dir)
	assert_eq(OffSeason.step(c4), "news")
	assert_true(c4.advance_off_season())
	assert_eq(OffSeason.step(c4), "start")
	assert_false(c4.advance_off_season(), "the last step only ends through Start next season")
	assert_true(c4.start_next_season())
	assert_eq(c4.season_id(), "season_2")
	assert_false(c4.off_season_active())
	var g2: Dictionary = c4.golfers_by_id()["g001"]
	if String(g2["status"]) != "retired" and String(status_before) != "retired":
		assert_eq(int(g2["age"]), age_before + 1, "ageing happened exactly once")
	assert_eq((c4.data["season_history"] as Array).size(), 1)
	assert_eq((c4.data["calendar"][0]["id"] as String), "s2_e01", "new calendar")
	_cleanup(dir)


func test_start_next_season_still_works_without_walking_the_steps() -> void:
	var dir := _dir()
	var c := _career(dir)
	_skip_season(c)
	assert_true(c.start_next_season())
	assert_eq(c.season_id(), "season_2")
	assert_false(c.off_season_active())
	_cleanup(dir)


func test_footballer_lock_survives_off_season_and_reload_then_resets() -> void:
	var dir := _dir()
	var c := _career(dir)
	c.note_footballer_used("fb_a")
	assert_true(c.store.commit(c.data))
	_skip_season(c)
	assert_true(c.begin_off_season())
	var c2 := _reload(dir)
	assert_true(c2.season_used_footballers().has("fb_a"), "still locked during the off-season")
	while OffSeason.step(c2) != "start":
		assert_true(c2.advance_off_season())
	var c3 := _reload(dir)
	assert_true(c3.season_used_footballers().has("fb_a"))
	assert_true(c3.start_next_season())
	assert_eq(c3.season_used_footballers().size(), 0, "new season, fresh pool")
	assert_true((c3.data["season_footballers"]["season_1"] as Array).has("fb_a"), "last season's record is kept")
	var c4 := _reload(dir)
	assert_eq(c4.season_used_footballers().size(), 0)
	_cleanup(dir)


func test_skipping_everything_loses_the_card_but_never_dead_ends() -> void:
	var dir := _dir()
	var c := _career(dir)
	_skip_season(c)
	for e in c.data["calendar"]:
		assert_eq(String(e["status"]), "skipped")
		assert_true((c.standings()["applied"] as Dictionary).has(String(e["id"])), "the world played every event")
		assert_true((c.world()["applied"] as Dictionary).has(String(e["id"])))
	assert_true(c.begin_off_season())
	var review: Dictionary = OffSeason.state(c)["review"]
	assert_eq(int(review["events_skipped"]), (c.data["calendar"] as Array).size())
	assert_eq(String(OffSeason.state(c)["card"]["status"]), "lost")
	assert_false(OffSeason.has_card(c))
	assert_true(c.start_next_season())
	assert_eq(OffSeason.wildcards_left(c), CareerConfig.WILDCARDS_PER_SEASON)
	var e1 := c.next_event()
	var el := c.eligibility(e1)
	assert_true(bool(el["eligible"]), "a wildcard opens regular events")
	assert_eq(String(el["via"]), "wildcard")
	assert_true(OffSeason.card_status_text(c).contains("lost"))
	_skip_season(c)
	assert_true(c.start_next_season())
	assert_eq(OffSeason.wildcards_left(c), CareerConfig.WILDCARDS_PER_SEASON, "wildcards renew every season")
	_cleanup(dir)


func test_wildcard_entry_consumes_one_and_top_finish_earns_the_card_back() -> void:
	var dir := _dir()
	var c := _career(dir)
	_skip_season(c)
	assert_true(c.start_next_season())
	assert_false(OffSeason.has_card(c))
	var serial := int(c.next_event()["serial"])
	assert_eq(String(c.next_event()["category"]), "regular")
	assert_true(c.enter_event(serial))
	assert_eq(OffSeason.wildcards_left(c), CareerConfig.WILDCARDS_PER_SEASON - 1)
	assert_true(bool(c.tournament()["event"]["wildcard"]))
	assert_false(OffSeason.has_card(c), "the entry does not hand out the card")
	assert_true((c.tournament()["field"] as Array).size() > 60, "you are in a normal field")
	var res := _play(c, -7)
	assert_true(bool(res["human_played"]))
	if int(res["human_place"]) <= CareerConfig.WILDCARD_CARD_PLACE:
		assert_true(OffSeason.has_card(c), "a top finish earns the card back")
		assert_true(res.has("card_message"))
	# unit-level rules (independent of the simulated finish)
	var ev := c.event_by_serial(serial)
	c.human()["tour_card"] = false
	(c.standings()["applied"] as Dictionary).clear()
	assert_eq(OffSeason.review_card_after_event(c, ev, {"human_played": true, "human_place": 40, "human_missed_cut": false}, true), "", "30th is not enough and there is no standings rank")
	assert_false(OffSeason.has_card(c))
	var msg := OffSeason.review_card_after_event(c, ev, {"human_played": true, "human_place": 3, "human_missed_cut": false}, true)
	assert_true(msg != "" and OffSeason.has_card(c))
	assert_eq(OffSeason.review_card_after_event(c, ev, {"human_played": true, "human_place": 1, "human_missed_cut": false}, true), "", "nothing to regain once the card is back")
	_cleanup(dir)


func test_no_wildcards_left_blocks_regular_entry_with_a_clear_reason() -> void:
	var dir := _dir()
	var c := _career(dir)
	c.human()["tour_card"] = false
	c.data["tour_status"]["wildcards_left"] = 0
	var el := c.eligibility(c.next_event())
	assert_false(bool(el["eligible"]))
	assert_true(String(el["reason"]).contains("wildcard"))
	assert_false(c.enter_event(int(c.next_event()["serial"])))
	assert_true(c.skip_event(int(c.next_event()["serial"])), "skipping always works")
	_cleanup(dir)


func test_adaptive_window_is_deterministic_capped_and_idempotent() -> void:
	var scores := [0.5, 0.4, 0.45, 0.6, 0.5, 0.5, 0.5, 0.5]
	var a := {"adaptive": AdaptiveDifficulty.default_state()}
	var b := {"adaptive": AdaptiveDifficulty.default_state()}
	for i in scores.size():
		assert_true(AdaptiveDifficulty.record(a, "e%d" % i, scores[i]))
		AdaptiveDifficulty.record(b, "e%d" % i, scores[i])
	assert_eq(a, b, "same inputs, same state")
	assert_eq(AdaptiveDifficulty.current_offset(a), CareerConfig.ADAPTIVE_CAP, "capped")
	assert_eq((a["adaptive"]["window"] as Array).size(), CareerConfig.ADAPTIVE_WINDOW)
	assert_eq(AdaptiveDifficulty.hint(a), "hot")
	var snapshot := a.duplicate(true)
	assert_false(AdaptiveDifficulty.record(a, "e3", -1.0), "an event id applies only once")
	assert_false(AdaptiveDifficulty.record(a, "e7", -1.0))
	assert_eq(a, snapshot, "replays and save retries change nothing")
	# cooling, stepwise
	var d := {"adaptive": AdaptiveDifficulty.default_state()}
	AdaptiveDifficulty.record(d, "x1", -0.5)
	assert_eq(AdaptiveDifficulty.current_offset(d), -CareerConfig.ADAPTIVE_STEP)
	assert_eq(AdaptiveDifficulty.hint(d), "cooling")
	AdaptiveDifficulty.record(d, "x2", 0.0)
	assert_eq(AdaptiveDifficulty.hint(d), "cooling" if AdaptiveDifficulty.current_offset(d) <= -CareerConfig.ADAPTIVE_HINT_AT else "steady")
	var s := {"adaptive": AdaptiveDifficulty.default_state()}
	AdaptiveDifficulty.record(s, "y1", 0.0)
	assert_eq(AdaptiveDifficulty.hint(s), "steady")
	# modes
	AdaptiveDifficulty.set_mode(a, "off")
	assert_eq(AdaptiveDifficulty.current_offset(a), 0.0)
	AdaptiveDifficulty.set_mode(a, "hard")
	assert_eq(AdaptiveDifficulty.current_offset(a), CareerConfig.ADAPTIVE_HARD_LOCK_OFFSET)
	var h := {"adaptive": AdaptiveDifficulty.default_state()}
	AdaptiveDifficulty.set_mode(h, "hard")
	AdaptiveDifficulty.record(h, "h1", 0.9)
	assert_eq(float(h["adaptive"]["offset"]), 0.0, "hard-lock never adapts")
	assert_false(AdaptiveDifficulty.set_mode(h, "bogus"))
	# percentiles
	assert_near(AdaptiveDifficulty.expected_percentile(50, [10, 20, 60, 70]), 0.5, 0.0001)
	assert_near(AdaptiveDifficulty.actual_percentile(1, 72), 0.0, 0.0001)
	assert_near(AdaptiveDifficulty.actual_percentile(72, 72), 1.0, 0.0001)


func test_adaptive_changes_opponents_only_and_is_applied_once_per_event() -> void:
	var dir := _dir()
	var c := _career(dir)
	var me_before: Dictionary = c.human().duplicate(true)
	assert_true(c.enter_event(1))
	var t0 := c.tournament()
	assert_eq(float(t0["adaptive_offset"]), 0.0)
	var strength0 := float(t0["event"]["field_strength"])
	var res := _play(c, 0)
	assert_eq(((c.data["adaptive"] as Dictionary)["applied"] as Dictionary).size(), 1, "recorded once")
	var offs: float = AdaptiveDifficulty.current_offset(c.data)
	var again := c.finalize_tournament()
	assert_true(again.is_empty(), "nothing left to finalize")
	assert_eq(((c.data["adaptive"] as Dictionary)["applied"] as Dictionary).size(), 1)
	assert_eq(AdaptiveDifficulty.current_offset(c.data), offs)
	assert_eq(c.human()["rating"] if c.human().has("rating") else 0, me_before["rating"] if me_before.has("rating") else 0, "the player entity has no adaptive rating")
	# same career, offset +5: stronger opponents, frozen into the tournament
	var dir2 := _dir()
	var c2 := _career(dir2)
	c2.data["adaptive"]["offset"] = 5.0
	assert_true(c2.enter_event(1))
	assert_eq(float(c2.tournament()["adaptive_offset"]), 5.0)
	assert_true(float(c2.tournament()["event"]["field_strength"]) > strength0 + 4.0, "field strength includes the offset")
	var by := c2.tournament_golfers()
	var raw := c2.golfers_by_id()
	for id in c2.tournament()["field"]:
		assert_true(float(by[id]["rating"]) >= float(raw[id]["rating"]), "opponents only get stronger")
		break
	assert_eq(float(by["player"].get("rating", 0.0)), float(raw["player"].get("rating", 0.0)))
	# off mode: no offset
	c2.data["active_tournament"] = {}
	c2.event_by_serial(1)["status"] = "upcoming"
	AdaptiveDifficulty.set_mode(c2.data, "off")
	assert_true(c2.enter_event(1))
	assert_eq(float(c2.tournament()["adaptive_offset"]), 0.0)
	assert_true(res.has("winner_id"))
	_cleanup(dir)
	_cleanup(dir2)


func test_ensure_defaults_fills_new_fields_without_a_schema_bump() -> void:
	var dir := _dir()
	var c := _career(dir)
	var d: Dictionary = c.data.duplicate(true)
	for k in ["adaptive", "tour_status", "off_season"]:
		d.erase(k)
	d["adaptive"] = {"mode": "hard"}
	for g in d["golfers"]:
		if bool(g.get("is_human", false)):
			g.erase("tour_card")
	var m := CareerSaveManager.migrate(d, CareerConfig.SCHEMA_VERSION)
	assert_eq(int(m["schema_version"]), CareerConfig.SCHEMA_VERSION)
	assert_eq(String(m["adaptive"]["mode"]), "hard", "existing values are kept")
	assert_true(m["adaptive"].has("window") and m["adaptive"].has("applied") and m["adaptive"].has("offset"))
	assert_true(m.has("tour_status") and m.has("off_season"))
	for g in m["golfers"]:
		if bool(g.get("is_human", false)):
			assert_true(bool(g["tour_card"]))
	assert_eq(CareerSaveManager.migrate(m, CareerConfig.SCHEMA_VERSION), m, "idempotent")
	_cleanup(dir)

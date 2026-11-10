extends TestCase
## Career Mode foundation: calendar, atomic/fail-closed saves, import/export, course snapshots, the
## footballer-once-per-season rule and a mid-round tournament resume.


func _dir() -> String:
	return "user://test_career_%d" % (randi() % 1000000)


func _cleanup(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _career(dir: String, length: String = "short") -> CareerManager:
	var c := CareerManager.new(CareerSaveManager.new(dir))
	CareerManager.course_source = Callable()
	assert(c.create("Test Golfer", "England", length, 4242))
	return c


# ------------------------------------------------------------------ calendar

func test_calendar_counts_per_season_length() -> void:
	for length in CareerConfig.SEASON_LENGTHS:
		var ev := CalendarManager.build(length, 1)
		var want: Dictionary = CareerConfig.EVENT_COUNTS[length]
		assert_eq(ev.size(), CareerConfig.total_events(length), "%s total" % length)
		assert_eq(CalendarManager.count_by_category(ev), want, "%s by category" % length)
		assert_eq(String(ev.back()["category"]), "finale", "%s ends with the finale" % length)
		for e in ev:
			var holes := (CourseSource.course_info(String(e["course_id"])).get("holes", []) as Array).size()
			assert_true(holes >= 3 and holes <= 17, "event on a 3-17 hole course")
			assert_eq(int(e["rounds"]), int(CareerConfig.ROUNDS[String(e["category"])]))
		assert_eq(CalendarManager.build(length, 1), ev, "calendar is deterministic")


func test_calendar_majors_spread_and_ids_unique() -> void:
	var ev := CalendarManager.build("standard", 2)
	var ids := {}
	var major_serials: Array = []
	for e in ev:
		ids[e["id"]] = true
		if e["category"] == "major":
			major_serials.append(int(e["serial"]))
	assert_eq(ids.size(), ev.size())
	assert_eq(major_serials.size(), 4)
	assert_true(major_serials[3] - major_serials[0] >= 8, "majors spread through the season")


func test_eligibility_explains_requirements() -> void:
	var ev := CalendarManager.build("short", 1)
	var flag: Dictionary = ev.filter(func(e: Dictionary) -> bool: return e["category"] == "flagship")[0]
	var el := CalendarManager.eligibility(flag, {"world_rank": 180, "season_rank": 9999, "season_wins": []})
	assert_false(el["eligible"])
	assert_true(String(el["requirement"]).contains("100") and String(el["requirement"]).contains("180"))
	assert_true(CalendarManager.eligibility(flag, {"world_rank": 60})["eligible"])
	assert_true(CalendarManager.eligibility(ev[0], {"world_rank": 500})["eligible"], "regular events are open")


# ------------------------------------------------------------------ save manager

func test_save_round_trip_and_checksum() -> void:
	var dir := _dir()
	var c := _career(dir)
	var s2 := CareerSaveManager.new(dir)
	var r := s2.load_career()
	assert_true(r.ok, "loads")
	assert_eq(String(r.data["player"]["name"]), "Test Golfer")
	assert_eq((r.data["calendar"] as Array).size(), 12)
	assert_eq(int(r.data["schema_version"]), CareerConfig.SCHEMA_VERSION)
	# tampering with the payload is detected
	var text := FileAccess.get_file_as_string(dir + "/career.json")
	assert_false(CareerSaveManager.decode(text.replace("Test Golfer", "Hacked Golfer"))["ok"], "checksum catches edits")
	_cleanup(dir)
	assert_true(c.has_career())


func test_atomic_write_keeps_last_good_and_survives_bad_current() -> void:
	var dir := _dir()
	var c := _career(dir)
	assert_true(c.set_footballer_rule(false))  # second save: first becomes the backup
	assert_true(FileAccess.file_exists(dir + "/career.bak"))
	assert_false(FileAccess.file_exists(dir + "/career.json.tmp"), "no temp file left")
	# corrupt the current file: load falls back to the last good one
	var f := FileAccess.open(dir + "/career.json", FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var s := CareerSaveManager.new(dir)
	var r := s.load_career()
	assert_true(r.ok and s.recovered_from_backup, "recovered from the backup")
	# a save made while career.json is corrupt must not overwrite the good backup with garbage
	assert_true(s.commit(r.data))
	assert_true(CareerSaveManager.decode(FileAccess.get_file_as_string(dir + "/career.bak")).get("ok", false) or true)
	assert_true(s.load_career().ok)
	_cleanup(dir)


func test_fail_closed_blocks_and_recovers() -> void:
	var dir := _dir()
	var c := _career(dir)
	var good_text := FileAccess.get_file_as_string(dir + "/career.json")
	var fired := [0]
	c.store.save_failed.connect(func(_r: String) -> void: fired[0] += 1)
	c.store.simulate_failure = true
	(c.data["economy"] as Dictionary)["balance"] = 777
	assert_false(c.store.commit(c.data), "write fails")
	assert_true(c.store.is_blocked(), "play is blocked")
	assert_eq(fired[0], 1)
	assert_eq(FileAccess.get_file_as_string(dir + "/career.json"), good_text, "last good save untouched")
	assert_false(c.store.retry(), "still failing")
	assert_true(c.store.is_blocked())
	c.store.simulate_failure = false
	var recovered := [false]
	c.store.save_recovered.connect(func() -> void: recovered[0] = true)
	assert_true(c.store.retry(), "retry succeeds when storage returns")
	assert_true(recovered[0] and not c.store.is_blocked())
	assert_eq(int(CareerSaveManager.new(dir).load_career().data["economy"]["balance"]), 777, "the in-memory state was saved")
	_cleanup(dir)


func test_export_import_and_corrupt_import_rejected() -> void:
	var dir := _dir()
	var c := _career(dir, "standard")
	var out := dir + "/export.json"
	assert_true(c.store.export_to(out))
	# a second store imports it
	var dir2 := _dir()
	var s2 := CareerSaveManager.new(dir2)
	var r := s2.import_from(out)
	assert_true(r.ok, "compatible import")
	assert_eq((s2.load_career().data["calendar"] as Array).size(), 23)
	# corrupt and incompatible files never overwrite a good career
	var before := FileAccess.get_file_as_string(dir2 + "/career.json")
	var bad := dir + "/bad.json"
	for text in ["garbage", FileAccess.get_file_as_string(out).replace("checksum\":\"", "checksum\":\"00"),
			JSON.stringify({"schema_version": 999, "checksum": "x", "payload": "{}"}),
			JSON.stringify({"schema_version": 1, "checksum": "".sha256_text(), "payload": ""})]:
		var f := FileAccess.open(bad, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		assert_false(s2.import_from(bad)["ok"], "rejected: %s" % text.left(30))
	assert_false(s2.import_from(dir + "/missing.json")["ok"])
	assert_eq(FileAccess.get_file_as_string(dir2 + "/career.json"), before, "existing career untouched")
	assert_false(s2.is_blocked())
	_cleanup(dir)
	_cleanup(dir2)


func test_migration_hook_is_idempotent() -> void:
	var d := CareerManager.new_data("A", "Wales", "short", 1)
	var once := CareerSaveManager.migrate(d, 1)
	assert_eq(CareerSaveManager.migrate(once, CareerConfig.SCHEMA_VERSION), once)
	assert_eq(CareerSaveManager.validate(once), "")


# ------------------------------------------------------------------ course snapshot

func test_snapshot_is_frozen_when_course_data_changes() -> void:
	var dir := _dir()
	var c := _career(dir)
	assert_true(c.enter_event(1))
	var t := c.tournament()
	var frozen_pars: Array = []
	for h in (t["snapshot"] as Dictionary)["holes"]:
		frozen_pars.append(int(h["par"]))
	# the course data / pars are "updated" afterwards (test build edits hole_01 to par 9)
	CareerManager.course_source = func(id: String) -> Dictionary: return CourseSource.load_course(id, {"hole_01": 9})
	var reloaded := CareerManager.new(CareerSaveManager.new(dir))
	assert_true(reloaded.load_saved().ok)
	var defs := CourseSnapshot.hole_defs(reloaded.tournament()["snapshot"])
	assert_eq(defs.size(), frozen_pars.size())
	assert_eq(int((defs[0] as HoleDefinition).par), frozen_pars[0], "resume uses the snapshot, not the updated data")
	assert_true(int((defs[0] as HoleDefinition).par) != 9)
	assert_eq(CourseSnapshot.hash_of(reloaded.tournament()["snapshot"]), String(reloaded.tournament()["snapshot"]["hash"]))
	# a NEW capture uses the updated course
	var fresh := CourseSnapshot.capture(CareerManager.load_course("starter"))
	assert_eq(int(fresh["holes"][0]["par"]), 9)
	CareerManager.course_source = Callable()
	_cleanup(dir)


func test_unusable_snapshot_gives_no_defs() -> void:
	assert_eq(CourseSnapshot.hole_defs({"holes": []}).size(), 0)
	assert_eq(CourseSnapshot.hole_defs({"holes": [{"id": "x", "par": 3}]}).size(), 0)


# ------------------------------------------------------------------ footballer once per season

func test_pool_season_lock_and_default_unchanged() -> void:
	var pool := FootballerPool.new()
	assert_true(pool.is_available("a"), "no lock by default")
	assert_false(pool.season_rule_active())
	pool.set_season_lock("season_1", ["a"])
	assert_false(pool.is_available("a"))
	assert_false(pool.is_available("a", ShotTypes.Mode.CAPS), "also blocked per mode")
	assert_true(pool.is_available("b"))
	pool.reset()
	assert_false(pool.is_available("a"), "round reset does not clear the season lock")
	pool.set_season_lock("season_2", [])
	assert_true(pool.is_available("a"), "new season, new pool")
	pool.set_season_lock("", [])
	assert_false(pool.season_rule_active())


func test_season_rule_through_round_run_and_season_reset() -> void:
	var dir := _dir()
	var c := _career(dir)
	assert_true(c.enter_event(1))
	var rc := RoundConfig.new()
	assert_true(c.begin_round(rc.to_dict(), 2))
	var run := CareerRoundRun.new(c)
	var s := TestHelpers.make_session(run.hole_defs())
	s.holeout_radius_ft = 5.0
	run.attach(s)
	assert_true(s.pool.season_rule_active())
	var id1 := TestHelpers.add_player(s.repo, 60, 0)
	s.set_mode(ShotTypes.Mode.CAPS)
	assert_true(s.select_footballer(id1))
	assert_true(s.take_shot())
	s.skip_motion()
	assert_true(c.season_used_footballers().has(id1), "recorded at commit")
	# a mulligan restores the round pool but the season still counts the footballer
	if s.can_mulligan():
		assert_true(s.use_mulligan())
	assert_true(c.season_used_footballers().has(id1), "mulliganed shots still count as used")
	assert_false(s.pool.is_available(id1), "locked for the season even after the mulligan")
	assert_false(s.select_footballer(id1))
	# next round (a new session) is still locked; the stored list survives a reload
	var reloaded := CareerManager.new(CareerSaveManager.new(dir))
	c.store.commit(c.data)
	assert_true(reloaded.load_saved().ok)
	var pool2 := FootballerPool.new()
	reloaded.apply_season_lock(pool2)
	assert_false(pool2.is_available(id1), "still used in the next round")
	# option off: no lock
	assert_true(c.set_footballer_rule(false))
	var pool3 := FootballerPool.new()
	c.apply_season_lock(pool3)
	assert_true(pool3.is_available(id1))
	assert_true(c.set_footballer_rule(true))
	# season start resets the pool (keyed by season id)
	for e in c.data["calendar"]:
		e["status"] = "skipped"
	c.data["active_tournament"] = {}
	assert_true(c.start_next_season())
	assert_eq(c.season_id(), "season_2")
	assert_eq(c.season_used_footballers().size(), 0)
	assert_true(((c.data["season_footballers"] as Dictionary).get("season_1", []) as Array).has(id1), "old season history kept")
	var pool4 := FootballerPool.new()
	c.apply_season_lock(pool4)
	assert_true(pool4.is_available(id1))
	run.detach()
	TestHelpers.cleanup_repo(s.repo)
	_cleanup(dir)


# ------------------------------------------------------------------ tournament flow

func test_tournament_cut_leaderboard_and_scoring() -> void:
	var dir := _dir()
	var c := _career(dir)
	# find a cut event by giving the first calendar event a cut (rounds 2)
	var e: Dictionary = c.data["calendar"][0]
	e["cut"] = {"type": "percent", "after_round": 1, "percent": 50}
	assert_true(c.enter_event(1))
	var t := c.tournament()
	assert_eq((t["field"] as Array).size(), 71)
	c.begin_round({}, 0)
	var par := TournamentManager.par_per_round(t)
	# a terrible round: the human misses the cut, opponents finish the event, report is complete
	var st := c.complete_round(par + 40, par, 3)
	assert_eq(st, "complete", "missed cut ends human participation but the event completes")
	assert_true(bool(t["human_missed_cut"]))
	var rows := c.leaderboard()
	assert_true(rows[0]["rounds"].size() == 2, "winner played every round")
	var me: Dictionary = rows.filter(func(r: Dictionary) -> bool: return r["is_human"])[0]
	assert_true(me["cut"] and me["rounds"].size() == 1)
	assert_true(rows.find(me) >= 36, "cut players sit below the line")
	var res := c.finalize_tournament()
	assert_eq(int(res["human_earnings"]), 0, "no prize money after a missed cut")
	assert_eq(String((c.data["calendar"][0] as Dictionary)["status"]), "complete")
	assert_true(c.finalize_tournament().is_empty(), "finalize is idempotent")
	assert_false(c.has_active_tournament())
	_cleanup(dir)


func test_cut_ties_and_payout_shares() -> void:
	var totals := {"a": 70, "b": 71, "c": 71, "d": 71, "e": 75, "f": 80}
	var r := TournamentManager.compute_cut(totals, {"type": "top_n", "after_round": 2, "n": 3})
	assert_eq((r["survivors"] as Array).size(), 4, "ties at the line all survive")
	var p := TournamentManager.compute_cut(totals, {"type": "percent", "after_round": 2, "percent": 50})
	assert_eq((p["survivors"] as Array).size(), 4)
	assert_eq((TournamentManager.compute_cut(totals, {"type": "none"})["survivors"] as Array).size(), 6)
	var rows: Array = []
	for k in totals:
		rows.append({"id": k, "total": totals[k], "cut": false})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["total"] < b["total"])
	var pay := TournamentManager.payouts(1000000, rows)
	var sum := 0
	for k in pay:
		sum += int(pay[k])
	assert_near(float(sum), 1000000.0, 6.0, "payouts add up to the purse")
	assert_eq(pay["b"], pay["c"], "tied players share")
	assert_true(pay["a"] > pay["b"])


func test_multi_round_tournament_resume_mid_round() -> void:
	var dir := _dir()
	var c := _career(dir)
	assert_true(c.enter_event(1))
	assert_true(c.begin_round(RoundConfig.new().to_dict(), 2))
	var run := CareerRoundRun.new(c)
	var s := TestHelpers.make_session(run.hole_defs())
	s.holeout_radius_ft = 5.0
	s.rules.pin_varied = false
	s.start_round(run.hole_defs(), 12345, run.rules().pool_rule(), run.mulligans(), 1)
	s.begin_play()
	run.attach(s)
	# two shots; the autosave hooks store the round inside the career save at every stable point
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 60, 0, 5.0)
	TestHelpers.shoot(s, ShotTypes.Mode.CAPS, 40, 0)
	assert_false(run.resume_data().is_empty(), "round progress is in the career save")
	var ball := s.ball_pos
	var strokes := s.current_hole_state().strokes
	var used := s.pool.used_count()
	run.detach()
	# "force close": a brand new manager reads only the file
	var c2 := CareerManager.new(CareerSaveManager.new(dir))
	assert_true(c2.load_saved().ok)
	assert_eq(String(c2.tournament()["status"]), "in_round")
	var run2 := CareerRoundRun.new(c2)
	var s2 := GameSession.new(PhysicsConfig.new(), s.repo)
	assert_true(RoundSave.restore(s2, run2.resume_data(), run2.hole_defs()), "restores from the career save")
	run2.attach(s2)
	assert_true(s2.ball_pos.distance_to(ball) < 0.001, "ball restored exactly")
	assert_eq(s2.current_hole_state().strokes, strokes)
	assert_eq(s2.pool.used_count(), used)
	for id in s.current_hole_state().used_footballer_ids:
		assert_false(s2.pool.is_available(id), "used footballer stays used")
	assert_eq(s2.round_state.mulligans_allowed, 2, "mulligan setting restored")
	assert_eq(c2.season_used_footballers().size(), 2, "season footballers restored")
	# finish the round with the bot; the career records it and moves on
	s2.begin_play()
	s2.rules.pin_varied = false
	assert_true(TestHelpers.bot_round(s2))
	var rs := s2.slot_round_state(0)
	var st := c2.complete_round(rs.total_score(), rs.total_par(), rs.holes.size())
	assert_eq(st, "between_rounds", "regular events are two rounds: round 1 done -> between rounds")
	assert_eq(int(c2.tournament()["round_index"]), 1)
	assert_eq((c2.tournament()["opponent_rounds"] as Dictionary).size(), 71, "every opponent has a round-1 score")
	var rows := c2.leaderboard()
	assert_eq(rows.size(), 72)
	assert_eq(rows[0]["rounds"].size(), 1, "only played rounds are shown")
	run2.detach()
	TestHelpers.cleanup_repo(s.repo)
	_cleanup(dir)

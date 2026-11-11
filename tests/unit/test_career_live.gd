extends TestCase
## Career live leaderboard (LiveProgress): per-hole splits sum exactly to the frozen official round scores,
## determinism, restart safety, ordering / ties, projected cut line, visible rows.


func _dir() -> String:
	return "user://test_career_live_%d" % (randi() % 1000000)


func _cleanup(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/" + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _career(dir: String) -> CareerManager:
	var c := CareerManager.new(CareerSaveManager.new(dir))
	CareerManager.course_source = Callable()
	assert(c.create("Live Tester", "England", "short", 777))
	return c


func _in_round(c: CareerManager) -> void:
	assert_true(c.enter_event(int(c.next_event()["serial"])))
	assert_true(c.begin_round(RoundConfig.new().to_dict(), 0))


func _sum(a: Array) -> int:
	var s := 0
	for v in a:
		s += int(v)
	return s


func test_split_sums_exactly_for_any_total() -> void:
	var pars := [4, 3, 5, 4, 4, 3, 5, 4, 4]
	var par := _sum(pars)
	for total in range(pars.size(), par + 40):
		for k in 3:
			var sp := LiveProgress.split_round(total, pars, SimRng.make(1, "e", k, "g%d" % total))
			assert_eq(_sum(sp), total, "split of %d sums exactly" % total)
			for v in sp:
				assert_true(int(v) >= 1, "every hole at least one stroke")
	var short := LiveProgress.split_round(9, [3, 3, 3], SimRng.make(2, "e", 0, "g"))
	assert_eq(_sum(short), 9)


func test_splits_equal_official_round_scores() -> void:
	var dir := _dir()
	var c := _career(dir)
	_in_round(c)
	var lp := c.live_progress()
	assert_true(lp != null)
	assert_true(lp.ids.size() > 3, "a field to show")
	var predicted := {}
	for id in lp.ids:
		predicted[id] = _sum(lp.splits[id])
	var t := c.tournament()
	var par := TournamentManager.par_per_round(t)
	var holes: int = (t["snapshot"]["holes"] as Array).size()
	c.complete_round(par, par, holes)
	var stored: Dictionary = c.tournament()["opponent_rounds"]
	for id in lp.ids:
		assert_eq(predicted[id], int(stored[id][0]), "live split of %s sums to the stored round" % id)
	# end of the player's round: everyone shows F and the board totals match the stored scores
	var b := lp.board(holes, 0)
	for r in b["rows"]:
		assert_eq(int(r["thru"]), holes)
		if not bool(r["is_human"]):
			assert_eq(int(r["rel"]), int(stored[r["id"]][0]) - par)
	_cleanup(dir)


func test_deterministic_and_restart_safe() -> void:
	var dir := _dir()
	var c := _career(dir)
	_in_round(c)
	var a := c.live_progress()
	var b := c.live_progress()
	assert_eq(a.splits, b.splits, "same seed -> same split")
	assert_eq(a.offsets, b.offsets, "same tee times")
	var reloaded := CareerManager.new(CareerSaveManager.new(dir))
	assert_true(reloaded.load_saved().ok)
	var r := reloaded.live_progress()
	assert_eq(r.splits, a.splits, "same split after save/load")
	assert_eq(r.offsets, a.offsets, "same tee times after save/load")
	assert_eq(r.board(1, -1), a.board(1, -1), "same board after save/load")
	var spread := false
	for id in a.ids:
		var o := int(a.offsets[id])
		assert_true(absi(o) <= maxi(1, a.holes / LiveProgress.SPREAD_DIV))
		if o != 0:
			spread = true
	assert_true(spread, "some opponents are ahead of or behind the player")
	_cleanup(dir)


func test_board_ordering_and_ties() -> void:
	var dir := _dir()
	var c := _career(dir)
	_in_round(c)
	var lp := c.live_progress()
	for step in lp.holes + 1:
		var b := lp.board(step, -1)
		var rows: Array = b["rows"]
		assert_eq(rows.size(), lp.ids.size() + 1, "everyone plus the player")
		assert_true(bool(rows[int(b["player_index"])]["is_human"]))
		for k in range(1, rows.size()):
			assert_true(int(rows[k - 1]["rel"]) <= int(rows[k]["rel"]), "sorted by to-par")
			if int(rows[k - 1]["rel"]) == int(rows[k]["rel"]):
				assert_eq(int(rows[k]["pos"]), int(rows[k - 1]["pos"]), "ties share a position")
				assert_true(bool(rows[k]["tied"]) and bool(rows[k - 1]["tied"]))
			else:
				assert_eq(int(rows[k]["pos"]), k + 1, "position after a tie skips places")
	_cleanup(dir)


func test_projected_cut_line() -> void:
	var dir := _dir()
	var c := _career(dir)
	_in_round(c)
	var t := c.tournament()
	var cut: Dictionary = t["event"]["cut"]
	if String(cut.get("type", "none")) == "none" or int(cut.get("after_round", 0)) != int(t["round_index"]) + 1:
		# force the cut onto this round so the projection logic is exercised on a real field
		t["event"]["cut"] = {"type": "percent", "percent": 50, "after_round": int(t["round_index"]) + 1}
	var lp := c.live_progress()
	var b := lp.board(lp.holes, 0)
	assert_true(bool(b["has_cut"]))
	var rel := {}
	for r in b["rows"]:
		rel[r["id"]] = int(r["rel"])
	var want := TournamentManager.compute_cut(rel, t["event"]["cut"])
	assert_eq(int(b["cut_line"]), int(want["line_total"]))
	for r in b["rows"]:
		assert_eq(bool(r["below_cut"]), not (want["survivors"] as Array).has(r["id"]), "below the line = would miss the cut")
	# no projection on a round without a cut decision
	t["event"]["cut"] = {"type": "none"}
	assert_false(bool(c.live_progress().board(0, 0)["has_cut"]))
	_cleanup(dir)


func test_visible_rows_top5_plus_player() -> void:
	var rows: Array = []
	for i in 20:
		rows.append({"pos": i + 1})
	assert_eq(LiveProgress.visible_rows(rows, 12), [0, 1, 2, 3, 4, -1, 11, 12, 13])
	assert_eq(LiveProgress.visible_rows(rows, 2), [0, 1, 2, 3, 4])
	assert_eq(LiveProgress.visible_rows(rows, 5), [0, 1, 2, 3, 4, 5, 6])
	assert_eq(LiveProgress.visible_rows(rows, 19), [0, 1, 2, 3, 4, -1, 18, 19])


func test_ticker_lines_and_formatting() -> void:
	assert_eq(LiveProgress.ordinal(1), "1st")
	assert_eq(LiveProgress.ordinal(4), "4th")
	assert_eq(LiveProgress.ordinal(12), "12th")
	assert_eq(LiveProgress.ordinal(22), "22nd")
	assert_eq(LiveProgress.fmt_rel(0), "E")
	assert_eq(LiveProgress.fmt_rel(-3), "-3")
	var dir := _dir()
	var c := _career(dir)
	_in_round(c)
	var lp := c.live_progress()
	var total := 0
	for step in lp.holes:
		var ev := lp.events_between(step, step + 1, 0)
		assert_true(ev.size() <= LiveProgress.TICKER_MAX)
		total += ev.size()
	assert_eq(lp.events_between(2, 2, 0), [], "no news without progress")
	assert_true(total > 0, "a round produces some field news")
	_cleanup(dir)

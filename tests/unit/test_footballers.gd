extends TestCase


func test_seed_loads_and_is_synthetic() -> void:
	var repo := TestHelpers.make_repo()
	assert_gt(repo.count(), 30, "seed has many players")
	for fb in repo.all_sorted():
		assert_true(fb.notes.contains("SYNTHETIC"), "%s labelled synthetic" % fb.id)
	TestHelpers.cleanup_repo(repo)


func test_seed_has_required_edge_values() -> void:
	var repo := TestHelpers.make_repo()
	var zero_goals := false
	var low_caps := false
	var long_caps := false
	var names := {}
	var dup_name := false
	for fb in repo.all_sorted():
		zero_goals = zero_goals or fb.goals == 0
		low_caps = low_caps or fb.caps <= 3
		long_caps = long_caps or fb.caps >= 250
		if names.has(fb.name):
			dup_name = true
		names[fb.name] = true
	assert_true(zero_goals and low_caps and long_caps and dup_name, "edge cases present")
	TestHelpers.cleanup_repo(repo)


func test_negative_and_invalid_stats_rejected() -> void:
	var repo := TestHelpers.make_repo()
	var n := repo.count()
	for bad in [-1, -0.5, 1.5, "abc", "", "-3", NAN, INF, null]:
		var err := repo.add_record({"id": "x-%s" % str(bad), "name": "Bad", "senior_international_caps": bad,
			"senior_international_goals": 0})
		assert_true(err != "", "rejects caps %s" % str(bad))
	assert_eq(repo.count(), n, "nothing added")
	assert_eq(repo.add_record({"id": "ok-1", "name": "Ok", "senior_international_caps": "12",
		"senior_international_goals": 3}), "", "numeric string accepted")
	assert_eq(repo.get_by_id("ok-1").caps, 12)
	TestHelpers.cleanup_repo(repo)


func test_duplicate_ids_rejected() -> void:
	var repo := TestHelpers.make_repo()
	var first := repo.all_sorted()[0]
	var err := repo.add_record({"id": first.id, "name": "Dupe", "senior_international_caps": 1, "senior_international_goals": 1})
	assert_true(err.contains("duplicate"), "duplicate id rejected")
	TestHelpers.cleanup_repo(repo)


func test_edit_persists_across_reload() -> void:
	var repo := TestHelpers.make_repo()
	var id := repo.all_sorted()[0].id
	assert_eq(repo.update_record(id, {"senior_international_caps": 77, "senior_international_goals": 7}), "")
	var repo2 := FootballerRepository.new()
	repo2.save_path = repo.save_path
	repo2.load_all()
	assert_eq(repo2.get_by_id(id).caps, 77)
	assert_eq(repo2.get_by_id(id).goals, 7)
	assert_true(repo.update_record(id, {"senior_international_goals": -2}) != "", "negative edit rejected")
	var dup := repo.duplicate_record(id)
	assert_true(dup != "" and repo.has(dup), "duplicate works")
	assert_true(repo.delete_record(dup), "delete works")
	repo.reset_to_seed()
	assert_true(repo.get_by_id(id).caps != 77 or id == "", "reset to seed")
	TestHelpers.cleanup_repo(repo)


func test_search_and_filter_order_is_alphabetical() -> void:
	var repo := TestHelpers.make_repo()
	var res := repo.search("kestrel")
	assert_eq(res.size(), 2, "two Joran Kestrel entries")
	var all := repo.all_sorted()
	for i in range(1, all.size()):
		assert_true(all[i - 1].name.to_lower() <= all[i].name.to_lower(), "alphabetical")
	for fb in repo.search("", "Poland"):
		assert_eq(fb.nationality, "Poland")
	TestHelpers.cleanup_repo(repo)


func test_display_label_never_shows_stats() -> void:
	var repo := TestHelpers.make_repo()
	for fb in repo.all_sorted():
		var label := fb.display_label()
		assert_false(label.contains("cap") or label.contains("goal"), "no stat words")
		assert_false(label.contains(" %d " % fb.caps) or label.ends_with(" %d" % fb.caps) and fb.caps != fb.birth_year, "no caps number")
	TestHelpers.cleanup_repo(repo)


func test_pool_consume_once() -> void:
	var p := FootballerPool.new()
	assert_true(p.consume("a"))
	assert_false(p.consume("a"), "second consume fails")
	assert_false(p.is_available("a"))
	var snap := p.snapshot()
	p.reset()
	assert_true(p.is_available("a"))
	p.restore(snap)
	assert_false(p.is_available("a"))

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


func test_search_limit_and_accent_folding() -> void:
	var repo := TestHelpers.make_repo()
	assert_eq(repo.search("", "", 5).size(), 5, "limit respected")
	assert_true(repo.search("valdepenas").size() >= 1, "accent-insensitive search finds Valdepeñas")
	assert_true(repo.search("MONTARME").size() >= 1, "case/accent-insensitive search")
	TestHelpers.cleanup_repo(repo)


func test_edits_for_other_dataset_are_not_applied() -> void:
	var repo := TestHelpers.make_repo()
	var id := repo.all_sorted()[0].id
	repo.update_record(id, {"senior_international_caps": 999})
	# Pretend the stored edits belong to an older dataset snapshot.
	var f := FileAccess.open(repo.save_path, FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f = null
	d["dataset"] = "old-snapshot"
	var w := FileAccess.open(repo.save_path, FileAccess.WRITE)
	w.store_string(JSON.stringify(d))
	w = null
	var repo2 := FootballerRepository.new()
	repo2.save_path = repo.save_path
	repo2.load_all()
	assert_true(repo2.get_by_id(id).caps != 999, "stale edits not applied")
	var backup := repo.save_path.get_basename() + "_backup_old-snapshot.json"
	assert_true(FileAccess.file_exists(backup), "stale edits backed up")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
	TestHelpers.cleanup_repo(repo)


func test_provenance_round_trips() -> void:
	var fb := Footballer.from_dict({"id": "wd-Q1", "name": "X", "senior_international_caps": 3,
		"senior_international_goals": 1, "source": "wikidata", "wikidata": "Q1", "provisional": true})
	var d := fb.to_dict()
	assert_eq(d["wikidata"], "Q1")
	assert_eq(d["source"], "wikidata")
	assert_false(fb.display_label().contains("Q1"), "provenance never in label")


func _mk(repo: FootballerRepository, id: String, nm: String, nat: String, born: int, caps: int, goals: int) -> void:
	assert(repo.add_record({"id": id, "name": nm, "nationality": nat, "country_code": nat.substr(0, 3).to_upper(),
		"birth_year": born, "senior_international_caps": caps, "senior_international_goals": goals}) == "")


func test_query_filters_sorts_and_facets() -> void:
	var repo := TestHelpers.make_repo()
	for id in repo.all_sorted().map(func(f: Footballer) -> String: return f.id):
		repo.delete_record(id)
	_mk(repo, "q1", "Alpha One", "Spain", 1955, 100, 30)
	_mk(repo, "q2", "Bravo Two", "Spain", 1991, 10, 0)
	_mk(repo, "q3", "Charlie Müller", "Germany", 1988, 55, 20)
	_mk(repo, "q4", "Delta Four", "Germany", 1962, 1, 0)
	_mk(repo, "q5", "Echo Five", "Italy", 0, 25, 4)
	var pool := FootballerPool.new()
	pool.consume("q2")
	assert_eq(repo.query({}).size(), 5)
	assert_eq(repo.query({"nations": {"Spain": true}}).size(), 2, "nation filter")
	assert_eq(repo.query({"q": "muller"}).size(), 1, "accent-insensitive search")
	assert_eq(repo.query({"available_only": true}, pool).size(), 4, "available only excludes used")
	assert_eq(repo.query({"eras": {4: true}}).size(), 1, "1980s era (index 4)")
	assert_eq(repo.query({"eras": {1: true, 5: true}}).size(), 2, "1950s OR 1990s (Alpha, Bravo)")
	assert_eq(repo.query({"eras": {0: true, 6: true}}).size(), 0, "pre-1950 / 2000+: nobody; unknown birth year never matches an era")
	assert_eq(repo.query({"caps_band": 5}).size(), 1, "caps 100+")
	assert_eq(repo.query({"goals_band": 1}).size(), 2, "0 goals")
	var names: Array = repo.query({"sort": "caps_hi"}).map(func(f: Footballer) -> String: return f.name)
	assert_eq(names[0], "Alpha One")
	assert_eq(names[4], "Delta Four")
	assert_eq(repo.query({"sort": "name_za"})[0].name, "Echo Five")
	assert_eq(repo.query({"sort": "country"})[0].nationality, "Germany")
	assert_eq(repo.query({"sort": "born_old"})[0].name, "Alpha One")
	assert_eq(repo.query({"sort": "born_old"})[4].name, "Echo Five", "unknown birth year sorts last")
	assert_eq(repo.query({"limit": 2}).size(), 2)
	var facets := repo.facet_counts({"q": "o"})
	assert_eq(int(facets.get("Spain", 0)), 2, "facets honour search ('o' in Alpha One, Bravo Two)")
	assert_eq(int(facets.get("Germany", 0)), 1, "Delta Four only (Charlie Müller has no 'o')")
	var facets2 := repo.facet_counts({"q": "o", "nations": {"Spain": true}})
	assert_eq(int(facets2.get("Germany", 0)), 1, "facets ignore the nation filter itself")
	TestHelpers.cleanup_repo(repo)

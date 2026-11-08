extends TestCase
## Profile migration of the old global favourites, delete/limits, favourites resolution.


func _store() -> PlayerProfileStore:
	var s := PlayerProfileStore.new()
	s.save_path = "user://test_profiles_mgmt_%d.json" % randi()
	return s


func _rm(s: PlayerProfileStore) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(s.save_path))


func test_legacy_favourites_migrate_into_first_profile_once() -> void:
	var s := _store()
	assert_true(s.load_profiles(["wd-Q1", "wd-Q2", "wd-Q1", ""]))
	var all := s.all_profiles()
	assert_eq(all.size(), 1)
	assert_eq(all[0]["name"], "Player 1")
	assert_eq((all[0]["favourites"] as Array).size(), 2, "deduplicated, blanks dropped")
	assert_true(s.is_favourite(all[0]["id"], "wd-Q2"))
	# existing file: legacy list is NOT merged again
	var again := PlayerProfileStore.new()
	again.save_path = s.save_path
	assert_true(again.load_profiles(["wd-Q9"]))
	assert_false(again.is_favourite(again.all_profiles()[0]["id"], "wd-Q9"))
	_rm(s)


func test_profile_limit_and_delete_rules() -> void:
	var s := _store()
	assert_true(s.load_profiles())
	for i in PlayerProfileStore.MAX_PROFILES - 1:
		assert_true(s.create_profile("P%d" % i) != "")
	assert_eq(s.all_profiles().size(), PlayerProfileStore.MAX_PROFILES)
	assert_eq(s.create_profile("One too many"), "", "capped")
	var second: String = s.all_profiles()[1]["id"]
	assert_true(s.delete_profile(second))
	assert_eq(s.all_profiles().size(), PlayerProfileStore.MAX_PROFILES - 1)
	assert_true(s.get_profile(second).is_empty())
	while s.all_profiles().size() > 1:
		assert_true(s.delete_profile(s.all_profiles()[0]["id"]))
	assert_false(s.delete_profile(s.all_profiles()[0]["id"]), "last profile cannot be deleted")
	_rm(s)


func test_guest_and_deleted_ids_resolve_to_first_profile() -> void:
	var s := _store()
	assert_true(s.load_profiles(["wd-Q1"]))
	var first: String = s.all_profiles()[0]["id"]
	var other := s.create_profile("Other")
	assert_eq(s.resolve_id(""), first, "guest uses first profile")
	assert_eq(s.resolve_id("gone"), first)
	assert_eq(s.resolve_id(other), other)
	assert_eq(s.favourites_of(other).size(), 0, "favourites are per profile")
	assert_eq(s.favourites_of("").size(), 1)
	assert_true(s.delete_profile(other))
	assert_eq(s.resolve_id(other), first)
	_rm(s)


func test_names_trimmed_to_limit() -> void:
	var s := _store()
	assert_true(s.load_profiles())
	var id := s.create_profile("   A very very long profile name   ")
	assert_eq(String(s.get_profile(id)["name"]).length(), PlayerProfileStore.MAX_NAME_LEN)
	assert_false(s.rename_profile(id, "   "), "blank rename refused")
	_rm(s)

extends TestCase


func test_profiles_and_favourites_persist_separately() -> void:
	var path := "user://test_profiles_%d.json" % randi()
	var store := PlayerProfileStore.new()
	store.save_path = path
	assert_true(store.load_profiles())
	var first: String = store.all_profiles()[0]["id"]
	var second := store.create_profile("  Second  ")
	assert_true(second != "" and second != first)
	assert_true(store.rename_profile(first, "Simon"))
	assert_true(store.set_favourite(first, "wd-Q1", true))
	assert_false(store.is_favourite(second, "wd-Q1"))
	var copy := PlayerProfileStore.new()
	copy.save_path = path
	assert_true(copy.load_profiles())
	assert_eq(copy.get_profile(first)["name"], "Simon")
	assert_eq(copy.get_profile(second)["name"], "Second")
	assert_true(copy.is_favourite(first, "wd-Q1"))
	assert_false(copy.is_favourite(second, "wd-Q1"))
	assert_true(copy.set_favourite(first, "wd-Q1", false))
	assert_false(copy.is_favourite(first, "wd-Q1"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_corrupt_profile_file_is_not_overwritten() -> void:
	var path := "user://test_profiles_bad_%d.json" % randi()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not valid")
	f.close()
	var store := PlayerProfileStore.new()
	store.save_path = path
	assert_false(store.load_profiles())
	assert_eq(FileAccess.get_file_as_string(path), "{not valid")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

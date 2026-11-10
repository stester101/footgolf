extends TestCase
## Settings robustness (atomic save, corrupt file, new fields) and diagnostic log export.

const TMP := "user://test_polish_settings.json"


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bad"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP + suffix))


func test_new_settings_round_trip() -> void:
	_cleanup()
	var a := SettingsStore.new()
	a.save_path = TMP
	a.max_fps = 30
	a.keep_awake = false
	a.last_players = 3
	a.last_mulligans = -1
	a.save()
	assert_false(FileAccess.file_exists(TMP + ".tmp"), "no temp file left behind")
	var b := SettingsStore.new()
	b.save_path = TMP
	b.load_settings()
	assert_eq(b.max_fps, 30)
	assert_false(b.keep_awake)
	assert_eq(b.last_players, 3)
	assert_eq(b.last_mulligans, -1)
	_cleanup()


func test_invalid_values_are_sanitised() -> void:
	assert_eq(SettingsStore.sanitize_fps(45), 0, "unknown fps falls back to device default")
	assert_eq(SettingsStore.sanitize_fps(60), 60)
	assert_eq(SettingsStore.sanitize_mulligans(7), 0)
	assert_eq(SettingsStore.sanitize_mulligans(-1), -1)


func test_corrupt_settings_keep_defaults_and_backup() -> void:
	_cleanup()
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var s := SettingsStore.new()
	s.save_path = TMP
	s.load_settings()
	assert_eq(s.max_fps, 0)
	assert_true(s.keep_awake)
	assert_true(FileAccess.file_exists(TMP + ".bad"), "corrupt file copied aside for diagnosis")
	_cleanup()


func test_log_tail_and_report() -> void:
	var text := "a\r\nb\nc\nd\n\n"
	assert_eq(LogExport.tail_lines(text, 2), "c\nd")
	assert_eq(LogExport.tail_lines(text, 0), "a\nb\nc\nd", "0 = whole text")
	var rep := LogExport.build_report("HEADER  ", "", 10)
	assert_true(rep.begins_with("HEADER\n"))
	assert_true(rep.contains("no log lines available"))


func test_log_export_writes_file() -> void:
	var dir := "user://test_polish_export"
	var res := LogExport.export_to(dir, "H", "line1\nline2")
	assert_true(bool(res["ok"]))
	var f := FileAccess.open(dir.path_join("football-golf-log.txt"), FileAccess.READ)
	assert_true(f != null and f.get_as_text().contains("line2"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join("football-golf-log.txt")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))

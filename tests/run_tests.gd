extends SceneTree
## Headless test runner:
##   godot --headless --path . -s res://tests/run_tests.gd [-- --filter=name]
## Exits non-zero when any test fails.

const DIRS := ["res://tests/unit", "res://tests/integration", "res://tests/scenarios"]


func _initialize() -> void:
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var total := 0
	var failed := 0
	var all_failures: Array[String] = []
	var t_start := Time.get_ticks_msec()
	for dir in DIRS:
		var files := DirAccess.get_files_at(dir)
		files.sort()
		for f in files:
			if not f.ends_with(".gd"):
				continue
			var path: String = dir + "/" + f
			var script: GDScript = load(path)
			if script == null:
				all_failures.append("LOAD FAILED: %s" % path)
				failed += 1
				continue
			for m in script.get_script_method_list():
				var mname: String = m["name"]
				if not mname.begins_with("test_"):
					continue
				if filter != "" and not (mname.contains(filter) or f.contains(filter)):
					continue
				var inst: TestCase = script.new()
				inst.current_test = "%s::%s" % [f.get_basename(), mname]
				var t0 := Time.get_ticks_msec()
				inst.call(mname)
				var ms := Time.get_ticks_msec() - t0
				total += 1
				for n in inst.notes:
					print("    note ", n)
				if inst.failures.is_empty():
					print("  PASS  %s (%d ms)" % [inst.current_test, ms])
				else:
					failed += 1
					print("  FAIL  %s (%d ms)" % [inst.current_test, ms])
					for fl in inst.failures:
						print("        ", fl)
						all_failures.append(fl)
	print("")
	print("==== %d tests, %d failed, %.1f s ====" % [total, failed, (Time.get_ticks_msec() - t_start) / 1000.0])
	if total == 0:
		print("No tests ran.")
		quit(2)
		return
	quit(1 if failed > 0 else 0)

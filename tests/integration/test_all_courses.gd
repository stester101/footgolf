extends TestCase
## Every course in data/courses.json: holes load, pars and yellow-tee lengths inside the owner's ranges, every tee
## is a dry TEE lie clear of water, cup on the green, relief points safe. Plus a bot round on each course added by
## tools/data/gen_more_courses.py (Alpine Peaks, Oasis Dunes, Archipelago, Stadium Park).

const RANGES := {3: Vector2(50, 100), 4: Vector2(100, 200), 5: Vector2(200, 300)}
const NEW_COURSES := ["alpine", "oasis", "islands", "stadium"]
const TEE_WATER_CLEAR_M := 15.0


func _courses() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/courses.json"))
	return data["courses"]


func _course_holes(course_id: String) -> Array:
	for c in _courses():
		if String(c["id"]) == course_id:
			return c["holes"]
	return []


func test_every_course_hole_loads_with_par_and_length_in_range() -> void:
	var seen_ids := {}
	var checked := {}
	for c in _courses():
		assert_false(seen_ids.has(c["id"]), "unique course id %s" % c["id"])
		seen_ids[c["id"]] = true
		assert_gt(float((c["holes"] as Array).size()), 0.0, "%s has holes" % c["id"])
		assert_true(String(c.get("name", "")) != "", "%s has a name" % c["id"])
		for hid in c["holes"]:
			if checked.has(hid):
				continue
			checked[hid] = true
			var path := "res://data/holes/%s.json" % hid
			assert_true(FileAccess.file_exists(path), "%s (%s) exists" % [hid, c["id"]])
			var h := HoleDefinition.load_from_file(path)
			assert_true(h != null, "%s loads" % hid)
			if h == null:
				continue
			assert_true(RANGES.has(h.par), "%s par %d is 3/4/5" % [hid, h.par])
			if RANGES.has(h.par):
				var r: Vector2 = RANGES[h.par]
				assert_true(h.yards >= r.x and h.yards <= r.y, "%s %d yd inside par %d range" % [hid, int(h.yards), h.par])
	note("checked %d courses, %d distinct holes" % [seen_ids.size(), checked.size()])


func test_new_courses_registered_with_par_mix() -> void:
	for cid in NEW_COURSES:
		var ids := _course_holes(cid)
		assert_gt(float(ids.size()), 5.0, "%s has 6+ holes" % cid)
		var pars := {}
		for hid in ids:
			var h := HoleDefinition.load_from_file("res://data/holes/%s.json" % hid)
			pars[h.par] = int(pars.get(h.par, 0)) + 1
		for p in [3, 4, 5]:
			assert_gt(float(pars.get(p, 0)), 0.0, "%s has a par %d" % [cid, p])


func test_new_course_holes_fair_and_relief_valid() -> void:
	for cid in NEW_COURSES:
		for hid in _course_holes(cid):
			var h := HoleDefinition.load_from_file("res://data/holes/%s.json" % hid)
			var tees: Array = [h.tee]
			for to in h.tee_options.values():
				tees.append(to["pos"])
			for t in tees:
				var tp: Vector2 = t
				assert_eq(h.surface_at(tp.x, tp.y), Surface.Type.TEE, "%s tee %s is a TEE lie" % [hid, tp])
				assert_true(h.is_safe_spot(tp.x, tp.y, 5.0), "%s tee %s safe" % [hid, tp])
				for w in h.waters:
					assert_gt((w as HoleDefinition.Ellipse).signed_dist(tp.x, tp.y), TEE_WATER_CLEAR_M, "%s tee %s clear of water" % [hid, tp])
			assert_eq(h.surface_at(h.pin.x, h.pin.y), Surface.Type.GREEN, "%s cup on green" % hid)
			assert_true(is_finite(h.cup_position().y), "%s cup height finite" % hid)
			assert_gt(float(h.relief_points.size()), 0.0, "%s has relief points" % hid)
			for rp in h.relief_points:
				var q: Vector2 = rp
				assert_true(h.is_safe_spot(q.x, q.y, 2.0), "%s relief %s safe" % [hid, q])
				var s := h.surface_at(q.x, q.y)
				assert_true(s != Surface.Type.WATER and s != Surface.Type.BUNKER and s != Surface.Type.OOB, "%s relief %s dry" % [hid, q])
			assert_true(h.play_area.encloses(h.fairway_aabb.grow(10.0)), "%s fairway inside play area" % hid)


func _bot(cid: String) -> void:
	var s := TestHelpers.make_session(TestHelpers.load_hole_ids(_course_holes(cid)))
	TestHelpers.bot_round(s, 4000)
	assert_true(s.is_round_complete(), "%s round completes" % cid)
	var parts: Array[String] = []
	for hs in s.round_state.holes:
		var hst: HoleState = hs
		assert_true(hst.complete, "%s %s complete" % [cid, hst.hole_id])
		parts.append("%s:%d" % [hst.hole_id, hst.score()])
	note("bot %s %s total %d (%s)" % [cid, ", ".join(parts), s.round_state.total_score(), RoundState.fmt_relative(s.round_state.relative_to_par())])
	TestHelpers.cleanup_repo(s.repo)


func test_alpine_round_completes() -> void:
	_bot("alpine")


func test_oasis_round_completes() -> void:
	_bot("oasis")


func test_islands_round_completes() -> void:
	_bot("islands")


func test_stadium_round_completes() -> void:
	_bot("stadium")

extends TestCase
## Courses 5 and 6 (Jizzy Nash Nash, Canyon Mesa), three tees per hole, varied seeded pin positions.

const GREEN_SLOPE_LIMIT := 0.09  # same limit as test_course._check_generated_hole
const RANGES := {3: Vector2(50, 100), 4: Vector2(100, 200), 5: Vector2(200, 300)}


func _course_ids(course_id: String) -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/courses.json"))
	for c in data["courses"]:
		if String(c["id"]) == course_id:
			return c["holes"]
	return []


func _all_hole_ids() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at("res://data/holes"):
		if f.begins_with("hole_") and f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


func _slope(h: HoleDefinition, p: Vector2) -> float:
	var n := h.normal_at(p.x, p.y)
	return sqrt(1.0 - n.y * n.y) / maxf(n.y, 0.01)


func test_new_courses_registered() -> void:
	var jizzy := _course_ids("jizzy")
	var mesa := _course_ids("mesa")
	assert_eq(jizzy.size(), 9, "Jizzy Nash Nash has 9 holes")
	assert_true(mesa.size() == 6 or mesa.size() == 9, "second course has 6 or 9 holes")
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/courses.json"))
	var names := []
	for c in data["courses"]:
		names.append(String(c["name"]))
	assert_true("Jizzy Nash Nash" in names, "course named exactly Jizzy Nash Nash")
	var seen := {}
	for c in data["courses"]:
		assert_false(seen.has(c["id"]), "unique course id %s" % c["id"])
		seen[c["id"]] = true


func test_new_course_holes_valid() -> void:
	var ids: Array = _course_ids("jizzy") + _course_ids("mesa")
	var pars := {}
	for hid in ids:
		var h := HoleDefinition.load_from_file("res://data/holes/%s.json" % hid)
		assert_true(h != null, "%s loads" % hid)
		pars[h.par] = int(pars.get(h.par, 0)) + 1
		assert_true(RANGES.has(h.par), "%s par is 3/4/5" % hid)
		var r: Vector2 = RANGES[h.par]
		assert_true(h.yards >= r.x and h.yards <= r.y, "%s yellow %d yd inside the owner's par %d range" % [hid, int(h.yards), h.par])
		assert_eq(h.surface_at(h.tee.x, h.tee.y), Surface.Type.TEE, "%s tee" % hid)
		assert_true(h.in_bounds(h.tee.x, h.tee.y), "%s tee inside play area" % hid)
		assert_true(h.in_bounds(h.pin.x, h.pin.y), "%s cup inside play area" % hid)
		assert_eq(h.surface_at(h.pin.x, h.pin.y), Surface.Type.GREEN, "%s cup on green" % hid)
		var cup := h.cup_position()
		assert_true(is_finite(cup.y), "%s cup height finite" % hid)
		for w in h.waters:
			assert_gt((w as HoleDefinition.Ellipse).signed_dist(h.pin.x, h.pin.y), 8.0, "%s pin clear of water" % hid)
		assert_true(h.play_area.encloses(h.fairway_aabb.grow(10.0)), "%s fairway inside play area" % hid)
		assert_gt(h.trees.size() + h.bunkers.size() + h.waters.size(), 3, "%s has features" % hid)
		var line := 0.0
		for seg in h.fairway:
			line += (seg["p0"] as Vector2).distance_to(seg["p1"])
		assert_near(line, h.nominal_length_m(), h.nominal_length_m() * 0.06, "%s centreline length" % hid)
	assert_gt(float(pars.get(3, 0)), 1.0, "has several par 3s")
	assert_gt(float(pars.get(4, 0)), 1.0, "has par 4s")
	assert_gt(float(pars.get(5, 0)), 0.0, "has par 5s")
	# Jizzy Nash Nash features: a water-carry par 3 and a creek-fronted green
	var carry := false
	var creek_green := false
	for hid in _course_ids("jizzy"):
		var h := HoleDefinition.load_from_file("res://data/holes/%s.json" % hid)
		var g: HoleDefinition.Ellipse = h.greens[0]
		if h.par == 3 and not h.waters.is_empty():
			carry = true
		for w in h.waters:
			var we: HoleDefinition.Ellipse = w
			var d := Vector2(we.cx, we.cz).distance_to(Vector2(g.cx, g.cz))
			if h.par >= 4 and d < 40.0 and we.b < 8.0:
				creek_green = true
	assert_true(carry, "water-carry par 3")
	assert_true(creek_green, "creek in front of a green")


func test_every_hole_has_three_tees() -> void:
	for hid in _all_hole_ids():
		var h := HoleDefinition.load_from_file("res://data/holes/%s.json" % hid)
		assert_eq(h.tee_options.size(), 3, "%s has 3 tees" % hid)
		if h.tee_options.size() != 3:
			continue
		var y: Dictionary = h.tee_options["yellow"]
		var b: Dictionary = h.tee_options["blue"]
		var r: Dictionary = h.tee_options["red"]
		assert_near((y["pos"] as Vector2).distance_to(h.tee), 0.0, 1e-6, "%s yellow is the default tee" % hid)
		assert_near(float(y["yards"]), h.yards, 0.51, "%s yellow yards" % hid)
		var bp := float(b["yards"]) / float(y["yards"]) - 1.0
		var rp := 1.0 - float(r["yards"]) / float(y["yards"])
		assert_true(bp >= 0.115 and bp <= 0.185, "%s blue %.1f %% longer" % [hid, bp * 100.0])
		assert_true(rp >= 0.115 and rp <= 0.185, "%s red %.1f %% shorter" % [hid, rp * 100.0])
		# the three tees lie in order along the line of play and on tee boxes
		var pin: Vector2 = h.pin
		var db: float = (b["pos"] as Vector2).distance_to(pin)
		var dy: float = (y["pos"] as Vector2).distance_to(pin)
		var dr: float = (r["pos"] as Vector2).distance_to(pin)
		assert_true(db > dy and dy > dr, "%s blue back, red forward" % hid)
		for col in ["blue", "yellow", "red"]:
			var p: Vector2 = h.tee_options[col]["pos"]
			assert_eq(h.surface_at(p.x, p.y), Surface.Type.TEE, "%s %s tee on a tee box" % [hid, col])
			assert_true(h.in_bounds(p.x, p.y) and h.play_area.grow(-10.0).has_point(p), "%s %s tee in play" % [hid, col])
			assert_true(is_finite(h.tee_position(0.11).y), "%s %s tee height" % [hid, col])
			assert_true(h.is_safe_spot(p.x, p.y, 0.0), "%s %s tee is a safe spot" % [hid, col])


func test_every_hole_has_valid_pin_options() -> void:
	for hid in _all_hole_ids():
		var h := HoleDefinition.load_from_file("res://data/holes/%s.json" % hid)
		var n := h.pin_options.size()
		assert_true(n >= 3 and n <= 5, "%s has 3-5 pin options (%d)" % [hid, n])
		if n == 0:
			continue
		assert_near((h.pin_options[0]["pos"] as Vector2).distance_to(h.pin), 0.0, 1e-6, "%s option 0 is the fixed pin" % hid)
		var g: HoleDefinition.Ellipse = h.greens[0]
		for i in n:
			var p: Vector2 = h.pin_options[i]["pos"]
			assert_eq(h.surface_at(p.x, p.y), Surface.Type.GREEN, "%s pin %d on green" % [hid, i])
			assert_true(g.signed_dist(p.x, p.y) <= -2.0, "%s pin %d at least 2 m inside the green edge (%.1f)" % [hid, i, g.signed_dist(p.x, p.y)])
			if i > 0:  # option 0 is today's fixed pin (hole_05's sits near its hazards on a steeper spot)
				assert_lt(_slope(h, p), GREEN_SLOPE_LIMIT, "%s pin %d slope" % [hid, i])
			assert_true(is_finite(h.terrain_height(p.x, p.y)), "%s pin %d height" % [hid, i])
			for w in h.waters:
				assert_gt((w as HoleDefinition.Ellipse).signed_dist(p.x, p.y), 3.0, "%s pin %d clear of water" % [hid, i])
			for j in i:
				assert_gt(p.distance_to(h.pin_options[j]["pos"]), 2.5, "%s pins %d/%d distinct" % [hid, i, j])


func test_pin_choice_is_seeded_and_deterministic() -> void:
	var seen := {}
	for s in 60:
		var a := HoleDefinition.pin_index_for_seed(s, "hole_04", 4)
		assert_eq(a, HoleDefinition.pin_index_for_seed(s, "hole_04", 4), "same seed, same pin")
		assert_true(a >= 0 and a < 4)
		seen[a] = true
	assert_eq(seen.size(), 4, "all pin positions occur across seeds")
	assert_eq(HoleDefinition.pin_index_for_seed(7, "hole_04", 1), 0, "single option")
	# two independent loads (two phones / a resume) agree for the same seed, for every hole
	for hid in _all_hole_ids():
		var h1 := HoleDefinition.load_from_file("res://data/holes/%s.json" % hid)
		var h2 := HoleDefinition.load_from_file("res://data/holes/%s.json" % hid)
		h1.apply_round_options("yellow", true, 424242)
		h2.apply_round_options("yellow", true, 424242)
		assert_near(h1.pin.distance_to(h2.pin), 0.0, 1e-9, "%s same pin for the same seed" % hid)
		assert_near(h1.yards, h2.yards, 1e-9, "%s same yards" % hid)
	# fixed mode ignores the seed
	var f := HoleDefinition.load_from_file("res://data/holes/hole_04.json")
	var fixed := f.pin
	f.apply_round_options("yellow", false, 99)
	assert_near(f.pin.distance_to(fixed), 0.0, 1e-9, "fixed pin is today's pin")
	assert_near(f.yards, 170.0, 1e-9, "fixed yellow keeps the nominal yards")


func test_chosen_tee_and_pin_drive_tee_position_and_length() -> void:
	var h := HoleDefinition.load_from_file("res://data/holes/hole_04.json")
	h.apply_round_options("blue", false, 1)
	assert_eq(h.tee_color, "blue")
	assert_near(h.tee.distance_to(h.tee_options["blue"]["pos"]), 0.0, 1e-9, "tee is the blue tee")
	assert_near(h.yards, float(h.tee_options["blue"]["yards"]), 1e-9, "blue yards (fixed pin)")
	var pos := h.tee_position(0.11)
	assert_near(pos.x, h.tee.x, 1e-9)
	assert_near(pos.z, h.tee.y, 1e-9)
	assert_true(h.tee_marker_color().b > h.tee_marker_color().r, "blue markers")
	h.apply_round_options("red", false, 1)
	assert_lt(h.yards, 170.0, "red tee is shorter")
	assert_true(h.tee_marker_color().r > h.tee_marker_color().b, "red markers")
	h.apply_round_options("nonsense", false, 1)
	assert_eq(h.tee_color, "yellow", "unknown colour falls back to yellow")
	# displayed length follows the actual tee-to-pin distance of the chosen pin
	var base_pin := h.pin
	for s in 30:
		h.apply_round_options("yellow", true, s)
		var expect := 170.0 + (h.tee.distance_to(h.pin) - h.tee.distance_to(base_pin)) / 0.9144
		assert_near(h.yards, expect, 1e-6, "yards follow tee-to-pin distance")
		assert_lt(absf(h.yards - 170.0), 14.0, "pin changes length only a little")


func test_default_yards_stay_inside_owner_ranges_for_every_pin() -> void:
	for hid in _all_hole_ids():
		var h := HoleDefinition.load_from_file("res://data/holes/%s.json" % hid)
		var r: Vector2 = RANGES[h.par]
		for s in 40:
			h.apply_round_options("yellow", true, s)
			assert_true(h.yards >= r.x - 0.5 and h.yards <= r.y + 0.5, "%s yellow %.1f yd (%s) inside par %d range" % [hid, h.yards, h.pin_name, h.par])


func test_round_config_tee_and_pin_roundtrip() -> void:
	var rc := RoundConfig.new()
	assert_eq(rc.tee_color, "yellow", "default tee yellow")
	assert_true(rc.pin_varied, "default pins varied")
	rc.tee_color = "red"
	rc.pin_varied = false
	var rc2 := RoundConfig.from_dict(JSON.parse_string(JSON.stringify(rc.to_dict())))
	assert_eq(rc2.tee_color, "red")
	assert_false(rc2.pin_varied)
	var rc3 := rc.duplicate_config()
	assert_eq(rc3.tee_color, "red")
	assert_false(rc3.pin_varied)
	var old := RoundConfig.from_dict({"cup_diameter_ft": 1.0})  # host from an older build
	assert_eq(old.tee_color, "yellow")
	assert_true(old.pin_varied)
	assert_eq(RoundConfig.from_dict({"tee_color": "purple"}).tee_color, "yellow", "invalid colour clamps")
	var st := SettingsStore.new()
	st.save_path = "user://test_rc_tees_%d.json" % randi()
	rc.write_defaults(st)
	var back := RoundConfig.from_settings(st)
	assert_eq(back.tee_color, "red")
	assert_false(back.pin_varied)
	if FileAccess.file_exists(st.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(st.save_path))


func test_session_applies_tees_and_seeded_pins_identically() -> void:
	var rules := RoundConfig.new()
	rules.tee_color = "blue"
	var pins: Array = []
	for run in 2:
		var defs := TestHelpers.load_hole_ids(["hole_18", "hole_19", "hole_20"])
		var s := GameSession.new(PhysicsConfig.new(), TestHelpers.make_repo())
		s.apply_rules(rules)
		s.start_round(defs, 777)
		var these: Array = []
		for d in defs:
			var hd: HoleDefinition = d
			assert_eq(hd.tee_color, "blue")
			these.append(hd.pin)
		assert_near((s.ball_pos.x - (defs[0] as HoleDefinition).tee.x), 0.0, 1e-6, "ball starts on the blue tee")
		assert_near((s.ball_pos.z - (defs[0] as HoleDefinition).tee.y), 0.0, 1e-6, "ball starts on the blue tee (z)")
		pins.append(these)
		TestHelpers.cleanup_repo(s.repo)
	assert_eq(pins[0], pins[1], "same seed, same pins on both phones")


func test_new_course_greens_and_fairways_playable() -> void:
	for hid in _course_ids("jizzy") + _course_ids("mesa"):
		var h := HoleDefinition.load_from_file("res://data/holes/%s.json" % hid)
		var g: HoleDefinition.Ellipse = h.greens[0]
		var max_gr := 0.0
		var x := g.cx - g.a
		while x <= g.cx + g.a:
			var z := g.cz - g.a
			while z <= g.cz + g.a:
				if h.surface_at(x, z) == Surface.Type.GREEN and g.signed_dist(x, z) < -1.0:
					max_gr = maxf(max_gr, _slope(h, Vector2(x, z)))
				z += 1.5
			x += 1.5
		assert_lt(max_gr, GREEN_SLOPE_LIMIT, "%s green slope %.3f" % [hid, max_gr])
		var max_fw := 0.0
		for seg in h.fairway:
			var mid: Vector2 = ((seg["p0"] as Vector2) + (seg["p1"] as Vector2)) * 0.5
			if mid.distance_to(h.tee) > 15.0 and g.signed_dist(mid.x, mid.y) > 12.0:
				max_fw = maxf(max_fw, _slope(h, mid))
		assert_lt(max_fw, 0.30, "%s fairway slope %.3f" % [hid, max_fw])
		note("%s max green slope %.3f, fairway %.3f" % [hid, max_gr, max_fw])

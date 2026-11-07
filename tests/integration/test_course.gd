extends TestCase
## Course data sanity: lengths, tees, greens, hazards, collision proxies, round completion.


func test_three_holes_par_and_length() -> void:
	var defs := TestHelpers.load_holes()
	assert_eq(defs.size(), 3)
	var pars := [3, 4, 5]
	var yards := [150, 360, 510]
	for i in 3:
		var h: HoleDefinition = defs[i]
		assert_eq(h.par, pars[i])
		assert_eq(int(h.yards), yards[i])
		assert_eq(h.surface_at(h.tee.x, h.tee.y), Surface.Type.TEE, "%s tee on tee box" % h.id)
		assert_eq(h.surface_at(h.pin.x, h.pin.y), Surface.Type.GREEN, "%s pin on green" % h.id)
		assert_true(h.in_bounds(h.tee.x, h.tee.y) and h.in_bounds(h.pin.x, h.pin.y))
		var line := 0.0
		var prev := h.tee
		for seg in h.fairway:
			line += prev.distance_to(seg["p0"]) if prev.distance_to(seg["p0"]) > 0.5 else 0.0
			line += (seg["p0"] as Vector2).distance_to(seg["p1"])
			prev = seg["p1"]
		line += prev.distance_to(h.pin)
		note("%s centreline %.1f m vs nominal %.1f m, trees %d" % [h.id, line, h.nominal_length_m(), h.trees.size()])
		assert_near(line, h.nominal_length_m(), h.nominal_length_m() * 0.06, "%s centreline length" % h.id)


func test_holes_have_required_features() -> void:
	var defs := TestHelpers.load_holes()
	var h1: HoleDefinition = defs[0]
	var h2: HoleDefinition = defs[1]
	var h3: HoleDefinition = defs[2]
	assert_gt(h1.bunkers.size(), 0, "hole 1 bunker")
	assert_gt(h2.trees.size(), 40, "hole 2 trees")
	assert_gt(h3.waters.size(), 0, "hole 3 water")
	assert_gt(h3.boundary.size(), 2, "hole 3 OOB")
	var tee_h := h3.terrain_height(h3.tee.x, h3.tee.y)
	var green_h := h3.terrain_height(h3.pin.x, h3.pin.y)
	note("hole 3 tee %.1f m, green %.1f m elevation" % [tee_h, green_h])


func test_water_is_below_shore_and_classified() -> void:
	for hd in TestHelpers.load_holes():
		var h: HoleDefinition = hd
		for i in h.waters.size():
			var w: HoleDefinition.Ellipse = h.waters[i]
			assert_eq(h.surface_at(w.cx, w.cz), Surface.Type.WATER)
			assert_lt(h.terrain_height(w.cx, w.cz), float(h.water_level[i]), "bed below water level")


func test_terrain_is_finite_over_bounds() -> void:
	for hd in TestHelpers.load_holes():
		var h: HoleDefinition = hd
		var x := h.bounds.position.x
		while x <= h.bounds.end.x:
			var z := h.bounds.position.y
			while z <= h.bounds.end.y:
				var y := h.terrain_height(x, z)
				assert_true(is_finite(y))
				z += 7.3
			x += 7.3


func test_bot_completes_full_round() -> void:
	# Greedy bot: aim at pin; choose Caps when far, Goals when near. Must finish 3 holes.
	var s := TestHelpers.make_session()
	var guard := 200
	while not s.is_round_complete() and guard > 0:
		guard -= 1
		match s.state:
			ShotTypes.State.HOLE_INTRO:
				s.begin_play()
			ShotTypes.State.AIMING:
				var d := s.distance_to_pin_m()
				s.aim_at_pin()
				if d > 25.0:
					TestHelpers.shoot(s, ShotTypes.Mode.CAPS, int(Units.m_to_yards(minf(d, 200.0)) * 0.9), 0)
				else:
					TestHelpers.shoot(s, ShotTypes.Mode.GOALS, 0, maxi(1, int(Units.m_to_feet(d))))
			ShotTypes.State.SHOT_RESULT:
				s.acknowledge_result()
			ShotTypes.State.HOLE_COMPLETE:
				s.next_hole()
	assert_true(s.is_round_complete(), "round completes")
	var parts: Array[String] = []
	for hs in s.round_state.holes:
		var h: HoleState = hs
		assert_true(h.complete)
		assert_true(h.score() <= h.max_score())
		parts.append("%s:%d(%s)" % [h.hole_id, h.score(), h.completion])
	note("bot round %s total %d (%s)" % [", ".join(parts), s.round_state.total_score(), RoundState.fmt_relative(s.round_state.relative_to_par())])
	assert_eq(s.pool.used_count(), s.history.size(), "one footballer per shot across round")
	TestHelpers.cleanup_repo(s.repo)

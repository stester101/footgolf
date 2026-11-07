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


func test_ridge_holes_valid_and_hilly() -> void:
	var defs := TestHelpers.load_ridge_holes()
	var pars := [4, 3, 5, 4, 3, 5]
	var yards := [380, 195, 540, 335, 160, 575]
	assert_eq(defs.size(), 6)
	for i in 6:
		var h: HoleDefinition = defs[i]
		assert_true(h != null, "hole %d loads" % (i + 4))
		assert_eq(h.par, pars[i])
		assert_eq(int(h.yards), yards[i])
		assert_eq(h.surface_at(h.tee.x, h.tee.y), Surface.Type.TEE, "%s tee" % h.id)
		assert_eq(h.surface_at(h.pin.x, h.pin.y), Surface.Type.GREEN, "%s pin on green" % h.id)
		assert_true(h.in_bounds(h.tee.x, h.tee.y) and h.in_bounds(h.pin.x, h.pin.y), "%s tee/pin in bounds" % h.id)
		assert_gt(Geometry2D.triangulate_polygon(h.boundary).size(), 0, "%s boundary is a simple polygon" % h.id)
		for seg in h.fairway:
			assert_true(h.in_bounds((seg["p0"] as Vector2).x, (seg["p0"] as Vector2).y), "%s fairway inside OOB line" % h.id)
		# centreline length ≈ nominal
		var line := 0.0
		for seg in h.fairway:
			line += (seg["p0"] as Vector2).distance_to(seg["p1"])
		assert_near(line, h.nominal_length_m(), h.nominal_length_m() * 0.06, "%s length" % h.id)
		# terrain: relief overall, but playable surfaces stay playable (slope limits)
		var lo := INF
		var hi := -INF
		var max_fw := 0.0
		var max_gr := 0.0
		var x := h.bounds.position.x
		while x <= h.bounds.end.x:
			var z := h.bounds.position.y
			while z <= h.bounds.end.y:
				var y := h.terrain_height(x, z)
				lo = minf(lo, y)
				hi = maxf(hi, y)
				var s := h.surface_at(x, z)
				var near_hazard := false
				for bk in h.bunkers:
					if (bk as HoleDefinition.Ellipse).signed_dist(x, z) < 3.5:
						near_hazard = true
				for wt in h.waters:
					if (wt as HoleDefinition.Ellipse).signed_dist(x, z) < 5.0:
						near_hazard = true
				# tee/green terrain blends are not "playing" fairway: skip the first/last 12 m
				var g0: HoleDefinition.Ellipse = h.greens[0]
				if s == Surface.Type.FAIRWAY and (Vector2(x, z).distance_to(h.tee) < 12.0 or g0.signed_dist(x, z) < 12.0):
					near_hazard = true
				if not near_hazard and (s == Surface.Type.FAIRWAY or s == Surface.Type.GREEN):
					var n := h.normal_at(x, z)
					var slope := sqrt(1.0 - n.y * n.y) / maxf(n.y, 0.01)
					if s == Surface.Type.GREEN:
						max_gr = maxf(max_gr, slope)
					else:
						max_fw = maxf(max_fw, slope)
				z += 3.1
			x += 3.1
		note("%s: relief %.1f m, max fairway slope %.3f, max green slope %.3f, trees %d, water %d, bunkers %d" % [h.id, hi - lo, max_fw, max_gr, h.trees.size(), h.waters.size(), h.bunkers.size()])
		assert_gt(hi - lo, 12.0, "%s is hilly" % h.id)
		assert_lt(max_fw, 0.30, "%s fairway slope playable" % h.id)
		assert_lt(max_gr, 0.09, "%s green slope playable" % h.id)
		assert_gt(h.trees.size(), 150, "%s forested" % h.id)


func test_ridge_round_completes() -> void:
	var s := TestHelpers.make_session(TestHelpers.load_ridge_holes())
	var guard := 400
	while not s.is_round_complete() and guard > 0:
		guard -= 1
		match s.state:
			ShotTypes.State.HOLE_INTRO:
				s.begin_play()
			ShotTypes.State.AIMING:
				var d := s.distance_to_pin_m()
				s.aim_at_pin()
				if s.current_lie() == Surface.Type.GREEN or d <= 25.0:
					TestHelpers.shoot(s, ShotTypes.Mode.GOALS, 0, maxi(1, int(Units.m_to_feet(d))))
				else:
					TestHelpers.shoot(s, ShotTypes.Mode.CAPS, int(Units.m_to_yards(minf(d, 200.0)) * 0.9), 0)
			ShotTypes.State.SHOT_RESULT:
				s.acknowledge_result()
			ShotTypes.State.HOLE_COMPLETE:
				s.next_hole()
	assert_true(s.is_round_complete(), "ridge round completes")
	var parts: Array[String] = []
	for hs in s.round_state.holes:
		parts.append("%s:%d" % [(hs as HoleState).hole_id, (hs as HoleState).score()])
	note("bot ridge round %s total %d (%s)" % [", ".join(parts), s.round_state.total_score(), RoundState.fmt_relative(s.round_state.relative_to_par())])
	TestHelpers.cleanup_repo(s.repo)

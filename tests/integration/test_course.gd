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
	# Whole visible course is in play: fairway, green and the rough well beyond them are in bounds.
	for seg in h3.fairway:
		for lat in [0.0, 30.0, -30.0, 55.0, -55.0]:
			var p0: Vector2 = seg["p0"]
			var p1: Vector2 = seg["p1"]
			var n := (p1 - p0).normalized().orthogonal()
			var q: Vector2 = p0.lerp(p1, 0.5) + n * float(lat)
			assert_true(h3.in_bounds(q.x, q.y), "hole 3 %.0f m off the fairway is in play" % lat)
	assert_true(h3.in_bounds(h3.pin.x + 40.0, h3.pin.y), "hole 3 rough beside green in play")
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
	# Greedy bot on Starter Links: must hole out all 3 holes (no max-score cap).
	_bot_round(TestHelpers.load_holes(), "starter")


## Only the outer edge band of the rendered terrain is OOB; everything else visible is in play
## ("Make all visible course playable", docs/DECISIONS.md).
func test_whole_visible_course_in_play() -> void:
	for hd in TestHelpers.load_all_course_holes():
		var h: HoleDefinition = hd
		assert_true(h.bounds.encloses(h.play_area), "%s play area inside rendered terrain" % h.id)
		assert_near(h.play_area.position.x - h.bounds.position.x, HoleDefinition.OOB_INSET_M, 0.01, "%s 25 m edge band" % h.id)
		var inside_oob := 0
		var edge_in := 0
		var x := h.bounds.position.x + 1.0
		while x < h.bounds.end.x:
			var z := h.bounds.position.y + 1.0
			while z < h.bounds.end.y:
				var edge := minf(minf(x - h.bounds.position.x, h.bounds.end.x - x), minf(z - h.bounds.position.y, h.bounds.end.y - z))
				var s := h.surface_at(x, z)
				if edge > h.oob_inset + 0.5 and (s == Surface.Type.OOB or not h.in_bounds(x, z)):
					inside_oob += 1
				if edge < h.oob_inset - 0.5 and (s != Surface.Type.OOB or h.in_bounds(x, z)):
					edge_in += 1
				z += 6.1
			x += 6.1
		assert_eq(inside_oob, 0, "%s: no OOB inside the play area" % h.id)
		assert_eq(edge_in, 0, "%s: far edge band is OOB" % h.id)
		# every playing feature, with generous rough around it, is in play
		var fa := h.fairway_aabb.grow(20.0)
		assert_true(h.play_area.encloses(fa), "%s fairway + 20 m rough in play" % h.id)
		for g in h.greens:
			var ge: HoleDefinition.Ellipse = g
			assert_true(h.play_area.encloses(ge.aabb.grow(15.0)), "%s green surrounds in play" % h.id)
		for tb in h.tee_boxes:
			assert_true(h.play_area.encloses((tb as HoleDefinition.Box).aabb.grow(15.0)), "%s tee surrounds in play" % h.id)
		for w in h.waters:
			var we: HoleDefinition.Ellipse = w
			assert_true(h.in_bounds(we.cx, we.cz), "%s water hazard inside play area" % h.id)
		assert_eq(h.boundary.size(), 4, "%s OOB line is the play-area rectangle" % h.id)


## Shared validity checks for generated holes: tee/pin lies, length, slopes, water, finite terrain.
## Returns {relief, max_fw, max_gr}.
func _check_generated_hole(h: HoleDefinition, par: int, yards: int) -> Dictionary:
	assert_true(h != null, "hole loads")
	assert_eq(h.par, par, "%s par" % h.id)
	assert_eq(int(h.yards), yards, "%s yards" % h.id)
	assert_eq(h.surface_at(h.tee.x, h.tee.y), Surface.Type.TEE, "%s tee" % h.id)
	assert_eq(h.surface_at(h.pin.x, h.pin.y), Surface.Type.GREEN, "%s pin on green" % h.id)
	assert_true(h.in_bounds(h.tee.x, h.tee.y) and h.in_bounds(h.pin.x, h.pin.y), "%s tee/pin in bounds" % h.id)
	for seg in h.fairway:
		for p in [seg["p0"], seg["p1"]]:
			# the old OOB corridor was ~50 m off the centreline; now that and more is in play
			var d: Vector2 = (seg["p1"] - seg["p0"]).normalized().orthogonal()
			for lat in [0.0, 50.0, -50.0]:
				var q: Vector2 = p + d * lat
				assert_true(h.in_bounds(q.x, q.y), "%s fairway / rough %.0f m off line in play" % [h.id, lat])
	for i in h.waters.size():
		var w: HoleDefinition.Ellipse = h.waters[i]
		assert_eq(h.surface_at(w.cx, w.cz), Surface.Type.WATER, "%s water classified" % h.id)
		assert_lt(h.terrain_height(w.cx, w.cz), float(h.water_level[i]), "%s bed below water level" % h.id)
	var g0: HoleDefinition.Ellipse = h.greens[0]
	for w in h.waters:
		assert_gt((w as HoleDefinition.Ellipse).signed_dist(h.pin.x, h.pin.y), 8.0, "%s pin clear of water" % h.id)
	# centreline length ≈ nominal
	var line := 0.0
	for seg in h.fairway:
		line += (seg["p0"] as Vector2).distance_to(seg["p1"])
	assert_near(line, h.nominal_length_m(), h.nominal_length_m() * 0.06, "%s length" % h.id)
	# terrain: finite everywhere, playable surfaces stay playable (slope limits)
	var lo := INF
	var hi := -INF
	var max_fw := 0.0
	var max_gr := 0.0
	var finite := true
	var x := h.bounds.position.x
	while x <= h.bounds.end.x:
		var z := h.bounds.position.y
		while z <= h.bounds.end.y:
			var y := h.terrain_height(x, z)
			finite = finite and is_finite(y)
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
	assert_true(finite, "%s terrain finite" % h.id)
	note("%s %s par %d %d yd: relief %.1f m, max fairway slope %.3f, max green slope %.3f, trees %d, water %d, bunkers %d, wind %.1f m/s" % [h.id, h.display_name, h.par, int(h.yards), hi - lo, max_fw, max_gr, h.trees.size(), h.waters.size(), h.bunkers.size(), h.wind_speed])
	assert_lt(max_fw, 0.30, "%s fairway slope playable" % h.id)
	assert_lt(max_gr, 0.09, "%s green slope playable" % h.id)
	return {"relief": hi - lo, "max_fw": max_fw, "max_gr": max_gr}


## Greedy bot (aim at pin; Goals on the green or when close, else Caps at 90 % of the distance).
## There is no max-score cap, so the bot must actually hole out every hole.
func _bot_round(defs: Array, label: String) -> void:
	var s := TestHelpers.make_session(defs)
	var guard := 4000
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
	assert_true(s.is_round_complete(), "%s round completes" % label)
	var parts: Array[String] = []
	for hs in s.round_state.holes:
		var hst: HoleState = hs
		assert_true(hst.complete, "%s %s complete" % [label, hst.hole_id])
		parts.append("%s:%d(%s)" % [hst.hole_id, hst.score(), hst.completion])
	note("bot %s round %s total %d (%s)" % [label, ", ".join(parts), s.round_state.total_score(), RoundState.fmt_relative(s.round_state.relative_to_par())])
	assert_eq(s.pool.used_count(), s.history.size(), "%s one footballer per shot" % label)
	TestHelpers.cleanup_repo(s.repo)


func test_ridge_holes_valid_and_hilly() -> void:
	var defs := TestHelpers.load_ridge_holes()
	var pars := [4, 3, 5, 4, 3, 5]
	var yards := [380, 195, 540, 335, 160, 575]
	assert_eq(defs.size(), 6)
	for i in 6:
		var h: HoleDefinition = defs[i]
		var st := _check_generated_hole(h, pars[i], yards[i])
		assert_gt(float(st["relief"]), 12.0, "%s is hilly" % h.id)
		assert_gt(h.trees.size(), 150, "%s forested" % h.id)


func test_coastal_holes_valid_and_open() -> void:
	var defs := TestHelpers.load_hole_ids(TestHelpers.COASTAL_IDS)
	var pars := [4, 3, 5, 4]
	var yards := [395, 170, 555, 350]
	assert_eq(defs.size(), 4)
	var pots := 0
	var water := 0
	for i in defs.size():
		var h: HoleDefinition = defs[i]
		_check_generated_hole(h, pars[i], yards[i])
		assert_lt(h.trees.size(), 120, "%s is open links (few trees)" % h.id)
		assert_gt(h.wind_speed, 4.0, "%s is windy" % h.id)
		assert_gt(h.bunkers.size(), 3, "%s has pot bunkers" % h.id)
		for b in h.bunkers:
			var be: HoleDefinition.Ellipse = b
			if maxf(be.a, be.b) <= 3.5:
				pots += 1
		water += h.waters.size()
	assert_gt(pots, 15, "coastal pot bunkers")
	assert_gt(water, 0, "coastal burn")


func test_lakeside_holes_valid_with_water() -> void:
	var defs := TestHelpers.load_hole_ids(TestHelpers.LAKESIDE_IDS)
	var pars := [4, 3, 5, 4]
	var yards := [365, 165, 525, 405]
	assert_eq(defs.size(), 4)
	for i in defs.size():
		var h: HoleDefinition = defs[i]
		_check_generated_hole(h, pars[i], yards[i])
		assert_gt(h.waters.size(), 0, "%s has water" % h.id)
		assert_gt(h.trees.size(), 100, "%s is wooded parkland" % h.id)
		assert_lt(h.conifer_ratio, 0.3, "%s mostly deciduous" % h.id)
		# at least one lake crosses the line of play (a carry): the straight tee->pin line or the centreline
		var carry := false
		for w in h.waters:
			for seg in h.fairway:
				for k in 11:
					var q: Vector2 = (seg["p0"] as Vector2).lerp(seg["p1"], k / 10.0)
					if (w as HoleDefinition.Ellipse).contains(q.x, q.y):
						carry = true
		if h.id != "hole_17":
			assert_true(carry, "%s has a water carry" % h.id)


func test_ridge_round_completes() -> void:
	_bot_round(TestHelpers.load_ridge_holes(), "ridge")


func test_coastal_round_completes() -> void:
	_bot_round(TestHelpers.load_hole_ids(TestHelpers.COASTAL_IDS), "coastal")


func test_lakeside_round_completes() -> void:
	_bot_round(TestHelpers.load_hole_ids(TestHelpers.LAKESIDE_IDS), "lakeside")

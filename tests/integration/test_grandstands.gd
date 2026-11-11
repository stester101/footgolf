extends TestCase
## Grandstands are solid: the ball bounces off them, never comes to rest inside or on top of one, relief never
## drops a ball inside one, they are deterministic, and the neutral calibration plane has none.


func _holes_with_stands() -> Array:
	var out: Array = []
	for h in TestHelpers.load_all_course_holes():
		var hd: HoleDefinition = h
		if not hd.grandstands().is_empty():
			out.append(hd)
	return out


func _sim(h: HoleDefinition) -> BallSim:
	return BallSim.new(h, PhysicsConfig.new())


func test_neutral_plane_has_no_stands() -> void:
	var h := HoleDefinition.make_flat(Surface.Type.FAIRWAY)
	assert_eq(h.grandstands().size(), 0, "calibration plane stays obstacle-free")


func test_some_holes_have_stands_and_plans_are_deterministic() -> void:
	var holes := _holes_with_stands()
	assert_gt(float(holes.size()), 5.0, "most courses get grandstands")
	for hd in holes:
		var a: Array = Grandstands.plan(hd)
		var b: Array = Grandstands.plan(hd)
		assert_eq(a.size(), b.size(), "%s same count" % hd.id)
		for i in a.size():
			assert_eq((a[i]["xf"] as Transform2D), (b[i]["xf"] as Transform2D), "%s stand %d same spot" % [hd.id, i])


func test_ball_driven_into_back_of_stand_bounces_off() -> void:
	var holes := _holes_with_stands()
	var tested := 0
	for hd in holes.slice(0, 6):
		var st: Dictionary = hd.grandstands()[0]
		var xf: Transform2D = st["xf"]
		var start2 := xf * Vector2(0.0, Grandstands.BACK_W + 6.0)
		if not hd.in_bounds(start2.x, start2.y) or hd.surface_at(start2.x, start2.y) == Surface.Type.WATER:
			continue
		var start := Vector3(start2.x, hd.terrain_height(start2.x, start2.y) + 0.6, start2.y)
		var dir := -xf.y.normalized()
		var s := _sim(hd)
		s.launch(start, Vector3(dir.x, 2.0, dir.y) * 1.0 + Vector3(dir.x, 0, dir.y) * 18.0, true)
		s.run_until_done()
		var kinds: Array = s.collisions.map(func(c): return String(c["type"]))
		assert_true(kinds.has("stand_side") or kinds.has("stand_top"), "%s ball hit the stand (%s)" % [hd.id, kinds])
		assert_false(Grandstands.covers(hd.grandstands(), s.pos.x, s.pos.z, -0.05), "%s ball not left inside the stand" % hd.id)
		assert_true(s.is_done(), "%s ball stopped" % hd.id)
		tested += 1
	assert_gt(float(tested), 0.0, "at least one stand tested")


func test_ball_dropped_on_seats_runs_off_and_rests_outside() -> void:
	var holes := _holes_with_stands()
	assert_gt(float(holes.size()), 0.0)
	for hd in holes.slice(0, 6):
		for st in hd.grandstands():
			var xf: Transform2D = st["xf"]
			for w in [-2.0, 0.5, 2.4]:
				var p2 := xf * Vector2(1.0, w)
				var s := _sim(hd)
				s.launch(Vector3(p2.x, float(st["back_top"]) + 6.0, p2.y), Vector3(0, -2.0, 0), true)
				s.run_until_done()
				var kinds: Array = s.collisions.map(func(c): return String(c["type"]))
				assert_true(kinds.has("stand_top"), "%s landed on the seats" % hd.id)
				assert_true(s.is_done() and not s.timed_out, "%s ball settles (no timeout)" % hd.id)
				assert_false(Grandstands.covers(hd.grandstands(), s.pos.x, s.pos.z, -0.05), "%s w=%s ball came down off the stand" % [hd.id, w])


func test_relief_never_inside_a_stand() -> void:
	for hd in _holes_with_stands().slice(0, 4):
		var st: Dictionary = hd.grandstands()[0]
		var c: Vector2 = (st["xf"] as Transform2D).origin
		assert_false(hd.is_safe_spot(c.x, c.y, 1.0), "%s stand centre is not a relief spot" % hd.id)

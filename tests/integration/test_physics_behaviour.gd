extends TestCase
## Non-neutral physics behaviour: wind, lies, slopes, trees, stopping, finiteness.


func _caps_on(sim: BallSim, caps: int, bearing: float) -> BallSim:
	var cfg := sim.cfg
	var speed := ShotCalculator.solve_caps_speed(Units.caps_to_carry_m(caps), cfg)
	var start := Vector3(0, sim.hole.terrain_height(0, 0) + cfg.ball_radius, 0)
	sim.launch(start, ShotCalculator.launch_velocity(Units.bearing_to_dir(bearing), speed, cfg.launch_angle_deg), true)
	sim.run_until_done()
	return sim


func test_wind_changes_carry_and_deflects() -> void:
	var calm := _caps_on(TestHelpers.flat_sim(Surface.Type.FAIRWAY), 150, 0.0)
	var tail := TestHelpers.flat_sim(Surface.Type.FAIRWAY)
	tail.wind = Vector3(0, 0, 5.0)
	_caps_on(tail, 150, 0.0)
	var head := TestHelpers.flat_sim(Surface.Type.FAIRWAY)
	head.wind = Vector3(0, 0, -5.0)
	_caps_on(head, 150, 0.0)
	var cross := TestHelpers.flat_sim(Surface.Type.FAIRWAY)
	cross.wind = Vector3(5.0, 0, 0)
	_caps_on(cross, 150, 0.0)
	note("calm %.2f / tail %.2f / head %.2f m; cross deflection %.2f m" % [calm.carry_m, tail.carry_m, head.carry_m, cross.first_contact_pos.x])
	assert_gt(tail.carry_m, calm.carry_m + 2.0, "tailwind longer")
	assert_lt(head.carry_m, calm.carry_m - 2.0, "headwind shorter")
	assert_gt(cross.first_contact_pos.x, 1.0, "crosswind pushes downwind (+X)")


func test_surfaces_change_ground_behaviour() -> void:
	var cfg := PhysicsConfig.new()
	var v := ShotCalculator.solve_goals_speed(Units.goals_to_roll_m(30), cfg)
	var dist := {}
	for t in [Surface.Type.GREEN, Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.BUNKER]:
		var sim := TestHelpers.flat_sim(t)
		sim.launch(Vector3(0, cfg.ball_radius, 0), Vector3(0, 0, v), false)
		sim.run_until_done()
		dist[t] = sim.pos.z
	note("30-goal roll: green %.2f, fairway %.2f, rough %.2f, bunker %.2f m" % [dist[Surface.Type.GREEN], dist[Surface.Type.FAIRWAY], dist[Surface.Type.ROUGH], dist[Surface.Type.BUNKER]])
	assert_gt(dist[Surface.Type.GREEN], dist[Surface.Type.FAIRWAY])
	assert_gt(dist[Surface.Type.FAIRWAY], dist[Surface.Type.ROUGH])
	assert_gt(dist[Surface.Type.ROUGH], dist[Surface.Type.BUNKER])
	var landings := {}
	for t2 in [Surface.Type.GREEN, Surface.Type.FAIRWAY, Surface.Type.ROUGH, Surface.Type.BUNKER]:
		var s2 := _caps_on(TestHelpers.flat_sim(t2), 120, 0.0)
		landings[t2] = s2.pos.z - s2.carry_m
	note("120-cap rollout after landing: green %.2f, fairway %.2f, rough %.2f, bunker %.2f m" % [landings[Surface.Type.GREEN], landings[Surface.Type.FAIRWAY], landings[Surface.Type.ROUGH], landings[Surface.Type.BUNKER]])
	assert_lt(landings[Surface.Type.BUNKER], landings[Surface.Type.FAIRWAY], "bunker reduces rollout")
	assert_lt(landings[Surface.Type.ROUGH], landings[Surface.Type.FAIRWAY], "rough reduces rollout")


func test_uphill_vs_downhill() -> void:
	var cfg := PhysicsConfig.new()
	var h := HoleDefinition.new()
	h.flat_surface = -1
	h.has_cup = false
	h.plane_b = 0.03  # rises toward +Z
	h.base_height = 0.0
	h.default_surface = Surface.Type.FAIRWAY
	var v := ShotCalculator.solve_goals_speed(Units.goals_to_roll_m(40), cfg)
	var up := BallSim.new(h, cfg)
	up.launch(Vector3(0, h.terrain_height(0, 0) + cfg.ball_radius, 0), Vector3(0, 0, v), false)
	up.run_until_done()
	var down := BallSim.new(h, cfg)
	down.launch(Vector3(0, h.terrain_height(0, 0) + cfg.ball_radius, 0), Vector3(0, 0, -v), false)
	down.run_until_done()
	var flat := Units.goals_to_roll_m(40)
	note("40 goals: uphill %.2f m, flat %.2f m, downhill %.2f m" % [up.pos.z, flat, -down.pos.z])
	assert_lt(up.pos.z, flat * 0.95, "uphill shorter")
	assert_gt(-down.pos.z, flat * 1.05, "downhill longer")
	assert_eq(up.phase, BallSim.Phase.REST)
	assert_eq(down.phase, BallSim.Phase.REST)


func test_tree_trunk_blocks_ground_shot() -> void:
	var cfg := PhysicsConfig.new()
	var h := HoleDefinition.make_flat(Surface.Type.FAIRWAY)
	h.trees.append({"x": 0.0, "z": 10.0, "base_y": 0.0, "trunk_r": 0.3, "trunk_h": 7.0, "canopy_y": 9.0,
		"canopy_r": 3.0, "canopy_ry": 3.1, "height": 14.0, "kind": 0})
	h._tree_grid[Vector2i(0, 0)] = [0]
	var sim := BallSim.new(h, cfg)
	sim.launch(Vector3(0, cfg.ball_radius, 0), Vector3(0, 0, ShotCalculator.solve_goals_speed(30.0, cfg)), false)
	sim.run_until_done()
	assert_gt(sim.collisions.size(), 0, "hit trunk")
	assert_lt(sim.pos.z, 10.0, "did not pass through trunk")


func test_tree_canopy_shortens_flight() -> void:
	var cfg := PhysicsConfig.new()
	var h := HoleDefinition.make_flat(Surface.Type.FAIRWAY)
	h.trees.append({"x": 0.0, "z": 12.0, "base_y": 0.0, "trunk_r": 0.3, "trunk_h": 6.0, "canopy_y": 9.0,
		"canopy_r": 4.0, "canopy_ry": 4.2, "height": 14.0, "kind": 0})
	h._tree_grid[Vector2i(0, 0)] = [0]
	var sim := BallSim.new(h, cfg)
	var speed := ShotCalculator.solve_caps_speed(Units.caps_to_carry_m(150), cfg)
	sim.launch(Vector3(0, cfg.ball_radius, 0), ShotCalculator.launch_velocity(Vector3(0, 0, 1), speed, cfg.launch_angle_deg), true)
	sim.run_until_done()
	note("carry through canopy %.1f m (neutral 137.2 m), collisions %d" % [sim.carry_m, sim.collisions.size()])
	assert_gt(sim.collisions.size(), 0)
	assert_lt(sim.carry_m, 130.0)


func test_ball_always_stops_and_stays_finite_on_real_holes() -> void:
	var cfg := PhysicsConfig.new()
	var max_t := 0.0
	for hd in TestHelpers.load_holes():
		var hole: HoleDefinition = hd
		for bearing in [0.0, 30.0, 75.0, 150.0, 210.0, 300.0, 345.0]:
			for caps in [5, 60, 180, 400]:
				var sim := BallSim.new(hole, cfg)
				sim.wind = Vector3(3, 0, -2)
				var st := hole.tee_position(cfg.ball_radius)
				var spd := ShotCalculator.solve_caps_speed(Units.caps_to_carry_m(caps), cfg)
				sim.launch(st, ShotCalculator.launch_velocity(Units.bearing_to_dir(bearing), spd, cfg.launch_angle_deg), true)
				sim.run_until_done()
				assert_false(sim.is_moving(), "%s stops" % hole.id)
				assert_true(sim.phase != BallSim.Phase.ERROR, "%s no sim error" % hole.id)
				assert_false(sim.timed_out, "%s no timeout b=%s caps=%s" % [hole.id, bearing, caps])
				assert_true(is_finite(sim.pos.x) and is_finite(sim.pos.y) and is_finite(sim.pos.z))
				if sim.phase == BallSim.Phase.REST:
					assert_gt(sim.pos.y, hole.terrain_height(sim.pos.x, sim.pos.z) - 0.01, "not under terrain")
				max_t = maxf(max_t, sim.time)
	note("max time in motion %.2f s" % max_t)


func test_shallow_slope_micro_roll_terminates() -> void:
	var cfg := PhysicsConfig.new()
	var h := HoleDefinition.new()
	h.flat_surface = -1
	h.has_cup = false
	h.plane_a = 0.004
	var sim := BallSim.new(h, cfg)
	sim.launch(Vector3(0, h.terrain_height(0, 0) + cfg.ball_radius, 0), Vector3(0.05, 0, 0.02), false)
	sim.run_until_done()
	assert_eq(sim.phase, BallSim.Phase.REST)
	assert_lt(sim.time, 5.0)


func test_extreme_speed_is_finite() -> void:
	var cfg := PhysicsConfig.new()
	for hd in TestHelpers.load_holes():
		var sim := BallSim.new(hd, cfg)
		sim.launch((hd as HoleDefinition).tee_position(cfg.ball_radius), Vector3(400, 300, 900), true)
		sim.run_until_done()
		assert_false(sim.is_moving())
		assert_true(is_finite(sim.pos.length()))

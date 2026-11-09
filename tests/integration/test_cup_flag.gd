extends TestCase
## The cup is a real pit (BallSim): rim edge, wall, floor and flagstick all come from the physics.
## Nothing here uses a capture-speed rule: every outcome is the simulated ball's own path.

const CUP_Z := 10.0


func _sim(diameter_in: float = 12.0) -> BallSim:
	var h := HoleDefinition.make_flat(Surface.Type.GREEN)
	h.has_cup = true
	h.pin = Vector2(0.0, CUP_Z)
	var cfg := PhysicsConfig.new()
	cfg.set_cup_diameter_in(diameter_in)
	return BallSim.new(h, cfg)


## Roll a ball along +Z toward the cup, laterally offset by `off` metres, starting 0.1 m before the near rim.
func _roll(sim: BallSim, speed: float, off: float = 0.0, secs: float = 8.0) -> BallSim:
	var z0 := CUP_Z - sim.cfg.cup_radius - 0.1
	sim.launch(Vector3(off, sim.cfg.ball_radius, z0), Vector3(0, 0, speed), false)
	sim.run_until_done(secs)
	return sim


func _has(sim: BallSim, kind: String) -> bool:
	for c in sim.collisions:
		if c["type"] == kind:
			return true
	return false


func _holed(sim: BallSim) -> bool:
	return sim.phase == BallSim.Phase.HOLED


## A holed ball really is in the pit: inside the radius, centre below ground, resting on the floor.
func _assert_in_pit(sim: BallSim, msg: String) -> void:
	var cup := sim.hole.cup_position()
	assert_true(_holed(sim), msg + " (holed)")
	assert_lt(Units.horizontal_distance(sim.pos, cup), sim.cfg.cup_radius - sim.cfg.ball_radius + 1e-3, msg + " (inside the wall)")
	assert_lt(sim.pos.y, cup.y, msg + " (below ground level)")
	assert_near(sim.pos.y, cup.y - sim.cfg.cup_depth() + sim.cfg.ball_radius, 1e-3, msg + " (on the floor)")


func test_slow_centre_putt_drops_and_settles() -> void:
	var sim := _roll(_sim(), 0.9)
	_assert_in_pit(sim, "slow centre putt")
	assert_eq(sim.end_reason, "cup")
	assert_true(_has(sim, "cup_floor"), "fell to the floor")


func test_regulation_cup_slow_putt_drops() -> void:
	var sim := _roll(_sim(4.25), 0.8, 0.0, 10.0)
	_assert_in_pit(sim, "regulation cup, 0.8 m/s centre putt")


func test_fast_ball_across_small_cup_hits_far_rim_or_carries_over() -> void:
	# 12 in cup, no pole in the way (offset past pin + ball radius): too fast to drop the full 2r before the far rim.
	var sim := _sim()
	var off := 0.06
	_roll(sim, 6.0, off, 4.0)
	assert_false(_holed(sim), "6 m/s across a 1 ft cup does not stay in")
	assert_true(_has(sim, "rim") or _has(sim, "cup_wall"), "it met the far rim / wall")
	assert_gt(Units.horizontal_distance(sim.pos, sim.hole.cup_position()), sim.cfg.cup_radius, "it ended outside the hole")
	# A much faster ball barely dips: it skims across.
	var skim := _roll(_sim(), 12.0, off, 4.0)
	assert_false(_holed(skim), "12 m/s skims over")
	assert_gt(skim.pos.z, CUP_Z + skim.cfg.cup_radius)


func test_speed_threshold_is_emergent() -> void:
	# Somewhere between a gentle putt and a firm one the result flips from in to out; nobody coded the number.
	var speeds := [0.6, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0]
	var first_out := -1.0
	for v in speeds:
		var s := _roll(_sim(), float(v), 0.06, 6.0)
		if not _holed(s) and first_out < 0.0:
			first_out = float(v)
	assert_gt(first_out, 0.9, "gentle putts drop")
	assert_lt(first_out, 6.1, "firm ones do not")


func test_edge_graze_deflects() -> void:
	var sim0 := _sim()
	var R := sim0.cfg.cup_radius
	var off := R - sim0.cfg.ball_radius * 0.5  # centre line passes over the lip only
	var probe := _sim()
	probe.launch(Vector3(off, probe.cfg.ball_radius, CUP_Z - R - 0.3), Vector3(0, 0, 2.0), false)
	var max_dev := 0.0
	while probe.is_moving() and probe.pos.z < CUP_Z + R + 0.2:
		probe.step()
		max_dev = maxf(max_dev, absf(probe.vel.x))
	assert_gt(max_dev, 0.01, "the rim pulls the ball sideways")
	var fast := _roll(_sim(), 2.0, off, 4.0)
	assert_false(_holed(fast), "a 2 m/s graze of the lip stays out")
	var slow := _roll(_sim(), 0.65, R - sim0.cfg.ball_radius * 1.2, 8.0)
	assert_true(_holed(slow), "a dying putt over the edge falls in")


func test_cup_flag_deterministic() -> void:
	for args in [[3.0, 0.07], [1.2, 0.0], [0.6, 0.12]]:
		var a := _roll(_sim(), float(args[0]), float(args[1]), 6.0)
		var b := _roll(_sim(), float(args[0]), float(args[1]), 6.0)
		assert_eq(a.pos, b.pos, "same inputs, same end position")
		assert_eq(a.phase, b.phase)
		assert_eq(a.collisions.size(), b.collisions.size())
		assert_eq(a.time, b.time)


func test_moderate_pin_strike_stays_in() -> void:
	# 5 m/s into the pole: it rebounds at 35% of its normal speed, falls short of the near rim and drops.
	var sim := _roll(_sim(), 5.0, 0.0, 6.0)
	assert_true(_has(sim, "pin"), "pin strike recorded")
	_assert_in_pit(sim, "moderate pin strike")


func test_fast_ball_deflected_by_pin() -> void:
	var sim := _sim()
	_roll(sim, 12.0, 0.0, 3.0)
	assert_true(_has(sim, "pin"), "pin strike recorded")
	assert_false(_holed(sim), "hard head-on strike bounces back out")
	assert_lt(sim.pos.z, CUP_Z, "head-on strike sends the ball back")


func test_slow_ball_not_blocked_by_pin() -> void:
	var sim := _roll(_sim(), 0.9, 0.0)
	assert_false(_has(sim, "pin"), "slow ball ignores the pole")
	_assert_in_pit(sim, "slow dead-centre putt")


func test_pin_hit_in_air_can_drop() -> void:
	var sim := _sim()
	# Descending ball hits the pole about a metre up, falling into the cup.
	sim.launch(Vector3(0.005, 0.5, CUP_Z - 0.3), Vector3(0.0, -1.0, 2.5), true)
	sim.run_until_done(5.0)
	assert_true(_has(sim, "pin"), "pole hit in flight")
	_assert_in_pit(sim, "ball slowed by the pin")


func test_large_cup_ignores_pole() -> void:
	var big := _sim(72.0)
	assert_false(big.cfg.pin_active(), "6 ft cup has no active pole")
	_roll(big, 2.5, 0.0, 6.0)
	assert_false(_has(big, "pin"), "no pin collision on a large cup")
	assert_true(_sim().cfg.pin_active(), "a 12 in cup has an active pole")


func test_steep_drop_into_6ft_hole_stays_in() -> void:
	var sim := _sim(72.0)
	sim.launch(Vector3(0.2, 3.0, CUP_Z - 0.3), Vector3(0, -6.0, 3.0), true)
	sim.run_until_done(8.0)
	_assert_in_pit(sim, "steep drop into a 6 ft hole")
	assert_true(_has(sim, "cup_floor"), "it bounced on the floor")


func test_rolling_ball_ends_holed_in_6ft_hole() -> void:
	for v in [0.8, 2.0, 5.0, 9.0, 15.0]:
		var sim := _roll(_sim(72.0), float(v), 0.3, 10.0)
		_assert_in_pit(sim, "rolling %.1f m/s into a 6 ft hole" % float(v))


func test_flat_shots_at_6ft_hole_are_physical() -> void:
	# 12 m/s, flat, just above the turf at the near rim: it has 0.15 s to cross 1.8 m and sinks ~11 cm,
	# well below the far rim, so it hits the wall and stays in.
	var mid := _sim(72.0)
	var R := mid.cfg.cup_radius
	var r := mid.cfg.ball_radius
	mid.launch(Vector3(0.0, r + 0.02, CUP_Z - R - 0.02), Vector3(0, -0.5, 12.0), true)
	mid.run_until_done(8.0)
	assert_true(_has(mid, "cup_wall"), "12 m/s flat ball hits the far wall")
	_assert_in_pit(mid, "12 m/s flat ball into a 6 ft hole")
	# 25 m/s and rising slightly: it is still above the rim when it reaches the far side, so it skims across.
	var fast := _sim(72.0)
	fast.launch(Vector3(0.0, r + 0.03, CUP_Z - R - 0.02), Vector3(0, 0.3, 25.0), true)
	fast.run_until_done(8.0)
	assert_false(_holed(fast), "flat 25 m/s ball skims across")
	assert_gt(fast.pos.z, CUP_Z + R, "and carries on past the hole")


func test_landing_on_regulation_cup() -> void:
	# Falling almost vertically into a 4.25 in cup: in. Flat and fast onto the near lip: out.
	var steep := _sim(4.25)
	steep.launch(Vector3(0.0, 1.0, CUP_Z - 0.05), Vector3(0, -2.0, 0.3), true)
	steep.run_until_done(6.0)
	_assert_in_pit(steep, "steep drop into a regulation cup")
	var flat := _sim(4.25)
	flat.launch(Vector3(0.0, flat.cfg.ball_radius + 0.03, CUP_Z - 0.2), Vector3(0, -0.4, 10.0), true)
	flat.run_until_done(6.0)
	assert_false(_holed(flat), "10 m/s flat ball does not stay in a regulation cup")


func test_no_cup_hole_unaffected() -> void:
	var h := HoleDefinition.make_flat(Surface.Type.FAIRWAY)
	var sim := BallSim.new(h, PhysicsConfig.new())
	sim.launch(Vector3(0, sim.cfg.ball_radius, 0), Vector3(0, 0, 3.0), false)
	sim.run_until_done()
	assert_eq(sim.phase, BallSim.Phase.REST)


func test_config_roundtrip_cup_params() -> void:
	var c := PhysicsConfig.new()
	c.pin_soft_speed = 1.7
	c.cup_wall_restitution = 0.3
	c.cup_depth_max = 0.2
	c.cup_depth_min = 0.12
	var d := c.copy()
	assert_near(d.pin_soft_speed, 1.7, 1e-9)
	assert_near(d.cup_wall_restitution, 0.3, 1e-9)
	assert_near(d.cup_depth_min, 0.12, 1e-9)
	# settings saved by older builds (heuristic cup keys) still load
	var e := PhysicsConfig.new()
	e.apply_dict({"cup_capture_speed": 2.0, "cup_sink_fraction": 1.5, "cup_lip_loss": 0.1, "cup_rim_lip": 0.5,
		"cup_landing_capture_speed": 7.0, "cup_radius": 0.1524})
	assert_near(e.cup_radius, 0.1524, 1e-9)
	assert_near(PhysicsConfig.new().cup_depth(), 0.10, 1e-9, "6 ft hole: regulation 4 in deep")
	e.set_cup_diameter_in(4.25)
	assert_near(e.cup_depth(), 0.10, 1e-9, "small cup: minimum depth")

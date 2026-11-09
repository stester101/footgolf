extends TestCase
## Flagstick and cup-rim physics: pin deflection, gentle slow balls, lip-out vs drop, determinism.

const CUP_Z := 10.0


func _sim(cup_radius: float = -1.0) -> BallSim:
	var h := HoleDefinition.make_flat(Surface.Type.GREEN)
	h.has_cup = true
	h.pin = Vector2(0.0, CUP_Z)
	var cfg := PhysicsConfig.new()
	cfg.set_cup_diameter_in(12.0)  # these tests describe a 1 ft cup (the game default is now 6 ft)
	if cup_radius > 0.0:
		cfg.cup_radius = cup_radius
	return BallSim.new(h, cfg)


## Roll a ball along +Z toward the cup, laterally offset by `off` metres.
func _roll(sim: BallSim, speed: float, off: float = 0.0, secs: float = 8.0) -> BallSim:
	sim.launch(Vector3(off, sim.cfg.ball_radius, CUP_Z - 0.3), Vector3(0, 0, speed), false)
	sim.run_until_done(secs)
	return sim


func _has(sim: BallSim, kind: String) -> bool:
	for c in sim.collisions:
		if c["type"] == kind:
			return true
	return false


func test_fast_ball_deflected_by_pin() -> void:
	var sim := _sim()
	_roll(sim, 12.0, 0.0, 3.0)  # far above the physical capture speed of a 1 ft cup (~4.6 m/s)
	assert_true(_has(sim, "pin"), "pin strike recorded")
	assert_false(sim.phase == BallSim.Phase.HOLED, "fast ball does not drop")
	assert_lt(sim.vel.z, 0.0 + 1e-9, "head-on strike bounces the ball back")


func test_moderate_pin_strike_drops_hard_one_bounces() -> void:
	var cfg0 := _sim().cfg
	var cap := 2.0 * cfg0.cup_radius / sqrt(2.0 * cfg0.cup_sink_fraction * cfg0.ball_radius / 9.81)  # centre-line capture speed
	var mid := _roll(_sim(), cap * 0.8, 0.0)
	assert_true(_has(mid, "pin"), "moderate ball touches the pole")
	assert_eq(mid.phase, BallSim.Phase.HOLED, "moderate pin strike loses pace and drops")
	var hard := _roll(_sim(), cap * 1.6, 0.0, 3.0)
	assert_true(_has(hard, "pin"))
	assert_false(hard.phase == BallSim.Phase.HOLED, "hard pin strike bounces out")


func test_slow_ball_not_blocked_by_pin() -> void:
	var sim := _sim()
	_roll(sim, 0.9, 0.0)
	assert_false(_has(sim, "pin"), "slow ball ignores the pole")
	assert_eq(sim.phase, BallSim.Phase.HOLED, "slow dead-centre putt drops")


func test_rim_lip_out_vs_drop_speed() -> void:
	var sim0 := _sim()
	var off := sim0.cfg.cup_radius * 0.9
	# physical capture speed on this line: chord / sqrt(2 k r / g)
	var chord := 2.0 * sqrt(sim0.cfg.cup_radius * sim0.cfg.cup_radius - off * off)
	var cap := chord / sqrt(2.0 * sim0.cfg.cup_sink_fraction * sim0.cfg.ball_radius / 9.81)
	var slow := _roll(_sim(), cap * 0.5, off)
	assert_eq(slow.phase, BallSim.Phase.HOLED, "slow edge putt drops")
	var fast := _roll(_sim(), cap * 1.5, off, 2.5)
	assert_false(fast.phase == BallSim.Phase.HOLED, "fast edge putt lips out")
	assert_true(_has(fast, "lip"), "lip recorded")
	var lip_vx := 0.0
	var probe := _sim()
	probe.launch(Vector3(off, probe.cfg.ball_radius, CUP_Z - 0.3), Vector3(0, 0, cap * 1.5), false)
	while probe.is_moving() and not _has(probe, "lip"):
		probe.step()
	lip_vx = probe.vel.x
	assert_lt(lip_vx, 0.0, "ball offset +X curls toward the cup centre (-X)")
	var skip := _roll(_sim(), cap * 3.0, off, 2.0)
	assert_true(_has(skip, "skip"), "very fast edge putt skips over")
	assert_false(skip.phase == BallSim.Phase.HOLED, "skipped ball does not drop")
	# Same speed drops when dead centre but lips when at the edge (rim lowers the threshold).
	var s_mid := cap * 0.9
	var centre := _roll(_sim(), s_mid, 0.06)
	var edge := _roll(_sim(), s_mid, sim0.cfg.cup_radius * 0.95, 2.5)
	assert_eq(centre.phase, BallSim.Phase.HOLED, "centre drops at %.2f m/s" % s_mid)
	assert_false(edge.phase == BallSim.Phase.HOLED, "edge lips at %.2f m/s" % s_mid)


func test_pin_hit_in_air_can_drop() -> void:
	var sim := _sim()
	# Descending ball hits the pole about a metre up, falling into the cup.
	sim.launch(Vector3(0.005, 0.5, CUP_Z - 0.3), Vector3(0.0, -1.0, 2.5), true)
	sim.run_until_done(5.0)
	assert_true(_has(sim, "pin"), "pole hit in flight")
	assert_eq(sim.phase, BallSim.Phase.HOLED, "ball slowed by the pin drops")


func test_large_cup_ignores_pole() -> void:
	var big := _sim(Units.feet_to_m(6.0) * 0.5)
	assert_false(big.cfg.pin_active(), "6 ft cup has no active pole")
	_roll(big, 2.5, 0.0, 4.0)
	assert_false(_has(big, "pin"), "no pin collision on a large cup")
	var mid := _sim()
	assert_true(mid.cfg.pin_active(), "default 12 in cup has an active pole")


func test_cup_flag_deterministic() -> void:
	var a := _roll(_sim(), 3.0, 0.07, 6.0)
	var b := _roll(_sim(), 3.0, 0.07, 6.0)
	assert_eq(a.pos, b.pos, "same inputs, same end position")
	assert_eq(a.phase, b.phase)
	assert_eq(a.collisions.size(), b.collisions.size())
	assert_eq(a.time, b.time)


func test_config_roundtrip_pin_params() -> void:
	var c := PhysicsConfig.new()
	c.pin_soft_speed = 1.7
	c.cup_rim_lip = 0.3
	var d := c.copy()
	assert_near(d.pin_soft_speed, 1.7, 1e-9)
	assert_near(d.cup_rim_lip, 0.3, 1e-9)


func test_flat_fast_landing_skips_steep_landing_drops() -> void:
	# Battered in flat and fast: lands just inside the near rim and clears the hole (real physics).
	var fast := _sim()
	var r := fast.cfg.cup_radius
	fast.launch(Vector3(0.0, fast.cfg.ball_radius + 0.05, CUP_Z - r + 0.02), Vector3(0, -0.5, 12.0), true)
	fast.run_until_done(3.0)
	assert_false(fast.phase == BallSim.Phase.HOLED, "flat 12 m/s landing does not drop")
	# Dropping in steeply over the cup: always stays in.
	var steep := _sim()
	steep.launch(Vector3(0.0, steep.cfg.ball_radius + 1.0, CUP_Z), Vector3(0, -3.0, 0.5), true)
	steep.run_until_done(3.0)
	assert_eq(steep.phase, BallSim.Phase.HOLED, "steep landing in the cup drops")

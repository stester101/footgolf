extends TestCase
## Neutral baseline calibration through the real gameplay integrator (BallSim).


func _caps_tol_m(target_m: float) -> float:
	return maxf(Units.yards_to_m(0.25), target_m * 0.005)


func _goals_tol_m(target_m: float) -> float:
	return maxf(Units.feet_to_m(0.10), target_m * 0.01)


## Launch a Caps shot in gameplay fashion (via the solver) on a flat neutral plane and
## measure first contact carry with a full BallSim (not the solver's measurement helper).
func _gameplay_caps_carry(caps: int, cfg: PhysicsConfig) -> Dictionary:
	var flat := HoleDefinition.make_flat(Surface.Type.FAIRWAY)
	var target := Units.caps_to_carry_m(caps)
	var speed := ShotCalculator.solve_caps_speed(target, cfg)
	var sim := BallSim.new(flat, cfg)
	var start := Vector3(10.0, cfg.ball_radius, -20.0)
	var aim := Units.bearing_to_dir(37.0)
	sim.launch(start, ShotCalculator.launch_velocity(aim, speed, cfg.launch_angle_deg), true)
	sim.run_until_done()
	return {"target": target, "carry": sim.carry_m, "total": Units.horizontal_distance(start, sim.pos),
		"speed": speed, "phase": sim.phase, "fc": sim.first_contact_pos}


func test_caps_neutral_first_contact_carry() -> void:
	var cfg := PhysicsConfig.new()
	for caps in [1, 10, 50, 150, 200, 400]:
		var r := _gameplay_caps_carry(caps, cfg)
		var target: float = r["target"]
		var carry: float = r["carry"]
		assert_near(carry, target, _caps_tol_m(target), "caps %d carry" % caps)
		note("caps %d: target %.3f m, carry %.4f m (err %.4f%%), speed %.2f m/s, total-after-roll %.2f m" % [
			caps, target, carry, (carry - target) / target * 100.0, float(r["speed"]), float(r["total"])])
		assert_eq(r["phase"], BallSim.Phase.REST, "caps %d comes to rest" % caps)


func test_caps_200_total_is_not_carry() -> void:
	var r := _gameplay_caps_carry(200, PhysicsConfig.new())
	assert_near(float(r["carry"]), 182.88, _caps_tol_m(182.88), "200 caps = 200 yd FIRST CONTACT")
	assert_gt(float(r["total"]), float(r["carry"]), "total after bounce/roll exceeds carry")


func test_goals_neutral_ground_distance() -> void:
	var cfg := PhysicsConfig.new()
	var flat := HoleDefinition.make_flat(Surface.Type.FAIRWAY)
	for goals in [0, 1, 5, 30, 100, 200]:
		var target := Units.goals_to_roll_m(goals)
		var speed := ShotCalculator.solve_goals_speed(target, cfg)
		var sim := BallSim.new(flat, cfg)
		var start := Vector3(-3.0, cfg.ball_radius, 4.0)
		sim.launch(start, Units.bearing_to_dir(211.0) * speed, false)
		sim.run_until_done()
		var dist := Units.horizontal_distance(start, sim.pos)
		if goals == 0:
			assert_eq(speed, 0.0, "zero goals -> zero speed")
			assert_near(dist, 0.0, 1e-9, "zero goals does not move")
			continue
		assert_near(dist, target, _goals_tol_m(target), "goals %d roll" % goals)
		assert_eq(sim.phase, BallSim.Phase.REST, "goals %d rests" % goals)
		note("goals %d: target %.4f m, roll %.4f m (err %.4f%%), v0 %.3f m/s, t %.2f s" % [
			goals, target, dist, (dist - target) / target * 100.0, speed, sim.time])


func test_repeatability() -> void:
	var cfg := PhysicsConfig.new()
	var a := _gameplay_caps_carry(150, cfg)
	ShotCalculator.clear_cache()
	var b := _gameplay_caps_carry(150, cfg)
	assert_eq(float(a["carry"]), float(b["carry"]), "identical carry")
	assert_eq(float(a["total"]), float(b["total"]), "identical total")

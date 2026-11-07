class_name ShotCalculator
extends RefCounted
## Stats -> neutral distance conversion and calibrated launch speeds.
## Launch speeds are solved numerically with the very same BallSim integrator used in
## gameplay, on a flat neutral FAIRWAY reference plane with zero wind and no obstacles.

const SOLVER_REL_TOL := 1.0e-5
const MAX_ITER := 40

static var _caps_cache: Dictionary = {}
static var _goals_cache: Dictionary = {}
static var _flat: HoleDefinition = null


static func _reference_plane() -> HoleDefinition:
	if _flat == null:
		_flat = HoleDefinition.make_flat(Surface.Type.FAIRWAY)
	return _flat


static func clear_cache() -> void:
	_caps_cache.clear()
	_goals_cache.clear()


static func launch_velocity(aim_dir: Vector3, speed: float, angle_deg: float) -> Vector3:
	var h := Vector3(aim_dir.x, 0.0, aim_dir.z)
	if h.length() < 1e-9:
		h = Vector3(0, 0, 1)
	h = h.normalized()
	var th := deg_to_rad(angle_deg)
	return h * (speed * cos(th)) + Vector3.UP * (speed * sin(th))


## Neutral first-contact carry for a given launch speed (metres).
static func measure_neutral_carry(speed: float, cfg: PhysicsConfig) -> float:
	if speed <= 0.0:
		return 0.0
	var sim := BallSim.new(_reference_plane(), cfg)
	sim.stop_at_first_contact = true
	sim.launch(Vector3(0.0, cfg.ball_radius, 0.0), launch_velocity(Vector3(0, 0, 1), speed, cfg.launch_angle_deg), true)
	sim.run_until_done(120.0)
	return sim.carry_m


## Neutral ground travel until rest for a given initial rolling speed (metres).
static func measure_neutral_roll(speed: float, cfg: PhysicsConfig) -> float:
	if speed <= 0.0:
		return 0.0
	var sim := BallSim.new(_reference_plane(), cfg)
	sim.launch(Vector3(0.0, cfg.ball_radius, 0.0), Vector3(0.0, 0.0, speed), false)
	sim.run_until_done(cfg.max_motion_time)
	return Units.horizontal_distance(sim.launch_pos, sim.pos)


static func solve_caps_speed(carry_m: float, cfg: PhysicsConfig) -> float:
	if carry_m <= 0.0:
		return 0.0
	var key := "%s#%.6f" % [cfg.signature(), carry_m]
	if _caps_cache.has(key):
		return _caps_cache[key]
	var th := deg_to_rad(cfg.launch_angle_deg)
	var guess := sqrt(carry_m * cfg.gravity / maxf(0.05, sin(2.0 * th)))
	var v := _solve(guess, carry_m, func(s: float) -> float: return measure_neutral_carry(s, cfg))
	_caps_cache[key] = v
	return v


static func solve_goals_speed(roll_m: float, cfg: PhysicsConfig) -> float:
	if roll_m <= 0.0:
		return 0.0
	var key := "%s#%.6f" % [cfg.signature(), roll_m]
	if _goals_cache.has(key):
		return _goals_cache[key]
	var f: Dictionary = cfg.surface(Surface.Type.FAIRWAY)
	var guess := sqrt(2.0 * float(f["roll_decel"]) * roll_m)
	var v := _solve(guess, roll_m, func(s: float) -> float: return measure_neutral_roll(s, cfg))
	_goals_cache[key] = v
	return v


## Log-space secant solve of measure(v) == target, with bracketing bisection fallback.
static func _solve(guess: float, target: float, measure: Callable) -> float:
	var v0 := maxf(guess, 1e-3)
	var m0: float = measure.call(v0)
	if absf(m0 - target) <= SOLVER_REL_TOL * maxf(1.0, target):
		return v0
	var v1 := v0 * (1.15 if m0 < target else 0.87)
	var m1: float = measure.call(v1)
	var lo := 0.0
	var hi := INF
	for pair in [[v0, m0], [v1, m1]]:
		if float(pair[1]) < target:
			lo = maxf(lo, float(pair[0]))
		else:
			hi = minf(hi, float(pair[0]))
	for i in MAX_ITER:
		if absf(m1 - target) <= SOLVER_REL_TOL * maxf(1.0, target):
			return v1
		var v2: float
		if m0 > 0.0 and m1 > 0.0 and absf(log(m1) - log(m0)) > 1e-12:
			var slope := (log(m1) - log(m0)) / (log(v1) - log(v0))
			v2 = exp(log(v1) + (log(target) - log(m1)) / slope)
		else:
			v2 = v1 * 1.5
		if not is_finite(v2) or v2 <= lo or (hi < INF and v2 >= hi):
			v2 = (lo + hi) * 0.5 if hi < INF else maxf(v1 * 2.0, lo * 2.0)
		var m2: float = measure.call(v2)
		if m2 < target:
			lo = maxf(lo, v2)
		else:
			hi = minf(hi, v2)
		v0 = v1
		m0 = m1
		v1 = v2
		m1 = m2
	return v1

class_name GameSession
extends RefCounted
## Authoritative single-player game logic: state machine, atomic shot commit, simulation
## stepping, hazard resolution, scoring and developer test operations. Contains no
## rendering or UI code so that it can be driven headlessly by tests. The UI is never
## authoritative for score or footballer consumption.

signal state_changed(state: int)
signal shot_started(request: ShotRequest)
signal shot_resolved(result: ShotResult)
signal hole_started(index: int)
signal hole_completed(hole_state: HoleState)
signal round_completed
signal ball_placed
signal selection_changed
signal message(text: String)

const MAX_STEPS_PER_ADVANCE := 4000

var cfg: PhysicsConfig
var repo: FootballerRepository
var pool := FootballerPool.new()
var hole_defs: Array = []
var round_state := RoundState.new()
var hole: HoleDefinition
var state: int = ShotTypes.State.BOOT
var ball_pos := Vector3.ZERO
var last_safe_pos := Vector3.ZERO
var aim_bearing_deg := 0.0
var mode: int = ShotTypes.Mode.CAPS
## Strike-point spin for Caps shots: -1 full backspin .. +1 full topspin (0.05 steps).
var spin := 0.0
var selected_id := ""
var holeout_radius_ft := ScoringService.DEFAULT_HOLEOUT_FT
var wind_custom := false
var wind_custom_speed := 0.0
var wind_custom_bearing := 0.0
## Developer lie override for the launch lie (-1 = off).
var lie_override := -1
## Developer: also force that surface for every ground contact during the shot.
var force_surface := false
var sim: BallSim
var current_request: ShotRequest
var last_request: ShotRequest
var last_result: ShotResult
var history: Array = []  # Array[ShotResult] for the whole round
var undo_stack: Array = []
var shot_counter := 0
var state_version := 0
var _plan: Dictionary = {}
var _accum := 0.0
var _hole_start_pool: Dictionary = {}


func _init(p_cfg: PhysicsConfig, p_repo: FootballerRepository) -> void:
	cfg = p_cfg
	repo = p_repo


# ------------------------------------------------------------------ round / hole flow

func start_round(defs: Array, round_seed: int = -1) -> void:
	hole_defs = defs
	pool.reset()
	round_state = RoundState.new()
	round_state.round_seed = round_seed if round_seed >= 0 else int(Time.get_unix_time_from_system()) & 0x7fffffff
	for d in defs:
		var hd: HoleDefinition = d
		var hs := HoleState.new()
		hs.hole_id = hd.id
		hs.hole_name = hd.display_name
		hs.par = hd.par
		round_state.holes.append(hs)
		round_state.hole_ids.append(hd.id)
	history.clear()
	shot_counter = 0
	last_result = null
	last_request = null
	_set_state(ShotTypes.State.ROUND_SETUP)
	start_hole(0)


func start_hole(index: int) -> void:
	if index < 0 or index >= hole_defs.size():
		return
	round_state.current_index = index
	hole = hole_defs[index]
	ball_pos = hole.tee_position(cfg.ball_radius)
	last_safe_pos = ball_pos
	aim_at_pin()
	undo_stack.clear()
	sim = null
	_hole_start_pool = pool.snapshot()
	if selected_id != "" and not pool.is_available(selected_id):
		selected_id = ""
	_set_state(ShotTypes.State.HOLE_INTRO)
	hole_started.emit(index)
	ball_placed.emit()


func begin_play() -> void:
	if state == ShotTypes.State.HOLE_INTRO:
		_set_state(ShotTypes.State.AIMING)


func current_hole_state() -> HoleState:
	return round_state.current()


func aim_at_pin() -> void:
	if hole == null:
		return
	var cup := hole.cup_position()
	aim_bearing_deg = Units.dir_to_bearing(cup - ball_pos)


func aim_dir() -> Vector3:
	return Units.bearing_to_dir(aim_bearing_deg)


func set_aim(bearing_deg: float) -> void:
	if not is_finite(bearing_deg):
		return
	aim_bearing_deg = fposmod(bearing_deg, 360.0)


func set_mode(m: int) -> void:
	if m == ShotTypes.Mode.CAPS or m == ShotTypes.Mode.GOALS:
		mode = m
		selection_changed.emit()


func set_spin(value: float) -> void:
	if not is_finite(value):
		return
	spin = ShotCalculator.quantise_spin(value)
	selection_changed.emit()


func select_footballer(id: String) -> bool:
	if not repo.has(id) or not pool.is_available(id):
		return false
	selected_id = id
	selection_changed.emit()
	return true


func clear_selection() -> void:
	selected_id = ""
	selection_changed.emit()


func current_lie() -> int:
	if lie_override >= 0:
		return lie_override
	if hole == null:
		return Surface.Type.FAIRWAY
	return hole.surface_at(ball_pos.x, ball_pos.z)


func wind_speed() -> float:
	return wind_custom_speed if wind_custom else (hole.wind_speed if hole != null else 0.0)


func wind_bearing() -> float:
	return wind_custom_bearing if wind_custom else (hole.wind_bearing if hole != null else 0.0)


## Wind velocity vector (direction the air moves TOWARD), m/s.
func wind_vector() -> Vector3:
	return Units.bearing_to_dir(wind_bearing()) * wind_speed()


func distance_to_pin_m() -> float:
	if hole == null:
		return 0.0
	return Units.horizontal_distance(ball_pos, hole.cup_position())


func is_ball_moving() -> bool:
	return state == ShotTypes.State.BALL_IN_MOTION or state == ShotTypes.State.SHOT_COMMITTED


# ------------------------------------------------------------------ shot commit

## "" when a shot may be taken, otherwise a reason. Never mutates state.
func can_take_shot() -> String:
	if state != ShotTypes.State.AIMING:
		return "Not ready to shoot"
	var hs := current_hole_state()
	if hs == null or hs.complete:
		return "Hole is complete"
	if selected_id == "":
		return "Choose a footballer"
	if not repo.has(selected_id):
		return "Footballer no longer exists"
	if not pool.is_available(selected_id):
		return "Footballer already used this match"
	if mode != ShotTypes.Mode.CAPS and mode != ShotTypes.Mode.GOALS:
		return "Choose Caps or Goals"
	return ""


## Atomic Take Shot. Validates, plans (may fail without side effects), then commits the
## footballer + stroke exactly once and starts the simulation.
func take_shot() -> bool:
	var err := can_take_shot()
	if err != "":
		message.emit(err)
		return false
	var fb := repo.get_by_id(selected_id)
	var req := ShotRequest.new()
	req.shot_id = shot_counter + 1
	req.hole_id = hole.id
	req.footballer_id = fb.id
	req.mode = mode
	req.aim_bearing_deg = aim_bearing_deg
	req.spin = spin if mode == ShotTypes.Mode.CAPS else 0.0
	req.start_pos = ball_pos
	req.launch_lie = current_lie()
	req.wind_speed_mps = wind_speed()
	req.wind_bearing_deg = wind_bearing()
	req.seed = hash("%d:%s:%d" % [round_state.round_seed, hole.id, req.shot_id]) & 0x7fffffff
	req.state_version = state_version
	req.timestamp_ms = Time.get_ticks_msec()
	var plan := _plan_shot(req, fb.caps, fb.goals)
	if plan.is_empty():
		message.emit("Shot could not be prepared; nothing was consumed")
		return false
	# ---- commit (single, synchronous; no await between validation and commit)
	undo_stack.push_back(_snapshot())
	if not pool.consume(fb.id):
		undo_stack.pop_back()
		return false
	var hs := current_hole_state()
	hs.strokes += 1
	hs.used_footballer_ids.append(fb.id)
	shot_counter += 1
	state_version += 1
	plan["footballer"] = fb.copy()
	_set_state(ShotTypes.State.SHOT_COMMITTED)
	_launch(req, plan)
	return true


func _plan_shot(req: ShotRequest, caps: int, goals: int) -> Dictionary:
	if caps < 0 or goals < 0:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = req.seed
	var lie_p := cfg.surface(req.launch_lie)
	var plan := {"caps": caps, "goals": goals, "lie_factor": 1.0}
	if req.mode == ShotTypes.Mode.CAPS:
		var base := Units.caps_to_carry_m(caps)
		var cmin: float = lie_p["caps_min"]
		var cmax: float = lie_p["caps_max"]
		var factor := 1.0 if is_equal_approx(cmin, cmax) else lerpf(cmin, cmax, rng.randf())
		if is_equal_approx(cmin, cmax):
			factor = cmin
		var target := base * factor
		var speed := ShotCalculator.solve_caps_speed(target, cfg, req.spin)
		plan["stat"] = caps
		plan["base_m"] = base
		plan["lie_factor"] = factor
		plan["target_m"] = target
		plan["speed"] = speed
		plan["velocity"] = ShotCalculator.launch_velocity(Units.bearing_to_dir(req.aim_bearing_deg), speed, cfg.launch_angle_deg)
		plan["airborne"] = true
		plan["calib_err_pct"] = 0.0 if target <= 0.0 else (ShotCalculator.measure_neutral_carry(speed, cfg, ShotCalculator.quantise_spin(req.spin)) - target) / target * 100.0
	else:
		var base2 := Units.goals_to_roll_m(goals)
		var speed2 := ShotCalculator.solve_goals_speed(base2, cfg)
		var n := hole.normal_at(req.start_pos.x, req.start_pos.z)
		var d := Units.bearing_to_dir(req.aim_bearing_deg)
		d = (d - n * d.dot(n)).normalized()
		plan["stat"] = goals
		plan["base_m"] = base2
		plan["target_m"] = base2
		plan["speed"] = speed2
		plan["velocity"] = d * speed2
		plan["airborne"] = false
		plan["calib_err_pct"] = 0.0 if base2 <= 0.0 else (ShotCalculator.measure_neutral_roll(speed2, cfg) - base2) / base2 * 100.0
	var v: Vector3 = plan["velocity"]
	if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
		return {}
	return plan


func _launch(req: ShotRequest, plan: Dictionary) -> void:
	current_request = req
	_plan = plan
	sim = BallSim.new(hole, cfg)
	sim.wind = Units.bearing_to_dir(req.wind_bearing_deg) * req.wind_speed_mps
	sim.surface_override = req.launch_lie if (force_surface and lie_override >= 0) else -1
	sim.launch(req.start_pos, plan["velocity"], plan["airborne"], ShotCalculator.quantise_spin(req.spin))
	_accum = 0.0
	_set_state(ShotTypes.State.BALL_IN_MOTION)
	shot_started.emit(req)


## Advance the simulation by real time (scaled). Resolves the shot when the ball stops.
func advance(delta: float, speed_mult: float = 1.0) -> void:
	if state != ShotTypes.State.BALL_IN_MOTION or sim == null:
		return
	_accum += maxf(0.0, delta) * maxf(0.0, speed_mult)
	var steps := mini(int(_accum / cfg.dt), MAX_STEPS_PER_ADVANCE)
	_accum -= steps * cfg.dt
	for i in steps:
		if sim.is_done():
			break
		sim.step()
	if sim.is_done():
		_resolve()


## Run the remaining simulation instantly (same deterministic result).
func skip_motion() -> void:
	if state != ShotTypes.State.BALL_IN_MOTION or sim == null:
		return
	sim.run_until_done()
	_resolve()


func ball_render_pos() -> Vector3:
	if sim != null and state == ShotTypes.State.BALL_IN_MOTION:
		return sim.pos
	return ball_pos


func _resolve() -> void:
	var req := current_request
	var fb: Footballer = _plan["footballer"]
	var r := ShotResult.new()
	r.shot_id = req.shot_id
	r.hole_id = req.hole_id
	r.footballer_id = fb.id
	r.footballer_name = fb.name
	r.nationality = fb.nationality
	r.mode = req.mode
	r.caps = int(_plan["caps"])
	r.goals = int(_plan["goals"])
	r.stat_value = int(_plan["stat"])
	r.base_distance_m = _plan["base_m"]
	r.lie_factor = _plan["lie_factor"]
	r.target_distance_m = _plan["target_m"]
	r.launch_speed_mps = _plan["speed"]
	r.launch_angle_deg = cfg.launch_angle_deg if req.mode == ShotTypes.Mode.CAPS else 0.0
	r.aim_bearing_deg = req.aim_bearing_deg
	r.spin = ShotCalculator.quantise_spin(req.spin)
	r.wind_speed_mps = req.wind_speed_mps
	r.wind_bearing_deg = req.wind_bearing_deg
	r.start_pos = req.start_pos
	r.start_lie = req.launch_lie
	r.seed = req.seed
	r.developer_replay = req.developer_replay
	r.neutral_calibration_error_pct = _plan["calib_err_pct"]
	r.had_contact = sim.first_contact
	r.first_contact_pos = sim.first_contact_pos
	r.max_height_m = sim.max_height - req.start_pos.y
	r.bounces = sim.bounces
	r.collisions = sim.collisions.duplicate()
	r.time_in_motion_s = sim.time
	r.timed_out = sim.timed_out
	r.end_reason = sim.end_reason
	if req.mode == ShotTypes.Mode.CAPS:
		r.carry_m = sim.carry_m if sim.first_contact else 0.0
	var final := sim.pos
	var penalty := 0
	if sim.phase == BallSim.Phase.HAZARD:
		_set_state(ShotTypes.State.HAZARD_RESOLUTION)
		penalty = 1
		r.hazard = sim.hazard
		r.hazard_pos = sim.hazard_pos
		var relief := HazardResolver.find_relief(hole, sim.trail, [last_safe_pos, req.start_pos], cfg.ball_radius)
		final = relief["pos"]
		r.relief_pos = final
		r.relief_method = relief["method"]
	elif sim.phase == BallSim.Phase.ERROR:
		r.sim_error = true
		final = req.start_pos
	var end_for_distance := sim.hazard_pos if r.hazard != "" else final
	r.total_m = Units.horizontal_distance(req.start_pos, end_for_distance)
	if req.mode == ShotTypes.Mode.CAPS:
		r.roll_m = Units.horizontal_distance(sim.first_contact_pos, end_for_distance) if sim.first_contact else 0.0
	else:
		r.roll_m = r.total_m
	if r.target_distance_m > 0.0:
		var measured := r.carry_m if req.mode == ShotTypes.Mode.CAPS else r.total_m
		r.actual_vs_target_pct = (measured - r.base_distance_m) / maxf(1e-6, r.base_distance_m) * 100.0
	var in_cup := sim.phase == BallSim.Phase.HOLED
	var at_rest := sim.phase == BallSim.Phase.REST
	var cup := hole.cup_position()
	var dist := Units.horizontal_distance(final, cup)
	var holed := ScoringService.is_holed(in_cup, at_rest, dist, holeout_radius_ft)
	var hs := current_hole_state()
	ScoringService.apply_shot(hs, penalty, holed)
	r.penalty = penalty
	r.holed = holed
	r.final_pos = final
	r.final_lie = Surface.Type.GREEN if in_cup else hole.surface_at(final.x, final.z)
	r.remaining_m = 0.0 if holed else dist
	r.hole_score_after = hs.score()
	ball_pos = final
	if not holed and hole.is_safe_spot(final.x, final.z, 0.0):
		last_safe_pos = final
	hs.shots.append(r)
	history.append(r)
	last_result = r
	last_request = req
	sim = null
	_set_state(ShotTypes.State.SHOT_RESULT)
	shot_resolved.emit(r)


## Player dismisses the shot summary.
func acknowledge_result() -> void:
	if state != ShotTypes.State.SHOT_RESULT:
		return
	var hs := current_hole_state()
	if selected_id != "" and not pool.is_available(selected_id):
		selected_id = ""
	if hs.complete:
		_set_state(ShotTypes.State.HOLE_COMPLETE)
		hole_completed.emit(hs)
	else:
		aim_at_pin()
		_set_state(ShotTypes.State.AIMING)
		selection_changed.emit()


func next_hole() -> void:
	if state != ShotTypes.State.HOLE_COMPLETE:
		return
	var next := round_state.current_index + 1
	while next < round_state.holes.size() and (round_state.holes[next] as HoleState).complete:
		next += 1
	if next < round_state.holes.size():
		start_hole(next)
	elif round_state.all_complete():
		_set_state(ShotTypes.State.ROUND_COMPLETE)
		round_completed.emit()
	else:
		for i in round_state.holes.size():
			if not (round_state.holes[i] as HoleState).complete:
				start_hole(i)
				return


func is_round_complete() -> bool:
	return state == ShotTypes.State.ROUND_COMPLETE


# ------------------------------------------------------------------ developer operations
# Developer actions are labelled as such and never silently alter normal rules.

func _snapshot() -> Dictionary:
	return {
		"hole_index": round_state.current_index,
		"ball_pos": ball_pos,
		"last_safe_pos": last_safe_pos,
		"hole_state": current_hole_state().copy(),
		"pool": pool.snapshot(),
		"shot_counter": shot_counter,
		"history_size": history.size(),
		"aim": aim_bearing_deg,
		"mode": mode,
		"spin": spin,
		"selected": selected_id,
	}


func can_undo() -> bool:
	return not undo_stack.is_empty() and not is_ball_moving()


## Developer Undo (NOT a mulligan): restores ball, strokes, penalties, footballer availability
## and hole completion state of the most recent shot.
func dev_undo() -> bool:
	if not can_undo():
		return false
	var s: Dictionary = undo_stack.pop_back()
	if int(s["hole_index"]) != round_state.current_index:
		return false
	round_state.holes[round_state.current_index] = (s["hole_state"] as HoleState).copy()
	pool.restore(s["pool"])
	shot_counter = int(s["shot_counter"])
	history.resize(int(s["history_size"]))
	ball_pos = s["ball_pos"]
	last_safe_pos = s["last_safe_pos"]
	aim_bearing_deg = s["aim"]
	mode = s["mode"]
	spin = s.get("spin", 0.0)
	selected_id = s["selected"]
	last_result = null
	state_version += 1
	_set_state(ShotTypes.State.AIMING)
	ball_placed.emit()
	selection_changed.emit()
	message.emit("DEV: last shot undone")
	return true


## Developer Replay: undo the last shot, then re-run it with the same footballer, recorded
## stats, mode, aim, lie, wind and seed. Net effect on authoritative score: one shot, not two.
func dev_replay() -> bool:
	if last_request == null or last_result == null or not can_undo():
		return false
	var req := last_request.copy()
	var caps := last_result.caps
	var goals := last_result.goals
	if not dev_undo():
		return false
	var fb := repo.get_by_id(req.footballer_id)
	if fb == null:
		message.emit("DEV: footballer deleted; cannot replay")
		return false
	var snapshot_fb := fb.copy()
	snapshot_fb.caps = caps
	snapshot_fb.goals = goals
	req.developer_replay = true
	req.start_pos = ball_pos
	var plan := _plan_shot(req, caps, goals)
	if plan.is_empty():
		return false
	undo_stack.push_back(_snapshot())
	pool.consume(fb.id)
	var hs := current_hole_state()
	hs.strokes += 1
	hs.used_footballer_ids.append(fb.id)
	shot_counter += 1
	state_version += 1
	plan["footballer"] = snapshot_fb
	_set_state(ShotTypes.State.SHOT_COMMITTED)
	_launch(req, plan)
	return true


func dev_place_ball(x: float, z: float) -> String:
	if is_ball_moving() or state == ShotTypes.State.HOLE_COMPLETE or state == ShotTypes.State.ROUND_COMPLETE:
		return "Cannot place ball now"
	if not (is_finite(x) and is_finite(z)):
		return "Invalid coordinates"
	if not hole.is_safe_spot(x, z, 0.0):
		return "Not a safe spot (water/OOB/tree)"
	ball_pos = Vector3(x, hole.terrain_height(x, z) + cfg.ball_radius, z)
	last_safe_pos = ball_pos
	if state == ShotTypes.State.SHOT_RESULT or state == ShotTypes.State.HOLE_INTRO:
		_set_state(ShotTypes.State.AIMING)
	aim_at_pin()
	ball_placed.emit()
	return ""


func dev_reset_ball() -> void:
	if is_ball_moving():
		return
	ball_pos = hole.tee_position(cfg.ball_radius)
	last_safe_pos = ball_pos
	aim_at_pin()
	if state == ShotTypes.State.SHOT_RESULT or state == ShotTypes.State.HOLE_INTRO:
		_set_state(ShotTypes.State.AIMING)
	ball_placed.emit()


## Restart hole: fresh hole state, ball on tee, and footballers consumed on THIS hole are
## returned to the pool (restores the pool snapshot taken when the hole started).
func dev_restart_hole() -> void:
	if is_ball_moving():
		return
	_reset_hole_state(round_state.current_index)
	pool.restore(_hole_start_pool)
	start_hole(round_state.current_index)


## Jump to any hole (developer). That hole's state is reset and its consumptions returned.
func dev_select_hole(index: int) -> void:
	if is_ball_moving() or index < 0 or index >= hole_defs.size():
		return
	var hs: HoleState = round_state.holes[index]
	for id in hs.used_footballer_ids:
		pool.used_footballer_ids.erase(id)
	pool.changed.emit()
	_reset_hole_state(index)
	start_hole(index)


func _reset_hole_state(index: int) -> void:
	var old: HoleState = round_state.holes[index]
	var hs := HoleState.new()
	hs.hole_id = old.hole_id
	hs.hole_name = old.hole_name
	hs.par = old.par
	round_state.holes[index] = hs
	var keep: Array = []
	for r in history:
		if (r as ShotResult).hole_id != old.hole_id:
			keep.append(r)
	history = keep
	undo_stack.clear()


func dev_reset_pool() -> void:
	pool.reset()
	_hole_start_pool = pool.snapshot()
	selection_changed.emit()
	message.emit("DEV: footballer pool reset")


func _set_state(s: int) -> void:
	if state == s:
		return
	state = s
	state_changed.emit(s)

class_name BallSim
extends RefCounted
## Deterministic fixed-step golf-ball simulation (custom controller, not RigidBody3D).
## The SAME code path is used by gameplay, the calibration solver and the tests.
##
## AIR : gravity + quadratic drag relative to wind (RK2 midpoint), exact interpolated
##       ground contact, tree trunk (hard cylinder) and canopy (soft damping) proxies.
## ROLL: constrained to terrain; 5/7 g slope acceleration; surface rolling resistance
##       a = roll_decel + roll_drag * v; analytic stop within a step; static friction.
## Rest: speed below rest_speed for rest_time seconds; hard timeout failsafe.

enum Phase { IDLE, AIR, ROLL, REST, HOLED, HAZARD, ERROR }

const TRAIL_EVERY := 4
const KILL_DEPTH := -200.0

var hole: HoleDefinition
var cfg: PhysicsConfig
var wind := Vector3.ZERO
var stop_at_first_contact := false
## Developer override: force this surface for every ground contact (except water/OOB). -1 = off.
var surface_override := -1
## Current spin (-1 back .. +1 top); decays on each bounce for flight shots.
var spin := 0.0

var pos := Vector3.ZERO
var vel := Vector3.ZERO
var phase: int = Phase.IDLE
var time := 0.0
var still_time := 0.0
var launch_pos := Vector3.ZERO
var first_contact := false
var first_contact_pos := Vector3.ZERO
var carry_m := 0.0
var max_height := 0.0
var bounces := 0
var collisions: Array = []
var trail := PackedVector3Array()
var hazard := ""
var hazard_pos := Vector3.ZERO
var timed_out := false
var end_reason := ""
var _steps := 0
var _in_canopy: Dictionary = {}
var _cup := Vector3.ZERO
var _cup_decided := false
var _pin_hit_air := false


func _init(p_hole: HoleDefinition, p_cfg: PhysicsConfig) -> void:
	hole = p_hole
	cfg = p_cfg
	_cup = hole.cup_position()


func launch(start: Vector3, velocity: Vector3, airborne: bool, p_spin: float = 0.0) -> void:
	spin = clampf(p_spin, -1.0, 1.0) if airborne else 0.0
	pos = start
	vel = velocity
	launch_pos = start
	time = 0.0
	still_time = 0.0
	first_contact = false
	first_contact_pos = start
	carry_m = 0.0
	max_height = start.y
	bounces = 0
	collisions = []
	trail = PackedVector3Array([start])
	hazard = ""
	timed_out = false
	end_reason = ""
	_steps = 0
	_in_canopy = {}
	_cup_decided = false
	_pin_hit_air = false
	if velocity.length() <= 0.0:
		phase = Phase.REST
		end_reason = "no_motion"
	else:
		phase = Phase.AIR if airborne else Phase.ROLL


func is_moving() -> bool:
	return phase == Phase.AIR or phase == Phase.ROLL


func is_done() -> bool:
	return not is_moving()


func run_until_done(max_time: float = -1.0) -> void:
	var limit := cfg.max_motion_time if max_time < 0.0 else max_time
	var guard := int(ceil((limit + 1.0) / cfg.dt)) + 10
	while is_moving() and guard > 0:
		step()
		guard -= 1


func step() -> void:
	if not is_moving():
		return
	if phase == Phase.AIR:
		_step_air()
	else:
		_step_roll()
	time += cfg.dt
	_steps += 1
	if _steps % TRAIL_EVERY == 0 or not is_moving():
		trail.append(pos)
	if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)
			and is_finite(vel.x) and is_finite(vel.y) and is_finite(vel.z)):
		phase = Phase.ERROR
		end_reason = "non_finite"
		pos = launch_pos
		vel = Vector3.ZERO
		return
	if is_moving() and time >= cfg.max_motion_time:
		timed_out = true
		end_reason = "timeout"
		vel = Vector3.ZERO
		if phase == Phase.AIR:
			pos.y = hole.contact_height(pos.x, pos.z) + cfg.ball_radius
		phase = Phase.REST


# ------------------------------------------------------------------ helpers

func _surface(x: float, z: float) -> int:
	var s := hole.surface_at(x, z)
	if surface_override >= 0 and s != Surface.Type.WATER and s != Surface.Type.OOB:
		return surface_override
	return s


func _air_accel(v: Vector3) -> Vector3:
	var rel := v - wind
	var spd := rel.length()
	var a := Vector3(0.0, -cfg.gravity, 0.0) - rel * (cfg.drag_k * spd)
	if spin != 0.0 and spd > 1e-6:
		var d := rel / spd
		var up_perp := Vector3.UP - d * d.y
		var l := up_perp.length()
		if l > 1e-6:
			a += up_perp / l * (-spin * cfg.spin_lift_k * spd * spd)
	return a


func _set_hazard(kind: String) -> void:
	hazard = kind
	hazard_pos = pos
	vel = Vector3.ZERO
	phase = Phase.HAZARD
	end_reason = kind.to_lower()


func _hole_out() -> void:
	pos = Vector3(_cup.x, _cup.y - 0.06, _cup.z)
	vel = Vector3.ZERO
	phase = Phase.HOLED
	end_reason = "cup"


func _record(kind: String) -> void:
	collisions.append({"type": kind, "pos": pos, "time": time})


# ------------------------------------------------------------------ AIR

func _step_air() -> void:
	var dt := cfg.dt
	var r := cfg.ball_radius
	var p0 := pos
	var v0 := vel
	var vh := v0 + _air_accel(v0) * (dt * 0.5)
	var p1 := p0 + vh * dt
	var v1 := v0 + _air_accel(vh) * dt
	if not hole.trees.is_empty():
		var res := _collide_trees(p1, v1, true)
		p1 = res[0]
		v1 = res[1]
	if hole.has_cup and not _pin_hit_air and cfg.pin_active():
		var ph := _pin_strike(p0, p1, v1)
		if not ph.is_empty():
			_pin_hit_air = true
			p1 = ph[0]
			v1 = (ph[1] as Vector3) * cfg.pin_air_loss
	var g1 := hole.contact_height(p1.x, p1.z)
	if p1.y - r <= g1:
		var g0 := hole.contact_height(p0.x, p0.z)
		var d0 := p0.y - r - g0
		var d1 := p1.y - r - g1
		var f := 1.0
		if d0 > 0.0 and d0 - d1 > 1e-12:
			f = clampf(d0 / (d0 - d1), 0.0, 1.0)
		var pc := p0.lerp(p1, f)
		pc.y = hole.contact_height(pc.x, pc.z) + r
		pos = pc
		vel = v0.lerp(v1, f)
		_on_contact()
	else:
		pos = p1
		vel = v1
		max_height = maxf(max_height, pos.y)
		if pos.y < KILL_DEPTH:
			_set_hazard("OOB")


func _on_contact() -> void:
	if not first_contact:
		first_contact = true
		first_contact_pos = pos
		carry_m = Units.horizontal_distance(launch_pos, pos)
		if stop_at_first_contact:
			phase = Phase.REST
			end_reason = "first_contact"
			return
	var surf := _surface(pos.x, pos.z)
	if surf == Surface.Type.OOB:
		_set_hazard("OOB")
		return
	if surf == Surface.Type.WATER:
		_set_hazard("WATER")
		return
	if hole.has_cup:
		var dl := Units.horizontal_distance(pos, _cup)
		if dl <= cfg.cup_radius:
			# Real physics, same rule as rolling over the cup: from where it lands, the ball must sink k*r before it
			# reaches the far rim. Time to the far rim t = s / v_h; sink = v_down * t + g t^2 / 2. A ball dropping in
			# steeply always stays in; one battered in flat and fast clears the hole and carries on.
			var rel := Vector2(pos.x - _cup.x, pos.z - _cup.z)
			var vh2 := Vector2(vel.x, vel.z)
			var vhl := vh2.length()
			var captured := true
			if vhl > 1e-4:
				var dir2 := vh2 / vhl
				var bq := dir2.dot(rel)
				var s_ahead := -bq + sqrt(maxf(bq * bq - (rel.length_squared() - cfg.cup_radius * cfg.cup_radius), 0.0))
				var t := s_ahead / vhl
				var sink := maxf(-vel.y, 0.0) * t + 0.5 * 9.81 * t * t
				captured = sink >= cfg.cup_sink_fraction * cfg.ball_radius
			if captured:
				_hole_out()
				return
			_record("rim")
	var n := hole.normal_at(pos.x, pos.z)
	var vn := vel.dot(n)
	if vn >= 0.0:
		return
	var prm := cfg.surface(surf)
	var vt := vel - n * vn
	var e: float = float(prm["restitution"]) / (1.0 + absf(vn) / cfg.bounce_soft)
	var new_vn := -vn * e
	var ret: float = float(prm["retention"]) + spin * cfg.spin_retention
	vt *= clampf(ret, -0.15, 0.95)  # negative = strong backspin draws the ball back
	spin *= 0.5
	bounces += 1
	if new_vn < cfg.min_bounce_speed:
		vel = vt
		phase = Phase.ROLL
	else:
		vel = vt + n * new_vn


# ------------------------------------------------------------------ ROLL

func _step_roll() -> void:
	var dt := cfg.dt
	var r := cfg.ball_radius
	var surf := _surface(pos.x, pos.z)
	if surf == Surface.Type.OOB:
		_set_hazard("OOB")
		return
	if surf == Surface.Type.WATER:
		_set_hazard("WATER")
		return
	var prm := cfg.surface(surf)
	var decel: float = prm["roll_decel"]
	var drag: float = prm["roll_drag"]
	var n := hole.normal_at(pos.x, pos.z)
	var gv := Vector3(0.0, -cfg.gravity, 0.0)
	var g_t := (gv - n * gv.dot(n)) * (5.0 / 7.0)
	var holds := g_t.length() <= decel * cfg.static_factor
	vel = vel - n * vel.dot(n)
	var speed := vel.length()
	# Deep grass and sand catch a very slow ball even on the steep terrain used
	# by some courses; otherwise it can creep for over a minute on a hillside.
	if (surf == Surface.Type.ROUGH or surf == Surface.Type.BUNKER) and speed < 0.15:
		vel = Vector3.ZERO
		phase = Phase.REST
		end_reason = "grip"
		return
	var p_new := pos
	if speed < 1e-6:
		if holds:
			vel = Vector3.ZERO
		else:
			var dirg := g_t.normalized()
			var acc0 := g_t - dirg * decel
			vel = acc0 * dt
			p_new = pos + vel * (0.5 * dt)
	else:
		var dir := vel / speed
		var a_roll := decel + drag * speed
		var acc := g_t - dir * a_roll
		var v_new := vel + acc * dt
		if v_new.dot(dir) <= 0.0 and holds:
			var a_eff := a_roll - g_t.dot(dir)
			var travel := 0.0
			if a_eff > 1e-9:
				travel = minf(speed * dt, speed * speed / (2.0 * a_eff))
			p_new = pos + dir * travel
			vel = Vector3.ZERO
		else:
			p_new = pos + (vel + v_new) * (0.5 * dt)
			vel = v_new
	p_new.y = hole.terrain_height(p_new.x, p_new.z) + r
	if not hole.trees.is_empty():
		var res := _collide_trees(p_new, vel, false)
		p_new = res[0]
		vel = res[1]
		p_new.y = hole.terrain_height(p_new.x, p_new.z) + r
	if hole.has_cup:
		var pinned := -1.0
		if cfg.pin_active() and vel.length() > cfg.pin_soft_speed:
			var pre := vel.length()
			var ph := _pin_strike(pos, p_new, vel)
			if not ph.is_empty():
				p_new = ph[0]
				vel = ph[1]
				p_new.y = hole.terrain_height(p_new.x, p_new.z) + r
				pinned = pre
		if _roll_cup(pos, p_new, pinned):
			return
	pos = p_new
	if vel.length() < cfg.rest_speed:
		still_time += dt
	else:
		still_time = 0.0
	if still_time >= cfg.rest_time:
		if hole.has_cup and Units.horizontal_distance(pos, _cup) <= cfg.cup_radius:
			_hole_out()  # stopped on the lip: it falls in
			return
		vel = Vector3.ZERO
		phase = Phase.REST
		end_reason = "rest"


# ------------------------------------------------------------------ cup and flagstick

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Closest approach of the horizontal segment a->b to the cup centre: [t, flat distance].
func _closest_t(a: Vector3, b: Vector3) -> Array:
	var fa := _flat(a)
	var ab := _flat(b) - fa
	var l2 := ab.length_squared()
	var t := 0.0
	if l2 > 1e-12:
		t = clampf((_flat(_cup) - fa).dot(ab) / l2, 0.0, 1.0)
	return [t, (fa + ab * t - _flat(_cup)).length()]


## Flagstick contact on the segment a->b with velocity v. Returns [contact_pos, new_vel]
## (horizontal normal component reflected with pin_restitution) or [] when the pole is missed,
## already behind the ball, or the ball is above the top of the pole.
func _pin_strike(a: Vector3, b: Vector3, v: Vector3) -> Array:
	var rr := cfg.pin_radius + cfg.ball_radius
	var c := _closest_t(a, b)
	if float(c[1]) >= rr:
		return []
	var q := a.lerp(b, float(c[0]))
	if q.y - cfg.ball_radius > _cup.y + cfg.pin_height:
		return []
	var n := _flat(q) - _flat(_cup)
	var vh := _flat(v)
	if n.length() < 1e-5:
		if vh.length() < 1e-6:
			return []
		n = -vh.normalized()
	n = n.normalized()
	var vn := vh.dot(n)
	if vn >= 0.0:
		return []
	var nv := v - n * (vn * (1.0 + cfg.pin_restitution))
	var out := _flat(_cup) + n * (rr + 0.001)
	out.y = q.y
	collisions.append({"type": "pin", "pos": out, "time": time})
	return [out, nv]


## Rolling cup entry. The drop/lip/skip decision is made once per pass from the lateral offset of the
## ball's line from the cup centre. Returns true when the ball dropped.
## `pinned` >= 0 means the ball hit the flagstick this step at that pre-impact speed: the drop test uses
## that speed (a hard strike bounces off, a moderate one loses its pace and drops).
func _roll_cup(a: Vector3, b: Vector3, pinned: float = -1.0) -> bool:
	var c := _closest_t(a, b)
	if float(c[1]) > cfg.cup_radius:
		if (_flat(b) - _flat(_cup)).length() > cfg.cup_radius * 1.25:
			_cup_decided = false
		return false
	if _cup_decided:
		return false
	_cup_decided = true
	var vh := _flat(vel)
	var speed := vh.length()
	var off := float(c[1])
	var side := 0.0
	if speed > 1e-6:
		var d := vh / speed
		var rel := _flat(_cup) - _flat(a)
		off = absf(d.x * rel.z - d.z * rel.x)
		side = signf(d.x * rel.z - d.z * rel.x)
	var rn := minf(off / cfg.cup_radius, 1.0)
	var cap := cfg.cup_capture_speed_eff()
	if pinned < 0.0 and cfg.pin_active() and speed > cfg.pin_soft_speed \
			and off < cfg.pin_radius + cfg.ball_radius:
		_cup_decided = false  # the pole is still ahead: it decides first
		return false
	var dspeed := vel.length() if pinned < 0.0 else pinned
	# Real physics: a ball rolling over a gap of chord length L is in free fall for t = L / v and sinks
	# h = g t^2 / 2. It drops in once it sinks more than a fraction of its radius (it then meets the far wall).
	# So the critical speed is v_crit = L / sqrt(2 k r / g): about 1.6 m/s straight across a regulation cup,
	# less off-centre (shorter chord), and very high for a big hole (a 6 ft cup swallows almost anything).
	var chord := 2.0 * sqrt(maxf(cfg.cup_radius * cfg.cup_radius - off * off, 0.0))
	cap = chord / sqrt(2.0 * cfg.cup_sink_fraction * cfg.ball_radius / 9.81)
	if dspeed <= cap:
		_hole_out()
		return true
	if dspeed <= cap * cfg.cup_lip_max_factor:
		var ang := deg_to_rad(cfg.cup_lip_deflect_deg) * rn * side
		vel = vel.rotated(Vector3.UP, -ang) * (1.0 - cfg.cup_lip_loss)
		_record("lip")
	else:
		_record("skip")
	return false


# ------------------------------------------------------------------ trees

func _collide_trees(p: Vector3, v: Vector3, airborne: bool) -> Array:
	var r := cfg.ball_radius
	for idx in hole.trees_near(p.x, p.z):
		var t: Dictionary = hole.trees[idx]
		var dx: float = p.x - float(t["x"])
		var dz: float = p.z - float(t["z"])
		var d2 := dx * dx + dz * dz
		var rr: float = float(t["trunk_r"]) + r
		var base_y: float = t["base_y"]
		if d2 < rr * rr and p.y < base_y + float(t["trunk_h"]) and p.y > base_y - 1.0:
			var d := sqrt(d2)
			var nrm := Vector3(1, 0, 0) if d < 1e-6 else Vector3(dx / d, 0.0, dz / d)
			var vn := v.dot(nrm)
			if vn < 0.0:
				v = v - nrm * (vn * (1.0 + cfg.trunk_restitution))
				v *= 0.8
				collisions.append({"type": "trunk", "pos": p, "time": time})
			p.x = float(t["x"]) + nrm.x * (rr + 0.001)
			p.z = float(t["z"]) + nrm.z * (rr + 0.001)
		if airborne:
			var cr: float = t["canopy_r"]
			var dy: float = (p.y - float(t["canopy_y"])) * (cr / float(t["canopy_ry"]))
			if d2 + dy * dy < cr * cr:
				v *= exp(-cfg.canopy_damping * cfg.dt)
				if not _in_canopy.has(idx):
					_in_canopy[idx] = true
					collisions.append({"type": "canopy", "pos": p, "time": time})
			elif _in_canopy.has(idx):
				_in_canopy.erase(idx)
	return [p, v]

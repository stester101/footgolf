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
## CUP: a real pit under the green (radius R, vertical wall, flat floor cfg.cup_depth() below the rim). The rim is
##       a circular edge: a rolling ball follows its curved support and leaves the ground once the support falls
##       away faster than gravity can follow; in the air it meets the rim edge (sphere vs circle), the wall
##       (vertical cylinder of radius R - r for the centre) and the floor like any other surface. HOLED = the ball
##       comes to rest inside the pit. Near the cup each step is split into sub-steps (~r/4 of travel each).

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
var _cup_r := 0.0
var _cup_floor := 0.0
var _pin_hit_air := false
## The ball left rolling contact at the rim (it is not a flight shot coming down).
var _lip_air := false


func _init(p_hole: HoleDefinition, p_cfg: PhysicsConfig) -> void:
	hole = p_hole
	cfg = p_cfg
	_setup_cup()


func _setup_cup() -> void:
	_cup = hole.cup_position()
	_cup_r = maxf(cfg.cup_radius, cfg.ball_radius * 1.5)
	# floor level: depth below the LOWEST rim point (a big hole on a slope stays a proper pit all round)
	var n := hole.normal_at(_cup.x, _cup.z)
	var drop := _cup_r * sqrt(maxf(1.0 - n.y * n.y, 0.0)) / maxf(n.y, 0.3)
	_cup_floor = _cup.y - drop - cfg.cup_depth()


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
	_pin_hit_air = false
	_lip_air = false
	if hole.has_cup:
		_setup_cup()
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
	var n := _substeps()
	var h := cfg.dt / float(n)
	for i in n:
		if phase == Phase.AIR:
			_step_air(h)
		else:
			_step_roll(h)
		if not is_moving():
			break
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
		if _in_pit(pos):
			_hole_out()
			end_reason = "timeout"
			return
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


## The ball has come to rest inside the pit: it stays exactly where the physics left it.
func _hole_out() -> void:
	vel = Vector3.ZERO
	phase = Phase.HOLED
	end_reason = "cup"


func _record(kind: String) -> void:
	collisions.append({"type": kind, "pos": pos, "time": time})


# ------------------------------------------------------------------ AIR

func _step_air(dt: float) -> void:
	var r := cfg.ball_radius
	var p0 := pos
	var v0 := vel
	var vh := v0 + _air_accel(v0) * (dt * 0.5)
	var p1 := p0 + vh * dt
	var v1 := v0 + _air_accel(vh) * dt
	if not hole.trees.is_empty():
		var res := _collide_trees(p1, v1, true, dt)
		p1 = res[0]
		v1 = res[1]
	if hole.has_cup and not _pin_hit_air and cfg.pin_active() and not _on_green(p1):
		var ph := _pin_strike(p0, p1, v1)
		if not ph.is_empty():
			_pin_hit_air = true
			p1 = ph[0]
			# a flight coming down onto the pole loses most of its pace; a ball that just ran off the rim does not
			v1 = (ph[1] as Vector3) * (1.0 if _lip_air else cfg.pin_air_loss)
	if hole.has_cup and (_cup_d(p0) < _cup_r or _cup_d(p1) < _cup_r):
		_air_cup(p0, v0, p1, v1)
		return
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


## First ground contact bookkeeping (carry). Returns true when the sim stops here (calibration mode).
func _note_contact() -> bool:
	if not first_contact:
		first_contact = true
		first_contact_pos = pos
		carry_m = Units.horizontal_distance(launch_pos, pos)
		if stop_at_first_contact:
			phase = Phase.REST
			end_reason = "first_contact"
			return true
	return false


func _on_contact() -> void:
	if _note_contact():
		return
	var surf := _surface(pos.x, pos.z)
	if surf == Surface.Type.OOB:
		_set_hazard("OOB")
		return
	if surf == Surface.Type.WATER:
		_set_hazard("WATER")
		return
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

func _step_roll(dt: float) -> void:
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
	var in_cup := hole.has_cup and _cup_d(pos) < _cup_r
	var on_floor := false
	var n: Vector3
	if in_cup:
		on_floor = pos.y < _rim_h(pos)
		if on_floor:
			n = Vector3.UP
			var gp := cfg.surface(Surface.Type.GREEN)  # the hole is part of the green: same rolling model
			decel = float(gp["roll_decel"])
			drag = float(gp["roll_drag"])
		else:
			# on the rim edge itself: no turf under the ball, so no rolling resistance (a ball past the edge falls)
			n = _lip_normal(pos)
			decel = 0.0
			drag = 0.0
	else:
		n = hole.normal_at(pos.x, pos.z)
	var gv := Vector3(0.0, -cfg.gravity, 0.0)
	var g_t := (gv - n * gv.dot(n)) * (5.0 / 7.0)
	var holds := g_t.length() <= decel * cfg.static_factor
	vel = vel - n * vel.dot(n)
	var v_start := vel
	var speed := vel.length()
	# Deep grass and sand catch a very slow ball even on the steep terrain used
	# by some courses; otherwise it can creep for over a minute on a hillside.
	if not in_cup and (surf == Surface.Type.ROUGH or surf == Surface.Type.BUNKER) and speed < 0.15:
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
	if not in_cup and not (hole.has_cup and _cup_d(p_new) < _cup_r):
		p_new.y = hole.terrain_height(p_new.x, p_new.z) + r
		if not hole.trees.is_empty():
			var res := _collide_trees(p_new, vel, false, dt)
			p_new = res[0]
			vel = res[1]
			p_new.y = hole.terrain_height(p_new.x, p_new.z) + r
	else:
		if cfg.pin_active() and vel.length() > cfg.pin_soft_speed and not _on_green(p_new):
			var ph := _pin_strike(pos, p_new, vel)
			if not ph.is_empty():
				p_new = ph[0]
				vel = ph[1]
		if on_floor:
			var w := _pit_wall(pos, p_new, vel)
			p_new = w[0]
			vel = w[1]
			p_new.y = _cup_floor + r
		else:
			# Rolling contact holds only while the support stays under the ball: when it falls away faster than
			# gravity can follow (over the curved lip, or off the edge into the pit) the ball becomes airborne.
			var ball_y := pos.y + v_start.y * dt - 0.5 * cfg.gravity * dt * dt
			var sy := _roll_support_y(p_new)
			if sy < ball_y - 1e-7:
				pos = Vector3(p_new.x, ball_y, p_new.z)
				vel = Vector3(vel.x, v_start.y - cfg.gravity * dt, vel.z)
				still_time = 0.0
				phase = Phase.AIR
				_lip_air = true
				_pin_hit_air = false
				return
			p_new.y = sy
	pos = p_new
	if vel.length() < cfg.rest_speed:
		still_time += dt
	else:
		still_time = 0.0
	if still_time >= cfg.rest_time:
		if _in_pit(pos):
			_hole_out()
			return
		vel = Vector3.ZERO
		phase = Phase.REST
		end_reason = "rest"


# ------------------------------------------------------------------ cup (a real pit) and flagstick

static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Horizontal distance from the cup axis.
func _cup_d(p: Vector3) -> float:
	return Vector2(p.x - _cup.x, p.z - _cup.z).length()


## Sub-steps for this step: 1 away from the cup (the normal path is unchanged); near it, enough that the ball
## travels at most ~r/4 per sub-step, so the rim edge, wall and floor are never stepped over.
func _substeps() -> int:
	if not hole.has_cup:
		return 1
	var travel := vel.length() * cfg.dt
	if _cup_d(pos) > _cup_r + cfg.ball_radius + travel + 0.05:
		return 1
	return clampi(int(ceil(travel / (0.25 * cfg.ball_radius))), 1, 32)


## Point of the rim edge (a circle at ground level) nearest to `p`, in p's radial direction.
func _rim_point(p: Vector3) -> Vector3:
	var dx := p.x - _cup.x
	var dz := p.z - _cup.z
	var d := sqrt(dx * dx + dz * dz)
	if d < 1e-9:
		dx = 0.0
		dz = 1.0
		d = 1.0
	var x := _cup.x + dx / d * _cup_r
	var z := _cup.z + dz / d * _cup_r
	return Vector3(x, hole.terrain_height(x, z), z)


## Ground height at the rim in p's direction (the top of the wall).
func _rim_h(p: Vector3) -> float:
	return _rim_point(p).y


## Inside the pit: within the cup radius with the centre below the rim (below ground level).
func _in_pit(p: Vector3) -> bool:
	return hole.has_cup and _cup_d(p) < _cup_r and p.y < _rim_h(p)


## Centre height of a ball resting on the rim edge at horizontal distance d (R - r < d < R).
func _lip_y(p: Vector3) -> float:
	var w := _cup_r - _cup_d(p)
	var r := cfg.ball_radius
	return _rim_h(p) + sqrt(maxf(r * r - w * w, 0.0))


## Contact normal of a ball on the rim edge: from the edge point to the ball centre.
func _lip_normal(p: Vector3) -> Vector3:
	var q := _rim_point(p)
	var c := Vector3(p.x, _lip_y(p), p.z)
	var nv := c - q
	return nv.normalized() if nv.length() > 1e-9 else Vector3.UP


## Support height for the centre of a ball coming from above / outside: turf outside the cup, the curved
## rim edge across the lip (R - r < d < R), the pit floor inside R - r.
func _roll_support_y(p: Vector3) -> float:
	var d := _cup_d(p)
	var r := cfg.ball_radius
	if d >= _cup_r:
		return hole.terrain_height(p.x, p.z) + r
	if d > _cup_r - r:
		return _lip_y(p)
	return _cup_floor + r


## Pit wall: a ball inside the pit (centre below the rim) is kept within R - r of the axis.
## Returns [p1, v1] (reflected with cup_wall_restitution and Coulomb friction on contact).
func _pit_wall(p0: Vector3, p1: Vector3, v: Vector3) -> Array:
	var lim := _cup_r - cfg.ball_radius
	var d1 := _cup_d(p1)
	if d1 <= lim:
		return [p1, v]
	if not (_cup_d(p0) < _cup_r and p0.y < _rim_h(p0)) or p1.y >= _rim_h(p1):
		return [p1, v]
	var out := Vector3(p1.x - _cup.x, 0.0, p1.z - _cup.z) / maxf(d1, 1e-9)
	var nrm := -out
	p1.x = _cup.x + out.x * (lim - 1e-4)
	p1.z = _cup.z + out.z * (lim - 1e-4)
	var vn := v.dot(nrm)
	if vn < 0.0:
		v = _impact(v, nrm, vn, cfg.cup_wall_restitution)
		if vn < -0.3:
			collisions.append({"type": "cup_wall", "pos": p1, "time": time})
	return [p1, v]


## Impact response for the rim, wall and floor of the hole: the SAME bounce model as every other surface on the
## course (green parameters): speed-dependent restitution e = restitution / (1 + |vn| / bounce_soft), and the
## tangential velocity kept by the green's retention (plus spin), exactly as in the terrain bounce.
func _impact(v: Vector3, nrm: Vector3, vn: float, _unused_e: float, hard_edge: bool = true) -> Vector3:
	# Normal part: the green's speed-dependent restitution, like every other surface. Tangential part: the floor is
	# turf (green retention, as anywhere else); the rim lip and wall are a hard edge the ball slides/rolls along, so
	# a glancing touch keeps its pace (a fast ball rides over or lips out instead of stopping dead on the rim).
	var gp := cfg.surface(Surface.Type.GREEN)
	var vt := v - nrm * vn
	var e: float = float(gp["restitution"]) / (1.0 + absf(vn) / cfg.bounce_soft)
	var ret: float = cfg.cup_edge_retention if hard_edge else float(gp["retention"]) + spin * cfg.spin_retention
	return vt * clampf(ret, -0.15, 0.98) - nrm * (vn * e)


## Air step that touches the cup: pit wall, outer turf, rim edge (sphere vs circle) and floor.
func _air_cup(p0: Vector3, v0: Vector3, p1: Vector3, v1: Vector3) -> void:
	var r := cfg.ball_radius
	var w := _pit_wall(p0, p1, v1)
	p1 = w[0]
	v1 = w[1]
	var d1 := _cup_d(p1)
	if d1 >= _cup_r:
		var g1 := hole.contact_height(p1.x, p1.z)
		if p1.y - r <= g1:
			var g0 := hole.contact_height(p0.x, p0.z)
			var dd0 := p0.y - r - g0
			var dd1 := p1.y - r - g1
			var f := 1.0
			if dd0 > 0.0 and dd0 - dd1 > 1e-12:
				f = clampf(dd0 / (dd0 - dd1), 0.0, 1.0)
			var pc := p0.lerp(p1, f)
			if _cup_d(pc) < _cup_r:
				pc = p1
			pc.y = hole.contact_height(pc.x, pc.z) + r
			pos = pc
			vel = v0.lerp(v1, f)
			_on_contact()
			return
		pos = p1
		vel = v1
		max_height = maxf(max_height, pos.y)
		return
	if d1 > _cup_r - r:
		var q := _rim_point(p1)
		var dv := p1 - q
		var l := dv.length()
		if l < r:
			var nrm := dv / l if l > 1e-9 else Vector3.UP
			pos = q + nrm * r
			vel = v1
			_cup_contact(nrm, false)
			return
	if p1.y < _cup_floor + r:
		pos = Vector3(p1.x, _cup_floor + r, p1.z)
		vel = v1
		_cup_contact(Vector3.UP, true)
		return
	pos = p1
	vel = v1
	max_height = maxf(max_height, pos.y)


## Bounce off the rim edge or the pit floor. A gentle contact on a near-flat support becomes rolling.
func _cup_contact(nrm: Vector3, is_floor: bool) -> void:
	if _note_contact():
		return
	var vn := vel.dot(nrm)
	if vn >= 0.0:
		return
	var gp := cfg.surface(Surface.Type.GREEN)
	var e: float = float(gp["restitution"]) / (1.0 + absf(vn) / cfg.bounce_soft)
	vel = _impact(vel, nrm, vn, e, not is_floor)
	spin *= 0.5
	if vn < -0.3:
		bounces += 1
		_record("cup_floor" if is_floor else "rim")
	if nrm.y > 0.7 and -vn * e < cfg.min_bounce_speed:
		vel -= nrm * vel.dot(nrm)
		phase = Phase.ROLL


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
	# Speed-dependent bounce: a gentle touch barely rebounds (drops in), a firm hit rebounds towards pin_restitution.
	var speed := -vn
	var e := cfg.pin_restitution * speed / (speed + cfg.pin_bounce_speed)
	var nv := v - n * (vn * (1.0 + e))
	var out := _flat(_cup) + n * (rr + 0.001)
	out.y = q.y
	collisions.append({"type": "pin", "pos": out, "time": time})
	return [out, nv]


# ------------------------------------------------------------------ trees

func _collide_trees(p: Vector3, v: Vector3, airborne: bool, dt: float) -> Array:
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
				v *= exp(-cfg.canopy_damping * dt)
				if not _in_canopy.has(idx):
					_in_canopy[idx] = true
					collisions.append({"type": "canopy", "pos": p, "time": time})
			elif _in_canopy.has(idx):
				_in_canopy.erase(idx)
	return [p, v]


## Putting: the flagstick is taken out on the green, so a putt is decided by the rim and the floor alone.
func _on_green(p: Vector3) -> bool:
	return hole.surface_at(p.x, p.z) == Surface.Type.GREEN

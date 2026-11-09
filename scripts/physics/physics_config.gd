class_name PhysicsConfig
extends RefCounted
## All tunable physics parameters (engineering defaults). Shared by gameplay and the
## calibration solver so that both always use exactly the same model.

var gravity := Units.GRAVITY_MPS2
var dt := 1.0 / 240.0
var ball_radius := Units.BALL_RADIUS_M
var launch_angle_deg := 42.0
## Quadratic air drag: a = -drag_k * |v_rel| * v_rel  (v_rel = ball velocity - wind velocity).
var drag_k := 0.0011
## Impact-speed softening of restitution: e_eff = e / (1 + |vn| / bounce_soft)
var bounce_soft := 16.0
var min_bounce_speed := 0.65
var rest_speed := 0.02
var rest_time := 0.3
var static_factor := 1.0
var max_motion_time := 60.0
## Cup radius in metres. Regulation is 0.054 m (4.25 in diameter); the game default is a deliberately
## larger 12 in diameter so more shots drop. Adjustable in Settings / DEV.
const REGULATION_CUP_RADIUS := 0.054
const DEFAULT_CUP_DIAMETER_IN := 48.0  # owner: default hole is 4 ft
var cup_radius := DEFAULT_CUP_DIAMETER_IN * 0.0254 * 0.5
## The cup is a real pit (BallSim): a cylinder of radius cup_radius under the green with a vertical wall and a
## flat floor cup_depth() below the rim. The ball meets the rim edge, wall and floor like any other surface;
## nothing decides "holed" except the ball coming to rest inside the pit.
var cup_depth_min := 0.10  # regulation: about 4 in, whatever the hole width
var cup_depth_frac := 0.0
var cup_depth_max := 0.10
## Tangential speed kept when the ball touches the hole's rim lip or wall (a hard edge, not turf).
var cup_edge_retention := 0.92
## Pit contacts: normal restitution (wall and rim edge / floor), Coulomb friction on impact.
var cup_wall_restitution := 0.35
var cup_floor_restitution := 0.25
var cup_friction := 0.3
## Rolling on the pit floor (soft liner): a = decel + drag * v.
var cup_floor_roll_decel := 1.6
var cup_floor_roll_drag := 0.6
var pin_radius := 0.0125
var pin_height := 2.0
var pin_soft_speed := 1.0
var pin_restitution := 0.35
var pin_air_loss := 0.55
var pin_max_cup_radius := 0.45
var canopy_damping := 5.0
## Strike-point spin (flight only), s in [-1 backspin .. +1 topspin]:
## Magnus lift a = -s * spin_lift_k * |v_rel|^2 (perpendicular to flight, upward for backspin);
## landing grip: retention += s * spin_retention on the first bounce (halving each bounce).
var spin_lift_k := 0.0016
var spin_retention := 0.26
var trunk_restitution := 0.4
var surfaces: Dictionary = {}


func _init() -> void:
	surfaces = Surface.default_params()


func cup_diameter_in() -> float:
	return cup_radius * 2.0 / 0.0254


func set_cup_diameter_in(inches: float) -> void:
	cup_radius = clampf(inches, 4.25, 72.0) * 0.0254 * 0.5


## Pit depth below the rim: max(cup_depth_min, cup_depth_frac * R), capped at cup_depth_max.
func cup_depth() -> float:
	return clampf(cup_depth_frac * cup_radius, cup_depth_min, maxf(cup_depth_max, cup_depth_min))


func pin_active() -> bool:
	return cup_radius <= pin_max_cup_radius and pin_radius > 0.0


func surface(t: int) -> Dictionary:
	if surfaces.has(t):
		return surfaces[t]
	return surfaces[Surface.Type.FAIRWAY]


func copy() -> PhysicsConfig:
	var c := PhysicsConfig.new()
	c.apply_dict(to_dict())
	return c


## Signature used to key the calibration cache. Any parameter that affects the neutral
## flight or the neutral (FAIRWAY) roll must be part of it.
func signature() -> String:
	var f: Dictionary = surface(Surface.Type.FAIRWAY)
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [
		gravity, dt, ball_radius, launch_angle_deg, drag_k, rest_speed, rest_time,
		f["roll_decel"], f["roll_drag"], f["restitution"], f["retention"], static_factor] + "|%s" % spin_lift_k


func to_dict() -> Dictionary:
	var s := {}
	for k in surfaces.keys():
		s[Surface.name_of(int(k))] = (surfaces[k] as Dictionary).duplicate()
	return {
		"gravity": gravity,
		"dt": dt,
		"ball_radius": ball_radius,
		"launch_angle_deg": launch_angle_deg,
		"drag_k": drag_k,
		"bounce_soft": bounce_soft,
		"min_bounce_speed": min_bounce_speed,
		"rest_speed": rest_speed,
		"rest_time": rest_time,
		"static_factor": static_factor,
		"max_motion_time": max_motion_time,
		"cup_radius": cup_radius,
		"cup_depth_min": cup_depth_min,
		"cup_depth_frac": cup_depth_frac,
		"cup_depth_max": cup_depth_max,
		"cup_wall_restitution": cup_wall_restitution,
		"cup_floor_restitution": cup_floor_restitution,
		"cup_friction": cup_friction,
		"cup_floor_roll_decel": cup_floor_roll_decel,
		"cup_floor_roll_drag": cup_floor_roll_drag,
		"canopy_damping": canopy_damping,
		"pin_radius": pin_radius,
		"pin_height": pin_height,
		"pin_soft_speed": pin_soft_speed,
		"pin_restitution": pin_restitution,
		"pin_air_loss": pin_air_loss,
		"pin_max_cup_radius": pin_max_cup_radius,
		"trunk_restitution": trunk_restitution,
		"spin_lift_k": spin_lift_k,
		"spin_retention": spin_retention,
		"surfaces": s,
	}


func apply_dict(d: Dictionary) -> void:
	for key in ["gravity", "dt", "ball_radius", "launch_angle_deg", "drag_k", "bounce_soft",
			"min_bounce_speed", "rest_speed", "rest_time", "static_factor", "max_motion_time",
			"cup_radius", "cup_depth_min", "cup_depth_frac", "cup_depth_max", "cup_wall_restitution",
			"cup_floor_restitution", "cup_friction", "cup_floor_roll_decel", "cup_floor_roll_drag", "canopy_damping",
			"trunk_restitution", "spin_lift_k", "spin_retention",
			"pin_radius", "pin_height", "pin_soft_speed", "pin_restitution", "pin_air_loss", "pin_max_cup_radius"]:
		# keys of the old heuristic cup (cup_capture_speed, cup_sink_fraction, cup_lip_*, ...) are ignored
		if d.has(key):
			var v = d[key]
			if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v)):
				set(key, float(v))
	launch_angle_deg = clampf(launch_angle_deg, 5.0, 80.0)
	dt = clampf(dt, 1.0 / 1000.0, 1.0 / 30.0)
	drag_k = clampf(drag_k, 0.0, 0.02)
	cup_radius = clampf(cup_radius, REGULATION_CUP_RADIUS * 0.99, 72.0 * 0.0254 * 0.5)
	cup_depth_min = clampf(cup_depth_min, 0.05, 1.0)
	cup_depth_max = clampf(cup_depth_max, cup_depth_min, 1.0)
	cup_depth_frac = clampf(cup_depth_frac, 0.0, 2.0)
	cup_wall_restitution = clampf(cup_wall_restitution, 0.0, 0.95)
	cup_floor_restitution = clampf(cup_floor_restitution, 0.0, 0.95)
	cup_friction = clampf(cup_friction, 0.0, 2.0)
	cup_floor_roll_decel = maxf(cup_floor_roll_decel, 0.05)
	cup_floor_roll_drag = maxf(cup_floor_roll_drag, 0.0)
	if d.has("surfaces") and typeof(d["surfaces"]) == TYPE_DICTIONARY:
		var s: Dictionary = d["surfaces"]
		for name in s.keys():
			var t := Surface.from_name(String(name))
			if t < 0 or typeof(s[name]) != TYPE_DICTIONARY:
				continue
			var src: Dictionary = s[name]
			var dst: Dictionary = surface(t).duplicate()
			for pk in dst.keys():
				if src.has(pk) and (typeof(src[pk]) == TYPE_FLOAT or typeof(src[pk]) == TYPE_INT):
					var fv := float(src[pk])
					if is_finite(fv) and fv >= 0.0:
						dst[pk] = fv
			surfaces[t] = dst

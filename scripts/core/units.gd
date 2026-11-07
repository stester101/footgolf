class_name Units
extends RefCounted
## Unit conversions. World physics: 1 Godot unit = 1 metre, Y up.
## Horizontal distances are measured in the X/Z plane.

const METRES_PER_YARD := 0.9144
const METRES_PER_FOOT := 0.3048
const FEET_PER_YARD := 3.0
const GRAVITY_MPS2 := 9.81
const BALL_RADIUS_M := 0.02135
const MPS_TO_MPH := 2.236936


static func yards_to_m(yd: float) -> float:
	return yd * METRES_PER_YARD


static func m_to_yards(m: float) -> float:
	return m / METRES_PER_YARD


static func feet_to_m(ft: float) -> float:
	return ft * METRES_PER_FOOT


static func m_to_feet(m: float) -> float:
	return m / METRES_PER_FOOT


## Caps rule: 1 senior international cap = 1 yard of neutral first-contact carry.
static func caps_to_carry_m(caps: int) -> float:
	return float(maxi(caps, 0)) * METRES_PER_YARD


## Goals rule: 1 senior international goal = 1 foot of neutral ground travel.
static func goals_to_roll_m(goals: int) -> float:
	return float(maxi(goals, 0)) * METRES_PER_FOOT


## Bearing convention: 0 deg = world +Z, 90 deg = world +X. Direction is horizontal, unit length.
static func bearing_to_dir(bearing_deg: float) -> Vector3:
	var r := deg_to_rad(bearing_deg)
	return Vector3(sin(r), 0.0, cos(r))


static func dir_to_bearing(dir: Vector3) -> float:
	if absf(dir.x) < 1e-9 and absf(dir.z) < 1e-9:
		return 0.0
	return fposmod(rad_to_deg(atan2(dir.x, dir.z)), 360.0)


static func horizontal_distance(a: Vector3, b: Vector3) -> float:
	var dx := a.x - b.x
	var dz := a.z - b.z
	return sqrt(dx * dx + dz * dz)


static func fmt_yards(m: float) -> String:
	return "%d yd" % int(round(m_to_yards(m)))


static func fmt_feet(m: float) -> String:
	return "%.1f ft" % m_to_feet(m)


## Distance for normal display: yards when long, feet when close to the hole.
static func fmt_distance(m: float) -> String:
	if m < yards_to_m(20.0):
		return "%d ft" % int(round(m_to_feet(m)))
	return fmt_yards(m)

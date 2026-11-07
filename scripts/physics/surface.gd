class_name Surface
extends RefCounted
## Lie / surface metadata. Independent from visual textures.

enum Type { TEE, FAIRWAY, FRINGE, ROUGH, BUNKER, GREEN, WATER, OOB }

const NAMES := {
	Type.TEE: "Tee",
	Type.FAIRWAY: "Fairway",
	Type.FRINGE: "Fringe",
	Type.ROUGH: "Rough",
	Type.BUNKER: "Bunker",
	Type.GREEN: "Green",
	Type.WATER: "Water",
	Type.OOB: "Out of bounds",
}

## Surfaces a developer can force for a controlled test.
const PLAYABLE := [Type.TEE, Type.FAIRWAY, Type.FRINGE, Type.ROUGH, Type.BUNKER, Type.GREEN]


static func name_of(t: int) -> String:
	return NAMES.get(t, "Unknown")


static func from_name(n: String) -> int:
	for k in NAMES.keys():
		if String(NAMES[k]).to_lower() == n.to_lower():
			return int(k)
	return -1


## Engineering defaults (tunable in the developer panel; NOT locked game rules).
## roll_decel  : constant rolling deceleration, m/s^2
## roll_drag   : speed-proportional rolling deceleration, 1/s (a = roll_decel + roll_drag * v)
## restitution : normal coefficient of restitution at low impact speed
## retention   : fraction of tangential speed kept per bounce (crudely models spin/turf grab)
## caps_min/max: Caps launch-lie factor range applied to the neutral carry target
## The neutral reference surface for Goals calibration is FAIRWAY.
static func default_params() -> Dictionary:
	return {
		Type.TEE: _p(0.90, 0.22, 0.32, 0.32, 1.0, 1.0),
		Type.FAIRWAY: _p(0.90, 0.22, 0.32, 0.32, 1.0, 1.0),
		Type.FRINGE: _p(0.80, 0.18, 0.30, 0.28, 0.97, 1.0),
		Type.GREEN: _p(0.80, 0.17, 0.26, 0.22, 1.0, 1.0),
		Type.ROUGH: _p(2.20, 0.60, 0.18, 0.20, 0.80, 0.92),
		Type.BUNKER: _p(5.50, 1.50, 0.05, 0.06, 0.60, 0.80),
		Type.WATER: _p(50.0, 5.0, 0.0, 0.0, 0.3, 0.5),
		Type.OOB: _p(2.20, 0.60, 0.18, 0.20, 0.8, 0.9),
	}


static func _p(decel: float, drag: float, rest: float, ret: float, cmin: float, cmax: float) -> Dictionary:
	return {
		"roll_decel": decel,
		"roll_drag": drag,
		"restitution": rest,
		"retention": ret,
		"caps_min": cmin,
		"caps_max": cmax,
	}


## Approximate, player-facing description of a lie's effect. Never an exact prediction.
static func effect_hint(t: int, params: Dictionary) -> String:
	var p: Dictionary = params.get(t, {})
	if p.is_empty():
		return ""
	var cmin: float = p["caps_min"]
	var cmax: float = p["caps_max"]
	var caps_txt := "Caps neutral"
	if cmax < 0.999 or cmin < 0.999:
		caps_txt = "Caps carry ~-%d to -%d%%" % [int(round((1.0 - cmax) * 100.0)), int(round((1.0 - cmin) * 100.0))]
	var ref: Dictionary = params[Type.FAIRWAY]
	var ratio: float = float(p["roll_decel"]) / maxf(0.01, float(ref["roll_decel"]))
	var goals_txt := "Goals roll normal"
	if ratio > 3.0:
		goals_txt = "Goals roll heavily slowed"
	elif ratio > 1.3:
		goals_txt = "Goals roll slowed"
	elif ratio < 0.85:
		goals_txt = "Goals roll faster"
	return "%s · %s" % [caps_txt, goals_txt]

class_name SettingsStore
extends RefCounted
## Local preferences and developer test settings, persisted to user://settings.json.

const PATH := "user://settings.json"
const VERSION := 3

## Physics values shipped in settings_version 2 that were replaced by the v3 golf-ball tuning.
## A saved value equal to one of these is an untouched old default and is replaced by the new
## default on upgrade; any other value is treated as a deliberate custom edit and kept.
const V2_BOUNCE := {"bounce_soft": 8.0, "min_bounce_speed": 0.9}
const V2_SURFACE := {
	Surface.Type.TEE: {"roll_decel": 0.90, "roll_drag": 0.22, "restitution": 0.32, "retention": 0.32, "caps_min": 1.0, "caps_max": 1.0},
	Surface.Type.FAIRWAY: {"roll_decel": 0.90, "roll_drag": 0.22, "restitution": 0.32, "retention": 0.32, "caps_min": 1.0, "caps_max": 1.0},
	Surface.Type.FRINGE: {"roll_decel": 0.80, "roll_drag": 0.18, "restitution": 0.30, "retention": 0.28, "caps_min": 0.97, "caps_max": 1.0},
	Surface.Type.GREEN: {"roll_decel": 0.80, "roll_drag": 0.17, "restitution": 0.26, "retention": 0.22, "caps_min": 1.0, "caps_max": 1.0},
	Surface.Type.ROUGH: {"roll_decel": 2.20, "roll_drag": 0.60, "restitution": 0.18, "retention": 0.20, "caps_min": 0.80, "caps_max": 0.92},
	Surface.Type.BUNKER: {"roll_decel": 5.50, "roll_drag": 1.50, "restitution": 0.05, "retention": 0.06, "caps_min": 0.60, "caps_max": 0.80},
}


## Drops only the saved physics values that equal the old v2 defaults (see V2_* above).
static func migrate_physics_v2(p: Dictionary) -> Dictionary:
	var out := p.duplicate(true)
	for k in V2_BOUNCE.keys():
		if out.has(k) and is_equal_approx(float(out[k]), float(V2_BOUNCE[k])):
			out.erase(k)
	if typeof(out.get("surfaces")) == TYPE_DICTIONARY:
		var surf: Dictionary = out["surfaces"]
		for t in V2_SURFACE.keys():
			var name := Surface.name_of(int(t))
			if not surf.has(name) or typeof(surf[name]) != TYPE_DICTIONARY:
				continue
			var old: Dictionary = V2_SURFACE[t]
			var cur: Dictionary = surf[name]
			var same := true
			for pk in old.keys():
				if not cur.has(pk) or not is_equal_approx(float(cur[pk]), float(old[pk])):
					same = false
			if same:
				surf.erase(name)
	return out

var save_path := PATH
var holeout_radius_ft := ScoringService.DEFAULT_HOLEOUT_FT
var wind_custom := false
var wind_speed := 0.0
var wind_bearing := 0.0
var sim_speed := 1.0
var show_trail := true
var vibration := true
var drag_trajectory := true  # trial: drag up/down on the aim view to change trajectory
## Favourite footballer ids (starred in the picker). Global for now; per-profile later.
var favourites: Array = []
## TEST MODE: show caps/goals in the picker before the shot (developer/testing aid; off = normal rules).
var show_stats := true
## "real" = bundled Wikidata snapshot, "test" = synthetic test players.
var dataset := "real"
var tutorial_seen := false
var last_course := "starter"
## hole id -> par chosen by the player (overrides the hole file); applies to rounds started afterwards.
var par_overrides: Dictionary = {}
var lie_override := -1
var force_surface := false
var physics := PhysicsConfig.new()
var scenario: Dictionary = {}


func load_settings() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	holeout_radius_ft = ScoringService.clamp_radius_ft(float(d.get("holeout_radius_ft", holeout_radius_ft)))
	wind_custom = bool(d.get("wind_custom", false))
	wind_speed = clampf(float(d.get("wind_speed", 0.0)), 0.0, 30.0)
	wind_bearing = fposmod(float(d.get("wind_bearing", 0.0)), 360.0)
	sim_speed = clampf(float(d.get("sim_speed", 1.0)), 0.25, 8.0)
	show_trail = bool(d.get("show_trail", true))
	vibration = bool(d.get("vibration", true))
	drag_trajectory = bool(d.get("drag_trajectory", true))
	favourites = (d.get("favourites", []) as Array).duplicate() if typeof(d.get("favourites")) == TYPE_ARRAY else []
	show_stats = bool(d.get("show_stats", true))
	tutorial_seen = bool(d.get("tutorial_seen", false))
	last_course = String(d.get("last_course", "starter"))
	if typeof(d.get("par_overrides")) == TYPE_DICTIONARY:
		for k in (d["par_overrides"] as Dictionary).keys():
			var pv := int((d["par_overrides"] as Dictionary)[k])
			if pv >= 2 and pv <= 8:
				par_overrides[String(k)] = pv
	dataset = "test" if String(d.get("dataset", "real")) == "test" else "real"
	lie_override = int(d.get("lie_override", -1))
	if not Surface.PLAYABLE.has(lie_override):
		lie_override = -1
	force_surface = bool(d.get("force_surface", false))
	if typeof(d.get("physics")) == TYPE_DICTIONARY:
		var phys: Dictionary = d["physics"]
		if int(d.get("settings_version", 1)) < 3:
			phys = migrate_physics_v2(phys)  # untouched v2 defaults move to the v3 tuning
		physics.apply_dict(phys)
		if int(d.get("settings_version", 1)) < 2:
			physics.cup_radius = PhysicsConfig.new().cup_radius  # v2: larger default hole
	if typeof(d.get("scenario")) == TYPE_DICTIONARY:
		scenario = d["scenario"]


func save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"settings_version": VERSION,
		"last_course": last_course,
		"par_overrides": par_overrides,
		"holeout_radius_ft": holeout_radius_ft,
		"wind_custom": wind_custom,
		"wind_speed": wind_speed,
		"wind_bearing": wind_bearing,
		"sim_speed": sim_speed,
		"show_trail": show_trail,
		"vibration": vibration,
		"drag_trajectory": drag_trajectory,
		"favourites": favourites,
		"show_stats": show_stats,
		"dataset": dataset,
		"tutorial_seen": tutorial_seen,
		"lie_override": lie_override,
		"force_surface": force_surface,
		"physics": physics.to_dict(),
		"scenario": scenario,
	}, "  "))


func reset_physics() -> void:
	physics.apply_dict(PhysicsConfig.new().to_dict())


func apply_to(s: GameSession) -> void:
	s.cfg = physics
	s.holeout_radius_ft = holeout_radius_ft
	s.wind_custom = wind_custom
	s.wind_custom_speed = wind_speed
	s.wind_custom_bearing = wind_bearing
	s.lie_override = lie_override
	s.force_surface = force_surface


func capture_from(s: GameSession) -> void:
	holeout_radius_ft = s.holeout_radius_ft
	wind_custom = s.wind_custom
	wind_speed = s.wind_custom_speed
	wind_bearing = s.wind_custom_bearing
	lie_override = s.lie_override
	force_surface = s.force_surface

class_name SettingsStore
extends RefCounted
## Local preferences and developer test settings, persisted to user://settings.json.

const PATH := "user://settings.json"
const VERSION := 2

var save_path := PATH
var holeout_radius_ft := ScoringService.DEFAULT_HOLEOUT_FT
var wind_custom := false
var wind_speed := 0.0
var wind_bearing := 0.0
var sim_speed := 1.0
var show_trail := true
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
		physics.apply_dict(d["physics"])
		if int(d.get("settings_version", 1)) < 2:
			physics.cup_radius = PhysicsConfig.new().cup_radius  # v2: larger default hole
		_migrate_spin_defaults()
	if typeof(d.get("scenario")) == TYPE_DICTIONARY:
		scenario = d["scenario"]


## Saved settings carry the old (stronger) spin defaults; move untouched values to the new ones.
func _migrate_spin_defaults() -> void:
	var fresh := PhysicsConfig.new()
	if is_equal_approx(physics.spin_lift_k, PhysicsConfig.LEGACY_SPIN_LIFT_K):
		physics.spin_lift_k = fresh.spin_lift_k
	if is_equal_approx(physics.spin_retention, PhysicsConfig.LEGACY_SPIN_RETENTION):
		physics.spin_retention = fresh.spin_retention


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

class_name SettingsStore
extends RefCounted
## Local preferences and developer test settings, persisted to user://settings.json.

const PATH := "user://settings.json"

var save_path := PATH
var holeout_radius_ft := ScoringService.DEFAULT_HOLEOUT_FT
var wind_custom := false
var wind_speed := 0.0
var wind_bearing := 0.0
var sim_speed := 1.0
var show_trail := true
## TEST MODE: show caps/goals in the picker before the shot (developer/testing aid; off = normal rules).
var show_stats := true
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
	lie_override = int(d.get("lie_override", -1))
	if not Surface.PLAYABLE.has(lie_override):
		lie_override = -1
	force_surface = bool(d.get("force_surface", false))
	if typeof(d.get("physics")) == TYPE_DICTIONARY:
		physics.apply_dict(d["physics"])
	if typeof(d.get("scenario")) == TYPE_DICTIONARY:
		scenario = d["scenario"]


func save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"holeout_radius_ft": holeout_radius_ft,
		"wind_custom": wind_custom,
		"wind_speed": wind_speed,
		"wind_bearing": wind_bearing,
		"sim_speed": sim_speed,
		"show_trail": show_trail,
		"show_stats": show_stats,
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

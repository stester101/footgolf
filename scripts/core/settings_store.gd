class_name SettingsStore
extends RefCounted
## Local preferences and developer test settings, persisted to user://settings.json.

const PATH := "user://settings.json"
const VERSION := 7

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


## v4: rough 10-20% and bunker 20-40% distance penalty. Saved Rough/Bunker equal to the v3 defaults
## are untouched, so they are dropped and the new defaults apply; custom edits are kept.
const V3_SURFACE := {
	Surface.Type.ROUGH: {"roll_decel": 2.20, "roll_drag": 0.60, "restitution": 0.18, "retention": 0.20, "caps_min": 0.90, "caps_max": 0.97},
	Surface.Type.BUNKER: {"roll_decel": 5.50, "roll_drag": 1.50, "restitution": 0.05, "retention": 0.06, "caps_min": 0.82, "caps_max": 0.93},
}


static func migrate_physics_v3(p: Dictionary) -> Dictionary:
	var out := p.duplicate(true)
	if typeof(out.get("surfaces")) == TYPE_DICTIONARY:
		var surf: Dictionary = out["surfaces"]
		for t in V3_SURFACE.keys():
			var name := Surface.name_of(int(t))
			if not surf.has(name) or typeof(surf[name]) != TYPE_DICTIONARY:
				continue
			var old: Dictionary = V3_SURFACE[t]
			var cur: Dictionary = surf[name]
			var same := true
			for pk in old.keys():
				if not cur.has(pk) or not is_equal_approx(float(cur[pk]), float(old[pk])):
					same = false
			if same:
				surf.erase(name)
	return out


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
## Graphics quality: 0 = Low (original look/cost), 1 = High (sky shader, ground variation, per-hole sun).
var graphics_quality := 1
## Optional subtle bloom inside High graphics (default off).
var graphics_glow := false
var lie_effect_exact := false  # spin-ball lie read-out: false = range (-10 to -20%), true = this shot's exact value
var auto_continue := true  # result card continues by itself after a few seconds (progress bar); tap to skip
## Battery / performance: frame-rate cap in fps (0 = device default) and keeping the screen awake during a round.
const FPS_CHOICES := [0, 30, 60]
var max_fps := 0
var keep_awake := true
## Last Round Setup choices (mulligans: 0 off, 1, 3, 5, -1 unlimited; players 1..4), restored on the next launch.
const MULLIGAN_CHOICES := [0, 1, 3, 5, -1]
var last_mulligans := 0
var last_players := 1
var drag_trajectory := true  # trial: drag up/down on the aim view to change trajectory
## Favourite footballer ids (starred in the picker). Global for now; per-profile later.
## LEGACY: only read once to migrate into the first profile (PlayerProfileStore); no longer used in play.
var favourites: Array = []
## Round Setup defaults beyond the legacy fields (see RoundConfig.write_defaults).
var round_defaults: Dictionary = {}
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
	var j := JSON.new()
	var d = j.data if j.parse(f.get_as_text()) == OK else null
	f.close()
	if typeof(d) != TYPE_DICTIONARY:
		# Corrupt file: keep a copy for diagnosis and start from defaults instead of failing silently.
		DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(save_path + ".bad"))
		return
	holeout_radius_ft = ScoringService.clamp_radius_ft(float(d.get("holeout_radius_ft", holeout_radius_ft)))
	wind_custom = bool(d.get("wind_custom", false))
	wind_speed = clampf(float(d.get("wind_speed", 0.0)), 0.0, 30.0)
	wind_bearing = fposmod(float(d.get("wind_bearing", 0.0)), 360.0)
	sim_speed = clampf(float(d.get("sim_speed", 1.0)), 0.25, 8.0)
	show_trail = bool(d.get("show_trail", true))
	vibration = bool(d.get("vibration", true))
	graphics_quality = clampi(int(d.get("graphics_quality", 1)), 0, 1)
	graphics_glow = bool(d.get("graphics_glow", false))
	lie_effect_exact = bool(d.get("lie_effect_exact", false))
	drag_trajectory = bool(d.get("drag_trajectory", true))
	max_fps = sanitize_fps(int(d.get("max_fps", 0)))
	keep_awake = bool(d.get("keep_awake", true))
	last_mulligans = sanitize_mulligans(int(d.get("last_mulligans", 0)))
	last_players = clampi(int(d.get("last_players", 1)), 1, 4)
	auto_continue = bool(d.get("auto_continue", true))
	favourites = (d.get("favourites", []) as Array).duplicate() if typeof(d.get("favourites")) == TYPE_ARRAY else []
	show_stats = bool(d.get("show_stats", true))
	if typeof(d.get("round_defaults")) == TYPE_DICTIONARY:
		round_defaults = (d["round_defaults"] as Dictionary).duplicate()
		if int(d.get("settings_version", 1)) < 5 and round_defaults.has("cup_diameter_ft") and is_equal_approx(float(round_defaults["cup_diameter_ft"]), 1.0):
			round_defaults.erase("cup_diameter_ft")  # v5: old 1 ft default -> new default
		if int(d.get("settings_version", 1)) < 6 and round_defaults.has("cup_diameter_ft") and is_equal_approx(float(round_defaults["cup_diameter_ft"]), 6.0):
			round_defaults.erase("cup_diameter_ft")  # v6: untouched 6 ft default -> new 4 ft default
		if int(d.get("settings_version", 1)) < 7 and round_defaults.has("cup_diameter_ft") and is_equal_approx(float(round_defaults["cup_diameter_ft"]), 4.0):
			round_defaults.erase("cup_diameter_ft")  # v7: untouched 4 ft default -> new 12 in default
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
		if int(d.get("settings_version", 1)) < 4:
			phys = migrate_physics_v3(phys)  # untouched v3 rough/bunker move to the v4 penalties
		if int(d.get("settings_version", 1)) < 5 and phys.has("cup_radius") and is_equal_approx(float(phys["cup_radius"]), 12.0 * 0.0254 * 0.5):
			phys = phys.duplicate()
			phys.erase("cup_radius")  # v5: the untouched old 1 ft default moves to the new default
		if int(d.get("settings_version", 1)) < 6 and phys.has("cup_radius") and is_equal_approx(float(phys["cup_radius"]), 72.0 * 0.0254 * 0.5):
			phys = phys.duplicate()
			phys.erase("cup_radius")  # v6: the untouched 6 ft default moves to the new 4 ft default
		if int(d.get("settings_version", 1)) < 7 and phys.has("cup_radius") and is_equal_approx(float(phys["cup_radius"]), 48.0 * 0.0254 * 0.5):
			phys = phys.duplicate()
			phys.erase("cup_radius")  # v7: the untouched 4 ft default moves to the new 12 in default
		physics.apply_dict(phys)
		if int(d.get("settings_version", 1)) < 2:
			physics.cup_radius = PhysicsConfig.new().cup_radius  # v2: larger default hole
	if typeof(d.get("scenario")) == TYPE_DICTIONARY:
		scenario = d["scenario"]


func save() -> void:
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
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
		"graphics_quality": graphics_quality,
		"graphics_glow": graphics_glow,
		"lie_effect_exact": lie_effect_exact,
		"drag_trajectory": drag_trajectory,
		"max_fps": max_fps,
		"keep_awake": keep_awake,
		"last_mulligans": last_mulligans,
		"last_players": last_players,
		"auto_continue": auto_continue,
		"favourites": favourites,
		"round_defaults": round_defaults,
		"show_stats": show_stats,
		"dataset": dataset,
		"tutorial_seen": tutorial_seen,
		"lie_override": lie_override,
		"force_surface": force_surface,
		"physics": physics.to_dict(),
		"scenario": scenario,
	}, "  "))
	f.close()
	# Write-then-rename: a crash or power loss mid-save can never leave a half-written settings file.
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(save_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


static func sanitize_mulligans(v: int) -> int:
	return v if MULLIGAN_CHOICES.has(v) else 0


static func sanitize_fps(v: int) -> int:
	return v if FPS_CHOICES.has(v) else 0


## Applies the frame-rate cap (0 = engine default, uncapped by us).
func apply_runtime() -> void:
	Engine.max_fps = sanitize_fps(max_fps)


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

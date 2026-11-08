extends Node
## Autoload "App": shared offline services (footballer repository, settings, hole data).

const COURSES_PATH := "res://data/courses.json"
const HOLE_DIR := "res://data/holes/"

var settings := SettingsStore.new()
var repo := FootballerRepository.new()
var profiles := PlayerProfileStore.new()
## On-device shot/hole/round log (user://telemetry); exported from Settings.
var telemetry := TelemetryLog.new()
var online := OnlineRoom.new()
var dev_mode := false
var build_info := {}


func _ready() -> void:
	add_child(online)
	settings.load_settings()
	profiles.load_profiles()
	load_dataset()
	if FileAccess.file_exists("res://build_info.json"):
		var f := FileAccess.open("res://build_info.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			build_info = d
	print("[FootballGolf] v%s commit=%s footballers=%d" % [version(), build_info.get("commit", "local"), repo.count()])


## Load the footballer dataset chosen in settings (falls back to synthetic test players if the
## real snapshot is not bundled).
func load_dataset() -> void:
	var want_real := settings.dataset == "real" and FileAccess.file_exists(FootballerRepository.REAL_PATH)
	repo.seed_path = FootballerRepository.REAL_PATH if want_real else FootballerRepository.SEED_PATH
	repo.load_all()


func dataset_label() -> String:
	if repo.seed_path == FootballerRepository.REAL_PATH:
		return "Real players (Wikidata snapshot, %d players)" % repo.count()
	return "Synthetic test players (%d)" % repo.count()


## [{id, name, blurb, holes:[hole ids]}]
func courses() -> Array:
	var f := FileAccess.open(COURSES_PATH, FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) == TYPE_DICTIONARY and d.has("courses"):
		return d["courses"]
	return []


func course_info(course_id: String) -> Dictionary:
	for c in courses():
		if String(c["id"]) == course_id:
			return c
	var all := courses()
	return all[0] if not all.is_empty() else {}


func load_holes(course_id: String = "starter") -> Array:
	var out: Array = []
	for hid in course_info(course_id).get("holes", []):
		var h := HoleDefinition.load_from_file("%s%s.json" % [HOLE_DIR, hid])
		if h != null:
			h.par = par_for(h.id, h.par)
			out.append(h)
	return out


func par_for(hole_id: String, base_par: int) -> int:
	return int(settings.par_overrides.get(hole_id, base_par))


## [{id, name, yards, base_par}] for every hole file (for the par editor).
func all_hole_infos() -> Array:
	var out: Array = []
	var seen := {}
	for c in courses():
		for hid in c["holes"]:
			if seen.has(hid):
				continue
			seen[hid] = true
			var f := FileAccess.open("%s%s.json" % [HOLE_DIR, hid], FileAccess.READ)
			if f == null:
				continue
			var d = JSON.parse_string(f.get_as_text())
			if typeof(d) == TYPE_DICTIONARY:
				out.append({"id": hid, "name": String(d.get("name", hid)), "yards": int(d.get("yards", 0)), "base_par": int(d.get("par", 4))})
	return out


## Course par from the (possibly edited) hole pars.
func course_par(course_id: String) -> int:
	var total := 0
	for info in all_hole_infos():
		if (course_info(course_id).get("holes", []) as Array).has(info["id"]):
			total += par_for(info["id"], info["base_par"])
	return total


func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.1.0"))


func build_label() -> String:
	var c := String(build_info.get("commit", "local"))
	return "v%s · build %s · Godot %s" % [version(), c.substr(0, 7), Engine.get_version_info()["string"]]

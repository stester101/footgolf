extends Node
## Autoload "App": shared offline services (footballer repository, settings, hole data).

const COURSES_PATH := "res://data/courses.json"
const HOLE_DIR := "res://data/holes/"

var settings := SettingsStore.new()
var repo := FootballerRepository.new()
var dev_mode := false
var build_info := {}


func _ready() -> void:
	settings.load_settings()
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
			out.append(h)
	return out


func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.1.0"))


func build_label() -> String:
	var c := String(build_info.get("commit", "local"))
	return "v%s · build %s · Godot %s" % [version(), c.substr(0, 7), Engine.get_version_info()["string"]]

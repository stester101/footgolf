extends Node
## Autoload "App": shared offline services (footballer repository, settings, hole data).

const HOLE_PATHS := [
	"res://data/holes/hole_01.json",
	"res://data/holes/hole_02.json",
	"res://data/holes/hole_03.json",
]

var settings := SettingsStore.new()
var repo := FootballerRepository.new()
var dev_mode := false
var build_info := {}


func _ready() -> void:
	settings.load_settings()
	repo.load_all()
	if FileAccess.file_exists("res://build_info.json"):
		var f := FileAccess.open("res://build_info.json", FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			build_info = d
	print("[FootballGolf] v%s commit=%s footballers=%d" % [version(), build_info.get("commit", "local"), repo.count()])


func load_holes() -> Array:
	var out: Array = []
	for p in HOLE_PATHS:
		var h := HoleDefinition.load_from_file(p)
		if h != null:
			out.append(h)
	return out


func version() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.1.0"))


func build_label() -> String:
	var c := String(build_info.get("commit", "local"))
	return "v%s · build %s · Godot %s" % [version(), c.substr(0, 7), Engine.get_version_info()["string"]]

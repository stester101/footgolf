class_name CourseSource
extends RefCounted
## Reads a course (data/courses.json + data/holes/*.json) as plain Dictionaries, without App. Pure data.
## Output: {id, name, holes:[{id, par, data:<hole json dict>}]}; empty Dictionary when the course is unknown.
## `par_overrides` (hole id -> par) are the player's edited pars (Settings); they are baked into the result.

const COURSES_PATH := "res://data/courses.json"
const HOLE_DIR := "res://data/holes/"


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return j.data


static func courses() -> Array:
	var d = read_json(COURSES_PATH)
	return d["courses"] if typeof(d) == TYPE_DICTIONARY and d.has("courses") else []


static func course_info(course_id: String) -> Dictionary:
	for c in courses():
		if String(c["id"]) == course_id:
			return c
	return {}


static func load_course(course_id: String, par_overrides: Dictionary = {}) -> Dictionary:
	var info := course_info(course_id)
	if info.is_empty():
		return {}
	var holes: Array = []
	for hid in info.get("holes", []):
		var d = read_json("%s%s.json" % [HOLE_DIR, hid])
		if typeof(d) != TYPE_DICTIONARY:
			return {}
		var par := int(par_overrides.get(String(hid), int(d.get("par", 4))))
		(d as Dictionary)["par"] = par
		holes.append({"id": String(hid), "par": par, "data": d})
	return {"id": course_id, "name": String(info.get("name", course_id)), "holes": holes}

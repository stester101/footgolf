class_name CourseSnapshot
extends RefCounted
## A tournament's frozen course: the full hole definitions (JSON dictionaries) and pars as they were when the
## event started. Resume rebuilds HoleDefinitions from this, never from the current data files (Career spec
## decision 30). A snapshot that cannot be rebuilt is a recovery error, never silently replaced.


## course: CourseSource.load_course() result. Returns {course_id, name, holes, hash}.
static func capture(course: Dictionary) -> Dictionary:
	if course.is_empty() or (course.get("holes", []) as Array).is_empty():
		return {}
	var snap := {"course_id": String(course["id"]), "name": String(course["name"]),
		"holes": (course["holes"] as Array).duplicate(true)}
	snap["hash"] = hash_of(snap)
	return snap


static func hash_of(snap: Dictionary) -> String:
	return JSON.stringify({"c": snap.get("course_id", ""), "h": snap.get("holes", [])}, "", true).sha256_text()


static func is_valid(snap: Dictionary) -> bool:
	if not snap.has("holes") or typeof(snap["holes"]) != TYPE_ARRAY or (snap["holes"] as Array).is_empty():
		return false
	for h in snap["holes"]:
		if typeof(h) != TYPE_DICTIONARY or not (h as Dictionary).has("data") or typeof(h["data"]) != TYPE_DICTIONARY:
			return false
	return true


static func total_par(snap: Dictionary) -> int:
	var p := 0
	for h in snap.get("holes", []):
		p += int(h["par"])
	return p


## HoleDefinitions in play order with the frozen pars; [] when the snapshot is unusable.
static func hole_defs(snap: Dictionary) -> Array:
	var out: Array = []
	if not is_valid(snap):
		return out
	for h in snap["holes"]:
		var def := HoleDefinition.load_from_dict((h["data"] as Dictionary).duplicate(true), "snapshot:%s" % String(h["id"]))
		def.par = int(h["par"])
		out.append(def)
	return out

class_name CourseCombo
extends RefCounted
## Custom course combination: an ordered list of courses from data/courses.json played as ONE round.
## Encoded in a plain course id ("combo:starter+lakeside") so every place that already passes a course id
## (Round Setup, telemetry, the online setup dictionary) carries it unchanged. Pure logic, no App access.

const PREFIX := "combo:"
const MAX_COURSES := 6


static func is_combo(course_id: String) -> bool:
	return course_id.begins_with(PREFIX)


static func make_id(course_ids: Array) -> String:
	return PREFIX + "+".join(PackedStringArray(course_ids.map(func(c) -> String: return String(c))))


static func parse(course_id: String) -> Array:
	if not is_combo(course_id):
		return [course_id]
	return Array(course_id.trim_prefix(PREFIX).split("+", false))


## courses = App.courses() rows. Holes are concatenated in order; a hole id already played earlier in the
## list is skipped (hole ids key the scorecard, pars and telemetry), so overlapping courses are safe.
## Returns {} when no listed course matches.
static func info(course_id: String, courses: Array) -> Dictionary:
	var names: Array = []
	var holes: Array = []
	var seen := {}
	for cid in parse(course_id):
		for c in courses:
			if String(c.get("id", "")) != cid:
				continue
			names.append(String(c.get("name", cid)))
			for h in c.get("holes", []):
				if not seen.has(h):
					seen[h] = true
					holes.append(h)
			break
	if holes.is_empty():
		return {}
	var title := " + ".join(PackedStringArray(names))
	if names.size() > 2:
		title = "%d courses" % names.size()
	return {"id": course_id, "name": "Custom: " + title,
		"blurb": " + ".join(PackedStringArray(names)), "holes": holes}

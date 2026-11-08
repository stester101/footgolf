class_name Season
extends RefCounted
## Mini season: an ordered list of courses played back to back in one sitting (no save/resume).
## Each course is its own round (own History/telemetry entry). Points per course by finishing place,
## scaled by the number of holes: 1st 2.0 x holes, 2nd 1.2 x, 3rd 0.7 x, 4th 0.4 x, rounded to the nearest
## integer with a minimum of 1. Tied players share the average of the places they cover.
## One player: no points, the season is the sum of personal course scores. Pure logic, no App access.

const FACTORS := [2.0, 1.2, 0.7, 0.4]
const MAX_COURSES := 12

var courses: Array = []  # course ids in play order
var index := 0  # course being played
## One entry per finished course: {course, name, holes, par, names:[], strokes:[], rel:[], points:[]}
var results: Array = []


static func clean_course_ids(raw) -> Array:
	var out: Array = []
	if raw is Array:
		for v in raw:
			if v is String and not String(v).is_empty() and String(v).length() <= 160 and out.size() < MAX_COURSES:
				out.append(String(v))
	return out


static func create(course_ids: Array) -> Season:
	var s := Season.new()
	s.courses = clean_course_ids(course_ids)
	return s


func current_course() -> String:
	return String(courses[index]) if index < courses.size() else ""


func has_next() -> bool:
	return index + 1 < courses.size()


## Moves to the next course (no-op on the last one).
func advance() -> void:
	if has_next():
		index += 1


func is_finished() -> bool:
	return not courses.is_empty() and results.size() >= courses.size()


static func _rel_before(rels: Array, a: int, b: int) -> bool:
	if int(rels[a]) != int(rels[b]):
		return int(rels[a]) < int(rels[b])
	return a < b


## Points for one course. rels = strokes relative to par per player (lower wins). Same order as rels.
static func points_for(rels: Array, holes: int) -> Array:
	var order: Array = range(rels.size())
	order.sort_custom(func(a: int, b: int) -> bool: return _rel_before(rels, a, b))
	var out: Array = []
	out.resize(rels.size())
	var i := 0
	while i < order.size():
		var j := i
		while j + 1 < order.size() and int(rels[order[j + 1]]) == int(rels[order[i]]):
			j += 1
		var total := 0.0
		for k in range(i, j + 1):
			total += float(FACTORS[mini(k, FACTORS.size() - 1)])
		var pts := maxi(1, roundi(total / float(j - i + 1) * float(holes)))
		for k in range(i, j + 1):
			out[order[k]] = pts
		i = j + 1
	return out


## Places (1-based, ties share the lowest place) for one course, same order as rels.
static func places_for(rels: Array) -> Array:
	var out: Array = []
	for a in rels.size():
		var better := 0
		for b in rels.size():
			if int(rels[b]) < int(rels[a]):
				better += 1
		out.append(better + 1)
	return out


## Records (or replaces) the result of the course at `at` (idempotent, so every phone may call it).
func record_course(at: int, course_id: String, course_name: String, holes: int, par: int,
		names: Array, strokes: Array, rels: Array) -> void:
	var r := {"course": course_id, "name": course_name, "holes": holes, "par": par,
		"names": names.duplicate(), "strokes": strokes.duplicate(), "rel": rels.duplicate(),
		"points": points_for(rels, holes) if names.size() > 1 else []}
	while results.size() <= at:
		results.append({})
	results[at] = r


func player_count() -> int:
	if results.is_empty() or not results[0].has("names"):
		return 0
	return (results[0].names as Array).size()


## Season table, best first: [{name, seat, points, strokes, rel, place}]. Multi-player: by points (ties broken by
## total strokes relative to par; equal on both = same place). Single player: one row of summed scores.
func standings() -> Array:
	var rows: Array = []
	var n := player_count()
	for p in n:
		var row := {"name": "", "seat": p, "points": 0, "strokes": 0, "rel": 0}
		for r in results:
			if r.is_empty():
				continue
			row.name = String(r.names[p])
			row.points += int(r.points[p]) if (r.points as Array).size() > p else 0
			row.strokes += int(r.strokes[p])
			row.rel += int(r.rel[p])
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if n > 1 and a.points != b.points:
			return a.points > b.points
		if a.rel != b.rel:
			return a.rel < b.rel
		return a.seat < b.seat)
	var place := 1
	for i in rows.size():
		if i > 0 and (rows[i].points != rows[i - 1].points or rows[i].rel != rows[i - 1].rel):
			place = i + 1
		rows[i]["place"] = place
	return rows


## Names sharing first place in the season table.
func winners() -> Array:
	var out: Array = []
	for row in standings():
		if int(row.place) == 1:
			out.append(String(row.name))
	return out


func to_dict() -> Dictionary:
	return {"courses": courses.duplicate(), "index": index, "results": results.duplicate(true)}


static func from_dict(d: Dictionary) -> Season:
	var s := Season.create(d.get("courses", []))
	s.index = clampi(int(d.get("index", 0)), 0, maxi(s.courses.size() - 1, 0))
	var raw = d.get("results", [])
	if raw is Array:
		for r in raw:
			if r is Dictionary and r.get("names") is Array and r.get("strokes") is Array \
					and r.get("rel") is Array and r.get("points") is Array and s.results.size() < s.courses.size():
				s.results.append({"course": String(r.get("course", "")), "name": String(r.get("name", "")),
					"holes": int(r.get("holes", 0)), "par": int(r.get("par", 0)),
					"names": (r.names as Array).map(func(x) -> String: return String(x)),
					"strokes": (r.strokes as Array).map(func(x) -> int: return int(x)),
					"rel": (r.rel as Array).map(func(x) -> int: return int(x)),
					"points": (r.points as Array).map(func(x) -> int: return int(x))})
			else:
				break
	return s

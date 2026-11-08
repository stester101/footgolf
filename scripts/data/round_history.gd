class_name RoundHistory
extends RefCounted
## Finished-round history (user://history.json, versioned, atomic writes) and the personal bests
## derived from it. Records are plain JSON dictionaries; nothing here touches the UI or App.

const PATH := "user://history.json"
const VERSION := 1
const MAX_RECORDS := 500


# ------------------------------------------------------------------ build a record (pure)

## meta: {id, course_id, course_name, date (unix, optional)}. One entry per local player.
static func build_record(s: GameSession, meta: Dictionary) -> Dictionary:
	var players: Array = []
	var n := maxi(s.slots.size(), 1)
	for i in n:
		var rs: RoundState = s.slot_round_state(i)
		var holes: Array = []
		var best := {}
		var worst := {}
		for j in rs.holes.size():
			var hs: HoleState = rs.holes[j]
			if not hs.complete:
				continue
			var e := {"id": hs.hole_id, "name": hs.hole_name, "par": hs.par, "strokes": hs.strokes,
				"penalties": hs.penalties, "score": hs.score(), "to_par": hs.relative_to_par()}
			holes.append(e)
			if best.is_empty() or int(e["to_par"]) < int(best["to_par"]):
				best = e
			if worst.is_empty() or int(e["to_par"]) > int(worst["to_par"]):
				worst = e
		players.append({
			"name": s.player_names[i] if i < s.player_names.size() else "Player %d" % (i + 1),
			"score": rs.total_score(), "par": rs.total_par_played(), "to_par": rs.relative_to_par(),
			"strokes": rs.total_score() - rs.total_penalties(), "penalties": rs.total_penalties(),
			"holes": holes,
			"best_hole": _brief(best), "worst_hole": _brief(worst),
		})
	var winner := ""
	if players.size() > 1:
		var low := 999999
		for p in players:
			low = mini(low, int(p["score"]))
		var tied := 0
		for p in players:
			if int(p["score"]) == low:
				tied += 1
				winner = String(p["name"])
		if tied > 1:
			winner = ""
	return {
		"v": VERSION,
		"id": String(meta.get("id", "")),
		"course_id": String(meta.get("course_id", "")),
		"course_name": String(meta.get("course_name", "")),
		"date": int(meta.get("date", Time.get_unix_time_from_system())),
		"rules": rules_of(s),
		"players": players,
		"winner": winner,
	}


static func _brief(e: Dictionary) -> Dictionary:
	if e.is_empty():
		return {}
	return {"name": e["name"], "id": e["id"], "to_par": e["to_par"], "score": e["score"], "par": e["par"]}


## The rule set that applies to records ("per course and rule set").
static func rules_of(s: GameSession) -> Dictionary:
	return {"holeout_ft": s.holeout_radius_ft, "cup_in": snappedf(s.cfg.cup_radius * 2.0 / 0.0254, 0.1),
		"mulligans": s.round_state.mulligans_allowed, "once_per_mode": s.pool.reuse_rule == FootballerPool.ReuseRule.ONCE_PER_MODE,
		"wind_custom": s.wind_custom}


static func rules_key(r: Dictionary) -> String:
	return "%s|%s|%s|%s|%s" % [r.get("holeout_ft", 5), r.get("cup_in", 12), r.get("mulligans", 0), r.get("once_per_mode", false), r.get("wind_custom", false)]


static func rules_label(r: Dictionary) -> String:
	var mul := int(r.get("mulligans", 0))
	return "Cup %s in · hole-out %s ft · %s" % [_trim(float(r.get("cup_in", 12))), _trim(float(r.get("holeout_ft", 5))),
		"no mulligans" if mul == 0 else ("unlimited mulligans" if mul < 0 else "%d mulligans" % mul)]


static func _trim(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else "%.1f" % v


# ------------------------------------------------------------------ file

static func load_records(path: String = PATH) -> Array:
	var d = RoundSave.read_json(path)
	if typeof(d) != TYPE_DICTIONARY or int((d as Dictionary).get("history_version", -1)) != VERSION:
		return []
	var out: Array = []
	if typeof(d.get("records")) != TYPE_ARRAY:
		return []
	for r in d["records"]:
		if _valid(r):
			out.append(r)
	return out


static func _valid(r: Variant) -> bool:
	if typeof(r) != TYPE_DICTIONARY:
		return false
	for k in ["id", "course_id", "course_name", "date", "players", "rules"]:
		if not (r as Dictionary).has(k):
			return false
	if typeof(r["players"]) != TYPE_ARRAY or (r["players"] as Array).is_empty():
		return false
	for p in r["players"]:
		if typeof(p) != TYPE_DICTIONARY or not (p as Dictionary).has("score") or typeof(p.get("holes")) != TYPE_ARRAY:
			return false
	return true


## Adds a record; a record whose id is already stored (e.g. completed twice after a resume) is ignored.
static func append(record: Dictionary, path: String = PATH) -> bool:
	if not _valid(record):
		return false
	var recs := load_records(path)
	var id := String(record["id"])
	if id != "":
		for r in recs:
			if String(r["id"]) == id:
				return false
	recs.append(record)
	while recs.size() > MAX_RECORDS:
		recs.pop_front()
	return RoundSave.write_json_atomic(path, {"history_version": VERSION, "records": recs})


## Newest first.
static func recent(path: String = PATH) -> Array:
	var recs := load_records(path)
	recs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["date"]) > int(b["date"]))
	return recs


# ------------------------------------------------------------------ personal bests

## {rounds, holes, holes_in_one, birdies_or_better, best_hole: {...}, courses: [{course_id, course_name, rules_key,
## rules_label, rounds, best_score, best_to_par, best_player, best_date, avg_to_par}]}
static func records(recs: Array) -> Dictionary:
	var groups := {}
	var total_holes := 0
	var aces := 0
	var birdies := 0
	var best_hole := {}
	for r in recs:
		var rules: Dictionary = r.get("rules", {})
		var key := "%s#%s" % [r["course_id"], rules_key(rules)]
		var g: Dictionary = groups.get(key, {"course_id": r["course_id"], "course_name": r["course_name"], "rules_key": rules_key(rules),
			"rules_label": rules_label(rules), "rounds": 0, "best_score": 999999, "best_to_par": 999999, "best_player": "", "best_date": 0, "sum_to_par": 0, "n": 0})
		g["rounds"] = int(g["rounds"]) + 1
		for p in r["players"]:
			g["sum_to_par"] = int(g["sum_to_par"]) + int(p.get("to_par", 0))
			g["n"] = int(g["n"]) + 1
			if int(p["score"]) < int(g["best_score"]) or (int(p["score"]) == int(g["best_score"]) and int(r["date"]) > int(g["best_date"])):
				g["best_score"] = int(p["score"])
				g["best_to_par"] = int(p.get("to_par", 0))
				g["best_player"] = String(p.get("name", ""))
				g["best_date"] = int(r["date"])
			for h in p["holes"]:
				total_holes += 1
				if int(h["score"]) == 1:
					aces += 1
				if int(h["to_par"]) <= -1:
					birdies += 1
				if best_hole.is_empty() or int(h["to_par"]) < int(best_hole["to_par"]):
					best_hole = {"name": h["name"], "to_par": h["to_par"], "score": h["score"], "par": h["par"],
						"course_name": r["course_name"], "player": p.get("name", "")}
		groups[key] = g
	var courses: Array = []
	for k in groups:
		var g: Dictionary = groups[k]
		g["avg_to_par"] = float(g["sum_to_par"]) / maxf(1.0, float(g["n"]))
		courses.append(g)
	courses.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["course_name"]) < String(b["course_name"]) or (a["course_name"] == b["course_name"] and String(a["rules_key"]) < String(b["rules_key"])))
	return {"rounds": recs.size(), "holes": total_holes, "holes_in_one": aces, "birdies_or_better": birdies,
		"best_hole": best_hole, "courses": courses}

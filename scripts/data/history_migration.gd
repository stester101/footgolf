class_name HistoryMigration
extends RefCounted
## One-time, idempotent migration into the per-profile round history (RoundHistory, version 2):
##  1. history players without a profile_id (version-1 file) are assigned to the default (first) profile;
##  2. completed rounds found only in the telemetry log (rounds played before History existed) are imported as
##     single-player rounds of the default profile. Their stats are computed by StatsEngine and are "limited"
##     (N/A for shot-level metrics) when the log predates detailed shot records (format version 1).
## Nothing is deleted or rewritten in the telemetry log. Re-running adds nothing (ids are the telemetry round ids).

static var _done := false


## Runs at most once per app session unless `force`. Returns the number of rounds imported.
static func ensure(telemetry: TelemetryLog, default_profile_id: String, history_path: String = RoundHistory.PATH, force: bool = false) -> int:
	if _done and not force:
		return 0
	_done = true
	return run(telemetry, default_profile_id, history_path)


static func run(telemetry: TelemetryLog, default_profile_id: String, history_path: String = RoundHistory.PATH) -> int:
	var recs := RoundHistory.load_records(history_path)
	var changed := false
	for r in recs:
		for p in r["players"]:
			if not (p as Dictionary).has("profile_id"):
				p["profile_id"] = default_profile_id
				changed = true
	var have := {}
	for r in recs:
		have[String(r["id"])] = true
	var imported := 0
	var by_round := {}
	for d in telemetry.load_records():
		var rid := String(d.get("round_id", ""))
		if rid == "":
			continue
		if not by_round.has(rid):
			by_round[rid] = []
		(by_round[rid] as Array).append(d)
	for rid in by_round:
		if have.has(rid):
			continue
		var rec := from_telemetry(by_round[rid], default_profile_id)
		if rec.is_empty():
			continue
		recs.append(rec)
		have[rid] = true
		imported += 1
	if imported == 0 and not changed:
		return 0
	recs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["date"]) < int(b["date"]))
	while recs.size() > RoundHistory.MAX_RECORDS:
		recs.pop_front()
	RoundSave.write_json_atomic(history_path, {"history_version": RoundHistory.VERSION, "records": recs})
	return imported


## History record for one round's telemetry records, or {} when it is not importable (unfinished, developer course,
## or shots from several players whose scorecards the log cannot separate).
static func from_telemetry(records: Array, profile_id: String) -> Dictionary:
	var start := {}
	var end := {}
	var holes := {}
	for d in records:
		match String(d.get("type", "")):
			"round_start":
				start = d
			"round":
				end = d
			"hole":
				holes[String(d.get("hole_id", ""))] = d
	if start.is_empty() or end.is_empty() or String(start.get("course_id", "")) == "all":
		return {}
	var shots := TelemetryLog.played_shots(records)
	var players := {}
	for s in shots:
		players[int(s.get("player_idx", 0))] = true
	if players.size() > 1 or holes.is_empty():
		return {}
	var hole_list: Array = holes.values()
	hole_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("hole_index", 0)) < int(b.get("hole_index", 0)))
	var rows: Array = []
	var best := {}
	var worst := {}
	for h in hole_list:
		var row := {"id": String(h["hole_id"]), "name": String(h.get("hole_name", h["hole_id"])), "par": int(h["par"]),
			"strokes": int(h["strokes"]), "penalties": int(h["penalties"]), "score": int(h["score"]), "to_par": int(h["to_par"]),
			"completion": String(h.get("completion", ""))}
		rows.append(row)
		if best.is_empty() or int(row["to_par"]) < int(best["to_par"]):
			best = row
		if worst.is_empty() or int(row["to_par"]) > int(worst["to_par"]):
			worst = row
	var stats := StatsEngine.round_stats(shots, rows)
	var player := {"profile_id": profile_id, "name": "Player 1", "score": int(end["score"]), "par": int(end["par_played"]),
		"to_par": int(end["to_par"]), "strokes": int(end["strokes"]), "penalties": int(end["penalties"]),
		"holes": rows, "best_hole": RoundHistory._brief(best), "worst_hole": RoundHistory._brief(worst),
		"stats": stats, "legacy": int(end.get("v", 1)) < 2}
	var when := int(Time.get_unix_time_from_datetime_string(String(end.get("time", ""))))
	return {"v": RoundHistory.VERSION, "id": String(start["round_id"]), "course_id": String(start.get("course_id", "")),
		"course_name": String(start.get("course_name", start.get("course_id", ""))), "date": when,
		"rules": {"legacy": true, "mulligans": int(start.get("mulligans_allowed", 0))}, "players": [player], "winner": ""}

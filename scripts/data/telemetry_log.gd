class_name TelemetryLog
extends RefCounted
## On-device play telemetry: one JSON object per line in user://telemetry/round_<id>.jsonl.
## Record types: "round_start", "shot", "hole", "round" (round totals, written when a round completes).
## Attached to a GameSession from the presentation layer (round_controller); it only listens to
## the session's signals and never changes game state. Export helpers build CSV / JSON / text.

const DIR := "user://telemetry"
const FORMAT_VERSION := 1
const EXPORT_FALLBACK := "user://export"
const CLIPBOARD_MAX_SHOTS := 500

const SHOT_COLUMNS := ["round_id", "time", "course_id", "hole_id", "hole_index", "shot_no", "shot_id",
	"footballer_id", "footballer_name", "nationality", "mode", "style", "stat", "caps", "goals", "spin",
	"trajectory", "launch_angle_deg", "launch_speed_mps", "aim_bearing_deg", "wind_speed_mps", "wind_bearing_deg",
	"start_lie", "final_lie", "start_x", "start_y", "start_z", "end_x", "end_y", "end_z",
	"carry_m", "carry_yd", "roll_m", "total_m", "total_yd", "max_height_m", "bounces", "collisions",
	"hazard", "penalty", "holed", "pin_before_m", "pin_before_yd", "pin_after_m", "pin_after_yd",
	"hole_score_after", "time_in_motion_s", "end_reason", "developer_replay"]
const HOLE_COLUMNS := ["round_id", "time", "course_id", "hole_id", "hole_name", "hole_index", "par",
	"strokes", "penalties", "score", "to_par", "completion", "shots", "footballers"]
const ROUND_COLUMNS := ["round_id", "time", "course_id", "course_name", "round_seed", "holes", "holes_completed",
	"strokes", "penalties", "score", "par_played", "to_par", "shots", "duration_s"]

var dir := DIR
var enabled := true


func _init(p_dir: String = DIR) -> void:
	dir = p_dir


# ------------------------------------------------------------------ hooking a session

## Listen to a session. Call before session.start_round(); a later start_round() on the same
## session (restart / play again) is detected and logged as a new round.
func attach(session: GameSession, course_id: String, course_name: String = "") -> void:
	var ctx := {"course_id": course_id, "course_name": course_name if course_name != "" else course_id,
		"round_obj": -1, "round_id": "", "started_ms": 0, "round_logged": false}
	session.hole_started.connect(_on_hole_started.bind(session, ctx))
	session.shot_resolved.connect(_on_shot_resolved.bind(session, ctx))
	session.shot_mulliganed.connect(_on_shot_mulliganed.bind(session, ctx))
	session.hole_completed.connect(_on_hole_completed.bind(session, ctx))
	session.round_completed.connect(_on_round_completed.bind(session, ctx))


func _ensure_round(session: GameSession, ctx: Dictionary) -> void:
	var rid := session.round_state.get_instance_id()
	if int(ctx["round_obj"]) == rid:
		return
	ctx["round_obj"] = rid
	ctx["round_id"] = make_round_id(int(Time.get_unix_time_from_system()), session.round_state.round_seed)
	ctx["started_ms"] = Time.get_ticks_msec()
	ctx["round_logged"] = false
	append(String(ctx["round_id"]), round_start_record(ctx, session.round_state))


func _on_hole_started(_index: int, session: GameSession, ctx: Dictionary) -> void:
	_ensure_round(session, ctx)


func _on_shot_resolved(r: ShotResult, session: GameSession, ctx: Dictionary) -> void:
	_ensure_round(session, ctx)
	var hs := session.current_hole_state()
	var shot_no := hs.shots.find(r) + 1 if hs != null else 0
	var cup := session.hole.cup_position() if session.hole != null else r.final_pos
	append(String(ctx["round_id"]), shot_record(ctx, r, session.last_request, cup, shot_no, session.round_state.current_index))


func _on_shot_mulliganed(r: ShotResult, session: GameSession, ctx: Dictionary) -> void:
	_ensure_round(session, ctx)
	append(String(ctx["round_id"]), {"type": "mulligan", "v": FORMAT_VERSION,
		"round_id": ctx["round_id"], "time": _now_iso(), "shot_id": r.shot_id,
		"hole_id": r.hole_id, "mulligans_used": session.round_state.mulligans_used})


func _on_hole_completed(hs: HoleState, session: GameSession, ctx: Dictionary) -> void:
	_ensure_round(session, ctx)
	append(String(ctx["round_id"]), hole_record(ctx, hs, session.round_state.holes.find(hs)))


func _on_round_completed(session: GameSession, ctx: Dictionary) -> void:
	_ensure_round(session, ctx)
	if bool(ctx["round_logged"]):
		return
	ctx["round_logged"] = true
	var dur := (Time.get_ticks_msec() - int(ctx["started_ms"])) / 1000.0
	append(String(ctx["round_id"]), round_record(ctx, session.round_state, dur))


# ------------------------------------------------------------------ records (pure)

static func make_round_id(unix_time: int, round_seed: int) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d%02d%02d-%02d%02d%02d-%04d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"], absi(round_seed) % 10000]


static func _now_iso() -> String:
	return Time.get_datetime_string_from_system(false, true)


static func _r(v: float, digits: int = 3) -> float:
	var k := pow(10.0, digits)
	return roundf(v * k) / k


static func _vec(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]


## Reads an optional property (e.g. a field another version may not have) without erroring.
static func opt(obj: Object, prop: String, fallback = null):
	if obj == null or not (prop in obj):
		return fallback
	var v = obj.get(prop)
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return v
		TYPE_VECTOR3:
			return _vec(v)
		TYPE_ARRAY, TYPE_DICTIONARY:
			return JSON.parse_string(JSON.stringify(v))
	return str(v)


static func round_start_record(ctx: Dictionary, rs: RoundState) -> Dictionary:
	var pars: Array = []
	for h in rs.holes:
		pars.append((h as HoleState).par)
	return {"type": "round_start", "v": FORMAT_VERSION, "round_id": ctx.get("round_id", ""), "time": _now_iso(),
		"course_id": ctx.get("course_id", ""), "course_name": ctx.get("course_name", ""),
		"round_seed": rs.round_seed, "holes": Array(rs.hole_ids), "pars": pars,
		"mulligans_allowed": rs.mulligans_allowed}


static func shot_record(ctx: Dictionary, r: ShotResult, req: Object, cup: Vector3, shot_no: int, hole_index: int) -> Dictionary:
	var before := Units.horizontal_distance(r.start_pos, cup)
	var after := 0.0 if r.holed else r.remaining_m
	var traj := ShotTypes.trajectory_name(r.trajectory)
	return {"type": "shot", "v": FORMAT_VERSION, "round_id": ctx.get("round_id", ""), "time": _now_iso(),
		"course_id": ctx.get("course_id", ""), "hole_id": r.hole_id, "hole_index": hole_index,
		"shot_no": shot_no, "shot_id": r.shot_id,
		"footballer_id": r.footballer_id, "footballer_name": r.footballer_name, "nationality": r.nationality,
		"mode": r.mode_name(), "style": ShotTypes.style_name(r.style), "stat": r.stat_value, "caps": r.caps, "goals": r.goals,
		"spin": _r(r.spin), "trajectory": traj,
		"launch_angle_deg": _r(r.launch_angle_deg, 2), "launch_speed_mps": _r(r.launch_speed_mps),
		"aim_bearing_deg": _r(r.aim_bearing_deg, 2),
		"wind_speed_mps": _r(r.wind_speed_mps), "wind_bearing_deg": _r(r.wind_bearing_deg, 1),
		"start_lie": Surface.name_of(r.start_lie), "final_lie": Surface.name_of(r.final_lie),
		"start_pos": _vec(r.start_pos), "end_pos": _vec(r.final_pos),
		"carry_m": _r(r.carry_m), "carry_yd": _r(Units.m_to_yards(r.carry_m), 2),
		"roll_m": _r(r.roll_m), "total_m": _r(r.total_m), "total_yd": _r(Units.m_to_yards(r.total_m), 2),
		"max_height_m": _r(r.max_height_m, 2), "bounces": r.bounces, "collisions": r.collisions.size(),
		"hazard": r.hazard, "penalty": r.penalty, "holed": r.holed,
		"pin_before_m": _r(before), "pin_before_yd": _r(Units.m_to_yards(before), 2),
		"pin_after_m": _r(after), "pin_after_yd": _r(Units.m_to_yards(after), 2),
		"hole_score_after": r.hole_score_after, "time_in_motion_s": _r(r.time_in_motion_s, 2),
		"end_reason": r.end_reason, "developer_replay": r.developer_replay}


static func hole_record(ctx: Dictionary, hs: HoleState, hole_index: int) -> Dictionary:
	return {"type": "hole", "v": FORMAT_VERSION, "round_id": ctx.get("round_id", ""), "time": _now_iso(),
		"course_id": ctx.get("course_id", ""), "hole_id": hs.hole_id, "hole_name": hs.hole_name,
		"hole_index": hole_index, "par": hs.par, "strokes": hs.strokes, "penalties": hs.penalties,
		"score": hs.score(), "to_par": hs.relative_to_par(), "completion": hs.completion,
		"shots": hs.shots.size(), "footballers": Array(hs.used_footballer_ids)}


static func round_record(ctx: Dictionary, rs: RoundState, duration_s: float = 0.0) -> Dictionary:
	var strokes := 0
	var shots := 0
	for h in rs.holes:
		strokes += (h as HoleState).strokes
		shots += (h as HoleState).shots.size()
	return {"type": "round", "v": FORMAT_VERSION, "round_id": ctx.get("round_id", ""), "time": _now_iso(),
		"course_id": ctx.get("course_id", ""), "course_name": ctx.get("course_name", ""),
		"round_seed": rs.round_seed, "holes": rs.holes.size(), "holes_completed": rs.holes_completed(),
		"strokes": strokes, "penalties": rs.total_penalties(), "score": rs.total_score(),
		"par_played": rs.total_par_played(), "to_par": rs.relative_to_par(), "shots": shots,
		"mulligans_used": rs.mulligans_used,
		"duration_s": _r(duration_s, 1)}


# ------------------------------------------------------------------ storage

func round_path(round_id: String) -> String:
	return "%s/round_%s.jsonl" % [dir, round_id.validate_filename()]


func append(round_id: String, rec: Dictionary) -> bool:
	if not enabled or round_id == "":
		return false
	DirAccess.make_dir_recursive_absolute(dir)
	var path := round_path(round_id)
	var f: FileAccess
	if FileAccess.file_exists(path):
		f = FileAccess.open(path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_line(JSON.stringify(rec))
	f.close()
	return true


func files() -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var names := DirAccess.get_files_at(dir)
	names.sort()
	for n in names:
		if n.ends_with(".jsonl"):
			out.append("%s/%s" % [dir, n])
	return out


## All records, oldest round file first, in write order. Corrupt lines are skipped.
func load_records() -> Array:
	var out: Array = []
	for p in files():
		out.append_array(parse_lines(FileAccess.get_file_as_string(p)))
	return out


static func parse_lines(text: String) -> Array:
	var out: Array = []
	var j := JSON.new()
	for line in text.split("\n", false):
		if j.parse(line) != OK:
			continue  # corrupt / truncated line (e.g. app killed mid-write)
		var d = j.data
		if typeof(d) == TYPE_DICTIONARY and d.has("type"):
			out.append(d)
	return out


func clear() -> int:
	var n := 0
	for p in files():
		if DirAccess.remove_absolute(p) == OK:
			n += 1
	return n


# ------------------------------------------------------------------ export

static func of_type(records: Array, type: String) -> Array:
	return records.filter(func(d) -> bool: return String(d.get("type", "")) == type)


static func csv_cell(v) -> String:
	var s: String
	match typeof(v):
		TYPE_NIL:
			s = ""
		TYPE_BOOL:
			s = "1" if v else "0"
		TYPE_FLOAT:
			s = String.num(v, 3) if not is_equal_approx(v, roundf(v)) else str(int(v))
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for x in v:
				parts.append(str(x))
			s = ";".join(parts)
		_:
			s = str(v)
	if s.contains(",") or s.contains("\"") or s.contains("\n") or s.contains("\r"):
		s = "\"%s\"" % s.replace("\"", "\"\"")
	return s


static func _flatten_shot(d: Dictionary) -> Dictionary:
	var o := d.duplicate()
	for pair in [["start_pos", "start_"], ["end_pos", "end_"]]:
		var a = d.get(pair[0], [])
		if typeof(a) == TYPE_ARRAY and (a as Array).size() == 3:
			o[pair[1] + "x"] = a[0]
			o[pair[1] + "y"] = a[1]
			o[pair[1] + "z"] = a[2]
	return o


static func to_csv(rows: Array, columns: Array) -> String:
	var lines := PackedStringArray([",".join(PackedStringArray(columns))])
	for d in rows:
		var row := _flatten_shot(d) if String((d as Dictionary).get("type", "")) == "shot" else (d as Dictionary)
		var cells := PackedStringArray()
		for c in columns:
			cells.append(csv_cell(row.get(c)))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


static func shots_csv(records: Array) -> String:
	return to_csv(played_shots(records), SHOT_COLUMNS)


## The append-only log retains discarded shots as an audit trail; exports and records
## only include shots that were not followed by a matching mulligan event.
static func played_shots(records: Array) -> Array:
	var kept: Array = []
	for record in records:
		var d: Dictionary = record
		if d.get("type", "") == "shot":
			kept.append(d)
		elif d.get("type", "") == "mulligan":
			for i in range(kept.size() - 1, -1, -1):
				if kept[i].get("round_id") == d.get("round_id") \
						and kept[i].get("shot_id") == d.get("shot_id") \
						and kept[i].get("hole_id") == d.get("hole_id"):
					kept.remove_at(i)
					break
	return kept


static func holes_csv(records: Array) -> String:
	return to_csv(of_type(records, "hole"), HOLE_COLUMNS)


static func rounds_csv(records: Array) -> String:
	return to_csv(of_type(records, "round"), ROUND_COLUMNS)


static func _fmt_rel(r: int) -> String:
	return RoundState.fmt_relative(r)


## Human-readable summary (rounds with their holes, aggregate shot stats), then the shots CSV.
static func summary_text(records: Array, include_csv: bool = true) -> String:
	var shots := played_shots(records)
	var rounds := of_type(records, "round_start")
	var ends := {}
	for d in of_type(records, "round"):
		ends[String(d["round_id"])] = d
	var holes_by_round := {}
	for d in of_type(records, "hole"):
		var rid := String(d["round_id"])
		if not holes_by_round.has(rid):
			holes_by_round[rid] = []
		holes_by_round[rid].append(d)
	var lines := PackedStringArray()
	lines.append("Football Golf data summary (%s)" % _now_iso())
	if records.is_empty():
		lines.append("No data recorded yet.")
		return "\n".join(lines) + "\n"
	var caps_n := 0
	var caps_carry := 0.0
	var goals_n := 0
	var goals_total := 0.0
	var pens := 0
	var holed := 0
	for s in shots:
		if String(s.get("mode", "")) == ShotTypes.mode_name(ShotTypes.Mode.CAPS):
			caps_n += 1
			caps_carry += float(s.get("carry_yd", 0.0))
		else:
			goals_n += 1
			goals_total += Units.m_to_feet(float(s.get("total_m", 0.0)))
		pens += int(s.get("penalty", 0))
		holed += 1 if bool(s.get("holed", false)) else 0
	lines.append("Rounds: %d (%d completed) · holes completed: %d · shots: %d" % [rounds.size(), ends.size(), of_type(records, "hole").size(), shots.size()])
	lines.append("Caps shots: %d (avg carry %.1f yd) · Goals shots: %d (avg %.1f ft) · penalties: %d · holed: %d" % [
		caps_n, caps_carry / maxi(caps_n, 1), goals_n, goals_total / maxi(goals_n, 1), pens, holed])
	for rs in rounds:
		var rid := String(rs["round_id"])
		lines.append("")
		var head := "Round %s · %s" % [rid, rs.get("course_name", rs.get("course_id", ""))]
		if ends.has(rid):
			var e: Dictionary = ends[rid]
			head += " · %d (%s) · %d shots" % [int(e["score"]), _fmt_rel(int(e["to_par"])), int(e["shots"])]
		else:
			head += " · not finished"
		lines.append(head)
		for h in holes_by_round.get(rid, []):
			lines.append("  %s par %d: %d (%s) · %d strokes + %d pen · %s" % [h.get("hole_name", h.get("hole_id", "")), int(h["par"]),
				int(h["score"]), _fmt_rel(int(h["to_par"])), int(h["strokes"]), int(h["penalties"]), h.get("completion", "")])
	if include_csv and not shots.is_empty():
		lines.append("")
		var tail := shots.slice(maxi(0, shots.size() - CLIPBOARD_MAX_SHOTS))
		lines.append("Shots CSV (%d of %d, most recent):" % [tail.size(), shots.size()])
		return "\n".join(lines) + "\n" + to_csv(tail, SHOT_COLUMNS)
	return "\n".join(lines) + "\n"


## Writable export folders, best first: shared Documents / Downloads on Android, then user://export.
static func export_dir_candidates() -> Array[String]:
	var out: Array[String] = []
	if OS.get_name() == "Android":
		for sd in [OS.SYSTEM_DIR_DOCUMENTS, OS.SYSTEM_DIR_DOWNLOADS]:
			var p := OS.get_system_dir(sd)
			if p != "":
				out.append(p.path_join("FootballGolf"))
	out.append(EXPORT_FALLBACK)
	return out


static func _writable(d: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(d) != OK and not DirAccess.dir_exists_absolute(d):
		return false
	var probe := d.path_join(".write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("ok")
	f.close()
	DirAccess.remove_absolute(probe)
	return true


## Writes shots/holes/rounds CSV + all records as JSON. Returns {ok, dir, files, error}.
func export_files(dest_dirs: Array = []) -> Dictionary:
	var records := load_records()
	var candidates: Array = dest_dirs if not dest_dirs.is_empty() else Array(export_dir_candidates())
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "-")
	var outputs := {
		"football_golf_%s_shots.csv" % stamp: shots_csv(records),
		"football_golf_%s_holes.csv" % stamp: holes_csv(records),
		"football_golf_%s_rounds.csv" % stamp: rounds_csv(records),
		"football_golf_%s_all.json" % stamp: JSON.stringify({"format_version": FORMAT_VERSION,
			"exported": _now_iso(), "records": records}, " "),
	}
	for d in candidates:
		var ds := String(d)
		if not _writable(ds):
			continue
		var written: Array[String] = []
		var ok := true
		for name in outputs.keys():
			var f := FileAccess.open(ds.path_join(name), FileAccess.WRITE)
			if f == null:
				ok = false
				break
			f.store_string(String(outputs[name]))
			f.close()
			written.append(name)
		if ok:
			var shown := ProjectSettings.globalize_path(ds) if ds.begins_with("user://") or ds.begins_with("res://") else ds
			return {"ok": true, "dir": shown, "files": written, "records": records.size(), "error": ""}
	return {"ok": false, "dir": "", "files": [], "records": records.size(), "error": "no writable export folder"}

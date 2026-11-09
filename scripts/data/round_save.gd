class_name RoundSave
extends RefCounted
## Save & resume for unfinished OFFLINE rounds (solo and pass-and-play). Pure data layer: it reads
## and writes GameSession fields, never touches App or the UI.
##
## One versioned JSON file per unfinished round in user://saves/round_<id>.json, written atomically
## (temp file + rename). Round objects reuse NetCodec's JSON-safe encoding. A save is only taken at a
## stable moment (hole intro, aiming, shot result, hole complete), never while a ball is moving, and a
## resumed round continues at the hole intro of the current hole (or the next hole after a finished one).

## 2 = full frozen RoundConfig ("rules") + profile ids; 1 (no rules) still loads with default rules.
const VERSION := 2
const MIN_VERSION := 1
const DIR := "user://saves"
const MAX_SAVES := 20


# ------------------------------------------------------------------ files

static func path_for(id: String, dir: String = DIR) -> String:
	return "%s/round_%s.json" % [dir, id]


static func is_valid_id(id: String) -> bool:
	return id != "" and id.length() <= 64 and id.is_valid_filename() and not id.contains(".")


static func write_json_atomic(path: String, data: Variant) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true


static func read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var j := JSON.new()  # instance parse: a corrupt file returns an error code instead of logging an engine ERROR
	if j.parse(f.get_as_text()) != OK:
		return null
	return j.data


static func write(data: Dictionary, dir: String = DIR) -> bool:
	var id := String(data.get("id", ""))
	if not is_valid_id(id):
		return false
	return write_json_atomic(path_for(id, dir), data)


## The parsed save, or an empty Dictionary when missing, corrupt or from another version.
static func load_save(id: String, dir: String = DIR) -> Dictionary:
	if not is_valid_id(id):
		return {}
	var d = read_json(path_for(id, dir))
	if typeof(d) != TYPE_DICTIONARY or not validate(d):
		return {}
	return d


static func delete(id: String, dir: String = DIR) -> void:
	if is_valid_id(id) and FileAccess.file_exists(path_for(id, dir)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_for(id, dir)))


## Summaries of every readable save, newest first. Unreadable or old-version files are skipped.
static func list_saves(dir: String = DIR) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for fn in DirAccess.get_files_at(dir):
		if not (fn.begins_with("round_") and fn.ends_with(".json")):
			continue
		var id := fn.trim_prefix("round_").trim_suffix(".json")
		var d := load_save(id, dir)
		if d.is_empty():
			continue
		var sm: Dictionary = d["summary"]
		out.append({"id": id, "course_id": d["course_id"], "course_name": d["course_name"],
			"saved_at": int(d["saved_at"]), "holes_done": int(sm["holes_done"]), "holes_total": int(sm["holes_total"]),
			"hole_index": int(sm["hole_index"]), "players": sm["players"]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["saved_at"]) > int(b["saved_at"]))
	return out


## Keep the newest MAX_SAVES saves.
static func prune(dir: String = DIR) -> void:
	var all := list_saves(dir)
	for i in range(MAX_SAVES, all.size()):
		delete(String(all[i]["id"]), dir)


static func make_id(unix_time: int, round_seed: int) -> String:
	return TelemetryLog.make_round_id(unix_time, round_seed)


# ------------------------------------------------------------------ validation

static func validate(d: Dictionary) -> bool:
	var ver := int(d.get("save_version", -1))
	if ver < MIN_VERSION or ver > VERSION:
		return false
	for k in ["id", "course_id", "course_name", "saved_at", "resume", "turn", "hole_index", "player_names",
			"pars", "pool", "settings", "slots", "summary", "shot_counter"]:
		if not d.has(k):
			return false
	if typeof(d["slots"]) != TYPE_ARRAY or (d["slots"] as Array).is_empty() or (d["slots"] as Array).size() > 4:
		return false
	if typeof(d["player_names"]) != TYPE_ARRAY or (d["player_names"] as Array).size() != (d["slots"] as Array).size():
		return false
	if typeof(d["summary"]) != TYPE_DICTIONARY or typeof(d["pool"]) != TYPE_DICTIONARY or typeof(d["settings"]) != TYPE_DICTIONARY:
		return false
	for k in ["holes_done", "holes_total", "hole_index", "players"]:
		if not (d["summary"] as Dictionary).has(k):
			return false
	if not String(d["resume"]) in ["play", "hole_complete"]:
		return false
	var turn := int(d["turn"])
	return turn >= 0 and turn < (d["slots"] as Array).size()


# ------------------------------------------------------------------ capture

## Can the session be saved right now? (not while the ball is moving or before the first shot)
static func can_capture(s: GameSession) -> bool:
	if s.slots.is_empty() or s.hole == null:
		return false
	if not s.state in [ShotTypes.State.HOLE_INTRO, ShotTypes.State.AIMING, ShotTypes.State.SHOT_RESULT, ShotTypes.State.HOLE_COMPLETE]:
		return false
	return s.shot_counter > 0 or s.round_state.mulligans_used > 0


## meta: {id, course_id, course_name, telemetry_round_id, created_at}. Does not change gameplay state.
static func capture(s: GameSession, meta: Dictionary) -> Dictionary:
	if not can_capture(s):
		return {}
	s._save_active()
	var resume := "play"
	var turn := s.turn
	if s.state == ShotTypes.State.HOLE_COMPLETE:
		resume = "hole_complete"
	elif s.state == ShotTypes.State.SHOT_RESULT:
		# resume exactly where acknowledge_result() would have gone
		if s.slots.size() > 1:
			var nxt := s._next_unfinished()
			if nxt < 0:
				resume = "hole_complete"
			else:
				turn = nxt
		elif s.current_hole_state().complete:
			resume = "hole_complete"
	var slots_out: Array = []
	var pars := {}
	var player_sum: Array = []
	for i in s.slots.size():
		var sl: GameSession.PlayerSlot = s.slots[i]
		slots_out.append({"round_state": NetCodec.encode(sl.round_state), "ball_pos": NetCodec.encode(sl.ball_pos),
			"last_safe_pos": NetCodec.encode(sl.last_safe_pos), "aim": sl.aim})
		var strokes := 0
		for h in sl.round_state.holes:
			var hs: HoleState = h
			pars[hs.hole_id] = hs.par
			strokes += hs.raw_total()
		player_sum.append({"name": s.player_names[i] if i < s.player_names.size() else "Player %d" % (i + 1),
			"strokes": strokes, "to_par": sl.round_state.relative_to_par(), "holes_done": sl.round_state.holes_completed()})
	var rs0: RoundState = (s.slots[0] as GameSession.PlayerSlot).round_state
	var data := {
		"save_version": VERSION,
		"id": String(meta["id"]),
		"course_id": String(meta.get("course_id", "")),
		"course_name": String(meta.get("course_name", "")),
		"telemetry_round_id": String(meta.get("telemetry_round_id", "")),
		"created_at": int(meta.get("created_at", Time.get_unix_time_from_system())),
		"saved_at": int(Time.get_unix_time_from_system()),
		"resume": resume,
		"turn": turn,
		"hole_index": s.round_state.current_index,
		"player_names": s.player_names.duplicate(),
		"profile_ids": s.profile_ids.duplicate(),
		"rules": s.rules.to_dict(),
		"mulligans": rs0.mulligans_allowed,
		"players": s.slots.size(),
		"pars": pars,
		"pool": s.pool.snapshot(),
		"hole_start_pool": s._hole_start_pool.duplicate(true),
		"shot_counter": s.shot_counter,
		"state_version": s.state_version,
		"next_is_replacement": s._next_is_replacement,
		"settings": {
			"cfg": s.cfg.to_dict(), "holeout_radius_ft": s.holeout_radius_ft, "wind_custom": s.wind_custom,
			"wind_custom_speed": s.wind_custom_speed, "wind_custom_bearing": s.wind_custom_bearing,
			"lie_override": s.lie_override, "force_surface": s.force_surface,
		},
		"slots": slots_out,
		"summary": {"holes_done": rs0.holes_completed() if s.slots.size() == 1 else _min_done(s),
			"holes_total": rs0.holes.size(), "hole_index": s.round_state.current_index, "players": player_sum},
	}
	if turn == s.turn:
		data["pre_shot"] = {"mode": s.mode, "style": s.style, "spin": s.spin, "trajectory": s.trajectory, "selected_id": s.selected_id}
	if s.last_result != null:
		data["last_result"] = NetCodec.encode(s.last_result)
	if s.last_request != null:
		data["last_request"] = NetCodec.encode(s.last_request)
	return data


## The frozen RoundConfig stored in a save (defaults for a version-1 save).
static func rules_of(d: Dictionary) -> RoundConfig:
	return RoundConfig.from_dict(d.get("rules", {})) if typeof(d.get("rules")) == TYPE_DICTIONARY else RoundConfig.new()


static func mulligans_of(d: Dictionary) -> int:
	return int(d.get("mulligans", 0))


static func players_of(d: Dictionary) -> int:
	return clampi(int(d.get("players", (d.get("slots", [1]) as Array).size())), 1, 4)


static func _min_done(s: GameSession) -> int:
	var m := 999
	for sl in s.slots:
		m = mini(m, (sl as GameSession.PlayerSlot).round_state.holes_completed())
	return m


# ------------------------------------------------------------------ restore

static func _vec(v: Variant) -> Variant:
	var d = NetCodec.decode(v)
	return d if d is Vector3 else null


## Rebuild `s` from a save. `defs` are the course's HoleDefinitions (same ids, in order); saved pars are
## applied to them. Returns false (and leaves the session untouched) if the save does not fit.
## Emits hole_started so the presentation builds the hole; the round continues at the hole intro.
static func restore(s: GameSession, data: Dictionary, defs: Array) -> bool:
	if not validate(data):
		return false
	var new_slots: Array = []
	for sd in data["slots"]:
		if typeof(sd) != TYPE_DICTIONARY:
			return false
		var rs = NetCodec.decode(sd.get("round_state"))
		var bp = _vec(sd.get("ball_pos"))
		var sp = _vec(sd.get("last_safe_pos"))
		if not (rs is RoundState) or bp == null or sp == null:
			return false
		var round_state: RoundState = rs
		if round_state.holes.size() != defs.size() or round_state.current_index < 0 or round_state.current_index >= defs.size():
			return false
		for i in defs.size():
			if not (round_state.holes[i] is HoleState) or (round_state.holes[i] as HoleState).hole_id != (defs[i] as HoleDefinition).id:
				return false
		var sl := GameSession.PlayerSlot.new()
		sl.round_state = round_state
		sl.ball_pos = bp
		sl.last_safe_pos = sp
		sl.aim = float(sd.get("aim", 0.0))
		new_slots.append(sl)
	var idx := int(data["hole_index"])
	if idx < 0 or idx >= defs.size():
		return false
	# ---- everything decoded: apply
	var pars: Dictionary = data["pars"]
	for d in defs:
		var hd: HoleDefinition = d
		if pars.has(hd.id):
			hd.par = int(pars[hd.id])
	var st: Dictionary = data["settings"]
	var cfg := PhysicsConfig.new()
	if typeof(st.get("cfg")) == TYPE_DICTIONARY:
		cfg.apply_dict(st["cfg"])
	s.cfg = cfg
	s.holeout_radius_ft = ScoringService.clamp_radius_ft(float(st.get("holeout_radius_ft", ScoringService.DEFAULT_HOLEOUT_FT)))
	s.wind_custom = bool(st.get("wind_custom", false))
	s.wind_custom_speed = float(st.get("wind_custom_speed", 0.0))
	s.wind_custom_bearing = float(st.get("wind_custom_bearing", 0.0))
	s.lie_override = int(st.get("lie_override", -1))
	s.force_surface = bool(st.get("force_surface", false))
	s.rules = rules_of(data)
	s.wind_scale = s.rules.wind_multiplier()
	var round_seed := (new_slots[0] as GameSession.PlayerSlot).round_state.round_seed
	for d in defs:  # same tee box and seeded pin as the original round
		(d as HoleDefinition).apply_round_options(s.rules.tee_color, s.rules.pin_varied, round_seed)
	s.hole_defs = defs
	s.slots = new_slots
	s.profile_ids.clear()
	for pid in data.get("profile_ids", []):
		s.profile_ids.append(String(pid))
	s.player_names.clear()
	for n in data["player_names"]:
		s.player_names.append(String(n))
	s.pool.restore(_int_pool(data["pool"]))
	s._hole_start_pool = _int_pool(data.get("hole_start_pool", data["pool"]))
	s.shot_counter = int(data["shot_counter"])
	s.state_version = int(data.get("state_version", 0))
	s._next_is_replacement = bool(data.get("next_is_replacement", false))
	# the shared shot log is every player's shots in firing order
	var hist: Array = []
	for sl in new_slots:
		for h in (sl as GameSession.PlayerSlot).round_state.holes:
			hist.append_array((h as HoleState).shots)
	hist.sort_custom(func(a: ShotResult, b: ShotResult) -> bool: return a.shot_id < b.shot_id)
	s.history = hist
	var lr = NetCodec.decode(data.get("last_result"))
	s.last_result = lr if lr is ShotResult else null
	var lq = NetCodec.decode(data.get("last_request"))
	s.last_request = lq if lq is ShotRequest else null
	s.undo_stack.clear()
	s.sim = null
	s._accum = 0.0
	var turn := int(data["turn"])
	s.turn = turn
	var sl: GameSession.PlayerSlot = new_slots[turn]
	s.round_state = sl.round_state
	s.ball_pos = sl.ball_pos
	s.last_safe_pos = sl.last_safe_pos
	s.aim_bearing_deg = sl.aim
	s.selected_id = ""
	if String(data["resume"]) == "hole_complete":
		# every player finished this hole: carry on at the next unfinished hole
		var nxt := s.round_state.upcoming_index()
		if nxt < 0:
			return false
		s.round_state.current_index = idx
		s.hole = defs[idx]
		s.start_hole(nxt)
		return true
	for slot in new_slots:
		(slot as GameSession.PlayerSlot).round_state.current_index = idx
	s.hole = defs[idx]
	var pre = data.get("pre_shot")
	if typeof(pre) == TYPE_DICTIONARY:
		s.mode = int(pre.get("mode", s.mode))
		s.style = int(pre.get("style", s.style))
		s.spin = float(pre.get("spin", 0.0))
		s.trajectory = int(pre.get("trajectory", ShotTypes.Trajectory.STANDARD))
		var sel := String(pre.get("selected_id", ""))
		if sel != "" and s.repo.has(sel) and s.pool.is_available(sel, s.mode):
			s.selected_id = sel
	else:
		s.aim_at_pin()
		s.apply_lie_defaults()
	s._set_state(ShotTypes.State.HOLE_INTRO)
	s.hole_started.emit(idx)
	s.ball_placed.emit()
	s.selection_changed.emit()
	return true


## JSON turns integers into floats; the pool's order counters and entries must be ints again.
static func _int_pool(snap: Dictionary) -> Dictionary:
	var used := {}
	var saved = snap.get("used", {})
	if typeof(saved) == TYPE_DICTIONARY:
		for id in saved:
			var e = saved[id]
			if typeof(e) == TYPE_DICTIONARY:
				var o := {}
				for k in e:
					o[String(k)] = int(e[k])
				used[String(id)] = o
	return {"used": used, "order": int(snap.get("order", 0)), "reuse_rule": int(snap.get("reuse_rule", FootballerPool.ReuseRule.ONCE_PER_ROUND))}

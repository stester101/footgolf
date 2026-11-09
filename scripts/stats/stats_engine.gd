class_name StatsEngine
extends RefCounted
## Pure round + lifetime metrics. Exact definitions: docs/STATS_DEFINITIONS.md.
## Input is the authoritative telemetry shot record (TelemetryLog.shot_record) of ONE player, already
## filtered to counted shots (replaced / undone shots removed), plus that player's hole scorecard rows.
## null = not applicable / not reliably computable (never a nominal value).

const VERSION := 1
const ACC_KEYS := ["approach_carry_yd", "approach_total_yd", "putt_total_ft", "caps_total_yd", "goals_total_ft",
	"caps_gain_yd", "goals_gain_yd", "caps_remaining_yd", "goals_remaining_yd"]


static func _acc_new() -> Dictionary:
	return {"n": 0, "sum": 0.0, "max": 0.0}


static func _acc_add(a: Dictionary, v: float) -> void:
	a["n"] = int(a["n"]) + 1
	a["sum"] = float(a["sum"]) + v
	a["max"] = maxf(float(a["max"]), v) if int(a["n"]) > 1 else v


static func acc_merge(a: Dictionary, b: Dictionary) -> void:
	if int(b.get("n", 0)) == 0:
		return
	a["max"] = maxf(float(a["max"]), float(b["max"])) if int(a["n"]) > 0 else float(b["max"])
	a["n"] = int(a["n"]) + int(b["n"])
	a["sum"] = float(a["sum"]) + float(b["sum"])


static func acc_avg(a: Variant) -> Variant:
	if a == null or int((a as Dictionary).get("n", 0)) == 0:
		return null
	return float(a["sum"]) / float(a["n"])


static func acc_max(a: Variant) -> Variant:
	if a == null or int((a as Dictionary).get("n", 0)) == 0:
		return null
	return float(a["max"])


static func _f(v: Variant) -> Variant:
	return float(v) if (v is float or v is int) else null


## holes: [{id, name, par, strokes, penalties, score, to_par, completion}] (completed holes only).
## shots: counted shot records of this player in play order (all holes).
static func round_stats(shots: Array, holes: Array) -> Dictionary:
	var out := {"stats_version": VERSION, "level": "full", "limited_reason": ""}
	# ---- scorecard metrics (always reliable)
	var strokes := 0
	var pens := 0
	var score := 0
	var par := 0
	var birdies := 0
	var pars := 0
	var bogeys := 0
	var aces := 0
	for h in holes:
		strokes += int(h["strokes"])
		pens += int(h["penalties"])
		score += int(h["score"])
		par += int(h["par"])
		var tp := int(h["to_par"])
		if tp <= -1:
			birdies += 1
		elif tp == 0:
			pars += 1
		else:
			bogeys += 1
		if int(h["score"]) == 1:
			aces += 1
	out.merge({"holes_played": holes.size(), "strokes": strokes, "penalties": pens, "score": score, "par": par,
		"to_par": score - par, "birdies_or_better": birdies, "pars": pars, "bogeys_plus": bogeys, "aces": aces})
	# ---- group counted shots by hole
	var by_hole := {}
	for s in shots:
		var hid := String(s.get("hole_id", ""))
		if not by_hole.has(hid):
			by_hole[hid] = []
		(by_hole[hid] as Array).append(s)
	var reason := _limited_reason(shots, holes, by_hole)
	# ---- usage (mode + footballers) needs only the mode / footballer fields
	var caps_n := 0
	var goals_n := 0
	var fb := {}
	for s in shots:
		if String(s.get("mode", "")) == "GOALS":
			goals_n += 1
		else:
			caps_n += 1
		var fid := String(s.get("footballer_id", ""))
		if fid != "":
			var e: Dictionary = fb.get(fid, {"id": fid, "name": String(s.get("footballer_name", fid)), "n": 0})
			e["n"] = int(e["n"]) + 1
			fb[fid] = e
	out.merge({"shots": shots.size(), "caps_shots": caps_n, "goals_shots": goals_n, "footballers": fb.values()})
	for k in ACC_KEYS:
		out[k] = null
	out.merge({"fairways": null, "gir": null, "putts": null, "caps_holed": null, "goals_holed": null, "hole_rows": []})
	var rows: Array = []
	for h in holes:
		rows.append({"id": h["id"], "name": h["name"], "par": h["par"], "strokes": h["strokes"], "penalties": h["penalties"],
			"score": h["score"], "to_par": h["to_par"], "putts": null, "fairway": null, "gir": null})
	out["hole_rows"] = rows
	if reason != "":
		out["level"] = "limited"
		out["limited_reason"] = reason
		return out
	# ---- full shot-level metrics
	var accs := {}
	for k in ACC_KEYS:
		accs[k] = _acc_new()
	var fw_hit := 0
	var fw_elig := 0
	var gir_hit := 0
	var putts := 0
	var caps_holed := 0
	var goals_holed := 0
	for i in holes.size():
		var h: Dictionary = holes[i]
		var hs: Array = by_hole.get(String(h["id"]), [])
		var row: Dictionary = rows[i]
		var par_h := int(h["par"])
		var cum := 0
		var gir_done := false
		var hole_putts := 0
		for j in hs.size():
			var s: Dictionary = hs[j]
			var pen := int(s.get("penalty", 0))
			cum += int(s.get("stroke_delta", 1)) + pen
			var holed := bool(s.get("holed", false))
			if j == 0 and par_h >= 4:
				fw_elig += 1
				var hit: bool = String(s.get("final_lie", "")) == "Fairway" and pen == 0
				row["fairway"] = hit
				fw_hit += 1 if hit else 0
			if not gir_done and pen == 0 and (holed or bool(s.get("on_green_end", false))):
				gir_done = true
				row["gir"] = cum <= par_h - 2
			if String(s.get("start_lie", "")) == "Green":
				hole_putts += 1
			_accumulate(accs, s)
			if holed:
				if String(s.get("mode", "")) == "GOALS":
					goals_holed += 1
				else:
					caps_holed += 1
		if not gir_done:
			row["gir"] = false
		gir_hit += 1 if bool(row["gir"]) else 0
		row["putts"] = hole_putts
		putts += hole_putts
	for k in ACC_KEYS:
		out[k] = accs[k]
	out["fairways"] = {"hit": fw_hit, "eligible": fw_elig}
	out["gir"] = {"hit": gir_hit, "holes": holes.size()}
	out["putts"] = putts
	out["caps_holed"] = caps_holed
	out["goals_holed"] = goals_holed
	return out


static func _accumulate(accs: Dictionary, s: Dictionary) -> void:
	var is_putt := String(s.get("shot_type", "")) == "Putt"
	var goals := String(s.get("mode", "")) == "GOALS"
	var total_m = _f(s.get("total_m"))
	var carry_yd = _f(s.get("carry_yd"))
	var before = _f(s.get("pin_before_m"))
	var after = _f(s.get("pin_after_m"))
	if total_m != null:
		var yd: float = Units.m_to_yards(total_m)
		var ft: float = Units.m_to_feet(total_m)
		if is_putt:
			_acc_add(accs["putt_total_ft"], ft)
		else:
			_acc_add(accs["approach_total_yd"], yd)
		_acc_add(accs["goals_total_ft"] if goals else accs["caps_total_yd"], ft if goals else yd)
	if carry_yd != null and not is_putt:
		_acc_add(accs["approach_carry_yd"], carry_yd)
	if before != null and after != null:
		var pre := "goals" if goals else "caps"
		_acc_add(accs[pre + "_gain_yd"], Units.m_to_yards(before - after))
		_acc_add(accs[pre + "_remaining_yd"], Units.m_to_yards(after))


## "" when the shot-level metrics are reliable, else why not.
static func _limited_reason(shots: Array, holes: Array, by_hole: Dictionary) -> String:
	if holes.is_empty():
		return "no completed holes"
	var n := 0
	var pens := 0
	for s in shots:
		if int(s.get("v", 1)) < 2:
			return "recorded before detailed shot tracking"
		n += 1
		pens += int(s.get("penalty", 0))
	var strokes := 0
	var hp := 0
	for h in holes:
		strokes += int(h["strokes"])
		hp += int(h["penalties"])
		if not by_hole.has(String(h["id"])):
			return "shots missing for a hole"
	if n != strokes or pens != hp:
		return "shot log does not match the scorecard"
	return ""


# ------------------------------------------------------------------ building from a session / log

## Counted shot records of one player slot, straight from the authoritative HoleState shots (replaced and
## undone shots are no longer there), in the telemetry record format.
static func shot_records_of(s: GameSession, slot: int) -> Array:
	var out: Array = []
	var rs := s.slot_round_state(slot)
	for j in rs.holes.size():
		var hs: HoleState = rs.holes[j]
		var cup := (s.hole_defs[j] as HoleDefinition).cup_position() if j < s.hole_defs.size() else Vector3.ZERO
		for k in hs.shots.size():
			out.append(TelemetryLog.shot_record({}, hs.shots[k], null, cup, k + 1, j,
				{"seq": (hs.shots[k] as ShotResult).shot_id, "player_idx": slot,
				"player_id": s.profile_ids[slot] if slot < s.profile_ids.size() else "",
				"player_name": s.player_names[slot] if slot < s.player_names.size() else "", "par": hs.par}))
	return out


static func hole_rows_of(rs: RoundState) -> Array:
	var rows: Array = []
	for h in rs.holes:
		var hs: HoleState = h
		if hs.complete:
			rows.append({"id": hs.hole_id, "name": hs.hole_name, "par": hs.par, "strokes": hs.strokes,
				"penalties": hs.penalties, "score": hs.score(), "to_par": hs.relative_to_par(), "completion": hs.completion})
	return rows


static func round_stats_of(s: GameSession, slot: int) -> Dictionary:
	return round_stats(shot_records_of(s, slot), hole_rows_of(s.slot_round_state(slot)))


# ------------------------------------------------------------------ lifetime

## Aggregates round_stats dictionaries (of one profile). Shot-level metrics only use rounds whose level is "full".
static func lifetime(stat_list: Array) -> Dictionary:
	var L := {"rounds": stat_list.size(), "full_rounds": 0, "holes": 0, "strokes": 0, "penalties": 0, "score": 0, "par": 0,
		"birdies_or_better": 0, "pars": 0, "bogeys_plus": 0, "aces": 0, "shots": 0, "caps_shots": 0, "goals_shots": 0,
		"fw_hit": 0, "fw_elig": 0, "gir_hit": 0, "gir_holes": 0, "putts": 0, "full_holes": 0,
		"caps_holed": 0, "goals_holed": 0}
	var accs := {}
	for k in ACC_KEYS:
		accs[k] = _acc_new()
	var fb := {}
	for st in stat_list:
		var d: Dictionary = st
		for k in ["holes_played:holes", "strokes:strokes", "penalties:penalties", "score:score", "par:par",
				"birdies_or_better:birdies_or_better", "pars:pars", "bogeys_plus:bogeys_plus", "aces:aces",
				"shots:shots", "caps_shots:caps_shots", "goals_shots:goals_shots"]:
			var kv := (k as String).split(":")
			L[kv[1]] = int(L[kv[1]]) + int(d.get(kv[0], 0))
		for f in d.get("footballers", []):
			var e: Dictionary = fb.get(f["id"], {"id": f["id"], "name": f["name"], "n": 0})
			e["n"] = int(e["n"]) + int(f["n"])
			fb[f["id"]] = e
		if String(d.get("level", "limited")) != "full":
			continue
		L["full_rounds"] = int(L["full_rounds"]) + 1
		L["full_holes"] = int(L["full_holes"]) + int(d["holes_played"])
		L["fw_hit"] = int(L["fw_hit"]) + int(d["fairways"]["hit"])
		L["fw_elig"] = int(L["fw_elig"]) + int(d["fairways"]["eligible"])
		L["gir_hit"] = int(L["gir_hit"]) + int(d["gir"]["hit"])
		L["gir_holes"] = int(L["gir_holes"]) + int(d["gir"]["holes"])
		L["putts"] = int(L["putts"]) + int(d["putts"])
		L["caps_holed"] = int(L["caps_holed"]) + int(d["caps_holed"])
		L["goals_holed"] = int(L["goals_holed"]) + int(d["goals_holed"])
		for k in ACC_KEYS:
			acc_merge(accs[k], d[k])
	L["to_par"] = int(L["score"]) - int(L["par"])
	L["acc"] = accs
	var f_list: Array = fb.values()
	f_list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["n"]) > int(b["n"]) or (int(a["n"]) == int(b["n"]) and String(a["name"]) < String(b["name"])))
	L["footballers_used"] = f_list.size()
	L["top_footballers"] = f_list.slice(0, 3)
	return L


## Fraction 0..1, or null when the denominator is 0 (N/A).
static func ratio(num: int, den: int) -> Variant:
	return null if den <= 0 else float(num) / float(den)


static func fmt_pct(r: Variant) -> String:
	return "N/A" if r == null else "%d%%" % int(round(float(r) * 100.0))


static func fmt_num(v: Variant, digits: int = 1, unit: String = "") -> String:
	if v == null:
		return "N/A"
	return ("%." + str(digits) + "f%s") % [float(v), unit]


## Simple trend: average to-par per round of the newest `n` rounds minus the previous `n`. rounds newest first.
## null when fewer than 2n rounds.
static func trend_to_par(newest_first_to_par: Array, n: int = 3) -> Variant:
	if newest_first_to_par.size() < 2 * n:
		return null
	var a := 0.0
	var b := 0.0
	for i in n:
		a += float(newest_first_to_par[i])
		b += float(newest_first_to_par[n + i])
	return (a - b) / float(n)

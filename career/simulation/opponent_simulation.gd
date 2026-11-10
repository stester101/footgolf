class_name OpponentSimulation
extends RefCounted
## Mathematical opponent scoring (never ball physics). Pure, deterministic, Dictionary in / Dictionary out.
## course_info = {par:int (per round), holes:int, difficulty:float (optional strokes/hole offset, default 0)}.
## Round indices are 0-based. See career/simulation/README.md for result shapes.


static func field_strength(field: Array) -> float:
	var sum := 0.0
	var n := 0
	for g in field:
		if bool(g.get("is_human", false)) or not g.has("rating"):
			continue
		sum += float(g["rating"])
		n += 1
	return sum / float(n) if n > 0 else CareerConfig.FIELD_STRENGTH_REFERENCE


static func mean_per_hole(golfer: Dictionary, category: String, course_info: Dictionary, strength: float, adaptive: float) -> float:
	var rating: float = float(golfer.get("rating", 70.0))
	var t: float = clampf((rating - CareerConfig.RATING_MIN) / (CareerConfig.RATING_MAX - CareerConfig.RATING_MIN), 0.0, 1.0)
	var m: float = lerpf(CareerConfig.MEAN_PER_HOLE_WORST, CareerConfig.MEAN_PER_HOLE_BEST, t)
	m += float(CareerConfig.EVENT_DIFFICULTY_PER_HOLE.get(category, 0.0))
	m += float(course_info.get("difficulty", 0.0))
	m -= clampf(float(golfer.get("form", 0.0)), -1.0, 1.0) * CareerConfig.FORM_EFFECT_PER_HOLE
	m += CareerConfig.FIELD_STRENGTH_SCORE_EFFECT * (strength - CareerConfig.FIELD_STRENGTH_REFERENCE) / CareerConfig.FIELD_STRENGTH_REFERENCE
	var cap: float = CareerConfig.ADAPTIVE_MAX_ADJUST_PER_HOLE
	m += clampf(adaptive, -cap, cap)
	return m


static func round_sd(golfer: Dictionary, holes: int) -> float:
	var c: float = clampf(float(golfer.get("consistency", 0.6)), 0.0, 1.0)
	return CareerConfig.SD_PER_SQRT_HOLE * sqrt(float(holes)) * (1.5 - c)


## One golfer, one round. `strength` = field strength (default reference); the adaptive-difficulty hook is
## event["adaptive_adjust"] (strokes per hole, capped, default 0 = unused).
static func simulate_round(golfer: Dictionary, course_info: Dictionary, event: Dictionary, round_index: int, career_seed: int, strength: float = -1.0) -> Dictionary:
	var holes: int = maxi(1, int(course_info.get("holes", 9)))
	var par: int = int(course_info.get("par", holes * 4))
	if strength < 0.0:
		strength = CareerConfig.FIELD_STRENGTH_REFERENCE
	var category: String = str(event.get("category", "regular"))
	var mean: float = mean_per_hole(golfer, category, course_info, strength, float(event.get("adaptive_adjust", 0.0))) * float(holes)
	var rng := SimRng.make(career_seed, str(event.get("id", "")), round_index, str(golfer.get("id", "")))
	var strokes: int = int(round(float(par) + mean + rng.randfn(0.0, 1.0) * round_sd(golfer, holes)))
	var lo: int = int(ceil(CareerConfig.MIN_STROKES_PER_HOLE * holes))
	var hi: int = par + int(ceil(CareerConfig.MAX_OVER_PAR_PER_HOLE * holes))
	strokes = clampi(strokes, lo, hi)
	return {"strokes": strokes, "to_par": strokes - par}


## Full event. `human_rounds` = the player's strokes per completed round (entry with is_human = true).
## through_round (-1 = all) limits how many rounds are revealed (leaderboard mid-event); the cut is applied
## once the cut round is included. The human entry is "incomplete" until it has the rounds required.
static func simulate_event_field(field: Array, event: Dictionary, course_info: Dictionary, career_seed: int, human_rounds: Array = [], through_round: int = -1) -> Dictionary:
	var total_rounds: int = int(event.get("rounds", 2))
	var upto: int = total_rounds if through_round < 0 else mini(through_round, total_rounds)
	var par: int = int(course_info.get("par", 0))
	var strength: float = field_strength(field)
	var event_id: String = str(event.get("id", ""))
	var entries: Array = []
	for g in field:
		var is_human: bool = bool(g.get("is_human", false))
		var e := {
			"id": str(g.get("id", "")), "name": str(g.get("name", "")), "nationality": str(g.get("nationality", "")),
			"is_human": is_human, "rounds": [], "status": "made_cut", "incomplete": false,
			"total": 0, "to_par": 0, "position": 0, "tied": false, "position_label": "-",
			"payout": 0, "world_points": 0.0, "season_points": 0.0, "playoff": false,
		}
		if is_human:
			for r in range(mini(human_rounds.size(), upto)):
				e["rounds"].append(int(human_rounds[r]))
			e["incomplete"] = e["rounds"].size() < upto
		else:
			for r in range(upto):
				e["rounds"].append(int(simulate_round(g, course_info, event, r, career_seed, strength)["strokes"]))
		entries.append(e)

	# --- cut
	var cut_info := {}
	var cut: Dictionary = event.get("cut", {"type": "none"})
	var ctype: String = str(cut.get("type", "none"))
	var after: int = int(cut.get("after_round", CareerConfig.CUT_AFTER_ROUND))
	if ctype != "none" and upto >= after and after < total_rounds:
		var eligible: Array = []
		for e in entries:
			if e["rounds"].size() >= after:
				eligible.append(e)
		if not eligible.is_empty():
			var totals: Array = []
			for e in eligible:
				totals.append(_sum(e["rounds"], after))
			totals.sort()
			var n: int
			if ctype == "top_n":
				n = int(cut.get("n", 65))
			else:
				n = int(ceil(float(eligible.size()) * float(cut.get("percent", CareerConfig.CUT_PERCENT)) / 100.0))
			n = clampi(n, 1, totals.size())
			var line: int = int(totals[n - 1])
			var made := 0
			for e in eligible:
				if _sum(e["rounds"], after) > line:
					e["status"] = "cut"
					e["rounds"] = e["rounds"].slice(0, after)
					e["incomplete"] = false   # out of the event: nothing further to wait for
				else:
					made += 1
			cut_info = {"type": ctype, "after_round": after, "line_total": line, "line_to_par": line - par * after, "made_cut": made, "missed_cut": eligible.size() - made}

	# --- totals and positions
	for e in entries:
		e["total"] = _sum(e["rounds"], e["rounds"].size())
		e["to_par"] = int(e["total"]) - par * e["rounds"].size()
	var alive: Array = []
	var cut_list: Array = []
	var incomplete: Array = []
	for e in entries:
		if e["incomplete"]:
			e["status"] = "incomplete"
			incomplete.append(e)
		elif e["status"] == "cut":
			cut_list.append(e)
		else:
			alive.append(e)
	alive.sort_custom(_by_total)
	cut_list.sort_custom(_by_total)
	incomplete.sort_custom(_by_total)
	var next_pos := _assign_positions(alive, 1)
	_assign_positions(cut_list, next_pos)
	var ordered: Array = alive + cut_list + incomplete

	var result := {
		"event_id": event_id, "category": str(event.get("category", "regular")), "rounds_played": upto,
		"complete": upto >= total_rounds and incomplete.is_empty(), "par_per_round": par,
		"field_size": entries.size(), "field_strength": strength, "cut": cut_info,
		"leaderboard": ordered, "winner_id": "",
		"playoff": {"needed": false, "tied_ids": [], "human_involved": false, "resolved": false},
	}
	if result["complete"] and not alive.is_empty():
		var tied: Array = []
		for e in alive:
			if int(e["position"]) == 1:
				tied.append(e["id"])
		if tied.size() == 1:
			result["winner_id"] = tied[0]
		else:
			var human := false
			for e in alive:
				if int(e["position"]) == 1 and e["is_human"]:
					human = true
			result["playoff"] = {"needed": true, "tied_ids": tied, "human_involved": human, "resolved": false}
			if not human:
				var tied_golfers: Array = []
				for g in field:
					if tied.has(str(g.get("id", ""))):
						tied_golfers.append(g)
				var po := sudden_death(tied_golfers, event, course_info, career_seed)
				apply_playoff_result(result, po["groups"], event, course_info)
				result["playoff"]["holes"] = po["holes"]
	compute_awards(result, event)
	return result


## Re-order the tied-for-first golfers after a playoff. `groups` = ids best to worst, ties as inner arrays
## (e.g. [["a"], ["b","c"]]). Re-runs positions and awards. Used for AI playoffs (automatic) and for human
## ties (the caller plays the playoff and supplies the order).
static func apply_playoff_result(result: Dictionary, groups: Array, event: Dictionary, _course_info: Dictionary = {}) -> void:
	var lb: Array = result["leaderboard"]
	var by_id := {}
	for e in lb:
		by_id[e["id"]] = e
	var pos := 1
	for grp in groups:
		for id in grp:
			var e: Dictionary = by_id[id]
			e["position"] = pos
			e["tied"] = grp.size() > 1
			e["playoff"] = true
		pos += grp.size()
	var tied_count: int = result["playoff"]["tied_ids"].size()
	# remaining (non-playoff) entries keep their positions
	for e in lb:
		e["position_label"] = _label(int(e["position"]), bool(e["tied"]), str(e["status"]))
	lb.sort_custom(_by_position_then_total)
	result["winner_id"] = str(groups[0][0]) if not groups.is_empty() and groups[0].size() == 1 else ""
	result["playoff"]["resolved"] = true
	result["playoff"]["groups"] = groups
	result["playoff"]["count"] = tied_count
	compute_awards(result, event)


## Payouts and points from final positions (idempotent). Ties share the average of the places they occupy.
## Only golfers who made the cut and finished earn money/points.
static func compute_awards(result: Dictionary, event: Dictionary) -> void:
	var lb: Array = result["leaderboard"]
	var paid: Array = []
	for e in lb:
		if e["status"] == "made_cut" and not e["incomplete"]:
			paid.append(e)
	var n: int = paid.size()
	var category: String = str(result.get("category", "regular"))
	var purse: float = float(event.get("purse", CareerConfig.PURSE.get(category, 0)))
	var d: float = CareerConfig.PAYOUT_DECAY
	var pd: float = CareerConfig.POINTS_DECAY_PER_PLACE
	var share_sum := 0.0
	for i in range(n):
		share_sum += pow(d, i)
	var pts_w: Dictionary = _points_config(event, category)
	var strength_factor: float = (1.0 - CareerConfig.FIELD_STRENGTH_BLEND) + CareerConfig.FIELD_STRENGTH_BLEND * float(result.get("field_strength", CareerConfig.FIELD_STRENGTH_REFERENCE)) / CareerConfig.FIELD_STRENGTH_REFERENCE
	for e in lb:
		e["payout"] = 0
		e["world_points"] = 0.0
		e["season_points"] = 0.0
	if n == 0 or not result.get("complete", false):
		return
	var i := 0
	while i < n:
		var j := i
		while j + 1 < n and int(paid[j + 1]["position"]) == int(paid[i]["position"]):
			j += 1
		var money := 0.0
		var wp := 0.0
		var sp := 0.0
		for k in range(i, j + 1):
			money += purse * pow(d, k) / share_sum
			wp += float(pts_w["world"]) * pow(pd, k)
			sp += float(pts_w["season"]) * pow(pd, k)
		var cnt: float = float(j - i + 1)
		for k in range(i, j + 1):
			paid[k]["payout"] = int(floor(money / cnt))
			paid[k]["world_points"] = snappedf(wp / cnt * strength_factor, 0.01)
			paid[k]["season_points"] = snappedf(sp / cnt, 0.01)
		i = j + 1


static func _points_config(event: Dictionary, category: String) -> Dictionary:
	var world: float = float(CareerConfig.WINNER_POINTS.get(category, 0))
	var season: float = float(CareerConfig.SEASON_WINNER_POINTS.get(category, 0))
	var p = event.get("points", null)
	if p is Dictionary:
		world = float(p.get("world", world))
		season = float(p.get("season", season))
	elif p != null and (p is int or p is float):
		world = float(p)
		season = float(p) if category != "finale" else 0.0
	return {"world": world, "season": season}


## Sudden-death playoff between golfers (dicts with id/rating/form/consistency). Hole by hole all survivors
## score; only the lowest score(s) continue. Returns {winner_id, groups (best to worst, ties inner), holes}.
static func sudden_death(golfers: Array, event: Dictionary, course_info: Dictionary, career_seed: int) -> Dictionary:
	var survivors: Array = []
	for g in golfers:
		survivors.append(g)
	var eliminated: Array = []   # groups, first eliminated first
	var holes_log: Array = []
	var strength := CareerConfig.FIELD_STRENGTH_REFERENCE
	var category: String = str(event.get("category", "regular"))
	var ci := {"par": CareerConfig.PLAYOFF_HOLE_PAR, "holes": 1, "difficulty": course_info.get("difficulty", 0.0)}
	var hole := 1
	while survivors.size() > 1 and hole <= CareerConfig.PLAYOFF_MAX_HOLES:
		var scores := {}
		var best := 999
		for g in survivors:
			var rng := SimRng.make(career_seed, str(event.get("id", "")), 1000 + hole, str(g["id"]), "playoff")
			var mean := mean_per_hole(g, category, ci, strength, float(event.get("adaptive_adjust", 0.0)))
			var s: int = clampi(int(round(float(CareerConfig.PLAYOFF_HOLE_PAR) + mean + rng.randfn(0.0, 1.0) * round_sd(g, 1))), 2, CareerConfig.PLAYOFF_HOLE_PAR + 3)
			scores[g["id"]] = s
			best = mini(best, s)
		var keep: Array = []
		var out: Array = []
		for g in survivors:
			if int(scores[g["id"]]) == best:
				keep.append(g)
			else:
				out.append(str(g["id"]))
		if not out.is_empty():
			eliminated.append(out)
		holes_log.append({"hole": hole, "scores": scores})
		survivors = keep
		hole += 1
	var groups: Array = []
	if survivors.size() > 1:
		# still level after the cap: seeded draw decides, singletons
		var order: Array = []
		for g in survivors:
			var rng2 := SimRng.make(career_seed, str(event.get("id", "")), 2000, str(g["id"]), "playoff_draw")
			order.append([rng2.randf(), str(g["id"])])
		order.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		for o in order:
			groups.append([o[1]])
	if survivors.size() == 1:
		groups.append([str(survivors[0]["id"])])
	for k in range(eliminated.size() - 1, -1, -1):
		groups.append(eliminated[k])
	return {"winner_id": str(groups[0][0]) if not groups.is_empty() else "", "groups": groups, "holes": holes_log}


# --- helpers
static func _sum(arr: Array, count: int) -> int:
	var s := 0
	for i in range(mini(count, arr.size())):
		s += int(arr[i])
	return s


static func _by_total(a: Dictionary, b: Dictionary) -> bool:
	if int(a["total"]) != int(b["total"]):
		return int(a["total"]) < int(b["total"])
	return str(a["id"]) < str(b["id"])


static func _by_position_then_total(a: Dictionary, b: Dictionary) -> bool:
	var ga: int = _group_rank(a)
	var gb: int = _group_rank(b)
	if ga != gb:
		return ga < gb
	if int(a["position"]) != int(b["position"]):
		return int(a["position"]) < int(b["position"])
	return _by_total(a, b)


static func _group_rank(e: Dictionary) -> int:
	return {"made_cut": 0, "cut": 1, "incomplete": 2}.get(str(e["status"]), 3)


## Assigns shared positions to a total-sorted list; returns the next free position.
static func _assign_positions(sorted_list: Array, start: int) -> int:
	var i := 0
	var n := sorted_list.size()
	while i < n:
		var j := i
		while j + 1 < n and int(sorted_list[j + 1]["total"]) == int(sorted_list[i]["total"]):
			j += 1
		for k in range(i, j + 1):
			sorted_list[k]["position"] = start + i
			sorted_list[k]["tied"] = j > i
			sorted_list[k]["position_label"] = _label(start + i, j > i, str(sorted_list[k]["status"]))
		i = j + 1
	return start + n


static func _label(pos: int, tied: bool, status: String) -> String:
	if status == "incomplete":
		return "-"
	return ("T%d" % pos) if tied else str(pos)

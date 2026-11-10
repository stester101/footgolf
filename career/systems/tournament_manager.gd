class_name TournamentManager
extends RefCounted
## Pure tournament logic on the `active_tournament` Dictionary (shape: career/models/README.md): creating it,
## recording rounds, simulating the opponents (through `sim.simulate_round`), cuts, leaderboard, final result,
## prize money and season points. No App, no UI, no I/O. The human is the id "player".
## TODO (documented, not approved): sudden-death playoffs (ties for 1st share the win, id order decides the
## trophy for now); proper World Ranking points (RankingManager); adaptive difficulty (adaptive = 0).

const PLAYER := "player"


static func create(event: Dictionary, snapshot: Dictionary, field_ids: Array, p_seed: int) -> Dictionary:
	return {
		"id": "t_%s" % String(event["id"]), "event": event.duplicate(true), "snapshot": snapshot.duplicate(true),
		"field": field_ids.duplicate(), "status": "setup", "round_index": 0, "human_rounds": [],
		"opponent_rounds": {}, "cut": {"applied": false, "line_total": 0, "survivors": [], "human_made": true},
		"rules": {}, "mulligans": 0, "round_save": {}, "sim_seed": p_seed, "finalized": false, "has_human": true,
	}


static func course_info(t: Dictionary) -> Dictionary:
	var holes: Array = (t["snapshot"] as Dictionary).get("holes", [])
	return {"holes": holes.size(), "par": CourseSnapshot.total_par(t["snapshot"]), "difficulty": 0.0}


static func par_per_round(t: Dictionary) -> int:
	return CourseSnapshot.total_par(t["snapshot"])


## Opponent ids still playing round `r` (everyone before the cut, survivors after it).
static func active_opponents(t: Dictionary, _r: int) -> Array:
	if bool((t["cut"] as Dictionary)["applied"]):
		var out: Array = []
		for id in (t["cut"] as Dictionary)["survivors"]:
			if String(id) != PLAYER:
				out.append(String(id))
		return out
	return (t["field"] as Array).duplicate()


## Simulates round `r` (0-based) for the opponents still in and stores the scores. Idempotent: a round that already
## has scores for every active opponent is never rerolled.
static func simulate_opponent_round(t: Dictionary, golfers_by_id: Dictionary, r: int, sim: Object) -> void:
	var need: Array = []
	for id in active_opponents(t, r):
		var rounds: Array = (t["opponent_rounds"] as Dictionary).get(id, [])
		if rounds.size() <= r:
			need.append(golfers_by_id[id] if golfers_by_id.has(id) else {"id": id, "rating": 60.0, "consistency": 0.5, "form": 0.0})
	if need.is_empty():
		return
	var scores: Dictionary = sim.simulate_round(need, t["event"], r, course_info(t), int(t["sim_seed"]), 0.0)
	for g in need:
		var id := String(g["id"])
		var arr: Array = (t["opponent_rounds"] as Dictionary).get(id, [])
		arr.append(int(scores[id]))
		(t["opponent_rounds"] as Dictionary)[id] = arr


## totals (strokes so far) of everyone who has played `rounds_done` rounds.
static func totals_after(t: Dictionary, rounds_done: int) -> Dictionary:
	var out := {}
	for id in t["field"]:
		var a: Array = (t["opponent_rounds"] as Dictionary).get(id, [])
		if a.size() >= rounds_done:
			var s := 0
			for i in rounds_done:
				s += int(a[i])
			out[String(id)] = s
	if bool(t["has_human"]):
		var h: Array = t["human_rounds"]
		if h.size() >= rounds_done:
			var s2 := 0
			for i in rounds_done:
				s2 += int((h[i] as Dictionary)["strokes"])
			out[PLAYER] = s2
	return out


## Cut line: returns {line_total, survivors}. type percent|top_n, always "and ties". "none" keeps everyone.
static func compute_cut(totals: Dictionary, cut: Dictionary) -> Dictionary:
	var ids: Array = totals.keys()
	var type := String(cut.get("type", "none"))
	if type == "none" or ids.is_empty():
		return {"line_total": 0, "survivors": ids}
	var sorted: Array = totals.values()
	sorted.sort()
	var keep := 0
	if type == "percent":
		keep = int(ceil(float(ids.size()) * float(cut["percent"]) / 100.0))
	else:
		keep = int(cut["n"])
	keep = clampi(keep, 1, ids.size())
	var line := int(sorted[keep - 1])
	var surv: Array = []
	for id in ids:
		if int(totals[id]) <= line:
			surv.append(id)
	return {"line_total": line, "survivors": surv}


## Records the human's finished round and moves the tournament on (opponent round, cut, status).
## Returns the new status. After a missed cut the opponents' remaining rounds are simulated at once.
static func record_human_round(t: Dictionary, golfers_by_id: Dictionary, strokes: int, par: int, holes: int, sim: Object) -> String:
	var r := (t["human_rounds"] as Array).size()
	(t["human_rounds"] as Array).append({"strokes": strokes, "par": par, "holes": holes})
	simulate_opponent_round(t, golfers_by_id, r, sim)
	return _after_round(t, golfers_by_id, r, sim)


static func _after_round(t: Dictionary, golfers_by_id: Dictionary, r: int, sim: Object) -> String:
	var ev: Dictionary = t["event"]
	var cut: Dictionary = ev["cut"]
	var cs: Dictionary = t["cut"]
	if String(cut.get("type", "none")) != "none" and r + 1 == int(cut["after_round"]) and not bool(cs["applied"]):
		var res := compute_cut(totals_after(t, r + 1), cut)
		cs["applied"] = true
		cs["line_total"] = int(res["line_total"])
		cs["survivors"] = res["survivors"]
		cs["human_made"] = (res["survivors"] as Array).has(PLAYER) if bool(t["has_human"]) else true
	if r + 1 >= int(ev["rounds"]):
		t["status"] = "complete"
	elif not bool(cs["human_made"]):
		for rr in range(r + 1, int(ev["rounds"])):
			simulate_opponent_round(t, golfers_by_id, rr, sim)
		t["status"] = "complete"
		t["human_missed_cut"] = true
	else:
		t["status"] = "between_rounds"
		t["round_index"] = r + 1
	if t["status"] == "complete":
		t["round_save"] = {}
	return String(t["status"])


## Plays the whole event for the opponents only (skipped event): no human.
static func simulate_all(t: Dictionary, golfers_by_id: Dictionary, sim: Object) -> void:
	t["has_human"] = false
	for r in int(t["event"]["rounds"]):
		simulate_opponent_round(t, golfers_by_id, r, sim)
		var cut: Dictionary = t["event"]["cut"]
		var cs: Dictionary = t["cut"]
		if String(cut.get("type", "none")) != "none" and r + 1 == int(cut["after_round"]) and not bool(cs["applied"]):
			var res := compute_cut(totals_after(t, r + 1), cut)
			cs["applied"] = true
			cs["line_total"] = int(res["line_total"])
			cs["survivors"] = res["survivors"]
	t["status"] = "complete"


## Rows for the leaderboard, best first. Only rounds already played are included (no future scores leak).
## Row: {id, name, nationality, rounds:[strokes], total, rel, thru_rounds, is_human, cut:bool, place:int, tied:bool}
static func leaderboard(t: Dictionary, golfers_by_id: Dictionary, player_name: String, player_nat: String) -> Array:
	var par := par_per_round(t)
	var cs: Dictionary = t["cut"]
	var rows: Array = []
	for id in t["field"]:
		var a: Array = (t["opponent_rounds"] as Dictionary).get(id, [])
		var g: Dictionary = golfers_by_id.get(id, {})
		rows.append(_row(String(id), String(g.get("name", id)), String(g.get("nationality", "")), a, par, false,
			bool(cs["applied"]) and not (cs["survivors"] as Array).has(id)))
	if bool(t["has_human"]):
		var hr: Array = []
		for h in t["human_rounds"]:
			hr.append(int((h as Dictionary)["strokes"]))
		rows.append(_row(PLAYER, player_name, player_nat, hr, par, true, bool(cs["applied"]) and not bool(cs["human_made"])))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["cut"] != b["cut"]:
			return not a["cut"]
		if a["rounds"].size() != b["rounds"].size() and not a["cut"]:
			return a["rounds"].size() > b["rounds"].size()
		if a["total"] != b["total"]:
			return a["total"] < b["total"]
		return String(a["id"]) < String(b["id"]))
	# places (ties share the lowest place, within the same cut status)
	var i := 0
	while i < rows.size():
		var j := i
		while j + 1 < rows.size() and rows[j + 1]["total"] == rows[i]["total"] and rows[j + 1]["cut"] == rows[i]["cut"] and rows[j + 1]["rounds"].size() == rows[i]["rounds"].size():
			j += 1
		for k in range(i, j + 1):
			rows[k]["place"] = i + 1
			rows[k]["tied"] = j > i
		i = j + 1
	return rows


static func _row(id: String, p_name: String, nat: String, rounds: Array, par: int, human: bool, cut: bool) -> Dictionary:
	var total := 0
	for s in rounds:
		total += int(s)
	return {"id": id, "name": p_name, "nationality": nat, "rounds": rounds.duplicate(), "total": total,
		"rel": total - par * rounds.size(), "thru_rounds": rounds.size(), "is_human": human, "cut": cut, "place": 0, "tied": false}


## Prize money for each place among those who made the cut: {place: amount}; ties share the average of the
## places they cover. Shares decay by CareerConfig.PAYOUT_DECAY and sum to the purse.
static func payouts(purse: int, rows: Array) -> Dictionary:
	var made: Array = rows.filter(func(r: Dictionary) -> bool: return not r["cut"])
	var weights: Array = []
	var sum := 0.0
	for p in made.size():
		var w := pow(CareerConfig.PAYOUT_DECAY, p)
		weights.append(w)
		sum += w
	var out := {}  # id -> money
	var i := 0
	while i < made.size():
		var j := i
		while j + 1 < made.size() and made[j + 1]["total"] == made[i]["total"]:
			j += 1
		var share := 0.0
		for k in range(i, j + 1):
			share += float(weights[k])
		share /= float(j - i + 1)
		for k in range(i, j + 1):
			out[String(made[k]["id"])] = int(round(float(purse) * share / sum))
		i = j + 1
	return out


## Season points per player id for the final rows (winner points x decay^(place-1); ties share the average).
static func season_points(winner_points: int, rows: Array) -> Dictionary:
	var made: Array = rows.filter(func(r: Dictionary) -> bool: return not r["cut"])
	var out := {}
	var i := 0
	while i < made.size():
		var j := i
		while j + 1 < made.size() and made[j + 1]["total"] == made[i]["total"]:
			j += 1
		var sum := 0.0
		for k in range(i, j + 1):
			sum += pow(CareerConfig.POINTS_DECAY_PER_PLACE, k)
		var pts := int(round(float(winner_points) * sum / float(j - i + 1)))
		for k in range(i, j + 1):
			out[String(made[k]["id"])] = pts
		i = j + 1
	return out

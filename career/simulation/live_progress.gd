class_name LiveProgress
extends RefCounted
## Live tournament progress during a Career round (presentation data only, never changes a result).
## Each opponent's round score is the SAME frozen OpponentSimulation score the official result uses: the stored
## `opponent_rounds` value when it exists, otherwise the identical deterministic `sim.simulate_round` call that will
## store it at round end. That total is split into seeded per-hole scores that ALWAYS sum exactly to it.
## Opponents get seeded tee-time offsets (holes ahead of / behind the player). Everything is a pure function of
## (tournament, player progress): a restart (save/load) shows exactly the same board. No App, no UI, no I/O.

const SPREAD_DIV := 3          # tee-time offset range = +-max(1, holes / SPREAD_DIV)
const TICKER_TOP := 10         # birdies are news only for golfers inside this position
const TICKER_MAX := 3          # event lines per player hole

var round_index := 0
var pars: Array = []           # per-hole par of the current round (snapshot order)
var par_round := 0
var holes := 0
var player_name := ""
var player_prev := 0           # player's to-par from the rounds already recorded
var ids: Array = []            # opponents in this round
var names := {}                # id -> name
var prev_rel := {}             # id -> to-par from earlier rounds
var splits := {}               # id -> [per-hole strokes]
var offsets := {}              # id -> tee-time offset in holes (+ = ahead of the player)
var cut_rule := {}             # event cut when a PROJECTED line applies to this round, else {}


func _init(t: Dictionary, golfers_by_id: Dictionary, p_player_name: String, sim: Object) -> void:
	player_name = p_player_name
	if t.is_empty():
		return
	round_index = int(t.get("round_index", 0))
	for h in (t["snapshot"] as Dictionary).get("holes", []):
		pars.append(int((h as Dictionary).get("par", 4)))
	holes = pars.size()
	for p in pars:
		par_round += int(p)
	for i in mini(round_index, (t["human_rounds"] as Array).size()):
		player_prev += int((t["human_rounds"][i] as Dictionary)["strokes"]) - int((t["human_rounds"][i] as Dictionary).get("par", par_round))
	var ev: Dictionary = t["event"]
	var cut: Dictionary = ev.get("cut", {})
	if String(cut.get("type", "none")) != "none" and not bool((t["cut"] as Dictionary)["applied"]) and round_index + 1 == int(cut.get("after_round", 0)):
		cut_rule = cut
	var seed_v := int(t["sim_seed"])
	var eid := String(ev.get("id", ""))
	ids = TournamentManager.active_opponents(t, round_index)
	var ci := TournamentManager.course_info(t)
	for id in ids:
		var g: Dictionary = golfers_by_id.get(id, {"id": id, "rating": 60.0, "consistency": 0.5, "form": 0.0})
		names[id] = String(g.get("name", id))
		var stored: Array = (t["opponent_rounds"] as Dictionary).get(id, [])
		var rel := 0
		for i in mini(round_index, stored.size()):
			rel += int(stored[i]) - par_round
		prev_rel[id] = rel
		var total: int
		if stored.size() > round_index:
			total = int(stored[round_index])
		else:
			total = int((sim.simulate_round([g], ev, round_index, ci, seed_v, 0.0) as Dictionary)[id])
		splits[id] = split_round(total, pars, SimRng.make(seed_v, eid, round_index, id, "live_split"))
		offsets[id] = tee_offset(holes, SimRng.make(seed_v, eid, round_index, id, "live_tee"))


## Per-hole strokes summing EXACTLY to `total`. Each hole stays within [max(1, par-2), par+3] when the total allows,
## then a few seeded birdie/bogey swaps add colour (swaps never change the sum).
static func split_round(total: int, p_pars: Array, rng: RandomNumberGenerator) -> Array:
	var n := p_pars.size()
	var out: Array = []
	for p in p_pars:
		out.append(int(p))
	if n == 0:
		return out
	var lo: Array = []
	var hi: Array = []
	for p in p_pars:
		lo.append(maxi(1, int(p) - 2))
		hi.append(int(p) + 3)
	var sum := 0
	for v in out:
		sum += int(v)
	var widened := false
	while sum != total:
		var dir := 1 if total > sum else -1
		# candidates whose |delta from par| after the step is smallest (spreads the strokes evenly)
		var best: Array = []
		var best_d := 1 << 30
		for i in n:
			var nv := int(out[i]) + dir
			if nv < int(lo[i]) or nv > int(hi[i]):
				continue
			var d := absi(nv - int(p_pars[i]))
			if d < best_d:
				best_d = d
				best = [i]
			elif d == best_d:
				best.append(i)
		if best.is_empty():
			if widened:
				break  # total below n strokes: impossible split, never happens for simulated rounds
			widened = true
			for i in n:
				lo[i] = 1 if total >= n else 0
				hi[i] = 1 << 20
			continue
		var pick: int = best[rng.randi_range(0, best.size() - 1)]
		out[pick] = int(out[pick]) + dir
		sum += dir
	var swaps := rng.randi_range(0, maxi(1, n / 3))
	for s in swaps:
		var a := rng.randi_range(0, n - 1)
		var b := rng.randi_range(0, n - 1)
		if a == b or int(out[a]) - 1 < int(lo[a]) or int(out[b]) + 1 > int(hi[b]):
			continue
		out[a] = int(out[a]) - 1
		out[b] = int(out[b]) + 1
	return out


static func tee_offset(p_holes: int, rng: RandomNumberGenerator) -> int:
	var s := maxi(1, p_holes / SPREAD_DIV)
	return rng.randi_range(-s, s)


## Holes an opponent has completed when the player has completed `step` holes.
func thru_of(id: String, step: int) -> int:
	if step >= holes:
		return holes  # the player's round is over: the field has finished too (the official result follows)
	return clampi(step + int(offsets.get(id, 0)), 0, holes)


func round_rel_of(id: String, thru: int) -> int:
	var r := 0
	var sp: Array = splits.get(id, [])
	for i in mini(thru, sp.size()):
		r += int(sp[i]) - int(pars[i])
	return r


## Board after the player has completed `step` holes at `player_round_rel` to par this round.
## Rows best first: {id, name, is_human, rel, round_rel, thru, pos, tied, below_cut}. Ties share a position.
## Returns {rows, cut_line (to-par, only when projected), has_cut, player_index}.
func board(step: int, player_round_rel: int) -> Dictionary:
	var rows: Array = []
	for id in ids:
		var th := thru_of(id, step)
		var rr := round_rel_of(id, th)
		rows.append({"id": id, "name": names[id], "is_human": false, "rel": int(prev_rel[id]) + rr, "round_rel": rr, "thru": th})
	rows.append({"id": TournamentManager.PLAYER, "name": player_name, "is_human": true, "rel": player_prev + player_round_rel,
		"round_rel": player_round_rel, "thru": clampi(step, 0, holes)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["rel"] != b["rel"]:
			return a["rel"] < b["rel"]
		if a["thru"] != b["thru"]:
			return a["thru"] > b["thru"]
		return String(a["id"]) < String(b["id"]))
	var i := 0
	while i < rows.size():
		var j := i
		while j + 1 < rows.size() and rows[j + 1]["rel"] == rows[i]["rel"]:
			j += 1
		for k in range(i, j + 1):
			rows[k]["pos"] = i + 1
			rows[k]["tied"] = j > i
		i = j + 1
	var res := {"rows": rows, "has_cut": not cut_rule.is_empty(), "cut_line": 0, "player_index": 0}
	if not cut_rule.is_empty():
		var rel_map := {}
		for r in rows:
			rel_map[r["id"]] = int(r["rel"])
		var line := int(TournamentManager.compute_cut(rel_map, cut_rule)["line_total"])
		res["cut_line"] = line
	for k in rows.size():
		rows[k]["below_cut"] = bool(res["has_cut"]) and int(rows[k]["rel"]) > int(res["cut_line"])
		if bool(rows[k]["is_human"]):
			res["player_index"] = k
	return res


## Indices of the rows to show: the top `top` plus the player's row and one either side. -1 marks a gap.
static func visible_rows(rows: Array, player_index: int, top: int = 5) -> Array:
	var want := {}
	for k in mini(top, rows.size()):
		want[k] = true
	for k in range(player_index - 1, player_index + 2):
		if k >= 0 and k < rows.size():
			want[k] = true
	var keys: Array = want.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		if not out.is_empty() and int(k) > int(out.back()) + 1:
			out.append(-1)
		out.append(int(k))
	return out


## News lines for what the field did while the player went from `prev_step` to `step` holes (best first).
func events_between(prev_step: int, step: int, player_round_rel: int) -> Array:
	if step <= prev_step:
		return []
	var before: Dictionary = board(prev_step, player_round_rel)
	var after: Dictionary = board(step, player_round_rel)
	var pos_after := {}
	for r in after["rows"]:
		pos_after[r["id"]] = r
	var leader_before := _sole_leader(before["rows"])
	var leader_after := _sole_leader(after["rows"])
	var lines: Array = []  # [priority, text]
	var lead_told := false
	for id in ids:
		var a := thru_of(id, prev_step)
		var b := thru_of(id, step)
		for h in range(a, b):
			var d := int(splits[id][h]) - int(pars[h])
			var row: Dictionary = pos_after[id]
			var pos := int(row["pos"])
			var who := String(names[id])
			if d < 0 and leader_after == id and leader_before != id and h == b - 1:
				lines.append([0, "%s %s the %s to take the lead" % [who, score_verb(d), ordinal(h + 1)]])
				lead_told = true
			elif d <= -2 or (d < 0 and pos <= TICKER_TOP):
				lines.append([1 if d <= -2 else 2, "%s %s the %s (%s)" % [who, score_verb(d), ordinal(h + 1), fmt_rel(int(row["rel"]))]])
			elif d >= 2 and pos <= 5:
				lines.append([2, "%s %s the %s" % [who, score_verb(d), ordinal(h + 1)]])
	if not lead_told and leader_after != "" and leader_after != leader_before and leader_after != TournamentManager.PLAYER:
		lines.append([0, "%s takes the lead at %s" % [String(names.get(leader_after, leader_after)), fmt_rel(int(pos_after[leader_after]["rel"]))]])
	lines.sort_custom(func(x: Array, y: Array) -> bool: return int(x[0]) < int(y[0]))
	var out: Array = []
	for l in lines.slice(0, TICKER_MAX):
		out.append(String(l[1]))
	return out


static func _sole_leader(rows: Array) -> String:
	if rows.is_empty() or bool(rows[0]["tied"]):
		return ""
	return String(rows[0]["id"])


static func score_verb(d: int) -> String:
	match d:
		-1: return "birdies"
		-2: return "eagles"
		0: return "pars"
		1: return "bogeys"
		2: return "double-bogeys"
	return "albatrosses" if d <= -3 else "takes %+d on" % d


static func ordinal(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		suf = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, suf]


static func fmt_rel(r: int) -> String:
	return "E" if r == 0 else "%+d" % r


static func fmt_pos(row: Dictionary) -> String:
	return ("T%d" if bool(row.get("tied", false)) else "%d") % int(row["pos"])


static func fmt_thru(thru: int, p_holes: int) -> String:
	return "F" if thru >= p_holes else ("-" if thru <= 0 else str(thru))

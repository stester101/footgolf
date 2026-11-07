class_name RoundState
extends RefCounted
## Three-hole (or developer-selected) round progress.

var hole_ids: Array[String] = []
var current_index := 0
var holes: Array = []  # Array[HoleState], one per hole id
var round_seed := 0


func current() -> HoleState:
	if current_index < 0 or current_index >= holes.size():
		return null
	return holes[current_index]


func total_score() -> int:
	var t := 0
	for h in holes:
		var hs: HoleState = h
		if hs.complete or hs.raw_total() > 0:
			t += hs.score()
	return t


func total_par_played() -> int:
	var t := 0
	for h in holes:
		var hs: HoleState = h
		if hs.complete or hs.raw_total() > 0:
			t += hs.par
	return t


func total_par() -> int:
	var t := 0
	for h in holes:
		t += (h as HoleState).par
	return t


func relative_to_par() -> int:
	return total_score() - total_par_played()


func total_penalties() -> int:
	var t := 0
	for h in holes:
		t += (h as HoleState).penalties
	return t


func all_complete() -> bool:
	for h in holes:
		if not (h as HoleState).complete:
			return false
	return not holes.is_empty()


static func fmt_relative(r: int) -> String:
	if r == 0:
		return "E"
	return "%+d" % r

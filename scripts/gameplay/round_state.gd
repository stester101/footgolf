class_name RoundState
extends RefCounted
## Three-hole (or developer-selected) round progress.

var hole_ids: Array[String] = []
var current_index := 0
var holes: Array = []  # Array[HoleState], one per hole id
var round_seed := 0
## -1 means unlimited; otherwise the count selected before this round.
var mulligans_allowed := 0
var mulligans_used := 0
## Original mulliganed attempts (audit only; they never score).
var mulligan_audit: Array = []


func mulligans_remaining() -> int:
	return -1 if mulligans_allowed < 0 else maxi(0, mulligans_allowed - mulligans_used)


## Index of the hole GameSession.next_hole() will start from the current one (same rule: next
## incomplete hole after the current, else the first incomplete one), or -1 if the round ends.
func upcoming_index() -> int:
	var next := current_index + 1
	while next < holes.size() and (holes[next] as HoleState).complete:
		next += 1
	if next < holes.size():
		return next
	for i in holes.size():
		if not (holes[i] as HoleState).complete:
			return i
	return -1


func current() -> HoleState:
	if current_index < 0 or current_index >= holes.size():
		return null
	return holes[current_index]


## Sum of COMPLETED hole scores (an in-progress hole is not counted against par).
func total_score() -> int:
	var t := 0
	for h in holes:
		var hs: HoleState = h
		if hs.complete:
			t += hs.score()
	return t


func total_par_played() -> int:
	var t := 0
	for h in holes:
		var hs: HoleState = h
		if hs.complete:
			t += hs.par
	return t


func holes_completed() -> int:
	var n := 0
	for h in holes:
		if (h as HoleState).complete:
			n += 1
	return n


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

class_name HoleState
extends RefCounted
## Runtime progress on one hole (separate from the static HoleDefinition).

var hole_id := ""
var hole_name := ""
var par := 3
var strokes := 0
var penalties := 0
var complete := false
var completion := ""
var shots: Array = []  # Array[ShotResult]
var used_footballer_ids: Array[String] = []


func max_score() -> int:
	return ScoringService.max_score_for_par(par)


## Raw internal total (never clamped) — keeps an unambiguous record.
func raw_total() -> int:
	return strokes + penalties


## Displayed/recorded hole score, clamped at par + 5.
func score() -> int:
	return mini(raw_total(), max_score())


func relative_to_par() -> int:
	return score() - par


func copy() -> HoleState:
	var h := HoleState.new()
	h.hole_id = hole_id
	h.hole_name = hole_name
	h.par = par
	h.strokes = strokes
	h.penalties = penalties
	h.complete = complete
	h.completion = completion
	h.shots = shots.duplicate()
	h.used_footballer_ids = used_footballer_ids.duplicate()
	return h

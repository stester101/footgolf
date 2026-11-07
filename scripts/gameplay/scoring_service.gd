class_name ScoringService
extends RefCounted
## Stroke-play rules: 1 stroke per committed shot, +1 penalty for water/OOB,
## automatic maximum of par + 5, hole-out only for a ball AT REST inside the radius
## (or physically in the cup).

const MAX_OVER_PAR := 5
const DEFAULT_HOLEOUT_FT := 5.0
const MIN_HOLEOUT_FT := 0.0
const MAX_HOLEOUT_FT := 10.0


## Owner decision (docs/DECISIONS.md): there is NO maximum score. A hole ends only when holed.
static func max_score_for_par(_par: int) -> int:
	return 999999


static func clamp_radius_ft(ft: float) -> float:
	if not is_finite(ft):
		return DEFAULT_HOLEOUT_FT
	return clampf(ft, MIN_HOLEOUT_FT, MAX_HOLEOUT_FT)


## Hole-out decision for a resolved shot.
## in_cup: the simulation captured the ball in the physical cup.
## at_rest: the ball has stopped (never true while rolling).
static func is_holed(in_cup: bool, at_rest: bool, dist_to_cup_m: float, radius_ft: float) -> bool:
	if in_cup:
		return true
	if not at_rest:
		return false
	var r_ft := clamp_radius_ft(radius_ft)
	if r_ft <= 0.0:
		return false  # 0 ft: physical cup entry required
	return dist_to_cup_m <= Units.feet_to_m(r_ft)


## Applies a resolved shot to a hole state. Returns the completion reason ("" if still in play).
static func apply_shot(hs: HoleState, penalty: int, holed: bool) -> String:
	hs.penalties += penalty
	if holed:
		hs.complete = true
		hs.completion = ShotTypes.COMPLETION_HOLED
	return hs.completion

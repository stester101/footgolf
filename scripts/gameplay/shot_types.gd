class_name ShotTypes
extends RefCounted
## Shot modes, game states, completion reasons.

enum Mode { CAPS, GOALS }

enum State {
	BOOT, MAIN_MENU, ROUND_SETUP, HOLE_INTRO, AIMING, SHOT_COMMITTED,
	BALL_IN_MOTION, HAZARD_RESOLUTION, SHOT_RESULT, HOLE_COMPLETE, ROUND_COMPLETE,
}

const MODE_NAMES := {Mode.CAPS: "CAPS", Mode.GOALS: "GOALS"}
const STATE_NAMES := {
	State.BOOT: "BOOT", State.MAIN_MENU: "MAIN_MENU", State.ROUND_SETUP: "ROUND_SETUP",
	State.HOLE_INTRO: "HOLE_INTRO", State.AIMING: "AIMING", State.SHOT_COMMITTED: "SHOT_COMMITTED",
	State.BALL_IN_MOTION: "BALL_IN_MOTION", State.HAZARD_RESOLUTION: "HAZARD_RESOLUTION",
	State.SHOT_RESULT: "SHOT_RESULT", State.HOLE_COMPLETE: "HOLE_COMPLETE",
	State.ROUND_COMPLETE: "ROUND_COMPLETE",
}

const COMPLETION_HOLED := "HOLED"
const COMPLETION_MAX_SCORE := "MAX_SCORE"


static func mode_name(m: int) -> String:
	return MODE_NAMES.get(m, "?")


static func state_name(s: int) -> String:
	return STATE_NAMES.get(s, "?")

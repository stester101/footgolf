class_name ShotTypes
extends RefCounted
## Shot modes, game states, completion reasons.

enum Mode { CAPS, GOALS }
## Distance source and how the ball moves are independent choices.
enum Style { FLIGHT, ROLL }
const STYLE_NAMES := {Style.FLIGHT: "FLIGHT", Style.ROLL: "ROLL"}

## Flight launch trajectory (owner-approved, docs/DECISIONS.md). Carry stays exact for every
## option: the solver uses the chosen angle. STANDARD uses PhysicsConfig.launch_angle_deg.
enum Trajectory { PUNCH, LOW, STANDARD, HIGH }
const TRAJECTORY_NAMES := {Trajectory.PUNCH: "PUNCH", Trajectory.LOW: "LOW", Trajectory.STANDARD: "STANDARD", Trajectory.HIGH: "HIGH"}
const TRAJECTORY_ANGLES := {Trajectory.PUNCH: 12.0, Trajectory.LOW: 24.0, Trajectory.HIGH: 56.0}

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


static func style_name(s: int) -> String:
	return STYLE_NAMES.get(s, "?")


static func trajectory_name(t: int) -> String:
	return TRAJECTORY_NAMES.get(t, "STANDARD")


static func trajectory_angle(t: int, standard_deg: float) -> float:
	return float(TRAJECTORY_ANGLES.get(t, standard_deg))


static func state_name(s: int) -> String:
	return STATE_NAMES.get(s, "?")

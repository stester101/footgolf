class_name Feedback
extends RefCounted
## One place for haptic and sound cues so every screen behaves the same way.
## Haptics respect Settings > vibration. Sound is a STUB: no audio assets exist yet, so cues are
## only recorded behind the (default muted) sound setting; `cue_log` lets tests and a future
## audio player hook in without touching call sites.

## Haptic duration in ms per cue (0 = none). Shots and hole-outs keep their original values.
const HAPTIC_MS := {"shot": 35, "holed": 90, "penalty": 60, "eagle": 120, "confirm": 15}
const SFX_NAMES := ["shot", "holed", "penalty", "tap"]

## Most recent cues that would have played (bounded); read by tests.
static var cue_log: Array = []
const CUE_LOG_MAX := 16


static func haptic_ms(kind: String) -> int:
	return int(HAPTIC_MS.get(kind, 0))


## Vibrate for `kind` when enabled. Safe on desktop (no-op) and for unknown kinds.
static func haptic(kind: String, enabled: bool = true) -> void:
	var ms := haptic_ms(kind)
	if enabled and ms > 0:
		Input.vibrate_handheld(ms)


## Which haptic fits a resolved shot: holed (eagle or better is stronger), penalty, else plain shot.
static func haptic_for_result(holed: bool, penalty: int, relative_to_par: int) -> String:
	if holed:
		return "eagle" if relative_to_par <= -2 else "holed"
	if penalty > 0:
		return "penalty"
	return "shot"


## Sound hook. Muted by default (no assets yet); records the cue and returns true if it would play.
static func sfx(cue: String, muted: bool = true) -> bool:
	if muted or not SFX_NAMES.has(cue):
		return false
	cue_log.append(cue)
	if cue_log.size() > CUE_LOG_MAX:
		cue_log.pop_front()
	return true


## Backgrounding opens the Pause menu only for an offline round that is waiting for the player to aim
## (never online, mid-flight, over another overlay or with the developer panel open).
static func should_auto_pause(enabled: bool, online: bool, state: int, has_overlay: bool, dev_open: bool) -> bool:
	return enabled and not online and not has_overlay and not dev_open and state == ShotTypes.State.AIMING

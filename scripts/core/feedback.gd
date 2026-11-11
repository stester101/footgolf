class_name Feedback
extends RefCounted
## One place for haptic and sound cues so every screen behaves the same way.
## Haptics respect Settings > vibration. Sounds are synthesised at runtime (SfxSynth, no audio assets)
## and played by the SfxPlayer registered in `player` (a round creates one); they respect the
## sound mute and the SFX volume. `cue_log` records what would have played (tests read it).

## Haptic duration in ms per cue (0 = none). Shots and hole-outs keep their original values.
const HAPTIC_MS := {"shot": 35, "holed": 90, "penalty": 60, "eagle": 120, "confirm": 15}
const SFX_NAMES := ["shot", "holed", "penalty", "tap", "kick_soft", "kick", "kick_hard", "putt",
		"land_fairway", "land_rough", "land_green", "land_sand", "cup", "flag", "rim", "tree", "splash",
		"cheer", "groan", "applause"]

## The active SfxPlayer (or null: cues are only logged). Untyped so headless tests need no audio node.
static var player: Object = null
## Linear SFX volume 0..1 (Settings > Audio / Visual); applied to every cue.
static var volume := 0.8

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


## Sound hook: records the cue and plays it (gain = strength x volume) when a player exists.
## Returns true if it would play (not muted, known cue).
static func sfx(cue: String, muted: bool = true, strength: float = 1.0, pitch: float = 1.0) -> bool:
	if muted or not SFX_NAMES.has(cue):
		return false
	cue_log.append(cue)
	if cue_log.size() > CUE_LOG_MAX:
		cue_log.pop_front()
	if player != null and is_instance_valid(player):
		player.call("play", cue, clampf(strength, 0.0, 1.5) * volume, pitch)
	return true


## Backgrounding opens the Pause menu only for an offline round that is waiting for the player to aim
## (never online, mid-flight, over another overlay or with the developer panel open).
static func should_auto_pause(enabled: bool, online: bool, state: int, has_overlay: bool, dev_open: bool) -> bool:
	return enabled and not online and not has_overlay and not dev_open and state == ShotTypes.State.AIMING

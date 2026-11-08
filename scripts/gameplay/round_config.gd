class_name RoundConfig
extends RefCounted
## Difficulty / rules chosen in Round Setup and FROZEN for the round once it starts.
## Defaults equal the behaviour before this existed. Settings > Gameplay stores the defaults that
## pre-fill Round Setup (see from_settings / write_defaults).

enum WindMode { SETTINGS, NONE, SCALED }
enum MaxScore { NONE, PAR_PLUS_5, CUSTOM }

const MIN_CUP_FT := 0.35
const MAX_CUP_FT := 6.0
const WIND_SCALE_MIN := 0.25
const WIND_SCALE_MAX := 2.0
const CUSTOM_OVER_MIN := 1
const CUSTOM_OVER_MAX := 20

var cup_diameter_ft := PhysicsConfig.new().cup_diameter_in() / 12.0
## Gimme distance from the cup EDGE in ft (0 = no gimme).
var gimme_ft := ScoringService.DEFAULT_HOLEOUT_FT
## false = each footballer once per match; true = once for Caps AND once for Goals.
var reuse_per_mode := false
var wind_mode: int = WindMode.SETTINGS
var wind_scale := 1.0  # used when wind_mode == SCALED
var max_score_mode: int = MaxScore.NONE
var max_over_par_custom := 5  # strokes over par when max_score_mode == CUSTOM
var show_aim_arrow := true
var show_trail := true
var lie_exact := false
var show_stats := true


## Round Setup defaults from the saved settings.
static func from_settings(st: SettingsStore) -> RoundConfig:
	var rc := RoundConfig.new()
	rc.cup_diameter_ft = clampf(st.physics.cup_diameter_in() / 12.0, MIN_CUP_FT, MAX_CUP_FT)
	rc.gimme_ft = ScoringService.clamp_radius_ft(st.holeout_radius_ft)
	rc.show_trail = st.show_trail
	rc.lie_exact = st.lie_effect_exact
	rc.show_stats = st.show_stats
	rc.apply_dict(st.round_defaults)
	return rc


## Stores this as the Settings defaults (legacy fields plus settings.round_defaults).
func write_defaults(st: SettingsStore) -> void:
	st.physics.set_cup_diameter_in(cup_diameter_ft * 12.0)
	st.holeout_radius_ft = gimme_ft
	st.show_trail = show_trail
	st.lie_effect_exact = lie_exact
	st.show_stats = show_stats
	st.round_defaults = {
		"reuse_per_mode": reuse_per_mode, "wind_mode": wind_mode, "wind_scale": wind_scale,
		"max_score_mode": max_score_mode, "max_over_par_custom": max_over_par_custom,
		"show_aim_arrow": show_aim_arrow,
	}
	st.save()


func apply_dict(d: Dictionary) -> void:
	reuse_per_mode = bool(d.get("reuse_per_mode", reuse_per_mode))
	wind_mode = clampi(int(d.get("wind_mode", wind_mode)), WindMode.SETTINGS, WindMode.SCALED)
	wind_scale = clampf(float(d.get("wind_scale", wind_scale)), WIND_SCALE_MIN, WIND_SCALE_MAX)
	max_score_mode = clampi(int(d.get("max_score_mode", max_score_mode)), MaxScore.NONE, MaxScore.CUSTOM)
	max_over_par_custom = clampi(int(d.get("max_over_par_custom", max_over_par_custom)), CUSTOM_OVER_MIN, CUSTOM_OVER_MAX)
	show_aim_arrow = bool(d.get("show_aim_arrow", show_aim_arrow))


func duplicate_config() -> RoundConfig:
	var c := RoundConfig.new()
	c.cup_diameter_ft = cup_diameter_ft
	c.gimme_ft = gimme_ft
	c.reuse_per_mode = reuse_per_mode
	c.wind_mode = wind_mode
	c.wind_scale = wind_scale
	c.max_score_mode = max_score_mode
	c.max_over_par_custom = max_over_par_custom
	c.show_aim_arrow = show_aim_arrow
	c.show_trail = show_trail
	c.lie_exact = lie_exact
	c.show_stats = show_stats
	return c


## Strokes over par at which a hole ends, or -1 for no maximum.
func max_over_par() -> int:
	match max_score_mode:
		MaxScore.PAR_PLUS_5:
			return ScoringService.MAX_OVER_PAR
		MaxScore.CUSTOM:
			return max_over_par_custom
	return -1


## Multiplier on each hole's wind speed.
func wind_multiplier() -> float:
	match wind_mode:
		WindMode.NONE:
			return 0.0
		WindMode.SCALED:
			return wind_scale
	return 1.0


func max_score_label() -> String:
	var o := max_over_par()
	return "None" if o < 0 else "Par + %d" % o


func pool_rule() -> int:
	return FootballerPool.ReuseRule.ONCE_PER_MODE if reuse_per_mode else FootballerPool.ReuseRule.ONCE_PER_ROUND

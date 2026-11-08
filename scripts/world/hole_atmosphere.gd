class_name HoleAtmosphere
extends RefCounted
## Tier-1 look data: per-hole sun direction, sky colours and fog tint, derived DETERMINISTICALLY from
## the hole id (no hole JSON change) so a hole always looks the same. Presentation only.
## Every preset is a bright, readable day: sun elevation >= 30 deg, sun never in front of the camera
## (azimuth is relative to the tee -> pin bearing), fog tint == sky horizon so far terrain blends.

## Graphics quality: false = Low (the original look and cost), true = High. Set by RoundController
## and the settings page from SettingsStore.graphics_quality.
static var high_quality := true
## Optional subtle bloom inside High (SettingsStore.graphics_glow, default off).
static var glow := false

## Wind speed (m/s) that counts as "full strength" for the purely visual wind effects.
const WIND_FULL_MPS := 7.0

const PRESETS := [
	{ # clear blue
		"top": Color(0.13, 0.33, 0.70), "mid": Color(0.35, 0.58, 0.86), "horizon": Color(0.74, 0.84, 0.93),
		"sun": Color(1.0, 0.93, 0.78), "light": Color(1.0, 0.93, 0.80), "energy": 1.45,
		"cover": 0.50, "elev": 44.0,
	},
	{ # fresh morning: paler, slightly warm horizon
		"top": Color(0.18, 0.38, 0.72), "mid": Color(0.45, 0.65, 0.88), "horizon": Color(0.86, 0.88, 0.92),
		"sun": Color(1.0, 0.88, 0.68), "light": Color(1.0, 0.91, 0.76), "energy": 1.5,
		"cover": 0.42, "elev": 34.0,
	},
	{ # hazy high summer
		"top": Color(0.20, 0.40, 0.72), "mid": Color(0.52, 0.68, 0.86), "horizon": Color(0.82, 0.88, 0.93),
		"sun": Color(1.0, 0.96, 0.84), "light": Color(1.0, 0.96, 0.86), "energy": 1.4,
		"cover": 0.58, "elev": 52.0,
	},
	{ # late-afternoon gold, kept bright
		"top": Color(0.17, 0.34, 0.66), "mid": Color(0.48, 0.62, 0.82), "horizon": Color(0.92, 0.86, 0.80),
		"sun": Color(1.0, 0.82, 0.56), "light": Color(1.0, 0.88, 0.70), "energy": 1.5,
		"cover": 0.46, "elev": 33.0,
	},
]


## Deterministic per-hole parameters (see PRESETS for keys; plus sun_dir, offset).
static func for_hole(hole: HoleDefinition) -> Dictionary:
	var h := absi(hole.id.hash())
	var preset: Dictionary = (PRESETS[h % PRESETS.size()] as Dictionary).duplicate()
	var bearing := rad_to_deg(atan2(hole.pin.x - hole.tee.x, hole.pin.y - hole.tee.y))  # 0 = +Z, 90 = +X
	var side := 1.0 if ((h >> 5) % 2) == 0 else -1.0
	# Sun sits behind/beside the player (110..160 deg off the line of play), never ahead.
	var rel := side * (110.0 + float((h >> 9) % 51))
	var az := deg_to_rad(bearing + rel)
	var el := deg_to_rad(float(preset["elev"]) + float((h >> 13) % 7) - 3.0)
	preset["sun_dir"] = Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()
	preset["cover"] = clampf(float(preset["cover"]) + (float((h >> 17) % 21) - 10.0) * 0.006, 0.3, 0.65)
	preset["offset"] = Vector2(float((h >> 21) % 100) * 0.01, float((h >> 25) % 100) * 0.01)
	preset["fog"] = (preset["horizon"] as Color).lerp(Color(0.7, 0.82, 0.94), 0.25)
	return preset

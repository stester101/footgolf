class_name ShotResult
extends RefCounted
## Outcome of a resolved shot. Fields carry explicit units.

var shot_id := 0
var hole_id := ""
var footballer_id := ""
var footballer_name := ""
var nationality := ""
var mode: int = ShotTypes.Mode.CAPS
var stat_value := 0
var caps := 0
var goals := 0
var base_distance_m := 0.0
var lie_factor := 1.0
var target_distance_m := 0.0
var launch_speed_mps := 0.0
var launch_angle_deg := 0.0
var aim_bearing_deg := 0.0
var wind_speed_mps := 0.0
var wind_bearing_deg := 0.0
var start_pos := Vector3.ZERO
var start_lie: int = Surface.Type.TEE
var had_contact := false
var first_contact_pos := Vector3.ZERO
var carry_m := 0.0
var roll_m := 0.0
var total_m := 0.0
var max_height_m := 0.0
var bounces := 0
var collisions: Array = []
var hazard := ""
var hazard_pos := Vector3.ZERO
var relief_pos := Vector3.ZERO
var relief_method := ""
var penalty := 0
var final_pos := Vector3.ZERO
var final_lie: int = Surface.Type.FAIRWAY
var time_in_motion_s := 0.0
var stroke_delta := 1
var holed := false
var remaining_m := 0.0
var seed := 0
var neutral_calibration_error_pct := 0.0
var actual_vs_target_pct := 0.0
var timed_out := false
var sim_error := false
var developer_replay := false
var end_reason := ""
var hole_score_after := 0


func mode_name() -> String:
	return ShotTypes.mode_name(mode)


func stat_label() -> String:
	if mode == ShotTypes.Mode.CAPS:
		return "%d caps" % stat_value
	return "%d goals" % stat_value


func base_label() -> String:
	if mode == ShotTypes.Mode.CAPS:
		return "%d yd carry" % stat_value
	return "%d ft ground" % stat_value


func collision_summary() -> String:
	if collisions.is_empty():
		return "none"
	var counts := {}
	for c in collisions:
		var t: String = c["type"]
		counts[t] = int(counts.get(t, 0)) + 1
	var parts: Array[String] = []
	for k in counts.keys():
		parts.append("%s x%d" % [k, counts[k]])
	return ", ".join(parts)


static func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func diagnostic_text() -> String:
	var lines: Array[String] = []
	lines.append("Shot ID %d / seed %d%s" % [shot_id, seed, " [DEV REPLAY]" if developer_replay else ""])
	lines.append("Mode %s / footballer %s (%s)" % [mode_name(), footballer_id, footballer_name])
	lines.append("Input: %d caps, %d goals -> used %s" % [caps, goals, stat_label()])
	if mode == ShotTypes.Mode.CAPS:
		lines.append("Neutral target: %.2f yd (%.3f m) first-contact carry" % [Units.m_to_yards(base_distance_m), base_distance_m])
	else:
		lines.append("Neutral target: %.2f ft (%.4f m) ground travel" % [Units.m_to_feet(base_distance_m), base_distance_m])
	lines.append("Lie factor %.4f -> solved target %.3f m" % [lie_factor, target_distance_m])
	lines.append("Aim bearing %.1f deg" % aim_bearing_deg)
	lines.append("Launch angle %.1f deg, speed %.3f m/s" % [launch_angle_deg if mode == ShotTypes.Mode.CAPS else 0.0, launch_speed_mps])
	lines.append("Wind %.2f m/s (%.1f mph) toward %.0f deg" % [wind_speed_mps, wind_speed_mps * Units.MPS_TO_MPH, wind_bearing_deg])
	lines.append("Lie: start %s -> final %s" % [Surface.name_of(start_lie), Surface.name_of(final_lie)])
	lines.append("Carry %.2f yd / roll %.2f ft / total %.2f yd" % [Units.m_to_yards(carry_m), Units.m_to_feet(roll_m), Units.m_to_yards(total_m)])
	lines.append("First contact %s" % (_v(first_contact_pos) if had_contact else "n/a"))
	lines.append("Apex %.2f m, bounces %d" % [max_height_m, bounces])
	lines.append("Collisions: %d (%s)" % [collisions.size(), collision_summary()])
	if hazard != "":
		lines.append("Hazard %s at %s -> relief %s via %s" % [hazard, _v(hazard_pos), _v(relief_pos), relief_method])
	lines.append("Time in motion %.2f s (%s)%s" % [time_in_motion_s, end_reason, " TIMEOUT" if timed_out else ""])
	lines.append("Stroke delta +%d, penalties +%d%s" % [stroke_delta, penalty, ", HOLED" if holed else ""])
	lines.append("Neutral calibration error %.4f%%" % neutral_calibration_error_pct)
	lines.append("Actual vs neutral target %.2f%%" % actual_vs_target_pct)
	lines.append("Final %s, remaining %.1f yd" % [_v(final_pos), Units.m_to_yards(remaining_m)])
	return "\n".join(lines)


func to_dict() -> Dictionary:
	return {
		"shot_id": shot_id, "hole_id": hole_id, "footballer_id": footballer_id, "name": footballer_name,
		"mode": mode_name(), "stat": stat_value, "base_m": base_distance_m, "lie_factor": lie_factor,
		"carry_m": carry_m, "roll_m": roll_m, "total_m": total_m, "hazard": hazard, "penalty": penalty,
		"holed": holed, "remaining_m": remaining_m, "seed": seed, "speed_mps": launch_speed_mps,
		"time_s": time_in_motion_s, "start_lie": Surface.name_of(start_lie), "final_lie": Surface.name_of(final_lie),
	}

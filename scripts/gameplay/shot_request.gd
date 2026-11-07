class_name ShotRequest
extends RefCounted
## Everything needed to (re)run a shot deterministically.

var shot_id := 0
var hole_id := ""
var footballer_id := ""
var mode: int = ShotTypes.Mode.CAPS
var aim_bearing_deg := 0.0
var spin := 0.0
var trajectory: int = ShotTypes.Trajectory.STANDARD
var start_pos := Vector3.ZERO
var launch_lie: int = Surface.Type.TEE
var wind_speed_mps := 0.0
var wind_bearing_deg := 0.0
var seed := 0
var state_version := 0
var timestamp_ms := 0
var developer_replay := false


func copy() -> ShotRequest:
	var r := ShotRequest.new()
	for p in ["shot_id", "hole_id", "footballer_id", "mode", "aim_bearing_deg", "spin", "trajectory", "start_pos", "launch_lie",
			"wind_speed_mps", "wind_bearing_deg", "seed", "state_version", "timestamp_ms", "developer_replay"]:
		r.set(p, get(p))
	return r


func to_dict() -> Dictionary:
	return {
		"shot_id": shot_id, "hole_id": hole_id, "footballer_id": footballer_id,
		"mode": ShotTypes.mode_name(mode), "aim_bearing_deg": aim_bearing_deg, "spin": spin, "trajectory": ShotTypes.trajectory_name(trajectory),
		"start_pos": [start_pos.x, start_pos.y, start_pos.z], "launch_lie": Surface.name_of(launch_lie),
		"wind_speed_mps": wind_speed_mps, "wind_bearing_deg": wind_bearing_deg, "seed": seed,
		"developer_replay": developer_replay,
	}

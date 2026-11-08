class_name RoundAutosave
extends RefCounted
## Listens to an OFFLINE GameSession: autosaves at every stable point (RoundSave) and, when the round
## completes, writes the History record and deletes the save. Presentation-layer helper; it never
## changes game state. Not attached to online or developer rounds.

var session: GameSession
var course_id := ""
var course_name := ""
var save_dir := RoundSave.DIR
var history_path := RoundHistory.PATH
var telemetry: TelemetryLog
var save_id := ""
var created_at := 0
var _round_obj := 0
var _telemetry_round_id := ""


## resume: the loaded save when the session was restored from one (keeps its id and creation time).
func attach(p_session: GameSession, p_course_id: String, p_course_name: String, p_telemetry: TelemetryLog = null, resume: Dictionary = {}) -> void:
	session = p_session
	course_id = p_course_id
	course_name = p_course_name
	telemetry = p_telemetry
	if not resume.is_empty():
		save_id = String(resume["id"])
		created_at = int(resume.get("created_at", 0))
		_telemetry_round_id = String(resume.get("telemetry_round_id", ""))
		_round_obj = _round_key()
	session.state_changed.connect(_on_state_changed)
	session.round_completed.connect(_on_round_completed)


func _round_key() -> int:
	return (session.slots[0] as GameSession.PlayerSlot).round_state.get_instance_id() if not session.slots.is_empty() else 0


func _on_state_changed(s: int) -> void:
	if s == ShotTypes.State.ROUND_COMPLETE or not RoundSave.can_capture(session):
		return
	var key := _round_key()
	if key != _round_obj:  # a new round on the same session (play again / restart)
		_round_obj = key
		save_id = ""
	if save_id == "":
		created_at = int(Time.get_unix_time_from_system())
		save_id = RoundSave.make_id(created_at, session.round_state.round_seed)
	if telemetry != null and telemetry.last_round_id != "":
		_telemetry_round_id = telemetry.last_round_id
	var data := RoundSave.capture(session, {"id": save_id, "course_id": course_id, "course_name": course_name,
		"telemetry_round_id": _telemetry_round_id, "created_at": created_at})
	if not data.is_empty() and RoundSave.write(data, save_dir):
		RoundSave.prune(save_dir)


func _on_round_completed() -> void:
	var id := save_id if save_id != "" else RoundSave.make_id(int(Time.get_unix_time_from_system()), session.round_state.round_seed)
	RoundHistory.append(RoundHistory.build_record(session, {"id": id, "course_id": course_id, "course_name": course_name,
		"date": int(Time.get_unix_time_from_system())}), history_path)
	RoundSave.delete(save_id, save_dir)
	save_id = ""

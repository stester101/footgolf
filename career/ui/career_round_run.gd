class_name CareerRoundRun
extends RefCounted
## Glue between one career tournament round (a normal GameSession round played by RoundController) and the
## career save. Presentation-layer helper: it never changes gameplay, only stores state and gates Take Shot.
##  - course: the tournament's frozen snapshot (never the current data files)
##  - autosave: at every stable point (hole intro / aiming / shot result / hole complete) the RoundSave snapshot
##    goes INSIDE the career save (store_round_progress). A failed save is fail-closed: shots are blocked
##    (GameSession.shots_blocked_reason), a Save Error overlay offers Retry Save, nothing proceeds until saved.
##  - season footballer rule: every committed shot (mulliganed ones too) is recorded for the season.
##  - round end: records the round in the tournament, simulates the opponents, then `finished` is emitted.

signal finished

const SAVE_ERROR_TEXT := "Career progress could not be saved"

var career: CareerManager
var session: GameSession
var ui: GameUI
var round_label := ""
var _overlay: Control
var _done := false


func _init(p_career: CareerManager) -> void:
	career = p_career


func tournament() -> Dictionary:
	return career.tournament()


func hole_defs() -> Array:
	return CourseSnapshot.hole_defs(tournament().get("snapshot", {}))


func rules() -> RoundConfig:
	return RoundConfig.from_dict(tournament().get("rules", {}))


func mulligans() -> int:
	return int(tournament().get("mulligans", 0))


## The in-progress RoundSave dictionary, {} when the round starts fresh.
func resume_data() -> Dictionary:
	return tournament().get("round_save", {})


func course_id() -> String:
	return String((tournament()["snapshot"] as Dictionary).get("course_id", ""))


func course_name() -> String:
	return String((tournament()["snapshot"] as Dictionary).get("name", ""))


## Call after the session has been started or restored (start_round resets the pool).
func attach(p_session: GameSession, p_ui: GameUI = null) -> void:
	session = p_session
	ui = p_ui
	career.apply_season_lock(session.pool)
	session.state_changed.connect(_on_state_changed)
	session.shot_started.connect(_on_shot_started)
	if ui != null:
		ui.round_end_override = _on_round_end
		LiveLeaderboard.attach_to(ui, career, session)  # live tournament board (read-only)
	career.store.save_failed.connect(_on_save_failed)
	career.store.save_recovered.connect(_on_save_recovered)


func detach() -> void:
	if career.store.save_failed.is_connected(_on_save_failed):
		career.store.save_failed.disconnect(_on_save_failed)
	if career.store.save_recovered.is_connected(_on_save_recovered):
		career.store.save_recovered.disconnect(_on_save_recovered)


func _on_shot_started(req: ShotRequest) -> void:
	# committed at Take Shot: the footballer is spent for the season even if the shot is mulliganed later
	career.note_footballer_used(req.footballer_id)
	session.pool.lock_for_season(req.footballer_id)


func _on_state_changed(s: int) -> void:
	if _done or s == ShotTypes.State.ROUND_COMPLETE or not RoundSave.can_capture(session):
		return
	var t := tournament()
	var data := RoundSave.capture(session, {"id": "%s_r%d" % [String(t["id"]), int(t["round_index"]) + 1],
		"course_id": course_id(), "course_name": course_name(), "created_at": int(Time.get_unix_time_from_system())})
	if data.is_empty():
		return
	career.store_round_progress(data)  # a failure raises save_failed -> overlay + blocked shots


func _on_save_failed(_reason: String) -> void:
	session.shots_blocked_reason = SAVE_ERROR_TEXT
	show_save_error()


func _on_save_recovered() -> void:
	session.shots_blocked_reason = ""
	if _overlay != null and is_instance_valid(_overlay):
		if ui != null:
			ui._remove_overlay(_overlay)
		_overlay.queue_free()
	_overlay = null


func show_save_error() -> void:
	if ui == null or (_overlay != null and is_instance_valid(_overlay)):
		return
	_overlay = CareerPages.save_error_overlay(career.store, Callable())
	ui.push_overlay(_overlay)


func _on_round_end() -> void:
	if _done:
		return
	_done = true
	var rs := session.slot_round_state(0)
	var strokes := rs.total_score()
	var par := rs.total_par()
	var holes := rs.holes.size()
	RoundHistory.append(RoundHistory.build_record(session, {"id": "%s_r%d" % [String(tournament()["id"]), int(tournament()["round_index"]) + 1],
		"course_id": course_id(), "course_name": course_name(), "date": int(Time.get_unix_time_from_system())}))
	var status := career.complete_round(strokes, par, holes)
	if status == "":
		finished.emit()
		return
	_show_round_card(status, strokes, par)
	if career.store.is_blocked():
		session.shots_blocked_reason = SAVE_ERROR_TEXT
		show_save_error()  # on top of the card: Retry Save; the round result is retained in memory


func _show_round_card(status: String, strokes: int, par: int) -> void:
	if ui == null:
		finished.emit()
		return
	var t := tournament()
	var text := "Round %d: %d strokes (%s)" % [(t["human_rounds"] as Array).size(), strokes, RoundState.fmt_relative(strokes - par)]
	var sub: String = {"between_rounds": "Next: the leaderboard and round %d." % (int(t["round_index"]) + 1),
		"complete": "Tournament complete. See the results.", }.get(status, "")
	if bool(t.get("human_missed_cut", false)):
		sub = "You missed the cut. The event will finish without you."
	var card := CareerPages.round_done_overlay(text, String(sub), func() -> void:
		if career.store.is_blocked():
			return
		finished.emit())
	ui.push_overlay(card)


## Career shop cosmetics applied to a round's visuals (ball colour, flag colour). Visual only: never touches physics.
func apply_cosmetics(ball_mat: StandardMaterial3D, course_view: CourseView) -> void:
	var bc := ShopManager.equipped_color(career.data, "ball_color")
	if bc.a > 0.0:
		ball_mat.albedo_color = bc
		ball_mat.emission = bc * 0.25
	course_view.flag_tint = ShopManager.equipped_color(career.data, "flag")

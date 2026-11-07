class_name SmokeDriver
extends Node
## Runtime smoke test of the REAL scenes/UI. Enabled with:  godot --path . -- --smoke-test
## Optional: --screenshots=<dir> to save frames (needs a rendering driver, not --headless).
## Plays a full three-hole round by pressing the same UI buttons a player would.
## Exits 0 on success, 1 on failure.

var main: Node
var shots_dir := ""
var _log: Array[String] = []
var _shot_no := 0
var _picker_shot_done := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshots="):
			shots_dir = a.substr(14)
	_run.call_deferred()


func _say(t: String) -> void:
	print("[SMOKE] ", t)
	_log.append(t)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(shots_dir)
	img.save_png("%s/%02d_%s.png" % [shots_dir, _shot_no, name])
	_shot_no += 1


func _fail(msg: String) -> void:
	_say("FAIL: " + msg)
	get_tree().quit(1)


func _find_button(root: Node, text_prefix: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		var b := c as Button
		if b.is_visible_in_tree() and not b.disabled and b.text.begins_with(text_prefix):
			return b
	return null


func _press(text_prefix: String) -> bool:
	var b := _find_button(get_tree().root, text_prefix)
	if b == null:
		return false
	b.pressed.emit()
	return true


func _run() -> void:
	await _frames(5)
	await _shot("main_menu")
	var course_name := "Starter Links"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-course="):
			course_name = a.substr(15)
	if not _press(course_name):
		return _fail("no course button '%s'" % course_name)
	await _frames(10)
	var round_node: Node = get_tree().root.find_child("Round", true, false)
	if round_node == null:
		return _fail("round scene not created")
	var session: GameSession = round_node.session
	await _shot("hole_intro")
	var guard := 400
	var t0 := Time.get_ticks_msec()
	while session.state != ShotTypes.State.ROUND_COMPLETE and guard > 0:
		guard -= 1
		match session.state:
			ShotTypes.State.HOLE_INTRO:
				if not _press("Tee off"):
					return _fail("no Tee off button")
				await _frames(3)
				await _shot("hole%d_aim" % (session.round_state.current_index + 1))
			ShotTypes.State.AIMING:
				var d := session.distance_to_pin_m()
				session.aim_at_pin()
				var want_goals := d < 22.0
				if not _press("GOALS" if want_goals else "CAPS"):
					return _fail("mode button missing")
				if not _press("Choose footballer"):
					if not _press("▶"):
						return _fail("picker button missing")
				await _frames(2)
				if not _picker_shot_done:
					_picker_shot_done = true
					await _shot("picker")
				var picker := get_tree().root.find_children("*", "FootballerPicker", true, false)
				if picker.is_empty():
					return _fail("picker did not open")
				# pick first available footballer button in picker list
				var picked := false
				for c in (picker[0] as Node).find_children("*", "Button", true, false):
					var b := c as Button
					if not b.disabled and b.has_meta("footballer_id"):
						b.pressed.emit()
						picked = true
						break
				if not picked:
					# first page is all used by now: use the picker's Random button (also covers that feature)
					for c in (picker[0] as Node).find_children("*", "Button", true, false):
						if (c as Button).text == "Random" and not (c as Button).disabled:
							(c as Button).pressed.emit()
							picked = true
							break
				if not picked:
					return _fail("no available footballer")
				await _frames(2)
				if session.selected_id == "":
					return _fail("selection not applied")
				var before := session.current_hole_state().strokes
				if not _press("TAKE SHOT"):
					return _fail("Take Shot not pressable")
				if session.current_hole_state().strokes != before + 1:
					return _fail("stroke not counted exactly once")
				_press("TAKE SHOT")  # double tap must be ignored
				if session.current_hole_state().strokes != before + 1:
					return _fail("double tap counted twice")
				await _frames(20)
				if session.is_ball_moving():
					await _shot("in_flight")
					_press("Skip")
				await _frames(3)
			ShotTypes.State.SHOT_RESULT:
				await _shot("result")
				var r := session.last_result
				_say("H%d shot %d: %s %s -> %s, carry %.1f m total %.1f m, pen %d, holed %s" % [
					session.round_state.current_index + 1, r.shot_id, r.footballer_name, r.mode_name(), r.stat_label(),
					r.carry_m, r.total_m, r.penalty, r.holed])
				if not _press("Continue"):
					return _fail("no Continue")
				await _frames(2)
			ShotTypes.State.HOLE_COMPLETE:
				await _shot("hole_complete")
				if not (_press("Next hole") or _press("Finish round")):
					return _fail("no next hole button")
				await _frames(10)
			_:
				await _frames(1)
	if session.state != ShotTypes.State.ROUND_COMPLETE:
		return _fail("round did not complete (state %s)" % ShotTypes.state_name(session.state))
	await _frames(3)
	await _shot("round_complete")
	var rs := session.round_state
	_say("ROUND COMPLETE total %d (%s), shots %d, used %d, %.1f s" % [rs.total_score(), RoundState.fmt_relative(rs.relative_to_par()), session.history.size(), session.pool.used_count(), (Time.get_ticks_msec() - t0) / 1000.0])
	# developer panel opens and closes without error
	round_node.toggle_dev_panel()
	await _frames(3)
	await _shot("dev_panel")
	round_node.toggle_dev_panel()
	if not _press("Main menu"):
		return _fail("no main menu button")
	await _frames(5)
	_say("PASS")
	get_tree().quit(0)

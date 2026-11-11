class_name SmokeDriver
extends Node
## Runtime smoke test of the REAL scenes/UI. Enabled with:  godot --path . -- --smoke-test
## Optional: --screenshots=<dir> to save frames (needs a rendering driver, not --headless).
## Plays a full three-hole round by pressing the same UI buttons a player would.
## Exits 0 on success, 1 on failure.

var main: Node
var shots_dir := ""
var _stop_after := ""
var _log: Array[String] = []
var _shot_no := 0
var _picker_shot_done := false
var _card_done := false
var _pit_shots := 0
var _menus_done := false
var _last_pos := Vector3.INF
var _stuck := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshots="):
			shots_dir = a.substr(14)
		if a.begins_with("--smoke-stop="):
			_stop_after = a.substr(13)
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
	if _stop_after != "" and name == _stop_after:
		get_tree().quit(0)


func _fail(msg: String) -> void:
	_say("FAIL: " + msg)
	get_tree().quit(1)


func _find_button(root: Node, text_prefix: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		var b := c as Button
		if b.is_visible_in_tree() and not b.disabled and (b.text.to_lower().begins_with(text_prefix.to_lower()) or String(b.get_meta("press_text", "")).to_lower().begins_with(text_prefix.to_lower())):
			return b
	return null


func _find_id(root: Node, ui_id: String) -> Button:
	for c in root.find_children("*", "Button", true, false):
		var b := c as Button
		if b.is_visible_in_tree() and not b.disabled and b.has_meta("ui_id") and String(b.get_meta("ui_id")) == ui_id:
			return b
	return null


func _find_ui_prefix(prefix: String) -> Button:
	for c in get_tree().root.find_children("*", "Button", true, false):
		var b := c as Button
		if b.is_visible_in_tree() and not b.disabled and b.has_meta("ui_id") and String(b.get_meta("ui_id")).begins_with(prefix):
			return b
	return null


func _press_id(ui_id: String) -> bool:
	var b := _find_id(get_tree().root, ui_id)
	if b == null:
		return false
	b.pressed.emit()
	return true


func _press(text_prefix: String) -> bool:
	var b := _find_button(get_tree().root, text_prefix)
	if b == null:
		return false
	b.pressed.emit()
	return true


func _run() -> void:
	if OS.get_cmdline_user_args().has("--smoke-career"):
		await _career_run()
		return
	if OS.get_cmdline_user_args().has("--smoke-perf"):
		await _perf_run()
		return
	App.settings.holeout_radius_ft = 5.0  # smoke rounds rely on the auto hole-out radius (game default is 0 ft)
	await _frames(5)
	await _shot("main_menu")
	var course_name := "Starter Links"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-course="):
			course_name = a.substr(15)
		if a == "--smoke-gfx=low":
			App.settings.graphics_quality = 0
		if a == "--smoke-gfx=high":
			App.settings.graphics_quality = 1
		if a == "--smoke-glow":
			App.settings.graphics_glow = true
		if a == "--smoke-skylife":
			SkyLife.preview = true  # birds + jet appear straight ahead at once (for screenshots)
	if OS.get_cmdline_user_args().has("--smoke-tour"):
		for step in [["How to Play", "tutorial"], ["Next", "tutorial2"], ["Skip tutorial", ""],
				["Settings", "settings"], ["Gameplay", "settings_gameplay"], ["Edit hole pars", "par_editor"], ["Done", ""], ["BACK", ""], ["Controls", "settings_controls"], ["BACK", ""],
				["Audio", "settings_visual"], ["BACK", ""], ["Developer", "settings_developer"], ["Export data", "export"], ["Done", ""], ["BACK", ""], ["BACK", ""],
				["Statistics", "statistics"], ["Overview", "stats_overview"], ["BACK", ""], ["BACK", ""]]:
			if step[0] == "BACK":
				_press_id("back")
			elif not _press(String(step[0])):
				return _fail("tour: no button '%s'" % step[0])
			await _frames(3)
			if step[1] != "":
				await _shot(String(step[1]))
		await _shot("tour_end")
	if not _press("Single Player"):
		return _fail("no Single Player button")
	await _frames(3)
	await _shot("course_select")
	if not _press(course_name):
		return _fail("no course button '%s'" % course_name)
	await _frames(3)
	await _shot("round_setup")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-players="):
			_press_id("players_%s" % a.substr(16))
	if not _press("Start round"):
		return _fail("no Start round button")
	await _frames(10)
	var round_node: Node = get_tree().root.find_child("Round", true, false)
	if round_node == null:
		return _fail("round scene not created")
	var session: GameSession = round_node.session
	await _shot("hole_intro")
	var guard := 3000
	var t0 := Time.get_ticks_msec()
	while session.state != ShotTypes.State.ROUND_COMPLETE and guard > 0:
		guard -= 1
		match session.state:
			ShotTypes.State.HOLE_INTRO:
				if not _press("Tee off"):
					return _fail("no Tee off button")
				await _frames(3)
				if SkyLife.preview:
					await get_tree().create_timer(4.0).timeout  # let the birds/jet spawn
				await _shot("hole%d_aim" % (session.round_state.current_index + 1))
				if OS.get_cmdline_user_args().has("--smoke-near-pin"):
					# Dev tool check: drop the ball 4 m short of the pin and photograph the cup and flag close up.
					var pin3 := session.hole.cup_position()
					var tee3 := session.ball_pos
					var dir2 := Vector2(pin3.x - tee3.x, pin3.z - tee3.z).normalized()
					var err := session.dev_place_ball(pin3.x - dir2.x * 3.0 + dir2.y * 1.5, pin3.z - dir2.y * 3.0 - dir2.x * 1.5)
					await _frames(20)
					await _shot("hole%d_near_pin%s" % [session.round_state.current_index + 1, "" if err == "" else "_FAILED"])
			ShotTypes.State.AIMING:
				if OS.get_cmdline_user_args().has("--smoke-card") and session.shot_counter >= 2 and not _card_done:
					_card_done = true
					await _shot("before_card")
					if _press_id("card"):
						await _frames(3)
						await _shot("scorecard")
						_press_id("back_to_round")
						await _frames(3)
						await _shot("after_card")
				if OS.get_cmdline_user_args().has("--smoke-menus") and not _menus_done:
					_menus_done = true
					await _menus_tour()
				var d := session.distance_to_pin_m()
				session.aim_at_pin()
				var want_goals := d < 22.0 or session.current_lie() == Surface.Type.GREEN
				# no maximum score: if the last shot made no progress (trees + relief), escape sideways
				_stuck = _stuck + 1 if session.ball_pos.distance_to(_last_pos) < 3.0 else 0
				_last_pos = session.ball_pos
				if _stuck > 0:
					var offs := [35.0, -35.0, 70.0, -70.0, 100.0, -100.0]
					session.set_aim(session.aim_bearing_deg + float(offs[(_stuck - 1) % offs.size()]))
					want_goals = _stuck % 2 == 0
					d = minf(d * 0.5, 60.0)
				if not _press_id("mode_goals" if want_goals else "mode_caps"):
					return _fail("mode button missing")
				if not _press_id("style_roll" if want_goals else "style_flight"):
					return _fail("style button missing")
				if not want_goals and session.round_state.current_index == 1 and session.current_hole_state().strokes == 0:
					var t0_traj := session.trajectory
					if not _press_id("trajectory"):
						return _fail("trajectory button missing")
					if session.trajectory == t0_traj:
						return _fail("trajectory button did nothing")
					await _frames(2)
					await _shot("trajectory")
				if not _press_id("player_row"):
					return _fail("player row missing")
				await _frames(2)
				if not _picker_shot_done:
					_picker_shot_done = true
					await _shot("picker")
					if OS.get_cmdline_user_args().has("--smoke-filters") and _press_id("filters"):
						await _frames(2)
						for c in get_tree().root.find_children("*", "Button", true, false):
							var fbn := c as Button
							if fbn.is_visible_in_tree() and ((fbn.has_meta("nation") and String(fbn.get_meta("nation")) == "England") or fbn.text == "1980s"):
								fbn.pressed.emit()
						await _frames(2)
						await _shot("filters")
						_press_id("apply_filters")
						await _frames(3)
						await _shot("picker_filtered")
				var picker := get_tree().root.find_children("*", "FootballerPicker", true, false)
				if picker.is_empty():
					return _fail("picker did not open")
				# First shot of the round: tap the first list entry (covers the list). Afterwards behave
				# like a knowledgeable player (no score cap any more, so the bot must be able to hole out).
				var picked := false
				if session.round_state.current_index == 0 and session.current_hole_state().strokes == 0:
					for c in (picker[0] as Node).find_children("*", "Button", true, false):
						var b := c as Button
						if not b.disabled and b.has_meta("footballer_id"):
							b.pressed.emit()
							picked = true
							break
				else:
					var need := Units.m_to_feet(d) if want_goals else Units.m_to_yards(d)
					var best: Footballer = null
					for fb in session.repo.all_sorted():
						if not session.pool.is_available(fb.id, session.mode):
							continue
						var stat := float(fb.goals if want_goals else fb.caps)
						if best == null or absf(stat - need) < absf(float(best.goals if want_goals else best.caps) - need):
							best = fb
					if best != null and session.select_footballer(best.id):
						(picker[0] as FootballerPicker).picked.emit(best.id)
						picked = true
				if not picked:
					# first page is all used by now: use the picker's Random button (also covers that feature)
					for c in (picker[0] as Node).find_children("*", "Button", true, false):
						if ((c as Button).text == "Random" or String((c as Button).get_meta("ui_id", "")) == "random") and not (c as Button).disabled:
							(c as Button).pressed.emit()
							picked = true
							break
				if not picked:
					return _fail("no available footballer")
				await _frames(2)
				if session.selected_id == "":
					return _fail("selection not applied")
				var before := session.current_hole_state().strokes
				if not _press_id("take_shot"):
					return _fail("Take Shot not pressable")
				if session.current_hole_state().strokes != before + 1:
					return _fail("stroke not counted exactly once")
				_press_id("take_shot")  # double tap must be ignored
				if session.current_hole_state().strokes != before + 1:
					return _fail("double tap counted twice")
				await _frames(1 if OS.get_cmdline_user_args().has("--smoke-near-pin") else 20)
				if OS.get_cmdline_user_args().has("--smoke-near-pin") and _pit_shots < 8:
					# Dev tool check: photograph the ball at fixed intervals while it rolls up to and into the hole.
					for _k in 4:
						_pit_shots += 1
						await _shot("hole%d_in_pit_%d" % [session.round_state.current_index + 1, _pit_shots])
						await _frames(2)
				if session.is_ball_moving():
					await _shot("in_flight")
					_press_id("skip")
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
				# "Next hole" stays greyed while the next hole is prepared behind the loading bar.
				var waited := 0
				while _find_button(get_tree().root, "Next hole") == null and _find_button(get_tree().root, "Finish round") == null:
					waited += 1
					if waited > 1800:
						return _fail("no next hole button (still greyed after %d frames)" % waited)
					await _frames(1)
				if waited > 0:
					_say("next hole ready after %d frames" % waited)
					await _shot("hole_ready")
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


## Dev screenshots of the pause menu, confirm dialog, developer panel (--smoke-menus; quits afterwards).
func _menus_tour() -> void:
	if not _press_id("pause"):
		return _fail("menus: no pause button")
	await _frames(3)
	await _shot("pause")
	_press("Restart round")
	await _frames(3)
	await _shot("confirm")
	_press("Cancel")
	await _frames(2)
	_press_id("pause")
	await _frames(3)
	if not _press("Developer panel"):
		return _fail("menus: no developer panel button")
	await _frames(4)
	await _shot("dev_ball")
	var tabs: Array = get_tree().root.find_children("*", "TabContainer", true, false)
	for i in 4:
		if tabs.size() > 0:
			(tabs[0] as TabContainer).current_tab = i
			await _frames(3)
			await _shot("dev_tab%d" % i)
	get_tree().quit(0)


# ------------------------------------------------------------------ performance measurement (--smoke-perf)
# One course per process:  --smoke-perf --smoke-course="Pinewood Ridge" [--smoke-gfx=low] [--perf-out=<file>]
# Measures hole load, tee view, a full-flight shot, a putt and the hole-to-hole transition, using the real UI.
# Needs a rendering driver (xvfb), numbers from --headless would not include drawing. Never run in the test suite.
var _perf_lines: Array[String] = []


func _perf(t: String) -> void:
	print("[PERF] ", t)
	_perf_lines.append(t)


## Awaits frames until `until` returns true (or max_frames); returns the per-frame wall times in ms.
func _perf_n(default_n: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perf-frames="):
			return int(a.substr(14))
	return default_n


func _perf_frames(max_frames: int, until: Callable = Callable()) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for i in max_frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		out.append(float(now - last) / 1000.0)
		last = now
		if until.is_valid() and until.call():
			break
	return out


## Script time of RoundController._process since the last call (ms): avg, max, and grass/trail/advance totals per frame.
func _perf_script(label: String) -> void:
	var p: Dictionary = get_tree().root.find_child("Round", true, false).perf
	var n := maxi(int(p["n"]), 1)
	_perf("  script %s: _process avg %.2f ms, max %.2f ms; per frame: advance %.2f, place_grass %.2f, trail %.2f ms (%d frames)" % [label,
		float(p["sum"]) / n / 1000.0, float(p["max"]) / 1000.0, float(p["advance"]) / n / 1000.0,
		float(p["grass"]) / n / 1000.0, float(p["trail"]) / n / 1000.0, int(p["n"])])
	for k in p:
		p[k] = 0


func _perf_stats(label: String, f: PackedFloat64Array) -> void:
	if f.is_empty():
		_perf("%s: no frames" % label)
		return
	var s := Array(f)
	s.sort()
	var sum := 0.0
	for v in f:
		sum += v
	var p95: float = s[mini(int(ceil(0.95 * s.size())) - 1, s.size() - 1)]
	_perf("%s: frames %d, avg %.1f ms, p95 %.1f ms, max %.1f ms" % [label, f.size(), sum / f.size(), p95, s[s.size() - 1]])


func _perf_counters(label: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_perf("%s: nodes %d, objects/frame %d, draw calls/frame %d, primitives/frame %d, video mem %.1f MB" % [label,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])


## Same UI path a player uses: mode, style, footballer closest to the needed stat, Take Shot.
func _perf_shot(session: GameSession, want_goals: bool) -> bool:
	session.aim_at_pin()
	var d := session.distance_to_pin_m()
	if not _press_id("mode_goals" if want_goals else "mode_caps"):
		return false
	if not _press_id("style_roll" if want_goals else "style_flight"):
		return false
	if not _press_id("player_row"):
		return false
	await _frames(2)
	var need := Units.m_to_feet(d) if want_goals else Units.m_to_yards(d)
	var best: Footballer = null
	for fb in session.repo.all_sorted():
		if not session.pool.is_available(fb.id, session.mode):
			continue
		var stat := float(fb.goals if want_goals else fb.caps)
		if best == null or absf(stat - need) < absf(float(best.goals if want_goals else best.caps) - need):
			best = fb
	var picker := get_tree().root.find_children("*", "FootballerPicker", true, false)
	if best == null or picker.is_empty() or not session.select_footballer(best.id):
		return false
	(picker[0] as FootballerPicker).picked.emit(best.id)
	await _frames(2)
	return _press_id("take_shot")


func _perf_run() -> void:
	App.settings.holeout_radius_ft = 5.0
	var course_name := "Starter Links"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke-course="):
			course_name = a.substr(15)
		if a == "--smoke-gfx=low":
			App.settings.graphics_quality = 0
	_perf("== %s, graphics %s, renderer %s, driver %s" % [course_name, "High" if App.settings.graphics_quality == 1 else "Low",
		RenderingServer.get_current_rendering_method(), DisplayServer.get_name()])
	await _frames(5)
	if not _press("Single Player"):
		return _fail("perf: Single Player")
	await _frames(3)
	if not _press(course_name):
		return _fail("perf: course select")
	await _frames(3)
	# --- hole load: from Start round until the hole intro is ready and drawn
	var t0 := Time.get_ticks_usec()
	if not _press("Start round"):
		return _fail("perf: no Start round")
	var round_node: Node = get_tree().root.find_child("Round", true, false)
	var tb := Time.get_ticks_usec()
	if round_node == null:
		return _fail("perf: round scene missing")
	var session: GameSession = round_node.session
	_perf("hole 1 load, synchronous part (Start round press, includes round scene + HUD + hole build): %.0f ms" % ((tb - t0) / 1000.0))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_perf("hole 1 ready (first drawn frame): %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	var jobs := ""
	for k in round_node.course.job_usec:
		jobs += "%s %.0f ms; " % [k, float(round_node.course.job_usec[k]) / 1000.0]
	_perf("hole 1 build jobs: " + jobs)
	await _frames(20)
	if not _press("Tee off"):
		return _fail("perf: no Tee off")
	await _frames(60)  # let the camera settle
	for k in round_node.perf:
		round_node.perf[k] = 0
	_perf_stats("tee view (idle, aiming)", await _perf_frames(_perf_n(150)))
	_perf_script("tee view")
	await _perf_counters("tee view counters")
	# --- full flight shot
	if not await _perf_shot(session, false):
		return _fail("perf: flight shot not taken")
	var flight := await _perf_frames(900, func() -> bool: return not session.is_ball_moving())
	_perf_stats("full-flight shot (ball moving)", flight)
	_perf_script("flight")
	await _frames(3)
	var guard := 40
	while session.state != ShotTypes.State.AIMING and guard > 0:
		guard -= 1
		if session.state == ShotTypes.State.SHOT_RESULT:
			_press("Continue")
		await _frames(2)
	_perf_stats("aiming after shot (idle, new ball position)", await _perf_frames(_perf_n(60)))
	# --- putt: dev ball placement 3 m short of the pin, then hole out
	var pin := session.hole.cup_position()
	var dir2 := Vector2(pin.x - session.ball_pos.x, pin.z - session.ball_pos.z).normalized()
	var err := session.dev_place_ball(pin.x - dir2.x * 3.0 + dir2.y * 1.0, pin.z - dir2.y * 3.0 - dir2.x * 1.0)
	if err != "":
		return _fail("perf: dev_place_ball " + err)
	await _frames(30)
	_perf_stats("putt position (idle, on green)", await _perf_frames(_perf_n(100)))
	var putt := PackedFloat64Array()
	var tries := 0
	while session.state != ShotTypes.State.HOLE_COMPLETE and tries < 6:
		tries += 1
		if session.state == ShotTypes.State.SHOT_RESULT:
			_press("Continue")
			await _frames(2)
			continue
		if session.state != ShotTypes.State.AIMING:
			await _frames(2)
			continue
		if not await _perf_shot(session, true):
			return _fail("perf: putt not taken")
		putt.append_array(await _perf_frames(900, func() -> bool: return not session.is_ball_moving()))
		await _frames(3)
	_perf_stats("putt (ball rolling, %d putt(s))" % tries, putt)
	_perf_script("putt")
	if session.state == ShotTypes.State.SHOT_RESULT:
		_press("Continue")
		await _frames(3)
	if session.state != ShotTypes.State.HOLE_COMPLETE:
		return _fail("perf: hole not completed (state %s)" % ShotTypes.state_name(session.state))
	# --- hole-to-hole transition: preload behind the summary, then Next hole
	var pre_t0 := Time.get_ticks_usec()
	var pre := PackedFloat64Array()
	var last := pre_t0
	var waited := 0
	while _find_button(get_tree().root, "Next hole") == null and waited < 3000:
		waited += 1
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		pre.append(float(now - last) / 1000.0)
		last = now
	_perf("next-hole preload (hole summary shown, loading bar): %.0f ms wall over %d frames" % [(last - pre_t0) / 1000.0, waited])
	_perf_stats("  frame times during preload", pre)
	var t1 := Time.get_ticks_usec()
	if not _press("Next hole"):
		return _fail("perf: no Next hole")
	var tsync := Time.get_ticks_usec()
	_perf("Next hole press -> hole 2 swapped in (synchronous): %.0f ms" % ((tsync - t1) / 1000.0))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_perf("Next hole press -> first drawn frame of hole 2: %.0f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perf-out="):
			out = a.substr(11)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		if f != null:
			f.store_string("\n".join(_perf_lines) + "\n")
	_say("PERF DONE")
	get_tree().quit(0)


# ------------------------------------------------------------------ career pages (--smoke-career [--screenshots=<dir>])

func _scroll_down() -> void:
	for sc in get_tree().root.find_children("*", "ScrollContainer", true, false):
		var s := sc as ScrollContainer
		if s.is_visible_in_tree():
			s.scroll_vertical = 100000


## Seeds a career in a scratch folder (a few events played by a strong player, one skipped), then opens the
## Career pages through the real menu and saves screenshots of them. Does not touch the player's own career.
func _career_run() -> void:
	await _frames(5)
	if OS.get_cmdline_user_args().has("--large-text"):  # accessibility pass: Larger text + Reduced motion (not saved)
		App.settings.large_text = true
		App.settings.reduced_motion = true
	var c := CareerManager.new(CareerSaveManager.new("user://smoke_career"))
	c.store.delete_career()
	CareerManager.course_source = func(id: String) -> Dictionary: return CourseSource.load_course(id, App.settings.par_overrides)
	if not c.create("Sam Smoke", "England", "short", 31337):
		return _fail("career create")
	var played := 0
	while played < 8 and not c.season_finished():
		var e := c.next_event()
		var serial := int(e["serial"])
		if played == 1 or not bool(c.eligibility(e)["eligible"]):
			c.skip_event(serial)
		else:
			c.enter_event(serial)
			_career_play_out(c, played)
			c.finalize_tournament()
		CareerKit.note_ranks(c)  # the UI's previous-table cache, so the rank movement arrows have something to show
		played += 1
	CareerManager.active = c
	_say("career seeded: %d events, world rank %d" % [played, c.world_rank()])
	await _frames(3)
	var menu := get_tree().root.find_children("*", "MainMenu", true, false)[0] as MainMenu
	if menu._tutorial != null and is_instance_valid(menu._tutorial):
		menu.handle_back()  # first launch on this machine: close the tutorial
		await _frames(3)
	if not _press("Career Mode"):
		return _fail("no Career Mode button")
	await _career_shot("career_hub")
	_scroll_down()
	await _career_shot("career_hub_lower")
	# Schedule tab -> event -> report
	if not await _career_step("career_tab_schedule", "career_schedule"):
		return
	if not await _career_step("career_event_1", "career_event"):
		return
	if not await _career_step("career_event_report", "career_report"):
		return
	_scroll_down()
	await _career_shot("career_report_lower")
	_press_id("back")
	await _frames(3)
	_press_id("back")
	await _frames(3)
	# Rankings tab (world, standings, full table)
	if not await _career_step("career_tab_rankings", "career_rankings_world"):
		return
	if not await _career_step("career_rank_view_1", "career_rankings_standings"):
		return
	if not await _career_step("career_rank_full", "career_standings_full"):
		return
	_press_id("back")
	await _frames(3)
	# Me tab and its pages
	if not await _career_step("career_tab_me", "career_me"):
		return
	_scroll_down()
	await _career_shot("career_me_lower")
	for step in [["career_trophies", "career_trophies"], ["career_rivals", "career_rivals"], ["career_settings", "career_settings"]]:
		if not await _career_step(String(step[0]), String(step[1])):
			return
		_press_id("back")
		await _frames(3)
	if not await _career_step("career_sponsors_me", "career_sponsors"):
		return
	var sign_btn := _find_ui_prefix("sponsor_sign_")
	if sign_btn == null:
		return _fail("no sponsor offer to sign")
	sign_btn.pressed.emit()
	await _career_shot("career_sponsors_signed")
	_press_id("back")
	await _frames(3)
	if not await _career_step("career_shop_me", "career_shop"):
		return
	_press_id("back")
	await _frames(3)
	# Android Back from a non-Hub tab returns to the Hub
	menu.handle_back()
	await _frames(3)
	if String(menu._stack.back().get_meta("career_tab", "")) != "hub":
		return _fail("Back from the Me tab did not return to the Hub")
	_say("back from tab -> hub OK")
	# enter the next event through the Hub CTA: tournament page and round setup
	if not await _career_step("career_next_event", "career_tournament"):
		return
	if not await _career_step("career_setup_round", "career_round_setup"):
		return
	_press_id("back")
	await _frames(3)
	_career_play_out(c, 0)
	CareerPages._replace(menu, func() -> void: CareerPages.open_tournament(menu))  # the page reflects the finished rounds
	await _career_shot("career_tournament_done")
	if not await _career_step("career_finish", "career_results"):
		return
	if not await _career_step("career_results_done", "career_hub_after_event"):
		return
	# finish the season (skips) and walk the off-season
	while not c.season_finished():
		c.skip_next_event()
	CareerShell.go(menu, "schedule")
	CareerShell.go(menu, "hub")
	await _career_shot("career_hub_season_done")
	if not await _career_step("career_next_season", "career_offseason_1"):
		return
	for i in range(2, 6):
		if not await _career_step("career_offseason_next", "career_offseason_%d" % i):
			return
	if not _press_id("career_offseason_next"):
		return _fail("no Start next season button")
	await _career_shot("career_hub_new_season")
	_say("PASS career pages")
	get_tree().quit(0)


func _career_play_out(c: CareerManager, k: int) -> void:
	var t := c.tournament()
	var par := TournamentManager.par_per_round(t)
	var holes: int = ((t["snapshot"] as Dictionary)["holes"] as Array).size()
	while String(c.tournament()["status"]) != "complete":
		c.begin_round({}, 0)
		c.complete_round(maxi(holes, par - 2 * holes + (k % 3)), par, holes)


## Waits for the Career entrance motion (count-ups, fades) to settle, then saves a screenshot.
func _career_shot(name: String) -> void:
	await _frames(4)
	if shots_dir != "" and DisplayServer.get_name() != "headless":
		await get_tree().create_timer(1.1).timeout
	await _shot(name)


func _career_step(ui_id: String, shot: String) -> bool:
	if not _press_id(ui_id):
		_fail("no career button %s" % ui_id)
		return false
	await _career_shot(shot)
	return true

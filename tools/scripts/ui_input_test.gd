# Run under a display server: xvfb-run -a -s "-screen 0 720x1280x24" godot --path . --rendering-method mobile --resolution 450x800 -s res://tools/scripts/ui_input_test.gd
extends SceneTree
# Real input routing test: events go through Input.parse_input_event -> GUI -> unhandled input.
# Positions are given in VIEWPORT coordinates and converted to window pixels like a real touch.
var r
var k := 1.0
func w(p: Vector2) -> Vector2: return p * k
func tap(pos: Vector2, idx := 0) -> void:
	var t := InputEventScreenTouch.new(); t.index = idx; t.position = w(pos); t.pressed = true
	Input.parse_input_event(t)
	await process_frame
	t = InputEventScreenTouch.new(); t.index = idx; t.position = w(pos); t.pressed = false
	Input.parse_input_event(t)
	await process_frame
	await process_frame
func drag(a: Vector2, b: Vector2) -> void:
	var t := InputEventScreenTouch.new(); t.index = 0; t.position = w(a); t.pressed = true
	Input.parse_input_event(t)
	await process_frame
	for i in 6:
		var d := InputEventScreenDrag.new(); d.index = 0
		d.position = w(a.lerp(b, (i + 1) / 6.0)); d.relative = w((b - a) / 6.0)
		Input.parse_input_event(d)
		await process_frame
	t = InputEventScreenTouch.new(); t.index = 0; t.position = w(b); t.pressed = false
	Input.parse_input_event(t)
	await process_frame
func center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()
func _initialize():
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5: await process_frame
	if main._menu._tutorial: main._menu._tutorial.finished.emit()
	main.start_round("starter", false)
	for i in 10: await process_frame
	r = root.find_child("Round", true, false)
	var s: GameSession = r.session
	s.begin_play(); r.ui.close_all_overlays(); r._set_overhead(false)
	for i in 20: await process_frame
	var vp := root.get_visible_rect().size
	k = float(DisplayServer.window_get_size().x) / vp.x
	var ok := true
	var aim0 := s.aim_bearing_deg
	await drag(Vector2(vp.x * 0.4, vp.y * 0.45), Vector2(vp.x * 0.7, vp.y * 0.45))
	var aim1 := s.aim_bearing_deg
	print("1) open-space drag aim %.1f -> %.1f (expect change): %s" % [aim0, aim1, "PASS" if absf(aim1 - aim0) > 1.0 else "FAIL"])
	ok = ok and absf(aim1 - aim0) > 1.0
	await drag(center(r.ui._player_btn) + Vector2(-100, 0), center(r.ui._player_btn) + Vector2(100, 0))
	var aim2 := s.aim_bearing_deg
	print("2) drag across player row: aim %.1f -> %.1f (expect same): %s" % [aim1, aim2, "PASS" if absf(aim2 - aim1) < 0.01 else "FAIL"])
	ok = ok and absf(aim2 - aim1) < 0.01
	r.ui.close_all_overlays()
	for i in 3: await process_frame
	await tap(center(r.ui._right_shot.get_child(1)))
	var in_map: bool = r.rig.mode == CameraRig.Mode.OVERHEAD
	print("3) tap Map button: overhead=%s aim %.1f (expect true, unchanged): %s" % [in_map, s.aim_bearing_deg, "PASS" if in_map and absf(s.aim_bearing_deg - aim2) < 0.01 else "FAIL"])
	ok = ok and in_map and absf(s.aim_bearing_deg - aim2) < 0.01
	var size0: float = r.rig.cam.size
	await tap(center(r.ui._right_map.get_child(0)))
	print("4) tap +: cam size %.1f -> %.1f (expect smaller), no target placed: %s" % [size0, r.rig.cam.size, "PASS" if r.rig.cam.size < size0 and r.ui._target_dist_m < 0.0 else "FAIL"])
	ok = ok and r.rig.cam.size < size0 and r.ui._target_dist_m < 0.0
	await tap(Vector2(vp.x * 0.45, vp.y * 0.5))
	print("5) tap empty map: target %.1f m (expect >0): %s" % [r.ui._target_dist_m, "PASS" if r.ui._target_dist_m > 0.0 else "FAIL"])
	ok = ok and r.ui._target_dist_m > 0.0
	await tap(center(r.ui._map_controls.get_child(r.ui._map_controls.get_child_count() - 1)))
	print("6) tap Return to shot: overhead=%s (expect false): %s" % [r.rig.mode == CameraRig.Mode.OVERHEAD, "PASS" if r.rig.mode != CameraRig.Mode.OVERHEAD else "FAIL"])
	ok = ok and r.rig.mode != CameraRig.Mode.OVERHEAD
	var aim6 := s.aim_bearing_deg
	await tap(center(r.ui._shot_btn))
	var pk: bool = not root.find_children("*", "FootballerPicker", true, false).is_empty()
	print("7) tap Take shot (no player): picker open=%s strokes=%d aim unchanged=%s (expect true,0,true): %s" % [pk, s.current_hole_state().strokes, absf(s.aim_bearing_deg - aim6) < 0.01, "PASS" if pk and s.current_hole_state().strokes == 0 and absf(s.aim_bearing_deg - aim6) < 0.01 else "FAIL"])
	ok = ok and pk and s.current_hole_state().strokes == 0
	r.ui.close_all_overlays()
	for i in 3: await process_frame
	r.ui.show_scorecard()
	for i in 5: await process_frame
	var a8 := s.aim_bearing_deg
	await drag(Vector2(vp.x * 0.3, vp.y * 0.5), Vector2(vp.x * 0.7, vp.y * 0.5))
	print("8) drag behind scorecard: aim %.1f -> %.1f (expect same): %s" % [a8, s.aim_bearing_deg, "PASS" if absf(s.aim_bearing_deg - a8) < 0.01 else "FAIL"])
	ok = ok and absf(s.aim_bearing_deg - a8) < 0.01
	await tap(center(root.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("ui_id") and b.get_meta("ui_id") == "back_to_round")[0]))
	print("9) tap Back to round: scorecard closed=%s (expect true): %s" % [not r.ui.has_overlay(), "PASS" if not r.ui.has_overlay() else "FAIL"])
	ok = ok and not r.ui.has_overlay()
	print("INPUT ROUTING: ", "ALL PASS" if ok else "FAILURES")
	quit()

class_name GameUI
extends Control
## Portrait gameplay HUD + overlays (picker, shot result, hole intro/complete, scorecard,
## pause, round complete). Reads from GameSession; only calls session APIs to act.

signal camera_toggle_requested
signal main_menu_requested
signal developer_requested

var session: GameSession
var _top_title: Label
var _top_score: Label
var _lie_label: Label
var _pin_label: Label
var _wind_label: Label
var _wind: WindIndicator
var _bottom: VBoxContainer
var _controls: VBoxContainer
var _result_box: VBoxContainer
var _caps_btn: Button
var _goals_btn: Button
var _pick_btn: Button
var _shot_btn: Button
var _skip_btn: Button
var _hint: Label
var _toast: Label
var _toast_t := 0.0
var _measure_label: Label
var _view_btn: Button
var _overlays: Array[Control] = []
var _margin: MarginContainer
var camera_yaw := 0.0
var overhead := false


func setup(s: GameSession) -> void:
	session = s
	theme = UiKit.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)
	_apply_safe_area()
	var col := UiKit.vbox(10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(col)
	_build_top(col)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	_toast = UiKit.text("", 24, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.add_theme_constant_override("outline_size", 6)
	col.add_child(_toast)
	_build_bottom(col)
	session.state_changed.connect(func(_s: int) -> void: refresh())
	session.selection_changed.connect(refresh)
	session.shot_resolved.connect(_on_shot_resolved)
	session.hole_completed.connect(_on_hole_completed)
	session.round_completed.connect(_on_round_completed)
	session.message.connect(toast)
	session.ball_placed.connect(refresh)
	refresh()


func _apply_safe_area() -> void:
	var sm := UiKit.safe_margins(get_viewport()) if is_inside_tree() else [16.0, 16.0, 16.0, 16.0]
	_margin.add_theme_constant_override("margin_left", int(sm[0]))
	_margin.add_theme_constant_override("margin_top", int(sm[1]))
	_margin.add_theme_constant_override("margin_right", int(sm[2]))
	_margin.add_theme_constant_override("margin_bottom", int(sm[3]))


func _build_top(col: VBoxContainer) -> void:
	var p := UiKit.panel()
	col.add_child(p)
	var v := UiKit.vbox(4)
	p.add_child(v)
	var r1 := UiKit.hbox()
	_top_title = UiKit.expand(UiKit.label("", 28)) as Label
	_top_score = UiKit.label("", 22, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	r1.add_child(_top_title)
	r1.add_child(_top_score)
	v.add_child(r1)
	_lie_label = UiKit.text("", 21, UiKit.C_MUTED)
	v.add_child(_lie_label)
	var r3 := UiKit.hbox()
	_wind = WindIndicator.new()
	r3.add_child(_wind)
	_wind_label = UiKit.expand(UiKit.label("", 22)) as Label
	_wind_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r3.add_child(_wind_label)
	_pin_label = UiKit.label("", 24, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	_pin_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	r3.add_child(_pin_label)
	v.add_child(r3)
	var actions := UiKit.hbox(8)
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view_btn = UiKit.button("Overhead", func() -> void: camera_toggle_requested.emit(), 58, 22)
	actions.add_child(_view_btn)
	actions.add_child(UiKit.button("Card", show_scorecard, 58, 22))
	var dev := UiKit.button("DEV", func() -> void: developer_requested.emit(), 58, 22)
	dev.add_theme_color_override("font_color", UiKit.C_DEV)
	actions.add_child(dev)
	actions.add_child(UiKit.button("II", show_pause, 58, 22))
	col.add_child(actions)
	_measure_label = UiKit.text("", 22, UiKit.C_WARN, HORIZONTAL_ALIGNMENT_RIGHT)
	_measure_label.add_theme_constant_override("outline_size", 6)
	col.add_child(_measure_label)


func _build_bottom(col: VBoxContainer) -> void:
	var p := UiKit.panel()
	col.add_child(p)
	_bottom = UiKit.vbox(10)
	p.add_child(_bottom)
	_controls = UiKit.vbox(10)
	_bottom.add_child(_controls)
	var seg := UiKit.hbox(8)
	var group := ButtonGroup.new()
	_caps_btn = UiKit.button("CAPS · air", func() -> void: session.set_mode(ShotTypes.Mode.CAPS), 70, 26)
	_goals_btn = UiKit.button("GOALS · ground", func() -> void: session.set_mode(ShotTypes.Mode.GOALS), 70, 26)
	for b in [_caps_btn, _goals_btn]:
		b.toggle_mode = true
		b.button_group = group
		UiKit.expand(b)
		seg.add_child(b)
	_controls.add_child(seg)
	_pick_btn = UiKit.button("Choose footballer…", show_picker, 70, 25)
	_pick_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_controls.add_child(_pick_btn)
	var shot_row := UiKit.hbox(8)
	_shot_btn = UiKit.primary(UiKit.button("TAKE SHOT", _on_take_shot, 104, 34))
	UiKit.expand(_shot_btn)
	shot_row.add_child(_shot_btn)
	_skip_btn = UiKit.button("Skip ▸▸", func() -> void: session.skip_motion(), 104, 24)
	_skip_btn.custom_minimum_size.x = 150
	shot_row.add_child(_skip_btn)
	_controls.add_child(shot_row)
	_hint = UiKit.text("Drag the course left/right to aim · 360°", 20, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_controls.add_child(_hint)
	_result_box = UiKit.vbox(6)
	_result_box.visible = false
	_bottom.add_child(_result_box)


func toast(text: String, secs: float = 2.5) -> void:
	_toast.text = text
	_toast_t = secs


func set_measure(text: String) -> void:
	_measure_label.text = text


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.text = ""
	if session == null or session.hole == null:
		return
	_pin_label.text = "Pin %s" % Units.fmt_distance(Units.horizontal_distance(session.ball_render_pos(), session.hole.cup_position()))
	var wb := deg_to_rad(session.wind_bearing())
	_wind.set_wind(camera_yaw - wb if not overhead else -wb + camera_yaw, session.wind_speed())


func refresh() -> void:
	if session == null or session.hole == null:
		return
	var hs := session.current_hole_state()
	var h := session.hole
	_top_title.text = "Hole %d · Par %d · %d yd" % [session.round_state.current_index + 1, h.par, int(h.yards)]
	var pen := " (+%d pen)" % hs.penalties if hs.penalties > 0 else ""
	var thru := session.round_state.holes_completed()
	_top_score.text = "Strokes %d%s · Round %s%s" % [hs.raw_total(), pen, RoundState.fmt_relative(session.round_state.relative_to_par()), (" thru %d" % thru) if thru > 0 else ""]
	var lie := session.current_lie()
	var dev := " [DEV lie]" if session.lie_override >= 0 else ""
	_lie_label.text = "Lie: %s%s — %s" % [Surface.name_of(lie), dev, Surface.effect_hint(lie, session.cfg.surfaces)]
	_wind_label.text = "Wind %d mph" % int(round(session.wind_speed() * Units.MPS_TO_MPH))
	_caps_btn.set_pressed_no_signal(session.mode == ShotTypes.Mode.CAPS)
	_goals_btn.set_pressed_no_signal(session.mode == ShotTypes.Mode.GOALS)
	var fb := session.repo.get_by_id(session.selected_id) if session.selected_id != "" else null
	if fb == null:
		_pick_btn.text = "Choose footballer…"
	elif App.settings.show_stats:
		if session.mode == ShotTypes.Mode.CAPS:
			_pick_btn.text = "▶ %s · %d caps = %d yd carry" % [fb.name, fb.caps, fb.caps]
		else:
			_pick_btn.text = "▶ %s · %d goals = %d ft roll" % [fb.name, fb.goals, fb.goals]
	else:
		_pick_btn.text = "▶ %s" % fb.display_label()
	var moving := session.is_ball_moving()
	var aiming := session.state == ShotTypes.State.AIMING
	_controls.visible = session.state != ShotTypes.State.SHOT_RESULT
	_result_box.visible = session.state == ShotTypes.State.SHOT_RESULT
	_skip_btn.visible = moving
	_shot_btn.disabled = not (aiming and session.can_take_shot() == "" and _overlays.is_empty())
	if moving:
		_shot_btn.text = "Ball in motion…"
	elif aiming and fb == null:
		_shot_btn.text = "TAKE SHOT"
	else:
		_shot_btn.text = "TAKE SHOT"
	_caps_btn.disabled = moving
	_goals_btn.disabled = moving
	_pick_btn.disabled = moving
	if moving:
		_hint.text = "Ball in motion · Skip fast-forwards the same simulation"
	elif overhead:
		_hint.text = "Tap a point to measure yardage"
	else:
		_hint.text = "Drag the course left/right to aim · 360°"
	_view_btn.text = "Behind" if overhead else "Overhead"


func _on_take_shot() -> void:
	if not _overlays.is_empty():
		return
	session.take_shot()
	refresh()


# ------------------------------------------------------------------ overlays

func has_overlay() -> bool:
	return not _overlays.is_empty()


func push_overlay(c: Control) -> void:
	add_child(c)
	_overlays.append(c)
	refresh()


func close_top_overlay() -> bool:
	if _overlays.is_empty():
		return false
	var c: Control = _overlays.pop_back()
	if is_instance_valid(c):
		c.queue_free()
	refresh()
	return true


func close_all_overlays() -> void:
	while close_top_overlay():
		pass


func _remove_overlay(c: Control) -> void:
	_overlays.erase(c)
	if is_instance_valid(c):
		c.queue_free()
	refresh()


func show_picker() -> void:
	if session.is_ball_moving():
		return
	var p := FootballerPicker.new()
	p.show_stats = App.settings.show_stats
	push_overlay(p)
	p.setup(session)
	p.picked.connect(func(_id: String) -> void: _remove_overlay(p))
	p.closed.connect(func() -> void: _remove_overlay(p))


func _centered_card(min_w: float = 600.0) -> Array:
	var root := UiKit.overlay(0.5)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var p := UiKit.panel(UiKit.C_PANEL_SOLID)
	p.custom_minimum_size = Vector2(min_w, 0)
	center.add_child(p)
	var v := UiKit.vbox(14)
	p.add_child(v)
	return [root, v]


func show_hole_intro() -> void:
	var h := session.hole
	var parts := _centered_card()
	var root: Control = parts[0]
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.text("HOLE %d" % (session.round_state.current_index + 1), 30, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text(h.display_name, 44, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("Par %d · %d yd" % [h.par, int(h.yards)], 32, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("Max score %d (par + 5) · Round %s" % [h.par + 5, RoundState.fmt_relative(session.round_state.relative_to_par())], 22, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.primary(UiKit.button("Tee off", func() -> void:
		_remove_overlay(root)
		session.begin_play(), 90, 32)))
	root.color = Color(0, 0, 0, 0.15)
	push_overlay(root)


func _on_shot_resolved(r: ShotResult) -> void:
	UiKit.clear(_result_box)
	var head := UiKit.hbox()
	head.add_child(UiKit.expand(UiKit.label("%s (%s)" % [r.footballer_name, r.nationality], 26)))
	_result_box.add_child(head)
	var stat_line := "%s → %s" % [r.stat_label().to_upper(), r.base_label()]
	_result_box.add_child(UiKit.text(stat_line, 32, UiKit.C_ACCENT.lightened(0.3)))
	var dist_line := ""
	if r.mode == ShotTypes.Mode.CAPS:
		dist_line = "Carry %d yd · Roll %d ft · Total %d yd" % [int(round(Units.m_to_yards(r.carry_m))), int(round(Units.m_to_feet(r.roll_m))), int(round(Units.m_to_yards(r.total_m)))]
	else:
		dist_line = "Ground travel %.1f ft (%d yd)" % [Units.m_to_feet(r.total_m), int(round(Units.m_to_yards(r.total_m)))]
	_result_box.add_child(UiKit.text(dist_line, 24))
	var extra: Array[String] = []
	if r.lie_factor < 0.999:
		extra.append("%s lie cost %d%%" % [Surface.name_of(r.start_lie), int(round((1.0 - r.lie_factor) * 100.0))])
	if not r.collisions.is_empty():
		extra.append("Hit tree (%s)" % r.collision_summary())
	if r.wind_speed_mps > 0.1 and r.mode == ShotTypes.Mode.CAPS:
		extra.append("Wind %d mph" % int(round(r.wind_speed_mps * Units.MPS_TO_MPH)))
	if not extra.is_empty():
		_result_box.add_child(UiKit.text(" · ".join(extra), 21, UiKit.C_MUTED))
	if r.penalty > 0:
		_result_box.add_child(UiKit.text("%s! +%d penalty stroke · ball dropped safely" % ["Water" if r.hazard == "WATER" else "Out of bounds", r.penalty], 25, UiKit.C_WARN))
	if r.holed:
		_result_box.add_child(UiKit.text("HOLED!", 34, UiKit.C_WARN))
	else:
		_result_box.add_child(UiKit.text("Lie: %s · %s to pin" % [Surface.name_of(r.final_lie), Units.fmt_distance(r.remaining_m)], 24))
	var hs := session.current_hole_state()
	if hs.complete:
		_result_box.add_child(UiKit.text("Hole score %d (%s)" % [hs.score(), RoundState.fmt_relative(hs.relative_to_par())], 22, UiKit.C_MUTED))
	else:
		_result_box.add_child(UiKit.text("Strokes so far %d (par %d, max %d)" % [hs.raw_total(), hs.par, hs.max_score()], 22, UiKit.C_MUTED))
	var details := UiKit.text(r.diagnostic_text(), 17, UiKit.C_MUTED)
	details.visible = false
	var row := UiKit.hbox()
	var det_btn := UiKit.button("Details", func() -> void: details.visible = not details.visible, 66, 22)
	row.add_child(det_btn)
	var cont := UiKit.primary(UiKit.button("Continue", func() -> void: session.acknowledge_result(), 80, 30))
	UiKit.expand(cont)
	row.add_child(cont)
	_result_box.add_child(details)
	_result_box.add_child(row)
	refresh()


func _on_hole_completed(hs: HoleState) -> void:
	var parts := _centered_card()
	var root: Control = parts[0]
	var v: VBoxContainer = parts[1]
	var title := "HOLED!" if hs.completion == ShotTypes.COMPLETION_HOLED else "Maximum score reached"
	v.add_child(UiKit.text(title, 42, UiKit.C_WARN, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("%s · Par %d" % [hs.hole_name, hs.par], 26, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("Score %d (%s)  ·  %d shots, %d penalty" % [hs.score(), RoundState.fmt_relative(hs.relative_to_par()), hs.strokes, hs.penalties], 28, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	if hs.completion == ShotTypes.COMPLETION_MAX_SCORE and hs.raw_total() > hs.score():
		v.add_child(UiKit.text("(raw %d clamped to par + 5)" % hs.raw_total(), 20, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_scorecard_grid())
	var last := session.round_state.current_index >= session.round_state.holes.size() - 1 or session.round_state.all_complete()
	v.add_child(UiKit.primary(UiKit.button("Finish round" if last else "Next hole", func() -> void:
		_remove_overlay(root)
		session.next_hole(), 90, 32)))
	push_overlay(root)


func _on_round_completed() -> void:
	close_all_overlays()
	var parts := _centered_card()
	var root: Control = parts[0]
	var v: VBoxContainer = parts[1]
	var rs := session.round_state
	v.add_child(UiKit.text("ROUND COMPLETE", 40, UiKit.C_WARN, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("Total %d · %s (par %d)" % [rs.total_score(), RoundState.fmt_relative(rs.relative_to_par()), rs.total_par()], 32, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_scorecard_grid())
	v.add_child(UiKit.text("%d footballers used" % session.pool.used_count(), 22, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.primary(UiKit.button("Play again", func() -> void:
		_remove_overlay(root)
		session.start_round(session.hole_defs), 88, 30)))
	v.add_child(UiKit.button("Main menu", func() -> void: main_menu_requested.emit(), 76, 26))
	push_overlay(root)


func _scorecard_grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 5
	for hdr in ["Hole", "Par", "Score", "+/-", "Pen"]:
		g.add_child(UiKit.label(hdr, 22, UiKit.C_MUTED))
	var rs := session.round_state
	for i in rs.holes.size():
		var hs: HoleState = rs.holes[i]
		var played := hs.complete or hs.raw_total() > 0
		g.add_child(UiKit.label("%d%s" % [i + 1, "" if hs.complete else ("*" if played else "")], 24))
		g.add_child(UiKit.label(str(hs.par), 24))
		g.add_child(UiKit.label(str(hs.score()) if played else "–", 24))
		g.add_child(UiKit.label(RoundState.fmt_relative(hs.relative_to_par()) if played else "–", 24))
		g.add_child(UiKit.label(str(hs.penalties), 24))
	g.add_child(UiKit.label("Total", 24, UiKit.C_WARN))
	g.add_child(UiKit.label(str(rs.total_par()), 24, UiKit.C_WARN))
	g.add_child(UiKit.label(str(rs.total_score()), 24, UiKit.C_WARN))
	g.add_child(UiKit.label(RoundState.fmt_relative(rs.relative_to_par()), 24, UiKit.C_WARN))
	g.add_child(UiKit.label(str(rs.total_penalties()), 24, UiKit.C_WARN))
	return g


func show_scorecard() -> void:
	var root := UiKit.overlay(0.6)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 24)
	m.add_theme_constant_override("margin_top", 90)
	m.add_theme_constant_override("margin_bottom", 60)
	root.add_child(m)
	var p := UiKit.panel(UiKit.C_PANEL_SOLID)
	m.add_child(p)
	var v := UiKit.vbox(12)
	p.add_child(v)
	var head := UiKit.hbox()
	head.add_child(UiKit.expand(UiKit.label("Scorecard", 34)))
	head.add_child(UiKit.button("Close", func() -> void: _remove_overlay(root), 62, 24))
	v.add_child(head)
	v.add_child(_scorecard_grid())
	v.add_child(UiKit.text("Shot history (revealed after each shot)", 22, UiKit.C_MUTED))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := UiKit.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	if session.history.is_empty():
		list.add_child(UiKit.text("No shots yet.", 22, UiKit.C_MUTED))
	for r in session.history:
		var sr: ShotResult = r
		var hole_no := session.round_state.hole_ids.find(sr.hole_id) + 1
		var dist := ("carry %d yd" % int(round(Units.m_to_yards(sr.carry_m)))) if sr.mode == ShotTypes.Mode.CAPS else ("%.1f ft" % Units.m_to_feet(sr.total_m))
		var pen := " · +%d %s" % [sr.penalty, sr.hazard] if sr.penalty > 0 else ""
		list.add_child(UiKit.text("H%d #%d  %s (%s) — %d caps / %d goals — %s %s%s%s" % [hole_no, sr.shot_id, sr.footballer_name, sr.nationality, sr.caps, sr.goals, sr.mode_name(), dist, pen, " · HOLED" if sr.holed else ""], 20))
	push_overlay(root)


func show_pause() -> void:
	var parts := _centered_card(520.0)
	var root: Control = parts[0]
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.text("Paused", 38, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.primary(UiKit.button("Resume", func() -> void: _remove_overlay(root), 84, 30)))
	v.add_child(UiKit.button("Scorecard", func() -> void:
		_remove_overlay(root)
		show_scorecard(), 76, 26))
	v.add_child(UiKit.button("Restart round", func() -> void:
		close_all_overlays()
		session.start_round(session.hole_defs), 76, 26))
	v.add_child(UiKit.button("Main menu", func() -> void: main_menu_requested.emit(), 76, 26))
	push_overlay(root)

class_name GameUI
extends Control
## Portrait gameplay HUD + overlays (picker, shot result, hole intro/complete, scorecard,
## pause, round complete). Reads from GameSession; only calls session APIs to act.

signal camera_toggle_requested
## factor > 0 zooms the overhead map; 0 = fit whole hole.
signal overhead_zoom_requested(factor: float)
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
var _map_row: HBoxContainer
var _badge_num: Label
var _reveal: Tween
var _spin: SpinControl
var _spin_box: VBoxContainer
var _spin_label: Label
var _round_label: Label
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


func _chip(text_label: Label, min_w: float = 0.0) -> PanelContainer:
	var c := UiKit.panel(Color(0.04, 0.07, 0.06, 0.72))
	c.add_theme_stylebox_override("panel", UiKit.box(Color(0.04, 0.07, 0.06, 0.72), 22, 10))
	c.custom_minimum_size.x = min_w
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(text_label)
	return c


func _small_btn(text: String, cb: Callable) -> Button:
	var b := UiKit.button(text, cb, 54, 20)
	b.custom_minimum_size.x = 70
	b.add_theme_stylebox_override("normal", UiKit.box(Color(0.04, 0.07, 0.06, 0.78), 27, 10))
	return b


func _build_top(col: VBoxContainer) -> void:
	var p := UiKit.panel(Color(0.04, 0.08, 0.06, 0.86))
	col.add_child(p)
	var row := UiKit.hbox(14)
	p.add_child(row)
	# hole badge
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UiKit.box(UiKit.C_ACCENT_DARK, 16, 8))
	badge.custom_minimum_size = Vector2(86, 86)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bv := UiKit.vbox(0)
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_child(UiKit.label("HOLE", 16, Color(0.85, 1, 0.88), HORIZONTAL_ALIGNMENT_CENTER))
	_badge_num = UiKit.label("1", 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	bv.add_child(_badge_num)
	badge.add_child(bv)
	row.add_child(badge)
	var mid := UiKit.vbox(2)
	UiKit.expand(mid)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_title = UiKit.label("", 27)
	_top_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(_top_title)
	_pin_label = UiKit.label("", 21, UiKit.C_MUTED)
	mid.add_child(_pin_label)
	_lie_label = UiKit.label("", 19, UiKit.C_MUTED)
	_lie_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(_lie_label)
	row.add_child(mid)
	var right := UiKit.vbox(0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(UiKit.label("ROUND", 16, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
	_round_label = UiKit.label("E", 36, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_round_label)
	_top_score = UiKit.label("", 18, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_top_score)
	row.add_child(right)
	# chips + actions
	var bar := UiKit.hbox(8)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wind_chip := UiKit.hbox(6)
	wind_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wind = WindIndicator.new()
	wind_chip.add_child(_wind)
	_wind_label = UiKit.label("", 20)
	_wind_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wind_chip.add_child(_wind_label)
	var wc := UiKit.panel(Color(0.04, 0.07, 0.06, 0.72))
	wc.add_theme_stylebox_override("panel", UiKit.box(Color(0.04, 0.07, 0.06, 0.72), 27, 8))
	wc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wc.add_child(wind_chip)
	bar.add_child(wc)
	var sp := Control.new()
	UiKit.expand(sp)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(sp)
	_view_btn = _small_btn("MAP", func() -> void: camera_toggle_requested.emit())
	bar.add_child(_view_btn)
	bar.add_child(_small_btn("CARD", show_scorecard))
	var dev := _small_btn("DEV", func() -> void: developer_requested.emit())
	dev.add_theme_color_override("font_color", UiKit.C_DEV)
	bar.add_child(dev)
	bar.add_child(_small_btn("II", show_pause))
	col.add_child(bar)
	_map_row = UiKit.hbox(8)
	_map_row.alignment = BoxContainer.ALIGNMENT_END
	for spec in [["−", 1.0 / 1.4], ["+", 1.4], ["FIT", 0.0]]:
		var f: float = spec[1]
		_map_row.add_child(_small_btn(spec[0], func() -> void: overhead_zoom_requested.emit(f)))
	col.add_child(_map_row)
	_measure_label = UiKit.text("", 22, UiKit.C_WARN, HORIZONTAL_ALIGNMENT_RIGHT)
	_measure_label.add_theme_constant_override("outline_size", 6)
	col.add_child(_measure_label)


func _build_bottom(col: VBoxContainer) -> void:
	var p := UiKit.panel(Color(0.04, 0.08, 0.06, 0.88))
	col.add_child(p)
	_bottom = UiKit.vbox(10)
	p.add_child(_bottom)
	_controls = UiKit.vbox(10)
	_bottom.add_child(_controls)
	var seg := UiKit.hbox(8)
	var group := ButtonGroup.new()
	_caps_btn = UiKit.button("CAPS\nin the air · 1 cap = 1 yd", func() -> void: session.set_mode(ShotTypes.Mode.CAPS), 78, 22)
	_goals_btn = UiKit.button("GOALS\non the ground · 1 goal = 1 ft", func() -> void: session.set_mode(ShotTypes.Mode.GOALS), 78, 22)
	for b in [_caps_btn, _goals_btn]:
		b.toggle_mode = true
		b.button_group = group
		b.add_theme_stylebox_override("pressed", UiKit.box(UiKit.C_ACCENT_DARK, 14, 10))
		b.add_theme_stylebox_override("hover_pressed", UiKit.box(UiKit.C_ACCENT_DARK, 14, 10))
		UiKit.expand(b)
		seg.add_child(b)
	_controls.add_child(seg)
	_pick_btn = UiKit.button("Choose footballer…", show_picker, 84, 24)
	_pick_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_pick_btn.add_theme_constant_override("h_separation", 14)
	_pick_btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_controls.add_child(_pick_btn)
	var shot_row := UiKit.hbox(8)
	_shot_btn = UiKit.primary(UiKit.button("TAKE SHOT", _on_take_shot, 100, 34))
	UiKit.expand(_shot_btn)
	shot_row.add_child(_shot_btn)
	_skip_btn = UiKit.button("Skip ▸▸", func() -> void: session.skip_motion(), 100, 24)
	_skip_btn.custom_minimum_size.x = 150
	shot_row.add_child(_skip_btn)
	_spin_box = UiKit.vbox(2)
	_spin = SpinControl.new()
	_spin.spin_changed.connect(func(v: float) -> void: session.set_spin(v))
	_spin_box.add_child(_spin)
	_spin_label = UiKit.label("No spin", 16, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_spin_box.add_child(_spin_label)
	shot_row.add_child(_spin_box)
	_controls.add_child(shot_row)
	_hint = UiKit.text("", 19, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_controls.add_child(_hint)
	_result_box = UiKit.vbox(8)
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
	var h := session.hole
	_pin_label.text = "Par %d · %d yd · Pin %s" % [h.par, int(h.yards), Units.fmt_distance(Units.horizontal_distance(session.ball_render_pos(), h.cup_position()))]
	var wb := deg_to_rad(session.wind_bearing())
	_wind.set_wind(camera_yaw - wb, session.wind_speed())


func refresh() -> void:
	if session == null or session.hole == null:
		return
	var hs := session.current_hole_state()
	var h := session.hole
	_badge_num.text = str(session.round_state.current_index + 1)
	_top_title.text = h.display_name
	var pen := " (+%d pen)" % hs.penalties if hs.penalties > 0 else ""
	var thru := session.round_state.holes_completed()
	_round_label.text = RoundState.fmt_relative(session.round_state.relative_to_par())
	_top_score.text = "Strokes %d%s%s" % [hs.raw_total(), pen, (" · thru %d" % thru) if thru > 0 else ""]
	var lie := session.current_lie()
	var dev := " [DEV]" if session.lie_override >= 0 else ""
	_lie_label.text = "%s%s · %s" % [Surface.name_of(lie), dev, Surface.effect_hint(lie, session.cfg.surfaces)]
	_wind_label.text = "%d mph" % int(round(session.wind_speed() * Units.MPS_TO_MPH))
	_caps_btn.set_pressed_no_signal(session.mode == ShotTypes.Mode.CAPS)
	_goals_btn.set_pressed_no_signal(session.mode == ShotTypes.Mode.GOALS)
	var fb := session.repo.get_by_id(session.selected_id) if session.selected_id != "" else null
	if fb == null:
		_pick_btn.icon = null
		_pick_btn.text = "Choose footballer…\nSearch %d players by name or country" % session.repo.count()
	else:
		_pick_btn.icon = Flags.texture(fb.country_code)
		var line2 := fb.nationality
		if App.settings.show_stats:
			if session.mode == ShotTypes.Mode.CAPS:
				line2 += "  ·  %s = %d yd carry" % [UiKit.plural(fb.caps, "cap"), fb.caps]
			else:
				line2 += "  ·  %s = %d ft roll" % [UiKit.plural(fb.goals, "goal"), fb.goals]
		else:
			line2 += "  ·  stats revealed after the shot"
		_pick_btn.text = "▶ %s\n%s" % [fb.name, line2]
	var moving := session.is_ball_moving()
	var aiming := session.state == ShotTypes.State.AIMING
	if session.state != ShotTypes.State.SHOT_RESULT and _reveal != null and _reveal.is_valid():
		_reveal.kill()
		_result_box.modulate.a = 1.0
	_controls.visible = session.state != ShotTypes.State.SHOT_RESULT
	_result_box.visible = session.state == ShotTypes.State.SHOT_RESULT
	_skip_btn.visible = moving
	var caps_mode := session.mode == ShotTypes.Mode.CAPS
	_spin_box.visible = caps_mode and not moving
	_spin.set_spin(session.spin)
	if absf(session.spin) < 0.025:
		_spin_label.text = "No spin"
	else:
		_spin_label.text = "%s %d%%" % ["Top" if session.spin > 0.0 else "Back", int(round(absf(session.spin) * 100.0))]
	_shot_btn.disabled = not (aiming and session.can_take_shot() == "" and _overlays.is_empty())
	_shot_btn.text = "Ball in motion…" if moving else "TAKE SHOT"
	_caps_btn.disabled = moving
	_goals_btn.disabled = moving
	_pick_btn.disabled = moving
	if moving:
		_hint.text = "Ball in motion · Skip fast-forwards the same simulation"
	elif overhead:
		_hint.text = "Pinch/± to zoom · drag to pan · tap to measure"
	elif fb == null:
		_hint.text = "Drag the course to aim · then choose a footballer"
	else:
		_hint.text = "Drag the course left/right to aim · 360°"
	_view_btn.text = "BEHIND" if overhead else "MAP"
	_map_row.visible = overhead


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


func _stat_cell(caption: String, value: String) -> VBoxContainer:
	var v := UiKit.vbox(0)
	UiKit.expand(v)
	v.add_child(UiKit.label(value, 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label(caption, 16, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	return v


## Shot summary card with an animated stat reveal (only shown after the ball has stopped).
func _on_shot_resolved(r: ShotResult) -> void:
	if _reveal != null and _reveal.is_valid():
		_reveal.kill()
	UiKit.clear(_result_box)
	var head := UiKit.hbox(12)
	var fb := session.repo.get_by_id(r.footballer_id)
	var flag := TextureRect.new()
	flag.texture = Flags.texture(fb.country_code if fb != null else "")
	flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flag.custom_minimum_size = Vector2(60, 40)
	head.add_child(flag)
	var hv := UiKit.vbox(0)
	UiKit.expand(hv)
	var nm := UiKit.label(r.footballer_name, 26)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hv.add_child(nm)
	hv.add_child(UiKit.label(r.nationality, 18, UiKit.C_MUTED))
	head.add_child(hv)
	_result_box.add_child(head)
	# big animated stat
	var unit := "CAPS" if r.mode == ShotTypes.Mode.CAPS else "GOALS"
	var big := UiKit.label("0 %s" % unit, 46, Color(0.55, 0.95, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	_result_box.add_child(big)
	var sub := UiKit.label("= %s neutral %s" % [("%d yd" % r.stat_value) if r.mode == ShotTypes.Mode.CAPS else ("%d ft" % r.stat_value), "carry" if r.mode == ShotTypes.Mode.CAPS else "ground travel"], 20, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_result_box.add_child(sub)
	var grid := UiKit.hbox(6)
	if r.mode == ShotTypes.Mode.CAPS:
		grid.add_child(_stat_cell("CARRY", "%d yd" % int(round(Units.m_to_yards(r.carry_m)))))
		grid.add_child(_stat_cell("ROLL", "%d ft" % int(round(Units.m_to_feet(r.roll_m)))))
		grid.add_child(_stat_cell("TOTAL", "%d yd" % int(round(Units.m_to_yards(r.total_m)))))
	else:
		grid.add_child(_stat_cell("TRAVEL", "%.1f ft" % Units.m_to_feet(r.total_m)))
		grid.add_child(_stat_cell("LIE", Surface.name_of(r.final_lie)))
	if not r.holed:
		grid.add_child(_stat_cell("TO PIN", Units.fmt_distance(r.remaining_m)))
	_result_box.add_child(grid)
	var extra: Array[String] = []
	if r.lie_factor < 0.999:
		extra.append("%s lie cost %d%%" % [Surface.name_of(r.start_lie), int(round((1.0 - r.lie_factor) * 100.0))])
	if not r.collisions.is_empty():
		extra.append("Hit a tree")
	if r.wind_speed_mps > 0.1 and r.mode == ShotTypes.Mode.CAPS:
		extra.append("Wind %d mph" % int(round(r.wind_speed_mps * Units.MPS_TO_MPH)))
	if r.mode == ShotTypes.Mode.CAPS:
		if absf(r.spin) >= 0.025:
			extra.append(ShotResult.spin_label(r.spin).capitalize())
		extra.append("Now on the %s" % Surface.name_of(r.final_lie).to_lower())
	var extra_l := UiKit.text(" · ".join(extra), 19, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_result_box.add_child(extra_l)
	var banner: Label = null
	if r.penalty > 0:
		banner = UiKit.text("%s!  +%d penalty · ball dropped safely" % ["WATER" if r.hazard == "WATER" else "OUT OF BOUNDS", r.penalty], 24, UiKit.C_WARN, HORIZONTAL_ALIGNMENT_CENTER)
	elif r.holed:
		banner = UiKit.text("IN THE HOLE!", 36, UiKit.C_WARN, HORIZONTAL_ALIGNMENT_CENTER)
	if banner != null:
		_result_box.add_child(banner)
	var hs := session.current_hole_state()
	var status := ""
	if hs.complete:
		status = "Hole score %d (%s)" % [hs.score(), RoundState.fmt_relative(hs.relative_to_par())]
	else:
		status = "Strokes so far %d · par %d · max %d" % [hs.raw_total(), hs.par, hs.max_score()]
	_result_box.add_child(UiKit.label(status, 19, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var details := UiKit.text(r.diagnostic_text(), 16, UiKit.C_MUTED)
	details.visible = false
	var row := UiKit.hbox()
	row.add_child(UiKit.button("Details", func() -> void: details.visible = not details.visible, 70, 21))
	var cont := UiKit.primary(UiKit.button("Continue", func() -> void: session.acknowledge_result(), 80, 30))
	UiKit.expand(cont)
	row.add_child(cont)
	_result_box.add_child(details)
	_result_box.add_child(row)
	refresh()
	# --- reveal animation: count the stat up, then fade the breakdown in
	var later: Array = [sub, grid, extra_l, banner]
	for n in later:
		if n != null:
			(n as Control).modulate.a = 0.0
	_result_box.modulate.a = 0.0
	var tw := create_tween()
	_reveal = tw
	tw.tween_property(_result_box, "modulate:a", 1.0, 0.2)
	var target := r.stat_value
	tw.tween_method(func(v: float) -> void:
		if is_instance_valid(big):
			big.text = "%d %s" % [int(round(v)), unit], 0.0, float(target), clampf(0.25 + target * 0.004, 0.3, 1.1)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for n in later:
		if n != null:
			tw.tween_property(n, "modulate:a", 1.0, 0.18)


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
	sc.scroll_deadzone = 14
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

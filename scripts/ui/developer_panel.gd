class_name DeveloperPanel
extends Control
## Developer test panel (clearly labelled DEV). Ball placement, lie/wind/surface config,
## hole-out radius, hole select/restart, undo/replay, footballer CRUD, pool reset,
## diagnostics + calibration check, scenario save/load.

signal closed
signal tap_place_toggled(enabled: bool)

var session: GameSession
var settings: SettingsStore
var _tabs: TabContainer
var _status: Label
var _diag: Label
var _x: SpinBox
var _z: SpinBox
var _surf_sel: OptionButton
var _surf_spins: Dictionary = {}
var _player_list: ItemList
var _player_ids: Array[String] = []
var _p_name: LineEdit
var _p_nat: LineEdit
var _p_caps: LineEdit
var _p_goals: LineEdit
var _p_search: LineEdit
var _selected_player := ""
var _tap_place: CheckButton


func setup(s: GameSession, st: SettingsStore) -> void:
	session = s
	settings = st
	theme = UiKit.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := UiKit.panel(Color(0.07, 0.05, 0.10, 0.97))
	p.anchor_left = 0.0
	p.anchor_right = 1.0
	p.anchor_top = 0.40
	p.anchor_bottom = 1.0
	p.offset_left = 8
	p.offset_right = -8
	p.offset_bottom = -8
	add_child(p)
	var v := UiKit.vbox(8)
	p.add_child(v)
	var head := UiKit.hbox()
	head.add_child(UiKit.expand(UiKit.label("DEVELOPER TEST PANEL", 26, UiKit.C_DEV)))
	head.add_child(UiKit.button("Close", func() -> void: closed.emit(), 58, 22))
	v.add_child(head)
	_status = UiKit.text("Developer actions are labelled and bypass normal play rules.", 19, UiKit.C_MUTED)
	v.add_child(_status)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_tabs.add_child(_scroll("Ball", _build_ball_tab()))
	_tabs.add_child(_scroll("Env", _build_env_tab()))
	_tabs.add_child(_scroll("Players", _build_players_tab()))
	_tabs.add_child(_scroll("Diag", _build_diag_tab()))
	session.shot_resolved.connect(func(_r: ShotResult) -> void: _refresh_diag())
	session.pool.changed.connect(_refresh_players)
	_refresh_diag()


func _scroll(title: String, content: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.scroll_deadzone = 14
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	return sc


func _say(t: String) -> void:
	_status.text = t
	print("[DEV] ", t)


func _row(label_text: String, ctrl: Control) -> HBoxContainer:
	var h := UiKit.hbox()
	h.add_child(UiKit.expand(UiKit.label(label_text, 21)))
	h.add_child(ctrl)
	return h


func _btn_row(buttons: Array) -> HBoxContainer:
	var h := UiKit.hbox(6)
	for b in buttons:
		UiKit.expand(b)
		h.add_child(b)
	return h


func _b(text: String, cb: Callable) -> Button:
	var b := UiKit.button(text, cb, 60, 20)
	b.mouse_filter = Control.MOUSE_FILTER_PASS  # allow touch-drag scrolling of the panel
	return b


# ------------------------------------------------------------------ Ball tab

func _build_ball_tab() -> VBoxContainer:
	var v := UiKit.vbox(8)
	var holes: Array = []
	for i in session.hole_defs.size():
		var idx := i
		holes.append(_b("%d" % (i + 1), func() -> void:
			session.dev_select_hole(idx)
			session.begin_play()
			_say("Jumped to hole %d (its state reset)" % (idx + 1))))
	v.add_child(UiKit.text("Select / restart hole", 20, UiKit.C_MUTED))
	var hole_grid := GridContainer.new()
	hole_grid.columns = 5
	hole_grid.add_theme_constant_override("h_separation", 6)
	hole_grid.add_theme_constant_override("v_separation", 6)
	for hb in holes:
		UiKit.expand(hb)
		hole_grid.add_child(hb)
	v.add_child(hole_grid)
	v.add_child(_btn_row([_b("Restart hole", func() -> void:
		session.dev_restart_hole()
		session.begin_play()
		_say("Hole restarted; this hole's footballers returned")), _b("Reset ball", func() -> void:
		session.dev_reset_ball()
		_say("Ball reset to tee"))]))
	v.add_child(_btn_row([_b("Undo shot", func() -> void:
		_say("Undo: %s" % ("done" if session.dev_undo() else "nothing to undo / not now"))), _b("Replay shot", func() -> void:
		_say("Replay: %s" % ("running (no duplicate scoring)" if session.dev_replay() else "unavailable")))]))
	v.add_child(_btn_row([_b("Reset pool", func() -> void:
		session.dev_reset_pool()
		_say("Footballer pool reset (all available)")), _b("Skip motion", func() -> void: session.skip_motion())]))
	v.add_child(UiKit.text("Place ball (world metres; tee is at 0,0; +Z down the hole)", 20, UiKit.C_MUTED))
	_x = UiKit.spin(-500, 500, 0.5, 0, Callable())
	_z = UiKit.spin(-100, 700, 0.5, 0, Callable())
	v.add_child(_row("X (m)", _x))
	v.add_child(_row("Z (m)", _z))
	v.add_child(_btn_row([_b("Place at X/Z", func() -> void:
		var err := session.dev_place_ball(_x.value, _z.value)
		_say("Placed ball" if err == "" else err)), _b("Use current", func() -> void:
		_x.value = session.ball_pos.x
		_z.value = session.ball_pos.z), _b("Near pin", func() -> void:
		var c := session.hole.cup_position()
		var err2 := session.dev_place_ball(c.x, c.z - 6.0)
		_say("Placed 6 m short of pin" if err2 == "" else err2))]))
	_tap_place = CheckButton.new()
	_tap_place.text = "Tap-to-place in overhead view"
	_tap_place.add_theme_font_size_override("font_size", 21)
	_tap_place.toggled.connect(func(on: bool) -> void: tap_place_toggled.emit(on))
	v.add_child(_tap_place)
	var lie := OptionButton.new()
	lie.add_item("Lie override: off (use terrain)")
	for t in Surface.PLAYABLE:
		lie.add_item("Lie override: %s" % Surface.name_of(t))
	lie.selected = 0 if session.lie_override < 0 else Surface.PLAYABLE.find(session.lie_override) + 1
	lie.custom_minimum_size = Vector2(0, 58)
	lie.item_selected.connect(func(i: int) -> void:
		session.dev_set_lie_override(-1 if i == 0 else int(Surface.PLAYABLE[i - 1]))
		_save()
		_say("Lie override %s" % ("off" if i == 0 else Surface.name_of(session.lie_override))))
	v.add_child(lie)
	var force := CheckButton.new()
	force.text = "Force override surface for the whole shot"
	force.add_theme_font_size_override("font_size", 21)
	force.button_pressed = session.force_surface
	force.toggled.connect(func(on: bool) -> void:
		session.force_surface = on
		_save())
	v.add_child(force)
	v.add_child(UiKit.text("Scenario (ball, lie, wind, aim, mode)", 20, UiKit.C_MUTED))
	v.add_child(_btn_row([_b("Save scenario", _save_scenario), _b("Load scenario", _load_scenario)]))
	return v


func set_tap_place(on: bool) -> void:
	if _tap_place != null:
		_tap_place.set_pressed_no_signal(on)


func _save_scenario() -> void:
	settings.scenario = {
		"hole_index": session.round_state.current_index,
		"ball": [session.ball_pos.x, session.ball_pos.z],
		"aim": session.aim_bearing_deg,
		"mode": session.mode,
		"lie_override": session.lie_override,
		"wind_custom": session.wind_custom,
		"wind_speed": session.wind_custom_speed,
		"wind_bearing": session.wind_custom_bearing,
	}
	_save()
	_say("Scenario saved")


func _load_scenario() -> void:
	var sc := settings.scenario
	if sc.is_empty():
		_say("No saved scenario")
		return
	var hi := int(sc.get("hole_index", 0))
	if hi != session.round_state.current_index:
		session.dev_select_hole(hi)
		session.begin_play()
	session.lie_override = int(sc.get("lie_override", -1))
	session.wind_custom = bool(sc.get("wind_custom", false))
	session.wind_custom_speed = float(sc.get("wind_speed", 0.0))
	session.wind_custom_bearing = float(sc.get("wind_bearing", 0.0))
	var b: Array = sc.get("ball", [0, 0])
	var err := session.dev_place_ball(float(b[0]), float(b[1]))
	session.set_aim(float(sc.get("aim", 0.0)))
	session.set_mode(int(sc.get("mode", 0)))
	_say("Scenario loaded" if err == "" else "Scenario loaded; ball: %s" % err)


# ------------------------------------------------------------------ Env tab

func _build_env_tab() -> VBoxContainer:
	var v := UiKit.vbox(8)
	var wc := CheckButton.new()
	wc.text = "Custom wind (else hole default)"
	wc.add_theme_font_size_override("font_size", 21)
	wc.button_pressed = session.wind_custom
	v.add_child(wc)
	var ws := UiKit.spin(0, 25, 0.1, session.wind_custom_speed, Callable())
	var wb := UiKit.spin(0, 359, 1, session.wind_custom_bearing, Callable())
	wc.toggled.connect(func(on: bool) -> void:
		session.wind_custom = on
		_save())
	ws.value_changed.connect(func(val: float) -> void:
		session.wind_custom_speed = val
		_save())
	wb.value_changed.connect(func(val: float) -> void:
		session.wind_custom_bearing = val
		_save())
	v.add_child(_row("Wind speed (m/s)", ws))
	v.add_child(_row("Wind toward bearing (deg, 0=+Z)", wb))
	v.add_child(_b("Zero wind", func() -> void:
		session.wind_custom = true
		wc.set_pressed_no_signal(true)
		session.wind_custom_speed = 0.0
		ws.set_value_no_signal(0.0)
		_save()
		_say("Wind zeroed")))
	var cup_spin := UiKit.spin(4.25, 72, 0.25, session.cfg.cup_diameter_in(), Callable())
	cup_spin.value_changed.connect(func(val: float) -> void:
		session.cfg.set_cup_diameter_in(val)
		_save())
	v.add_child(_row("Hole size (diameter, in)", cup_spin))
	v.add_child(_btn_row([_b("Regulation 4.25", func() -> void: cup_spin.value = 4.25), _b("Default 12", func() -> void: cup_spin.value = 12.0), _b("Huge 24", func() -> void: cup_spin.value = 24.0)]))
	v.add_child(_row("Hole-out radius (ft, 0 = cup only)", UiKit.spin(0, 10, 0.5, session.holeout_radius_ft, func(val: float) -> void:
		session.holeout_radius_ft = ScoringService.clamp_radius_ft(val)
		_save())))
	v.add_child(_row("Sim speed x", UiKit.spin(0.25, 8, 0.25, settings.sim_speed, func(val: float) -> void:
		settings.sim_speed = val
		_save())))
	var cfg := session.cfg
	v.add_child(_row("Caps launch angle (deg)", UiKit.spin(10, 70, 0.5, cfg.launch_angle_deg, func(val: float) -> void:
		cfg.launch_angle_deg = val
		_save())))
	v.add_child(_row("Air drag k (1/m)", UiKit.spin(0, 0.01, 0.0001, cfg.drag_k, func(val: float) -> void:
		cfg.drag_k = val
		_save())))
	v.add_child(UiKit.text("Surface coefficients", 20, UiKit.C_MUTED))
	_surf_sel = OptionButton.new()
	for t in Surface.PLAYABLE:
		_surf_sel.add_item(Surface.name_of(t))
	_surf_sel.custom_minimum_size = Vector2(0, 56)
	_surf_sel.item_selected.connect(func(_i: int) -> void: _load_surface_spins())
	v.add_child(_surf_sel)
	var specs := [["roll_decel", "Rolling decel (m/s²)", 0.0, 20.0, 0.05], ["roll_drag", "Rolling drag (1/s)", 0.0, 5.0, 0.01],
		["restitution", "Restitution", 0.0, 1.0, 0.01], ["retention", "Tangential retention", 0.0, 1.0, 0.01],
		["caps_min", "Caps lie factor min", 0.1, 1.2, 0.01], ["caps_max", "Caps lie factor max", 0.1, 1.2, 0.01]]
	for sp in specs:
		var key: String = sp[0]
		var spin := UiKit.spin(sp[2], sp[3], sp[4], 0.0, func(val: float) -> void:
			var t2: int = Surface.PLAYABLE[_surf_sel.selected]
			(cfg.surfaces[t2] as Dictionary)[key] = val
			_save())
		_surf_spins[key] = spin
		v.add_child(_row(sp[1], spin))
	_load_surface_spins()
	v.add_child(_b("Reset all physics to defaults", func() -> void:
		settings.reset_physics()
		_load_surface_spins()
		_save()
		_say("Physics defaults restored (reopen panel to refresh angle/drag fields)")))
	return v


func _load_surface_spins() -> void:
	var t: int = Surface.PLAYABLE[_surf_sel.selected]
	var p: Dictionary = session.cfg.surface(t)
	for k in _surf_spins.keys():
		(_surf_spins[k] as SpinBox).set_value_no_signal(float(p[k]))


func _save() -> void:
	settings.capture_from(session)
	settings.save()


# ------------------------------------------------------------------ Players tab

func _build_players_tab() -> VBoxContainer:
	var v := UiKit.vbox(8)
	var ss := CheckButton.new()
	ss.text = "TEST MODE: show caps/goals in normal picker"
	ss.add_theme_font_size_override("font_size", 21)
	ss.button_pressed = settings.show_stats
	ss.toggled.connect(func(on: bool) -> void:
		settings.show_stats = on
		settings.save()
		session.selection_changed.emit())
	v.add_child(ss)
	v.add_child(UiKit.text("This editor always shows stats.", 20, UiKit.C_DEV))
	_p_search = LineEdit.new()
	_p_search.placeholder_text = "Search…"
	_p_search.custom_minimum_size = Vector2(0, 56)
	_p_search.text_changed.connect(func(_t: String) -> void: _refresh_players())
	v.add_child(_p_search)
	_player_list = ItemList.new()
	_player_list.custom_minimum_size = Vector2(0, 300)
	_player_list.add_theme_font_size_override("font_size", 20)
	_player_list.item_selected.connect(_on_player_selected)
	v.add_child(_player_list)
	_p_name = LineEdit.new()
	_p_nat = LineEdit.new()
	_p_caps = LineEdit.new()
	_p_goals = LineEdit.new()
	for le in [_p_name, _p_nat, _p_caps, _p_goals]:
		(le as LineEdit).custom_minimum_size = Vector2(300, 54)
	_p_caps.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_p_goals.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	v.add_child(_row("Name", _p_name))
	v.add_child(_row("Nationality", _p_nat))
	v.add_child(_row("Senior caps", _p_caps))
	v.add_child(_row("Senior goals", _p_goals))
	v.add_child(_btn_row([_b("Save", _save_player), _b("Add new", _add_player), _b("Duplicate", _dup_player)]))
	v.add_child(_btn_row([_b("Delete", _delete_player), _b("Reset to seed", func() -> void:
		session.repo.reset_to_seed()
		_refresh_players()
		_say("Footballer database reset to seed"))]))
	_refresh_players()
	return v


func _refresh_players() -> void:
	if _player_list == null:
		return
	_player_list.clear()
	_player_ids.clear()
	for fb in session.repo.search(_p_search.text if _p_search else "", "", 300):
		var used := " [USED]" if session.pool.is_used(fb.id, session.mode) else ""
		_player_list.add_item("%s (%s) — C %d / G %d%s" % [fb.name, fb.nationality, fb.caps, fb.goals, used])
		_player_ids.append(fb.id)
		if fb.id == _selected_player:
			_player_list.select(_player_list.item_count - 1)


func _on_player_selected(i: int) -> void:
	_selected_player = _player_ids[i]
	var fb := session.repo.get_by_id(_selected_player)
	_p_name.text = fb.name
	_p_nat.text = fb.nationality
	_p_caps.text = str(fb.caps)
	_p_goals.text = str(fb.goals)


func _form() -> Dictionary:
	return {"name": _p_name.text.strip_edges(), "nationality": _p_nat.text.strip_edges(),
		"country_code": _p_nat.text.strip_edges().substr(0, 3).to_upper(),
		"senior_international_caps": _p_caps.text, "senior_international_goals": _p_goals.text}


func _save_player() -> void:
	if _selected_player == "":
		_say("Select a footballer first")
		return
	var err := session.repo.update_record(_selected_player, _form())
	_say("Saved" if err == "" else "Rejected: %s" % err)
	_refresh_players()


func _add_player() -> void:
	var d := _form()
	d["id"] = session.repo.new_id()
	if String(d["name"]) == "":
		d["name"] = "Dev Player %s" % d["id"]
	if String(d["nationality"]) == "":
		d["nationality"] = "Test Nation"
	d["notes"] = "Developer-created test record"
	var err := session.repo.add_record(d)
	if err == "":
		_selected_player = d["id"]
	_say("Added %s" % d["id"] if err == "" else "Rejected: %s" % err)
	_refresh_players()


func _dup_player() -> void:
	if _selected_player == "":
		return
	var nid := session.repo.duplicate_record(_selected_player)
	if nid != "":
		_selected_player = nid
	_say("Duplicated -> %s" % nid)
	_refresh_players()


func _delete_player() -> void:
	if _selected_player == "":
		return
	if session.selected_id == _selected_player:
		session.clear_selection()
	session.repo.delete_record(_selected_player)
	_say("Deleted %s" % _selected_player)
	_selected_player = ""
	_refresh_players()


# ------------------------------------------------------------------ Diagnostics tab

func _build_diag_tab() -> VBoxContainer:
	var v := UiKit.vbox(8)
	v.add_child(_btn_row([_b("Copy report", func() -> void:
		DisplayServer.clipboard_set(_diag.text)
		print(_diag.text)
		_say("Diagnostic report copied + logged")), _b("Calibration check", _run_calibration)]))
	_diag = UiKit.text("", 18, UiKit.C_TEXT)
	v.add_child(_diag)
	return v


func _refresh_diag() -> void:
	if _diag == null:
		return
	var lines: Array[String] = []
	lines.append("State %s · hole %s · ball (%.2f, %.2f, %.2f) · lie %s" % [ShotTypes.state_name(session.state), session.hole.id if session.hole else "-",
		session.ball_pos.x, session.ball_pos.y, session.ball_pos.z, Surface.name_of(session.current_lie())])
	lines.append("Aim %.1f deg · wind %.2f m/s toward %.0f deg · hole-out %.1f ft" % [session.aim_bearing_deg, session.wind_speed(), session.wind_bearing(), session.holeout_radius_ft])
	lines.append("Slope normal %s" % str(session.hole.normal_at(session.ball_pos.x, session.ball_pos.z)) if session.hole else "")
	lines.append("")
	if session.last_result != null:
		lines.append(session.last_result.diagnostic_text())
	else:
		lines.append("No shot yet.")
	_diag.text = "\n".join(lines)


func _run_calibration() -> void:
	var cfg := session.cfg
	var lines: Array[String] = ["NEUTRAL CALIBRATION (flat FAIRWAY plane, zero wind, same integrator)"]
	for caps in [1, 10, 50, 150, 200, 400]:
		var target := Units.caps_to_carry_m(caps)
		var v := ShotCalculator.solve_caps_speed(target, cfg)
		var got := ShotCalculator.measure_neutral_carry(v, cfg)
		var tol := maxf(Units.yards_to_m(0.25), target * 0.005)
		lines.append("Caps %3d: target %.2f yd carry %.3f yd err %.4f%% v=%.2f m/s %s" % [caps, Units.m_to_yards(target), Units.m_to_yards(got), (got - target) / target * 100.0, v, "OK" if absf(got - target) <= tol else "FAIL"])
	for goals in [0, 1, 5, 30, 100, 200]:
		var t2 := Units.goals_to_roll_m(goals)
		var v2 := ShotCalculator.solve_goals_speed(t2, cfg)
		var got2 := ShotCalculator.measure_neutral_roll(v2, cfg)
		var tol2 := maxf(Units.feet_to_m(0.1), t2 * 0.01)
		var err_pct := 0.0 if t2 <= 0.0 else (got2 - t2) / t2 * 100.0
		lines.append("Goals %3d: target %.1f ft roll %.3f ft err %.4f%% v=%.2f m/s %s" % [goals, Units.m_to_feet(t2), Units.m_to_feet(got2), err_pct, v2, "OK" if absf(got2 - t2) <= tol2 else "FAIL"])
	_diag.text = "\n".join(lines)
	print("\n".join(lines))
	_say("Calibration check complete (also logged)")

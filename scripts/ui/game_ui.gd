class_name GameUI
extends Control
## Portrait gameplay HUD per the approved UI reference: full-screen viewport behind floating matte
## controls (no footer panel). Reads from GameSession; only calls session APIs to act.
## Tokens/theme: UiKit. World, camera, physics and rules are untouched.

signal camera_toggle_requested
## factor > 0 zooms the overhead map; 0 = fit whole hole.
signal overhead_zoom_requested(factor: float)
signal main_menu_requested
signal aim_here_requested
signal developer_requested

const GAP := 12          # 6 logical units between related elements
const PAD := 16          # 8 logical units inside plates
const HIT := 96          # 48 logical units: minimum hit target

var session: GameSession
var markers: HudMarkers
var camera_yaw := 0.0
var overhead := false

var _margin: MarginContainer
var _overlays: Array[Control] = []
# scoreboard
var _hole_num: Label
var _hole_name: Label
var _hole_sub: Label
var _round_score: Label
var _round_sub: Label
# utility
var _wind_icon: LineIcon
var _wind_label: Label
var _unit_btn: Button
var _utility_row: HBoxContainer
var _scorecard_root: Control
var _right_shot: VBoxContainer
var _right_map: VBoxContainer
var _aim_here_btn: Button
var _aim_icon: LineIcon
# shot controls
var _shot_controls: VBoxContainer
var _lie_label: Label
var _lie_hint: Label
var _caps_btn: Button
var _goals_btn: Button
var _flight_btn: Button
var _roll_btn: Button
var _player_btn: Button
var _player_flag: TextureRect
var _player_name: Label
var _player_sub: Label
var _spin_box: HBoxContainer
var _spin: SpinControl
var _spin_label: Label
var _traj_btn: Button
var _skip_btn: Button
var _shot_btn: Button
var _shot_label: Label
var _shot_icon: LineIcon
# result card
var _result_card: PanelContainer
var _result_box: VBoxContainer
var _reveal: Tween
var _result_distance_labels: Array[Dictionary] = []
var _result_base_label: Label
var _result_base_m := 0.0
var _result_base_mode := ShotTypes.Mode.CAPS
var _result_base_style := ShotTypes.Style.FLIGHT
var _unit_round_id := -1
var _unit_hole_id := ""
var _unit_aim_shot_id := -1
# map controls
var _map_controls: VBoxContainer
var _map_hint: Label
var _target_value: Label
var _pin_value: Label
var _toast: Label
var _toast_t := 0.0
var _target_dist_m := -1.0


func setup(s: GameSession) -> void:
	session = s
	theme = UiKit.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	markers = HudMarkers.new()
	add_child(markers)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)
	_apply_safe_area()
	var col := UiKit.vbox(GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(col)
	col.add_child(_build_scoreboard())
	_utility_row = _build_utility_row()
	col.add_child(_utility_row)
	_toast = UiKit.text("", 22, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.add_theme_constant_override("outline_size", 6)
	col.add_child(_toast)
	_shot_controls = _build_shot_controls()
	col.add_child(_shot_controls)
	_result_card = UiKit.panel(UiKit.C_SURFACE)
	_result_card.visible = false
	_result_box = UiKit.vbox(8)
	_result_card.add_child(_result_box)
	col.add_child(_result_card)
	_map_controls = _build_map_controls()
	col.add_child(_map_controls)
	session.state_changed.connect(func(_s: int) -> void: refresh())
	session.selection_changed.connect(refresh)
	session.shot_resolved.connect(_on_shot_resolved)
	session.hole_completed.connect(_on_hole_completed)
	session.round_completed.connect(_on_round_completed)
	session.message.connect(toast)
	session.ball_placed.connect(refresh)
	refresh()


func _apply_safe_area() -> void:
	var sm := UiKit.safe_margins(get_viewport()) if is_inside_tree() else [32.0, 32.0, 32.0, 32.0]
	_margin.add_theme_constant_override("margin_left", int(sm[0]))
	_margin.add_theme_constant_override("margin_top", int(sm[1]))
	_margin.add_theme_constant_override("margin_right", int(sm[2]))
	_margin.add_theme_constant_override("margin_bottom", int(sm[3]))


# ------------------------------------------------------------------ small builders

func _plate(h: int = PAD, v: int = 10, color: Color = UiKit.C_SURFACE) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiKit.box(color, UiKit.RADIUS, 0)
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v
	sb.content_margin_bottom = v
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _tag(text: String, size: int = 18, color: Color = UiKit.C_MUTED, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(text, size, color, align)
	l.add_theme_font_override("font", UiKit.font_semi())
	return l


func _num(text: String, size: int, color: Color = UiKit.C_TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(text, size, color, align)
	l.add_theme_font_override("font", UiKit.font_num())
	return l


func _flat_style(color: Color, bottom_border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var sb := UiKit.box(color, UiKit.RADIUS, 0)
	sb.border_width_bottom = border_w
	sb.border_color = bottom_border
	return sb


## Charcoal icon button (optional short label under the icon). Children never eat the click.
func _icon_btn(kind: String, label: String, cb: Callable, ui_id: String, w: int = HIT, h: int = HIT) -> Button:
	var b := UiKit.button("", cb, h, 20)
	b.custom_minimum_size = Vector2(w, h)
	for st in ["normal", "hover"]:
		b.add_theme_stylebox_override(st, _flat_style(UiKit.C_SURFACE))
	b.add_theme_stylebox_override("pressed", _flat_style(UiKit.C_SELECTED))
	b.add_theme_stylebox_override("disabled", _flat_style(UiKit.C_SURFACE.darkened(0.1)))
	b.set_meta("ui_id", ui_id)
	b.tooltip_text = label if label != "" else ui_id
	b.set("accessibility_name", label if label != "" else ui_id.replace("_", " "))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UiKit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := LineIcon.make(kind, 36)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	if label != "":
		var l := _tag(label, 17, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(l)
	center.add_child(v)
	b.add_child(center)
	b.set_meta("icon", icon)
	return b


func _build_scoreboard() -> PanelContainer:
	var p := _plate(PAD, 12)
	var row := UiKit.hbox(PAD)
	p.add_child(row)
	# ivory hole-number block
	var block := PanelContainer.new()
	block.add_theme_stylebox_override("panel", _flat_style(UiKit.C_TEXT))
	block.custom_minimum_size = Vector2(84, 84)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bv := UiKit.vbox(0)
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(_tag("HOLE", 16, UiKit.C_ACTION_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_hole_num = _num("01", 40, UiKit.C_ACTION_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_hole_num.add_theme_font_override("font", UiKit.font_semi())
	bv.add_child(_hole_num)
	block.add_child(bv)
	row.add_child(block)
	var mid := UiKit.vbox(2)
	UiKit.expand(mid)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hole_name = UiKit.label("", 34)
	_hole_name.add_theme_font_override("font", UiKit.font_semi())
	_hole_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mid.add_child(_hole_name)
	_hole_sub = _num("", 21, UiKit.C_MUTED)
	mid.add_child(_hole_sub)
	row.add_child(mid)
	var div := ColorRect.new()
	div.color = UiKit.C_DIVIDER
	div.custom_minimum_size = Vector2(2, 64)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(div)
	var right := UiKit.vbox(0)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.custom_minimum_size.x = 104
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_score = _num("E", 48, Color("#FBF6E9"), HORIZONTAL_ALIGNMENT_RIGHT)
	_round_score.add_theme_font_override("font", UiKit.font_semi())
	right.add_child(_round_score)
	_round_sub = _num("", 17, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(_round_sub)
	row.add_child(right)
	return p


func _toggle_units() -> void:
	Units.show_feet = not Units.show_feet
	_update_unit_btn()
	if _target_dist_m >= 0.0:
		_target_value.text = Units.fmt_len(_target_dist_m)
		markers.target_dist_text = Units.fmt_len(_target_dist_m)
	_refresh_result_distances()
	refresh()
	toast("Distances in %s" % ("feet" if Units.show_feet else "yards"), 1.5)


func _update_unit_btn() -> void:
	if _unit_btn != null:
		_unit_btn.text = "FT  ·  yd" if Units.show_feet else "YD  ·  ft"


func _build_utility_row() -> HBoxContainer:
	var row := UiKit.hbox(GAP)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# wind chip (upper left)
	var left := UiKit.vbox(GAP)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wind := _plate(14, 10)
	var wr := UiKit.hbox(10)
	wr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wind_icon = LineIcon.make("arrow_up", 32)
	wr.add_child(_wind_icon)
	_wind_label = _num("", 24)
	wr.add_child(_wind_label)
	wind.add_child(wr)
	wind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(wind)
	# yards / feet switch (any time); override lasts for this shot only
	_unit_btn = UiKit.button("", func() -> void: _toggle_units(), 64, 22)
	_unit_btn.custom_minimum_size.x = 120
	_unit_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_unit_btn.add_theme_font_override("font", UiKit.font_semi())
	_unit_btn.set_meta("ui_id", "units")
	_unit_btn.tooltip_text = "Switch distances between yards and feet"
	for st in ["normal", "hover", "pressed"]:
		_unit_btn.add_theme_stylebox_override(st, UiKit.box(UiKit.C_SURFACE, UiKit.RADIUS, 12))
	left.add_child(_unit_btn)
	_update_unit_btn()
	row.add_child(left)
	var spacer := Control.new()
	UiKit.expand(spacer)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	# right edge: shot view = pause / map / card; map view = + / - / fit / aim
	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_shot = UiKit.vbox(GAP)
	_right_shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_shot.add_child(_icon_btn("pause", "", show_pause, "pause", HIT, 84))
	_right_shot.add_child(_icon_btn("map", "Map", func() -> void: camera_toggle_requested.emit(), "map", HIT, 108))
	_right_shot.add_child(_icon_btn("list", "Card", show_scorecard, "card", HIT, 108))
	stack.add_child(_right_shot)
	_right_map = UiKit.vbox(GAP)
	_right_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_map.add_child(_icon_btn("plus", "", func() -> void: overhead_zoom_requested.emit(1.4), "zoom_in", HIT, 84))
	_right_map.add_child(_icon_btn("minus", "", func() -> void: overhead_zoom_requested.emit(1.0 / 1.4), "zoom_out", HIT, 84))
	_right_map.add_child(_icon_btn("fit", "Fit", func() -> void: overhead_zoom_requested.emit(0.0), "fit", HIT, 108))
	_aim_here_btn = _icon_btn("target", "Aim", func() -> void: aim_here_requested.emit(), "aim_here", HIT, 108)
	_aim_icon = _aim_here_btn.get_meta("icon")
	_right_map.add_child(_aim_here_btn)
	stack.add_child(_right_map)
	row.add_child(stack)
	return row


func _build_shot_controls() -> VBoxContainer:
	var v := UiKit.vbox(GAP)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 1. small lie / shot label above the controls
	var lie_row := UiKit.hbox(GAP)
	lie_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lie := _plate(14, 8)
	lie.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lv := UiKit.vbox(0)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lie_label = _tag("", 20, UiKit.C_TEXT)
	lv.add_child(_lie_label)
	_lie_hint = UiKit.label("", 17, UiKit.C_MUTED)
	lv.add_child(_lie_hint)
	lie.add_child(lv)
	lie_row.add_child(lie)
	v.add_child(lie_row)
	# 2. Distance source and ball movement are separate choices in one compact strip.
	var strip := _plate(4, 4)
	var sr := UiKit.hbox(0)
	strip.add_child(sr)
	var group := ButtonGroup.new()
	_caps_btn = _mode_btn("CAPS", group, "mode_caps", func() -> void: session.set_mode(ShotTypes.Mode.CAPS))
	_goals_btn = _mode_btn("GOALS", group, "mode_goals", func() -> void: session.set_mode(ShotTypes.Mode.GOALS))
	var style_group := ButtonGroup.new()
	_flight_btn = _mode_btn("FLIGHT", style_group, "style_flight", func() -> void: session.set_style(ShotTypes.Style.FLIGHT))
	_roll_btn = _mode_btn("ROLL", style_group, "style_roll", func() -> void: session.set_style(ShotTypes.Style.ROLL))
	sr.add_child(_caps_btn)
	sr.add_child(_goals_btn)
	var divider := VSeparator.new()
	divider.custom_minimum_size.x = 8
	sr.add_child(divider)
	sr.add_child(_flight_btn)
	sr.add_child(_roll_btn)
	v.add_child(strip)
	# 3. separate footballer row: flag, name, country, swap icon
	_player_btn = Button.new()
	_player_btn.custom_minimum_size = Vector2(0, 100)
	_player_btn.focus_mode = Control.FOCUS_ALL
	_player_btn.set_meta("ui_id", "player_row")
	_player_btn.tooltip_text = "Choose footballer"
	_player_btn.set("accessibility_name", "Choose footballer")
	for st in ["normal", "hover"]:
		_player_btn.add_theme_stylebox_override(st, _flat_style(UiKit.C_SURFACE))
	_player_btn.add_theme_stylebox_override("pressed", _flat_style(UiKit.C_SELECTED))
	_player_btn.add_theme_stylebox_override("disabled", _flat_style(UiKit.C_SURFACE.darkened(0.1)))
	_player_btn.pressed.connect(show_picker)
	var pm := MarginContainer.new()
	pm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		pm.add_theme_constant_override("margin_" + side, 18)
	var pr := UiKit.hbox(16)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_flag = TextureRect.new()
	_player_flag.custom_minimum_size = Vector2(56, 38)
	_player_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_player_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pr.add_child(_player_flag)
	var pv := UiKit.vbox(0)
	UiKit.expand(pv)
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_name = UiKit.label("", 32)
	_player_name.add_theme_font_override("font", UiKit.font_semi())
	_player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pv.add_child(_player_name)
	_player_sub = _num("", 21, UiKit.C_MUTED)
	_player_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pv.add_child(_player_sub)
	pr.add_child(pv)
	var swap := LineIcon.make("swap", 38, UiKit.C_TEXT)
	swap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pr.add_child(swap)
	pm.add_child(pr)
	_player_btn.add_child(pm)
	v.add_child(_player_btn)
	# 4. spin control lower left, ivory Take shot lower right
	var br := UiKit.hbox(GAP)
	br.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spin_box = UiKit.hbox(GAP)
	_spin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spin = SpinControl.new()
	_spin.spin_changed.connect(func(val: float) -> void: session.set_spin(val))
	_spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spin_box.add_child(_spin)
	var sl := _plate(14, 10)
	sl.custom_minimum_size = Vector2(132, 0)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_spin_label = _num("NO SPIN", 20, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_spin_label.add_theme_font_override("font", UiKit.font_semi())
	sl.add_child(_spin_label)
	_spin_box.add_child(sl)
	# Flight trajectory: tap to cycle Punch / Low / Standard / High; resets after each shot
	_traj_btn = Button.new()
	_traj_btn.custom_minimum_size = Vector2(132, 84)
	_traj_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_traj_btn.focus_mode = Control.FOCUS_ALL
	_traj_btn.set_meta("ui_id", "trajectory")
	_traj_btn.set("accessibility_name", "Trajectory")
	_traj_btn.tooltip_text = "Trajectory: tap to cycle Punch, Low, Standard, High"
	for st in ["normal", "hover"]:
		_traj_btn.add_theme_stylebox_override(st, _flat_style(UiKit.C_SURFACE))
	_traj_btn.add_theme_stylebox_override("pressed", _flat_style(UiKit.C_SELECTED))
	_traj_btn.add_theme_font_size_override("font_size", 19)
	_traj_btn.add_theme_font_override("font", UiKit.font_semi())
	_traj_btn.add_theme_color_override("font_color", UiKit.C_TEXT)
	_traj_btn.add_theme_color_override("font_hover_color", UiKit.C_TEXT)
	_traj_btn.add_theme_color_override("font_pressed_color", UiKit.C_TEXT)
	_traj_btn.pressed.connect(func() -> void: session.cycle_trajectory())
	_spin_box.add_child(_traj_btn)
	br.add_child(_spin_box)
	_skip_btn = UiKit.button("Skip", func() -> void: session.skip_motion(), 96, 24)
	_skip_btn.custom_minimum_size.x = 150
	_skip_btn.set_meta("ui_id", "skip")
	_skip_btn.visible = false
	br.add_child(_skip_btn)
	_shot_btn = UiKit.primary(Button.new())
	_shot_btn.custom_minimum_size = Vector2(0, 100)
	UiKit.expand(_shot_btn)
	_shot_btn.focus_mode = Control.FOCUS_ALL
	_shot_btn.set_meta("ui_id", "take_shot")
	_shot_btn.set("accessibility_name", "Take shot")
	_shot_btn.pressed.connect(_on_take_shot)
	var sc := CenterContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := UiKit.hbox(12)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shot_label = UiKit.label("Take shot", 29, UiKit.C_ACTION_TEXT)
	_shot_label.add_theme_font_override("font", UiKit.font_semi())
	sh.add_child(_shot_label)
	_shot_icon = LineIcon.make("arrow_right", 34, UiKit.C_ACTION_TEXT)
	sh.add_child(_shot_icon)
	sc.add_child(sh)
	_shot_btn.add_child(sc)
	br.add_child(_shot_btn)
	v.add_child(br)
	return v


func _mode_btn(text: String, group: ButtonGroup, ui_id: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 74)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_font_override("font", UiKit.font_semi())
	b.add_theme_stylebox_override("normal", _flat_style(UiKit.C_SURFACE))
	b.add_theme_stylebox_override("hover", _flat_style(UiKit.C_SURFACE))
	var on := _flat_style(UiKit.C_SURFACE, UiKit.C_ACCENT, 5)   # muted sage underline = selected
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("disabled", _flat_style(UiKit.C_SURFACE))
	b.add_theme_color_override("font_color", UiKit.C_MUTED)
	b.add_theme_color_override("font_hover_color", UiKit.C_TEXT)
	b.add_theme_color_override("font_pressed_color", UiKit.C_TEXT)
	b.add_theme_color_override("font_hover_pressed_color", UiKit.C_TEXT)
	b.add_theme_color_override("font_disabled_color", Color("#8F948B"))
	b.set_meta("ui_id", ui_id)
	b.pressed.connect(cb)
	return b


func _build_map_controls() -> VBoxContainer:
	var v := UiKit.vbox(GAP)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_hint = UiKit.text("Tap to measure  •  Drag to pan  •  Pinch to zoom", 20, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_map_hint.add_theme_constant_override("outline_size", 6)  # subtle text shadow instead of a glass panel
	v.add_child(_map_hint)
	var strip := _plate(PAD, 12)
	var r := UiKit.hbox(PAD)
	strip.add_child(r)
	var t := UiKit.hbox(8)
	UiKit.expand(t)
	t.alignment = BoxContainer.ALIGNMENT_CENTER
	t.add_child(_tag("TARGET", 18))
	_target_value = _num("—", 30)
	t.add_child(_target_value)
	r.add_child(t)
	var div := ColorRect.new()
	div.color = UiKit.C_DIVIDER
	div.custom_minimum_size = Vector2(2, 40)
	div.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(div)
	var pn := UiKit.hbox(8)
	UiKit.expand(pn)
	pn.alignment = BoxContainer.ALIGNMENT_CENTER
	pn.add_child(_tag("PIN", 18))
	_pin_value = _num("", 30)
	pn.add_child(_pin_value)
	r.add_child(pn)
	v.add_child(strip)
	var back := UiKit.primary(Button.new())
	back.custom_minimum_size = Vector2(0, 100)
	back.set_meta("ui_id", "return_to_shot")
	back.set("accessibility_name", "Return to shot")
	back.pressed.connect(func() -> void: camera_toggle_requested.emit())
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UiKit.hbox(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bl := UiKit.label("Return to shot", 32, UiKit.C_ACTION_TEXT)
	bl.add_theme_font_override("font", UiKit.font_semi())
	h.add_child(bl)
	h.add_child(LineIcon.make("arrow_right", 34, UiKit.C_ACTION_TEXT))
	cc.add_child(h)
	back.add_child(cc)
	v.add_child(back)
	return v


# ------------------------------------------------------------------ state binding

func toast(text: String, secs: float = 2.5) -> void:
	_toast.text = text
	_toast_t = secs


## Legacy hook: an empty string clears the map target.
func set_measure(text: String) -> void:
	if text == "":
		clear_target()


## Live map target (world position of the tapped point, distance from the ball, terrain text).
func set_target(world: Vector3, dist_m: float, surface_name: String, bearing: float) -> void:
	_target_dist_m = dist_m
	markers.target_world = world
	markers.target_dist_text = Units.fmt_len(dist_m)
	markers.target_sub_text = "%s · %d°" % [surface_name, int(round(bearing))]
	markers.show_target = true
	_target_value.text = Units.fmt_len(dist_m)


func clear_target() -> void:
	_target_dist_m = -1.0
	if markers != null:
		markers.show_target = false
		markers.target_world = Vector3.INF
	if _target_value != null:
		_target_value.text = "—"


func set_marker_ready(on: bool) -> void:
	if _aim_here_btn != null:
		_aim_here_btn.disabled = not on
		_aim_icon.set_color(UiKit.C_TEXT if on else Color("#6E736C"))


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		if _toast_t <= 0.0:
			_toast.text = ""
	if session == null or session.hole == null:
		return
	var pin_m := Units.horizontal_distance(session.ball_render_pos(), session.hole.cup_position())
	var pin_txt := Units.fmt_len(pin_m)
	markers.pin_world = session.hole.cup_position() + Vector3(0, 1.2, 0)
	markers.pin_text = pin_txt
	_pin_value.text = pin_txt
	var wb := deg_to_rad(session.wind_bearing())
	_wind_icon.set_rotation_rad(camera_yaw - wb)  # arrow shows where the wind blows TOWARD, as seen from the camera
	_wind_label.text = "%d mph" % int(round(session.wind_speed() * Units.MPS_TO_MPH))


func refresh() -> void:
	if session == null or session.hole == null:
		return
	_sync_shot_units()
	var hs := session.current_hole_state()
	var h := session.hole
	# --- scoreboard (live fields)
	_hole_num.text = "%02d" % (session.round_state.current_index + 1)
	_hole_name.text = h.display_name
	_hole_sub.text = "PAR %d  •  %d YD" % [h.par, int(h.yards)]
	_round_score.text = RoundState.fmt_relative(session.round_state.relative_to_par())
	var pen := "  +%d PEN" % hs.penalties if hs.penalties > 0 else ""
	_round_sub.text = "%d STR%s" % [hs.raw_total(), pen]
	# --- lie / shot label
	var lie := session.current_lie()
	var lie_txt := "%s  •  SHOT %d" % [Surface.name_of(lie).to_upper(), hs.raw_total() + 1]
	if session.lie_override >= 0:
		lie_txt += "  •  DEV LIE"
	_lie_label.text = lie_txt
	var hint := Surface.effect_hint(lie, session.cfg.surfaces)
	var neutral := hint.contains("neutral") and hint.contains("normal")
	_lie_hint.text = "" if neutral else hint
	_lie_hint.visible = not neutral
	if lie == Surface.Type.GREEN and h != null:
		var sl := h.normal_at(session.ball_pos.x, session.ball_pos.z)
		var pct := Vector2(sl.x, sl.z).length() / maxf(sl.y, 0.01) * 100.0
		var downhill := Vector3(sl.x, 0.0, sl.z)
		var right := session.aim_dir().cross(Vector3.UP)
		var breaks := "" if pct < 0.3 else (" · breaks right" if downhill.dot(right) > 0.0 else " · breaks left")
		_lie_hint.text = "Green slope %.1f%%%s" % [pct, breaks]
		_lie_hint.visible = true
	# --- mode strip
	_caps_btn.set_pressed_no_signal(session.mode == ShotTypes.Mode.CAPS)
	_goals_btn.set_pressed_no_signal(session.mode == ShotTypes.Mode.GOALS)
	_flight_btn.set_pressed_no_signal(session.style == ShotTypes.Style.FLIGHT)
	_roll_btn.set_pressed_no_signal(session.style == ShotTypes.Style.ROLL)
	# --- player row (names always; stats only in TEST MODE; reveal rules unchanged)
	var fb := session.repo.get_by_id(session.selected_id) if session.selected_id != "" else null
	if fb == null:
		_player_flag.texture = null
		_player_flag.visible = false
		_player_name.text = "Choose footballer"
		_player_sub.text = "Search %d players by name or country" % session.repo.count()
	else:
		_player_flag.visible = true
		_player_flag.texture = Flags.texture(fb.country_code)
		_player_name.text = fb.name
		var line2 := fb.nationality
		if App.settings.show_stats:
			if session.mode == ShotTypes.Mode.CAPS:
				line2 += "  •  %s = %d yd" % [UiKit.plural(fb.caps, "cap"), fb.caps]
			else:
				line2 += "  •  %s = %d ft" % [UiKit.plural(fb.goals, "goal"), fb.goals]
		_player_sub.text = line2
	# --- shot state
	var moving := session.is_ball_moving()
	var aiming := session.state == ShotTypes.State.AIMING
	if session.state != ShotTypes.State.SHOT_RESULT and _reveal != null and _reveal.is_valid():
		_reveal.kill()
		_result_box.modulate.a = 1.0
	var show_result := session.state == ShotTypes.State.SHOT_RESULT
	var between := session.state == ShotTypes.State.HOLE_COMPLETE or session.state == ShotTypes.State.ROUND_COMPLETE
	_shot_controls.visible = not show_result and not overhead and not between
	_utility_row.visible = (_scorecard_root == null or not is_instance_valid(_scorecard_root)) and not between
	_result_card.visible = show_result and not overhead
	_map_controls.visible = overhead
	_right_shot.visible = not overhead
	_right_map.visible = overhead
	_spin_box.visible = session.style == ShotTypes.Style.FLIGHT and not moving
	_skip_btn.visible = moving
	_spin.set_spin(session.spin)
	var traj := ShotTypes.trajectory_name(session.trajectory)
	_traj_btn.text = "%s\n%d°" % [traj, int(round(session.launch_angle_for(session.trajectory)))]
	_spin_label.text = "NO SPIN" if absf(session.spin) < 0.025 else "%s %d%%" % ["TOP" if session.spin > 0.0 else "BACK", int(round(absf(session.spin) * 100.0))]
	# Always tappable while aiming: with no footballer chosen it opens the picker instead.
	_shot_btn.disabled = not (aiming and _overlays.is_empty())
	if moving:
		_shot_label.text = "Ball in motion"
	elif fb == null:
		_shot_label.text = "Choose footballer"
	else:
		_shot_label.text = "Take shot"
	var shot_col := UiKit.C_MUTED if _shot_btn.disabled else UiKit.C_ACTION_TEXT
	_shot_label.add_theme_color_override("font_color", shot_col)
	_shot_icon.set_color(shot_col)
	_shot_icon.visible = not moving
	_caps_btn.disabled = moving
	_goals_btn.disabled = moving
	_flight_btn.disabled = moving
	_roll_btn.disabled = moving
	_player_btn.disabled = moving
	_map_hint.text = "Tap to measure  •  Drag to pan  •  Pinch to zoom"
	markers.visible = not (show_result and not overhead)


func _sync_shot_units() -> void:
	# Keep a manual choice through the shot and its result. Reset when the next shot
	# becomes aimable, or when a new hole's intro starts.
	if session.state != ShotTypes.State.AIMING and session.state != ShotTypes.State.HOLE_INTRO:
		return
	var round_id := session.round_state.get_instance_id()
	var unit_key: int = session.shot_counter * 2 + session.mode
	if _unit_round_id == round_id and _unit_hole_id == session.hole.id and _unit_aim_shot_id == unit_key:
		return
	_unit_round_id = round_id
	_unit_hole_id = session.hole.id
	_unit_aim_shot_id = unit_key
	Units.show_feet = session.mode == ShotTypes.Mode.GOALS  # CAPS = yards, GOALS = feet
	_update_unit_btn()
	if _target_dist_m >= 0.0:
		_target_value.text = Units.fmt_len(_target_dist_m)
		markers.target_dist_text = Units.fmt_len(_target_dist_m)


func _distance_stat_cell(caption: String, distance_m: float) -> VBoxContainer:
	var cell := _stat_cell(caption, Units.fmt_len(distance_m))
	_result_distance_labels.append({"label": cell.get_child(0), "metres": distance_m})
	return cell


func _refresh_result_distances() -> void:
	if _result_base_label != null and is_instance_valid(_result_base_label):
		var motion := "carry" if _result_base_style == ShotTypes.Style.FLIGHT else "ground travel"
		_result_base_label.text = "= %s neutral %s" % [Units.fmt_len(_result_base_m), motion]
	for entry in _result_distance_labels:
		var label: Label = entry["label"]
		if is_instance_valid(label):
			label.text = Units.fmt_len(float(entry["metres"]))


func _on_take_shot() -> void:
	if not _overlays.is_empty():
		return
	if session.selected_id == "" and session.state == ShotTypes.State.AIMING:
		show_picker()
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
	if c == _scorecard_root:
		_scorecard_root = null
	if is_instance_valid(c):
		c.queue_free()
	refresh()
	return true


func close_all_overlays() -> void:
	while close_top_overlay():
		pass
	_scorecard_root = null


func _remove_overlay(c: Control) -> void:
	_overlays.erase(c)
	if c == _scorecard_root:
		_scorecard_root = null
	if is_instance_valid(c):
		c.queue_free()
	refresh()


func show_picker() -> void:
	if session.is_ball_moving():
		return
	var p := FootballerPicker.new()
	p.context_text = "Ball %s to pin" % Units.fmt_len(session.distance_to_pin_m())
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
	v.add_child(UiKit.text("HOLE %d OF %d" % [session.round_state.current_index + 1, session.round_state.holes.size()], 30, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text(h.display_name, 44, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("Par %d · %d yd" % [h.par, int(h.yards)], 32, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("Round %s" % RoundState.fmt_relative(session.round_state.relative_to_par()), 22, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
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
	_result_distance_labels.clear()
	_result_base_label = null
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
	var big := UiKit.label("0 %s" % unit, 46, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_result_box.add_child(big)
	var sub := UiKit.label("", 20, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_result_base_label = sub
	_result_base_m = r.base_distance_m
	_result_base_mode = r.mode
	_result_base_style = r.style
	_refresh_result_distances()
	_result_box.add_child(sub)
	var grid := UiKit.hbox(6)
	if r.style == ShotTypes.Style.FLIGHT:
		grid.add_child(_distance_stat_cell("CARRY", r.carry_m))
		grid.add_child(_distance_stat_cell("ROLL", r.roll_m))
		grid.add_child(_distance_stat_cell("TOTAL", r.total_m))
	else:
		grid.add_child(_distance_stat_cell("TRAVEL", r.total_m))
		grid.add_child(_stat_cell("LIE", Surface.name_of(r.final_lie)))
	if not r.holed:
		grid.add_child(_distance_stat_cell("TO PIN", r.remaining_m))
	_result_box.add_child(grid)
	var extra: Array[String] = []
	if r.lie_factor < 0.999:
		extra.append("%s lie cost %d%%" % [Surface.name_of(r.start_lie), int(round((1.0 - r.lie_factor) * 100.0))])
	if not r.collisions.is_empty():
		extra.append("Hit a tree")
	if r.wind_speed_mps > 0.1 and r.style == ShotTypes.Style.FLIGHT:
		extra.append("Wind %d mph" % int(round(r.wind_speed_mps * Units.MPS_TO_MPH)))
	if r.style == ShotTypes.Style.FLIGHT:
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
		status = "Strokes so far %d · par %d" % [hs.raw_total(), hs.par]
	_result_box.add_child(UiKit.label(status, 19, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var details := UiKit.text(r.diagnostic_text(), 16, UiKit.C_MUTED)
	details.visible = false
	var row := UiKit.hbox()
	row.add_child(UiKit.button("Details", func() -> void: details.visible = not details.visible, 70, 21))
	if session.can_mulligan():
		var left := session.round_state.mulligans_remaining()
		var retry := UiKit.button("Mulligan%s" % ("" if left < 0 else " · %d" % left),
			func() -> void: session.use_mulligan(), 80, 23)
		row.add_child(retry)
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


# --- hole summary + next-hole loading (round_controller prepares the next hole in slices and
# reports progress through set_next_hole_progress; "Next hole" stays greyed until it is ready)
var _next_btn: Button
var _next_bar: ProgressBar
var _next_status: Label
var _next_progress_seen := false


static func _score_name(hs: HoleState) -> String:
	if hs.strokes == 1 and hs.penalties == 0:
		return "HOLE IN ONE!"
	var names := {-3: "ALBATROSS!", -2: "EAGLE!", -1: "BIRDIE!", 0: "PAR", 1: "BOGEY", 2: "DOUBLE BOGEY", 3: "TRIPLE BOGEY"}
	return String(names.get(hs.relative_to_par(), "HOLED"))


func _summary_cell(caption: String, value: String) -> VBoxContainer:
	var v := UiKit.vbox(0)
	UiKit.expand(v)
	v.add_child(UiKit.label(value, 28, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label(caption, 16, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	return v


func _on_hole_completed(hs: HoleState) -> void:
	var parts := _centered_card()
	var root: Control = parts[0]
	var v: VBoxContainer = parts[1]
	var rs := session.round_state
	v.add_child(UiKit.text("HOLE %d COMPLETE" % (rs.current_index + 1), 22, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text(_score_name(hs), 42, UiKit.C_WARN, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("%s · Par %d · Score %d (%s)" % [hs.hole_name, hs.par, hs.score(), RoundState.fmt_relative(hs.relative_to_par())], 24, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	var longest := 0.0
	for r in hs.shots:
		if r is ShotResult:
			longest = maxf(longest, (r as ShotResult).total_m)
	var stats := UiKit.hbox(6)
	stats.add_child(_summary_cell("SHOTS", str(hs.strokes)))
	stats.add_child(_summary_cell("PENALTY", str(hs.penalties)))
	stats.add_child(_summary_cell("LONGEST", "%d yd" % int(round(Units.m_to_yards(longest)))))
	stats.add_child(_summary_cell("ROUND", RoundState.fmt_relative(rs.relative_to_par())))
	v.add_child(stats)
	v.add_child(_rule())
	v.add_child(_scorecard_grid())
	var last := rs.current_index >= rs.holes.size() - 1 or rs.all_complete()
	var upcoming := rs.upcoming_index()
	_next_bar = null
	_next_status = null
	_next_progress_seen = false
	if upcoming >= 0 and upcoming < session.hole_defs.size():
		var nh: HoleDefinition = session.hole_defs[upcoming]
		v.add_child(_rule())
		v.add_child(UiKit.text("UP NEXT · HOLE %d" % (upcoming + 1), 18, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UiKit.text("%s · Par %d · %d yd" % [nh.display_name, nh.par, int(nh.yards)], 26, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		_next_bar = ProgressBar.new()
		_next_bar.min_value = 0.0
		_next_bar.max_value = 1.0
		_next_bar.step = 0.0
		_next_bar.show_percentage = false
		_next_bar.custom_minimum_size = Vector2(0, 10)
		_next_bar.add_theme_stylebox_override("background", UiKit.box(UiKit.C_RAISED, 3, 0))
		_next_bar.add_theme_stylebox_override("fill", UiKit.box(UiKit.C_ACCENT, 3, 0))
		_next_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(_next_bar)
		_next_status = UiKit.label("Preparing course…", 18, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(_next_status)
	_next_btn = UiKit.primary(UiKit.button("Finish round" if last else "Next hole", func() -> void:
		_remove_overlay(root)
		session.next_hole(), 90, 32))
	v.add_child(_next_btn)
	if _next_bar != null:
		_next_btn.disabled = true
		# safety net: if no loader ever reports in, never leave the button greyed
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if not _next_progress_seen:
				set_next_hole_progress(1.0))
	push_overlay(root)


## Loading progress of the upcoming hole (0..1); at 1 the "Next hole" button is enabled.
func set_next_hole_progress(p: float) -> void:
	_next_progress_seen = true
	if _next_bar != null and is_instance_valid(_next_bar):
		_next_bar.value = p
	if _next_status != null and is_instance_valid(_next_status):
		_next_status.text = "Ready" if p >= 1.0 else "Preparing course… %d%%" % int(p * 100.0)
	if p >= 1.0 and _next_btn != null and is_instance_valid(_next_btn):
		_next_btn.disabled = false


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
		session.start_round(session.hole_defs, -1, session.pool.reuse_rule, session.round_state.mulligans_allowed), 88, 30)))
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


## Inset matte scorecard over the live game (no full-screen replacement, no camera change).
func show_scorecard() -> void:
	var rs := session.round_state
	var root := Control.new()  # transparent: the game stays visible; blocks gestures behind it
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.color = Color(0.09, 0.10, 0.09, 0.30)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(scrim)
	var sm := UiKit.safe_margins(get_viewport()) if is_inside_tree() else [32.0, 32.0, 32.0, 32.0]
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", int(sm[0]))
	m.add_theme_constant_override("margin_right", int(sm[2]))
	m.add_theme_constant_override("margin_top", int(sm[1]) + 136)
	m.add_theme_constant_override("margin_bottom", int(sm[3]))
	root.add_child(m)
	var col := UiKit.vbox(GAP + 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	var panel := _plate(24, 20)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(panel)
	var v := UiKit.vbox(12)
	panel.add_child(v)
	# header: title, course, close
	var head := UiKit.hbox(12)
	var hv := UiKit.vbox(0)
	UiKit.expand(hv)
	var title := UiKit.label("Scorecard", 40)
	title.add_theme_font_override("font", UiKit.font_semi())
	hv.add_child(title)
	hv.add_child(UiKit.label(session.hole.display_name if session.hole != null else "", 22, UiKit.C_MUTED))
	head.add_child(hv)
	var close := _icon_btn("close", "", func() -> void: _remove_overlay(root), "close_scorecard", 72, 72)
	head.add_child(close)
	v.add_child(head)
	v.add_child(_rule())
	# summary: round score | strokes + holes completed (completed holes only)
	var sum := UiKit.hbox(16)
	var big := _num(RoundState.fmt_relative(rs.relative_to_par()), 56, Color("#FBF6E9"))
	big.add_theme_font_override("font", UiKit.font_semi())
	sum.add_child(big)
	var d1 := ColorRect.new()
	d1.color = UiKit.C_DIVIDER
	d1.custom_minimum_size = Vector2(2, 52)
	d1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sum.add_child(d1)
	var pen_txt := "  •  %d PEN" % rs.total_penalties() if rs.total_penalties() > 0 else ""
	var st := _num("%d STROKES  •  THRU %d%s" % [rs.total_score(), rs.holes_completed(), pen_txt], 22, UiKit.C_TEXT)
	st.add_theme_font_override("font", UiKit.font_semi())
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiKit.expand(st)
	sum.add_child(st)
	v.add_child(sum)
	v.add_child(_rule())
	# scrollable body: table + history
	var sc := ScrollContainer.new()
	sc.scroll_deadzone = 14
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var body := UiKit.vbox(6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	body.add_child(_score_row("HOLE", "PAR", "SCORE", "+/-", true, false))
	body.add_child(_rule())
	for i in rs.holes.size():
		var hs: HoleState = rs.holes[i]
		var played := hs.complete
		var in_prog := not hs.complete and hs.raw_total() > 0
		var score_txt := str(hs.score()) if played else ("(%d)" % hs.raw_total() if in_prog else "—")
		var rel_txt := RoundState.fmt_relative(hs.relative_to_par()) if played else "—"
		body.add_child(_score_row(str(i + 1), str(hs.par), score_txt, rel_txt, false, i == rs.current_index))
	body.add_child(_rule())
	body.add_child(_score_row("TOTAL", str(rs.total_par_played()), str(rs.total_score()) if rs.holes_completed() > 0 else "—",
		RoundState.fmt_relative(rs.relative_to_par()) if rs.holes_completed() > 0 else "—", true, false))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	body.add_child(gap)
	# per-hole shot history (newest hole first), nothing hidden
	if session.history.is_empty():
		body.add_child(_tag("SHOT HISTORY", 20, UiKit.C_TEXT))
		body.add_child(UiKit.text("No shots yet.", 22, UiKit.C_MUTED))
	var order: Array = []
	for i in rs.holes.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		if a == rs.current_index:
			return true
		if b == rs.current_index:
			return false
		return a > b)
	for hi in order:
		var hs2: HoleState = rs.holes[hi]
		if hs2.shots.is_empty():
			continue
		body.add_child(_tag("SHOT HISTORY  •  HOLE %d" % (hi + 1), 20, UiKit.C_TEXT))
		body.add_child(_rule())
		for r in hs2.shots:
			body.add_child(_history_row(r))
	# bottom action (outside the panel, like the reference)
	var back := UiKit.primary(Button.new())
	back.custom_minimum_size = Vector2(0, 100)
	back.set_meta("ui_id", "back_to_round")
	back.set("accessibility_name", "Back to round")
	back.pressed.connect(func() -> void: _remove_overlay(root))
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UiKit.hbox(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bl := UiKit.label("Back to round", 32, UiKit.C_ACTION_TEXT)
	bl.add_theme_font_override("font", UiKit.font_semi())
	h.add_child(bl)
	h.add_child(LineIcon.make("arrow_right", 34, UiKit.C_ACTION_TEXT))
	cc.add_child(h)
	back.add_child(cc)
	col.add_child(back)
	_scorecard_root = root
	push_overlay(root)


func _rule() -> ColorRect:
	var c := ColorRect.new()
	c.color = UiKit.C_DIVIDER
	c.custom_minimum_size = Vector2(0, 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## One aligned table row (hole / par / score / relative). The current hole gets a muted selected
## fill with a slim sage edge marker; unplayed holes show an em dash, never zero.
func _score_row(a: String, b: String, c: String, d: String, header: bool, current: bool) -> Control:
	var row := PanelContainer.new()
	var sb := _flat_style(UiKit.C_SELECTED if current else Color(0, 0, 0, 0))
	sb.content_margin_left = 16
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if current:
		sb.border_width_left = 6
		sb.border_color = UiKit.C_ACCENT
	row.add_theme_stylebox_override("panel", sb)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UiKit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vals := [a, b, c, d]
	var aligns := [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT]
	var weights := [1.1, 1.0, 1.0, 1.0]
	for k in 4:
		var l: Label
		if header:
			l = _tag(vals[k], 19, UiKit.C_TEXT, aligns[k])
		else:
			var dim: bool = vals[k] == "—" or str(vals[k]).begins_with("(")
			l = _num(vals[k], 30, UiKit.C_MUTED if dim else UiKit.C_TEXT, aligns[k])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = weights[k]
		h.add_child(l)
	row.add_child(h)
	return row


## History row: plain shot number, player + mode, right-aligned distance (HOLED / penalty tags).
func _history_row(r: ShotResult) -> Control:
	var row := UiKit.hbox(14)
	row.custom_minimum_size = Vector2(0, 84)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := _num(str(r.shot_id), 28, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	n.custom_minimum_size.x = 44
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(n)
	var mid := UiKit.vbox(0)
	UiKit.expand(mid)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UiKit.label(r.footballer_name, 26)
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # long names truncate, never cover the distance
	nm.clip_text = true
	mid.add_child(nm)
	var mode_txt := "CAPS" if r.mode == ShotTypes.Mode.CAPS else "GOALS"
	mid.add_child(_tag("%s  •  %d  •  %s" % [mode_txt, r.stat_value, ShotTypes.style_name(r.style)], 16, UiKit.C_MUTED))
	row.add_child(mid)
	var dv := UiKit.vbox(2)
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.custom_minimum_size.x = 150
	dv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var measured := r.carry_m if r.style == ShotTypes.Style.FLIGHT else r.total_m
	var dist := ("%d yd" % int(round(Units.m_to_yards(measured)))) if r.mode == ShotTypes.Mode.CAPS else ("%.1f ft" % Units.m_to_feet(measured))
	dv.add_child(_num(dist, 28, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT))
	if r.holed:
		dv.add_child(_status_tag("HOLED", UiKit.C_ACCENT))
	elif r.penalty > 0:
		dv.add_child(_status_tag("+%d PEN · %s" % [r.penalty, r.hazard], UiKit.C_WARN))
	row.add_child(dv)
	var wrap := VBoxContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(row)
	wrap.add_child(_rule())
	return wrap


## Small muted status label (e.g. HOLED in sage) right-aligned under a value.
func _status_tag(text: String, color: Color) -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_SHRINK_END
	var sb := _flat_style(Color(color, 0.22))
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(_tag(text, 15, color))
	return pc


func show_pause() -> void:
	var parts := _centered_card(560.0)
	var root: Control = parts[0]
	var v: VBoxContainer = parts[1]
	var t := UiKit.text("Paused", 38, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	t.add_theme_font_override("font", UiKit.font_semi())
	v.add_child(t)
	var resume := UiKit.primary(UiKit.button("Resume", func() -> void: _remove_overlay(root), 90, 30))
	v.add_child(resume)
	v.add_child(UiKit.button("Scorecard", func() -> void:
		_remove_overlay(root)
		show_scorecard(), 80, 26))
	v.add_child(UiKit.button("Restart round", func() -> void:
		_remove_overlay(root)
		confirm("Restart the round?", "Your score and used footballers for this round will be lost.", "Restart", func() -> void:
			close_all_overlays()
			session.start_round(session.hole_defs, -1, session.pool.reuse_rule, session.round_state.mulligans_allowed)), 80, 26))
	# developer tools stay reachable from the secondary menu
	var dev := UiKit.button("Developer panel", func() -> void:
		_remove_overlay(root)
		developer_requested.emit(), 80, 26)
	dev.add_theme_color_override("font_color", UiKit.C_DEV)
	v.add_child(dev)
	v.add_child(UiKit.button("Main menu", func() -> void:
		_remove_overlay(root)
		confirm("Leave the round?", "Progress in this round will be lost.", "Main menu", func() -> void: main_menu_requested.emit()), 80, 26))
	push_overlay(root)


## Simple confirm card for destructive actions.
func confirm(title: String, body: String, ok_text: String, on_ok: Callable) -> void:
	var parts := _centered_card(560.0)
	var root: Control = parts[0]
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.text(title, 34, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text(body, 22, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var row := UiKit.hbox(10)
	var cancel := UiKit.button("Cancel", func() -> void: _remove_overlay(root), 80, 26)
	UiKit.expand(cancel)
	row.add_child(cancel)
	var ok := UiKit.primary(UiKit.button(ok_text, func() -> void:
		_remove_overlay(root)
		on_ok.call(), 80, 26))
	UiKit.expand(ok)
	row.add_child(ok)
	v.add_child(row)
	push_overlay(root)

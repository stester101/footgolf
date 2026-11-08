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
var _spin_box: Control
var _spin: SpinControl
var _spin_label: Label
var _lie_effect_label: Label
var _traj_btn: Button
var _skip_btn: Button
var _fast_btn: Button
## True while the player holds the fast-forward button (shot animation runs faster).
var fast_forward := false
var _shot_btn: Button
var _shot_label: Label
var _shot_icon: LineIcon
# result card
var _result_card: PanelContainer
var _lie_chip: PanelContainer
var _lie_chip_label: Label
var _hole_banner: Label
var _skippable: Array = []  # reveal nodes to show at once when the player taps the card
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
var _card_dist: Label
var _turn_label: Label
var _turn_banner: Label
var _last_turn_key := ""
const PLAYER_COLS := [Color("#A0F344"), Color("#D63A44"), Color("#FFD84A"), Color("#52AAFF")]
const PLAYER_DARK_TEXT := [true, false, true, false]
var _tint_cache := {}
var _change_btn: Button
var _shot_text: Label
var _hole_strip: HBoxContainer

## Shot-screen design: broadcast-style blue banner, white shot card, dark spin strip.
const C_NAVY_BANNER := Color("#0D1B2E")
const C_BAN := Color("#1D57B0")
const C_BAN_DEEP := Color("#164A9A")
const C_BAN_TILE := Color("#E9EBEF")
const C_BAN_NAVY := Color("#1A3E7A")
const C_NAVY_DEEP := Color("#091424")
const C_GOLD := Color("#C9A96A")
const C_CREAM := Color("#F4EFE2")
const C_MUTED_NAVY := Color("#B9C2D0")
const C_BLUE := Color("#0E4BA8")
const C_BLUE_DEEP := Color("#0A3A88")
const C_BLUE_TEXT := Color("#C9D8F0")
const C_CARD := Color("#F2F5FA")
const C_CARD_DIM := Color("#E1E7F0")
const C_NAVY := Color("#0B2A5E")
const C_NAVY_MUTED := Color("#5B6A85")
const C_GO := Color("#3FE07A")
const C_GO_OFF := Color("#C5CCD8")
const C_CHIP := Color(0.07, 0.10, 0.09, 0.84)
const C_PANEL_G := Color(0.05, 0.15, 0.08, 0.86)
const C_LINE_W := Color(1, 1, 1, 0.30)
const C_LIME := Color("#A9F04E")
const C_LIME_TXT := Color("#0E2A07")
const C_ACT := Color("#1357C9")
const C_ACT_OFF := Color(0.14, 0.26, 0.45, 0.75)
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
	_lie_chip = PanelContainer.new()
	_lie_chip.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 18, 6))
	_lie_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_lie_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lie_chip.visible = false
	_lie_chip_label = UiKit.label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_lie_chip_label.add_theme_font_override("font", UiKit.font_semi())
	_lie_chip.add_child(_lie_chip_label)
	col.add_child(_lie_chip)
	_result_card = PanelContainer.new()
	_result_card.add_theme_stylebox_override("panel", UiKit.skin("glass", 8, 18, 14))
	_result_card.visible = false
	_result_box = UiKit.vbox(8)
	_result_card.add_child(_result_box)
	_result_card.gui_input.connect(_on_result_card_input)
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

func _plate(h: int = PAD, v: int = 10, _color: Color = UiKit.C_SURFACE) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.skin("glass", 6, h, v))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _tag(text: String, size: int = 18, color: Color = UiKit.C_MUTED, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(text, size, color, align)
	l.add_theme_font_override("font", UiKit.font_caps())
	return l


func _num(text: String, size: int, color: Color = UiKit.C_TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(text, size, color, align)
	l.add_theme_font_override("font", UiKit.font_num())
	return l


## Legacy helper: maps the old flat colours onto the shared button materials.
func _flat_style(color: Color, _bottom_border: Color = Color(0, 0, 0, 0), _border_w: int = 0) -> StyleBox:
	if color.is_equal_approx(UiKit.C_SELECTED):
		return UiKit.skin("btn_press", 6, 0, 0)
	if color.get_luminance() < UiKit.C_SURFACE.get_luminance() - 0.001:
		return UiKit.skin("disabled", 6, 0, 0)
	return UiKit.skin("btn", 6, 0, 0)


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


func _bordered(bg: Color, border: Color = C_LINE_W, radius: int = 4, pad: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(1 if border.a > 0.0 else 0)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	return sb


func _card_rule() -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(1, 1, 1, 0.25)
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _build_scoreboard() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.skin("header", 3, 0, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiKit.hbox(0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(row)
	# hole number on a white tile
	var block := PanelContainer.new()
	block.add_theme_stylebox_override("panel", UiKit.skin("tile", 3, 0, 0))
	block.custom_minimum_size = Vector2(104, 0)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bc := CenterContainer.new()
	bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hole_num = _num("01", 52, C_BAN_NAVY, HORIZONTAL_ALIGNMENT_CENTER)
	_hole_num.add_theme_font_override("font", UiKit.font_semi())
	bc.add_child(_hole_num)
	block.add_child(bc)
	row.add_child(block)
	var right := UiKit.vbox(0)
	UiKit.expand(right)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# name row with the round score on a white tile
	var top := UiKit.hbox(0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_m := MarginContainer.new()
	UiKit.expand(name_m)
	name_m.add_theme_constant_override("margin_left", 16)
	name_m.add_theme_constant_override("margin_top", 6)
	name_m.add_theme_constant_override("margin_bottom", 4)
	name_m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hole_name = UiKit.label("", 34, Color.WHITE)
	_hole_name.add_theme_font_override("font", UiKit.font_semi())
	_hole_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hole_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_m.add_child(_hole_name)
	top.add_child(name_m)
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", UiKit.skin("tile", 3, 0, 0))
	tile.custom_minimum_size = Vector2(112, 0)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tc := CenterContainer.new()
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_round_score = _num("E", 46, C_BAN_NAVY, HORIZONTAL_ALIGNMENT_CENTER)
	_round_score.add_theme_font_override("font", UiKit.font_semi())
	tc.add_child(_round_score)
	tile.add_child(tc)
	top.add_child(tile)
	right.add_child(top)
	_round_sub = _num("", 14, C_BAN_NAVY)
	_round_sub.visible = false
	right.add_child(_round_sub)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.6)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(rule)
	# stats row: par and yards | shot strip with the current shot ringed
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", UiKit.skin("header_deep", 3, 0, 0))
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := MarginContainer.new()
	bm.add_theme_constant_override("margin_left", 16)
	bm.add_theme_constant_override("margin_right", 14)
	bm.add_theme_constant_override("margin_top", 5)
	bm.add_theme_constant_override("margin_bottom", 6)
	bm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var brow := UiKit.hbox(14)
	brow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hole_sub = _num("", 21, Color.WHITE)
	_hole_sub.add_theme_font_override("font", UiKit.font_semi())
	brow.add_child(_hole_sub)
	var vdiv := ColorRect.new()
	vdiv.color = Color(1, 1, 1, 0.4)
	vdiv.custom_minimum_size = Vector2(2, 24)
	vdiv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brow.add_child(vdiv)
	_shot_text = _num("SHOT 1", 21, Color.WHITE)
	brow.add_child(_shot_text)
	var sp := Control.new()
	UiKit.expand(sp)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brow.add_child(sp)
	_hole_strip = UiKit.hbox(14)
	_hole_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brow.add_child(_hole_strip)
	bm.add_child(brow)
	bottom.add_child(bm)
	right.add_child(bottom)
	row.add_child(right)
	return p


## Shot numbers on this hole: the current shot is ringed.
func _refresh_hole_strip() -> void:
	if _hole_strip == null or session == null or session.hole == null:
		return
	UiKit.clear(_hole_strip)
	var cur := session.current_hole_state().raw_total() + 1
	if _shot_text != null:
		_shot_text.text = String(session.active_name()).to_upper() if session.player_count() > 1 else "SHOT %d" % cur
	var first := maxi(1, cur - 1)
	for k in 4:
		var n := first + k
		var is_cur := n == cur
		var lbl := _num(str(n), 21, Color.WHITE if is_cur else Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
		lbl.add_theme_font_override("font", UiKit.font_semi() if is_cur else UiKit.font_num())
		if is_cur:
			var ring := PanelContainer.new()
			var rsb := StyleBoxFlat.new()
			rsb.bg_color = Color(0, 0, 0, 0)
			rsb.set_corner_radius_all(18)
			rsb.set_border_width_all(2)
			rsb.border_color = Color.WHITE
			rsb.content_margin_left = 9
			rsb.content_margin_right = 9
			rsb.content_margin_top = 1
			rsb.content_margin_bottom = 1
			ring.add_theme_stylebox_override("panel", rsb)
			ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ring.add_child(lbl)
			_hole_strip.add_child(ring)
		else:
			_hole_strip.add_child(lbl)


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
	_unit_btn = UiKit.button("", func() -> void: _toggle_units(), 64, 20)
	_unit_btn.custom_minimum_size.x = HIT
	_unit_btn.add_theme_font_override("font", UiKit.font_semi())
	_unit_btn.set_meta("ui_id", "units")
	_unit_btn.tooltip_text = "Switch distances between yards and feet"
	for st in ["normal", "hover"]:
		_unit_btn.add_theme_stylebox_override(st, UiKit.skin("btn", 6, 4, 6))
	_unit_btn.add_theme_stylebox_override("pressed", UiKit.skin("btn_press", 6, 4, 6))
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
	_right_shot.add_child(_icon_btn("list", "Scorecard", show_scorecard, "card", HIT, 108))
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
	stack.add_child(_unit_btn)
	row.add_child(stack)
	return row


func _build_shot_controls() -> VBoxContainer:
	var v := UiKit.vbox(10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := UiKit.hbox(10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# --- spin panel: golf ball + trajectory. Stays visible for putts, greyed out and not selectable.
	var sp := PanelContainer.new()
	sp.add_theme_stylebox_override("panel", UiKit.skin("glass", 6, 10, 10))
	sp.mouse_filter = Control.MOUSE_FILTER_STOP
	_spin_box = sp
	var spv := UiKit.vbox(8)
	spv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spin = SpinControl.new()
	_spin.spin_changed.connect(func(val: float) -> void: session.set_spin(val))
	_spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	spv.add_child(_spin)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiKit.skin("recess", 4, 8, 5))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spin_label = _num("NO SPIN", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	pill.add_child(_spin_label)
	spv.add_child(pill)
	_lie_effect_label = _num("", 17, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	spv.add_child(_lie_effect_label)
	_traj_btn = Button.new()
	_traj_btn.custom_minimum_size = Vector2(0, 58)
	_traj_btn.focus_mode = Control.FOCUS_ALL
	_traj_btn.set_meta("ui_id", "trajectory")
	_traj_btn.set("accessibility_name", "Trajectory")
	_traj_btn.tooltip_text = "Trajectory: tap to cycle Punch, Low, Standard, High"
	_traj_btn.add_theme_stylebox_override("normal", UiKit.skin("btn", 4, 4, 4))
	_traj_btn.add_theme_stylebox_override("hover", UiKit.skin("btn_hover", 4, 4, 4))
	_traj_btn.add_theme_stylebox_override("pressed", UiKit.skin("btn_press", 4, 4, 4))
	_traj_btn.add_theme_stylebox_override("disabled", UiKit.skin("disabled", 4, 4, 4))
	_traj_btn.add_theme_font_size_override("font_size", 19)
	_traj_btn.add_theme_font_override("font", UiKit.font_semi())
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_traj_btn.add_theme_color_override(c, Color.WHITE)
	_traj_btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.4))
	_traj_btn.pressed.connect(func() -> void: session.cycle_trajectory())
	spv.add_child(_traj_btn)
	sp.add_child(spv)
	top.add_child(sp)
	# --- shot card: lie + footballer, one big action button, stat and shot-type switches
	var card := PanelContainer.new()
	UiKit.expand(card)
	card.add_theme_stylebox_override("panel", UiKit.skin("glass", 6, 14, 12))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var cv := UiKit.vbox(8)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hdr := UiKit.hbox(8)
	hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lie_label = _tag("", 20, Color.WHITE)
	_lie_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lie_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hdr.add_child(_lie_label)
	_turn_label = _tag("", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(_turn_label)
	# chosen footballer (tap to change); hidden until one is picked
	_change_btn = Button.new()
	_change_btn.custom_minimum_size = Vector2(220, 40)
	_change_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_change_btn.focus_mode = Control.FOCUS_ALL
	_change_btn.set_meta("ui_id", "change_footballer")
	_change_btn.tooltip_text = "Change footballer"
	for st in ["normal", "hover", "pressed", "disabled"]:
		_change_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	_change_btn.pressed.connect(show_picker)
	var cm := MarginContainer.new()
	cm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ch := UiKit.hbox(8)
	ch.alignment = BoxContainer.ALIGNMENT_END
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_flag = TextureRect.new()
	_player_flag.custom_minimum_size = Vector2(30, 20)
	_player_flag.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_flag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player_flag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_player_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(_player_flag)
	_player_name = UiKit.label("", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	_player_name.add_theme_font_override("font", UiKit.font_semi())
	_player_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_player_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(_player_name)
	var swap_icon := LineIcon.make("swap", 22, UiKit.C_TEXT)
	swap_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(swap_icon)
	cm.add_child(ch)
	_change_btn.add_child(cm)
	hdr.add_child(_change_btn)
	cv.add_child(hdr)
	cv.add_child(_card_rule())
	_lie_hint = UiKit.label("", 17, Color(1, 1, 1, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	_lie_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(_lie_hint)
	# one big action button: Choose footballer -> Take shot (-> Skip while the ball is moving)
	_shot_btn = Button.new()
	_player_btn = _shot_btn
	UiKit.expand(_shot_btn)
	_shot_btn.custom_minimum_size = Vector2(0, 84)
	_shot_btn.focus_mode = Control.FOCUS_ALL
	_shot_btn.set_meta("ui_id", "player_row")
	_shot_btn.set("accessibility_name", "Choose footballer")
	_shot_btn.add_theme_stylebox_override("normal", UiKit.skin("action", 6, 0, 0))
	_shot_btn.add_theme_stylebox_override("hover", UiKit.skin("action_hover", 6, 0, 0))
	_shot_btn.add_theme_stylebox_override("pressed", UiKit.skin("action_press", 6, 0, 0))
	_shot_btn.add_theme_stylebox_override("hover_pressed", UiKit.skin("action_press", 6, 0, 0))
	_shot_btn.add_theme_stylebox_override("disabled", UiKit.skin("disabled", 6, 0, 0))
	_shot_btn.pressed.connect(_on_action_pressed)
	var sc := CenterContainer.new()
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := UiKit.hbox(10)
	sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shot_label = UiKit.label("CHOOSE FOOTBALLER", 30, Color.WHITE)
	_shot_label.add_theme_font_override("font", UiKit.font_semi())
	sh.add_child(_shot_label)
	_shot_icon = LineIcon.make("arrow_right", 28, Color.WHITE)
	sh.add_child(_shot_icon)
	sc.add_child(sh)
	_shot_btn.add_child(sc)
	cv.add_child(_shot_btn)
	_fast_btn = Button.new()
	_fast_btn.text = "HOLD TO FAST-FORWARD  ▶▶"
	_fast_btn.custom_minimum_size = Vector2(0, 60)
	_fast_btn.visible = false
	_fast_btn.set_meta("ui_id", "fast_forward")
	_fast_btn.add_theme_font_size_override("font_size", 24)
	_fast_btn.button_down.connect(func() -> void: fast_forward = true)
	_fast_btn.button_up.connect(func() -> void: fast_forward = false)
	cv.add_child(_fast_btn)
	cv.add_child(_card_rule())
	var r1: Array = _seg_row("STAT", "CAPS", "mode_caps", func() -> void: session.set_mode(ShotTypes.Mode.CAPS),
		"GOALS", "mode_goals", func() -> void: session.set_mode(ShotTypes.Mode.GOALS))
	cv.add_child(r1[0])
	_caps_btn = r1[1] as Button
	_goals_btn = r1[2] as Button
	var r2: Array = _seg_row("SHOT", "APPROACH", "style_flight", func() -> void: session.set_style(ShotTypes.Style.FLIGHT),
		"PUTT", "style_roll", func() -> void: session.set_style(ShotTypes.Style.ROLL))
	cv.add_child(r2[0])
	_flight_btn = r2[1] as Button
	_roll_btn = r2[2] as Button
	card.add_child(cv)
	top.add_child(card)
	v.add_child(top)
	return v


## A labelled two-way switch row for the shot card. Returns [row, first button, second button].
func _seg_row(title: String, a_text: String, a_id: String, a_cb: Callable, b_text: String, b_id: String, b_cb: Callable) -> Array:
	var row := UiKit.hbox(8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := UiKit.label(title, 20, UiKit.C_MUTED)
	t.add_theme_font_override("font", UiKit.font_semi())
	t.custom_minimum_size = Vector2(74, 0)
	t.add_theme_font_override("font", UiKit.font_caps())
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(t)
	var g := ButtonGroup.new()
	var a := _seg_btn(a_text, g, a_id, a_cb)
	var b := _seg_btn(b_text, g, b_id, b_cb)
	row.add_child(a)
	row.add_child(b)
	return [row, a, b]


## Switch button: recessed when idle, raised lime when selected.
func _seg_btn(text: String, group: ButtonGroup, ui_id: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_font_override("font", UiKit.font_semi())
	b.add_theme_stylebox_override("normal", UiKit.skin("recess", 4, 4, 4))
	b.add_theme_stylebox_override("hover", UiKit.skin("btn", 4, 4, 4))
	b.add_theme_stylebox_override("pressed", UiKit.skin("lime", 4, 4, 4))
	b.add_theme_stylebox_override("hover_pressed", UiKit.skin("lime", 4, 4, 4))
	b.add_theme_stylebox_override("disabled", UiKit.skin("recess", 4, 4, 4))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", C_LIME_TXT)
	b.add_theme_color_override("font_hover_pressed_color", C_LIME_TXT)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.set_meta("ui_id", ui_id)
	b.set("accessibility_name", text)
	b.pressed.connect(cb)
	return b


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
	_hole_name.text = h.display_name.to_upper()
	_hole_sub.text = "PAR %d   %d YD" % [h.par, int(h.yards)]
	_refresh_hole_strip()
	_round_score.text = RoundState.fmt_relative(session.round_state.relative_to_par())
	var pen := "  +%d PEN" % hs.penalties if hs.penalties > 0 else ""
	_round_sub.text = "%d STR%s" % [hs.raw_total(), pen]
	# --- lie / shot label
	var lie := session.current_lie()
	var lie_txt := "TEE BOX" if lie == Surface.Type.TEE else Surface.name_of(lie).to_upper()
	if session.lie_override >= 0:
		lie_txt += "  •  DEV LIE"
	_lie_label.text = lie_txt
	# --- mode strip
	_caps_btn.set_pressed_no_signal(session.mode == ShotTypes.Mode.CAPS)
	_goals_btn.set_pressed_no_signal(session.mode == ShotTypes.Mode.GOALS)
	_flight_btn.set_pressed_no_signal(session.style == ShotTypes.Style.FLIGHT)
	_roll_btn.set_pressed_no_signal(session.style == ShotTypes.Style.ROLL)
	# --- footballer (header of the shot card; names always, stats only in TEST MODE)
	var fb := session.repo.get_by_id(session.selected_id) if session.selected_id != "" else null
	_change_btn.visible = fb != null
	if fb != null:
		_player_flag.texture = Flags.texture(fb.country_code)
		var nm := fb.name
		if (bool(App.online.setup.get("show_stats", false)) if App.online.started else App.settings.show_stats):
			nm += "  ·  " + (UiKit.plural(fb.caps, "cap") if session.mode == ShotTypes.Mode.CAPS else UiKit.plural(fb.goals, "goal"))
		_player_name.text = nm
	var lie_hint := Surface.effect_hint(lie, session.cfg.surfaces)
	var lie_neutral := lie_hint.contains("neutral") and lie_hint.contains("normal")
	_lie_hint.text = "" if lie_neutral else lie_hint
	_lie_hint.visible = not lie_neutral
	# --- shot state
	var moving := session.is_ball_moving()
	var aiming := session.state == ShotTypes.State.AIMING
	if session.state != ShotTypes.State.SHOT_RESULT and _reveal != null and _reveal.is_valid():
		_reveal.kill()
		_result_box.modulate.a = 1.0
	var show_result := session.state == ShotTypes.State.SHOT_RESULT
	var between := session.state == ShotTypes.State.HOLE_COMPLETE or session.state == ShotTypes.State.ROUND_COMPLETE
	_shot_controls.visible = not show_result and not overhead and not between
	_utility_row.visible = not between  # never hidden for a modal: that collapsed the layout and made the HUD jump
	_result_card.visible = show_result and not overhead
	_lie_chip.visible = _result_card.visible and _lie_chip_label.text != ""
	_map_controls.visible = overhead and session.state != ShotTypes.State.HOLE_INTRO  # the intro bar owns the bottom edge
	_right_shot.visible = not overhead
	_right_map.visible = overhead
	var flight := session.style == ShotTypes.Style.FLIGHT
	# spin ball and trajectory stay on screen for putts, dimmed and not selectable
	_spin_box.modulate = Color(1, 1, 1, 1.0 if flight else 0.4)
	_spin.mouse_filter = Control.MOUSE_FILTER_STOP if (flight and not moving) else Control.MOUSE_FILTER_IGNORE
	_traj_btn.disabled = moving or not flight
	_spin.set_spin(session.spin if flight else 0.0)
	_update_lie_effect(lie, flight)
	_apply_player_style()
	_traj_btn.text = "%s\n%d°" % [ShotTypes.trajectory_name(session.trajectory), int(round(session.launch_angle_for(session.trajectory)))]
	_spin_label.text = "NO SPIN" if (not flight or absf(session.spin) < 0.025) else "%s %d%%" % ["TOP" if session.spin > 0.0 else "BACK", int(round(absf(session.spin) * 100.0))]
	# one action button: Choose footballer -> Take shot -> Skip while the ball is moving
	var can_act := aiming and _overlays.is_empty()
	if session is OnlineSession:
		can_act = can_act and (session as OnlineSession).controls_turn()
	_fast_btn.visible = moving
	if not moving:
		fast_forward = false
	if moving:
		_shot_btn.set_meta("ui_id", "skip")
		_shot_label.text = "SKIP"
		_shot_btn.disabled = false
	elif fb == null:
		_shot_btn.set_meta("ui_id", "player_row")
		_shot_label.text = "CHOOSE FOOTBALLER"
		_shot_btn.disabled = not can_act
	else:
		_shot_btn.set_meta("ui_id", "take_shot")
		_shot_label.text = "TAKE SHOT"
		_shot_btn.disabled = not can_act
	if session is OnlineSession and not moving and not (session as OnlineSession).controls_turn():
		_shot_label.text = "WAITING"
	var shot_col := Color(1, 1, 1, 0.5) if _shot_btn.disabled else Color.WHITE
	_shot_label.add_theme_color_override("font_color", shot_col)
	_shot_icon.set_color(shot_col)
	_caps_btn.disabled = moving
	_goals_btn.disabled = moving
	_flight_btn.disabled = moving
	_roll_btn.disabled = moving
	_map_hint.text = "Tap to measure  •  Drag to pan  •  Pinch to zoom"
	var modal_hides := _modal_hides_hud()
	markers.visible = not ((show_result or between) and not overhead) and not modal_hides
	# A modal hides the HUD by fading it out; the layout underneath stays exactly where it was.
	_margin.modulate.a = 0.0 if modal_hides else 1.0
	# Only the top-most menu is visible; menus beneath it are hidden (not freed), so their state is
	# exactly as left when the top one closes, and nothing shows through a translucent modal.
	for i in _overlays.size():
		if is_instance_valid(_overlays[i]):
			_overlays[i].visible = i == _overlays.size() - 1


## Ball sits on the lie colour with the distance penalty underneath: a range, or this shot's exact value.
func _update_lie_effect(lie: int, flight: bool) -> void:
	_spin.set_lie(lie)
	var pv := session.lie_effect_preview()
	var nm := Surface.name_of(lie).to_upper()
	if not flight or int(pv["max_pct"]) <= 0:
		_lie_effect_label.text = nm
	elif App.settings.lie_effect_exact:
		_lie_effect_label.text = "%s  -%d%%" % [nm, int(pv["exact_pct"])]
	elif int(pv["min_pct"]) == int(pv["max_pct"]):
		_lie_effect_label.text = "%s  -%d%%" % [nm, int(pv["max_pct"])]
	else:
		_lie_effect_label.text = "%s  -%d to -%d%%" % [nm, int(pv["min_pct"]), int(pv["max_pct"])]


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


## Player colours: P1 green, P2 red, P3 yellow, P4 blue. Tints the spin markers and the selected
## stat / shot buttons, labels whose shot it is, and flashes a short "your shot" message on a turn change.
func _apply_player_style() -> void:
	var multi := session.player_count() > 1
	var i := clampi(session.turn, 0, 3) if multi else 0
	var col: Color = PLAYER_COLS[i]
	_spin.accent = col
	_spin.queue_redraw()
	if not _tint_cache.has(i):
		var k: UiSkin = UiKit.skin("lime", 4, 4, 4).duplicate()
		k.top = col.lightened(0.25 if i != 1 else 0.1)
		k.bottom = col.darkened(0.12)
		_tint_cache[i] = k
	var txt := Color("#0E2A07") if PLAYER_DARK_TEXT[i] else Color.WHITE
	for b in [_caps_btn, _goals_btn, _flight_btn, _roll_btn]:
		b.add_theme_stylebox_override("pressed", _tint_cache[i])
		b.add_theme_stylebox_override("hover_pressed", _tint_cache[i])
		b.add_theme_color_override("font_pressed_color", txt)
		b.add_theme_color_override("font_hover_pressed_color", txt)
	_turn_label.text = String(session.active_name()).to_upper() if multi else ""
	_turn_label.add_theme_color_override("font_color", col)
	if multi and session.state == ShotTypes.State.AIMING:
		var key := "%d:%d:%d" % [session.turn, session.round_state.current_index, session.shot_counter]
		if key != _last_turn_key:
			_last_turn_key = key
			_flash_turn(String(session.active_name()).to_upper() + (" · YOUR SHOT" if not (session is OnlineSession) or (session as OnlineSession).controls_turn() else " · TO PLAY"), col)


func _flash_turn(text: String, col: Color) -> void:
	if _turn_banner == null:
		_turn_banner = UiKit.label("", 54, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		_turn_banner.add_theme_font_override("font", UiKit.font_semi())
		_turn_banner.add_theme_constant_override("outline_size", 10)
		_turn_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		_turn_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_turn_banner.anchor_left = 0.0
		_turn_banner.anchor_right = 1.0
		_turn_banner.offset_left = 0.0
		_turn_banner.offset_right = 0.0
		_turn_banner.offset_top = 360.0
		add_child(_turn_banner)
	_turn_banner.text = text
	_turn_banner.add_theme_color_override("font_color", col)
	_turn_banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_turn_banner, "modulate:a", 1.0, 0.3)
	tw.tween_interval(0.9)
	tw.tween_property(_turn_banner, "modulate:a", 0.0, 0.5)


func _on_action_pressed() -> void:
	if session.is_ball_moving():
		session.skip_motion()
		return
	_on_take_shot()


func _on_take_shot() -> void:
	if not _overlays.is_empty():
		return
	if session.selected_id == "" and session.state == ShotTypes.State.AIMING:
		show_picker()
		return
	session.take_shot()
	refresh()


# ------------------------------------------------------------------ overlays

## True while a menu or modal is open that should cover the HUD. Overlays marked "keep_hud"
## (hole intro, hole complete, round complete) sit under the banner and leave it visible.
func _modal_hides_hud() -> bool:
	for o in _overlays:
		if is_instance_valid(o) and not bool(o.get_meta("keep_hud", false)):
			return true
	return false


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
	p.show_stats = (bool(App.online.setup.get("show_stats", false)) if App.online.started else App.settings.show_stats)
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


## Hole intro: a slim bar at the bottom so the whole hole stays visible in the bird's-eye view;
## "Tee off" glides the camera down to the tee (the camera rig eases between modes).
func show_hole_intro() -> void:
	var h := session.hole
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_meta("keep_hud", true)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	m.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for side in ["left", "right", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 24)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(m)
	var p := UiKit.panel(UiKit.C_PANEL_SOLID)
	m.add_child(p)
	var row := UiKit.hbox(16)
	p.add_child(row)
	var info := UiKit.vbox(2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UiKit.label("HOLE %d OF %d" % [session.round_state.current_index + 1, session.round_state.holes.size()], 20, UiKit.C_MUTED))
	var nm := UiKit.label(h.display_name, 34, UiKit.C_TEXT)
	nm.add_theme_font_override("font", UiKit.font_semi())
	info.add_child(nm)
	info.add_child(UiKit.label("Par %d · %d yd" % [h.par, int(h.yards)], 24, UiKit.C_TEXT))
	row.add_child(info)
	var go := UiKit.primary(UiKit.button("Waiting for host" if session is OnlineSession and App.online.seat != 0 else "Tee off", func() -> void:
		if session is OnlineSession and App.online.seat != 0: return
		_remove_overlay(root)
		session.begin_play(), 90, 32))
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(go)
	push_overlay(root)


func _stat_cell(caption: String, value: String) -> VBoxContainer:
	var v := UiKit.vbox(0)
	UiKit.expand(v)
	v.add_child(UiKit.label(value, 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label(caption, 16, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	return v


## Shot summary card with an animated stat reveal (only shown after the ball has stopped).
func _on_shot_resolved(r: ShotResult) -> void:
	if App.settings.vibration:
		Input.vibrate_handheld(90 if r.holed else 35)
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
	var hs := session.current_hole_state()
	var holed_done := r.holed and hs.complete
	var big: Label
	if holed_done:
		# State 3: the golf result for the finished hole (strokes relative to par, penalties included)
		big = UiKit.label(_score_name(hs).trim_suffix("!"), 56, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		big.add_theme_font_override("font", UiKit.font_semi())
	else:
		big = UiKit.label("0 %s" % unit, 46, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_result_box.add_child(big)
	var sub := UiKit.label("", 20, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_result_base_label = sub
	_result_base_m = r.base_distance_m
	_result_base_mode = r.mode
	_result_base_style = r.style
	_refresh_result_distances()
	if holed_done:
		sub.text = "%d %s · %s" % [hs.score(), "stroke" if hs.score() == 1 else "strokes", RoundState.fmt_relative(hs.relative_to_par())]
		_result_base_label = null
	_result_box.add_child(sub)
	var grid := UiKit.hbox(6)
	if holed_done:
		grid.add_child(_stat_cell("%s" % unit, "%d" % r.stat_value))
		grid.add_child(_divider())
		grid.add_child(_distance_stat_cell("LAST SHOT", r.total_m))
	elif r.style == ShotTypes.Style.FLIGHT:
		grid.add_child(_distance_stat_cell("CARRY", r.carry_m))
		grid.add_child(_divider())
		grid.add_child(_distance_stat_cell("ROLL", r.roll_m))
		grid.add_child(_divider())
		grid.add_child(_distance_stat_cell("TOTAL", r.total_m))
		grid.add_child(_divider())
		grid.add_child(_distance_stat_cell("TO PIN", r.remaining_m))
	else:
		grid.add_child(_distance_stat_cell("TRAVEL", r.total_m))
		grid.add_child(_divider())
		grid.add_child(_stat_cell("LIE", Surface.name_of(r.final_lie)))
		grid.add_child(_divider())
		grid.add_child(_distance_stat_cell("TO PIN", r.remaining_m))
	_result_box.add_child(grid)
	var extra: Array[String] = []
	if r.lie_factor < 0.999:
		extra.append("%s lie cost %d%%" % [Surface.name_of(r.start_lie), int(round((1.0 - r.lie_factor) * 100.0))])
	if not r.collisions.is_empty():
		extra.append("Hit a tree")
	if r.wind_speed_mps > 0.1 and r.style == ShotTypes.Style.FLIGHT:
		extra.append("Wind %d mph" % int(round(r.wind_speed_mps * Units.MPS_TO_MPH)))
	if r.style == ShotTypes.Style.FLIGHT and absf(r.spin) >= 0.025:
		extra.append(ShotResult.spin_label(r.spin).capitalize())
	if not holed_done:
		extra.append("Strokes %d · par %d" % [hs.raw_total(), hs.par])
	var extra_l := UiKit.text(" · ".join(extra), 19, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_result_box.add_child(extra_l)
	# contextual chip above the panel: the real final lie, or the hazard that was hit
	var chip := ""
	if r.penalty > 0:
		chip = "WATER · +%d PENALTY" % r.penalty if r.hazard == "WATER" else "OUT OF BOUNDS · +%d PENALTY" % r.penalty
	elif holed_done:
		chip = "IN THE HOLE"
	else:
		chip = _lie_phrase(r.final_lie)
	_lie_chip_label.text = chip
	_lie_chip_label.add_theme_color_override("font_color", UiKit.C_WARN if r.penalty > 0 else Color.WHITE)
	var banner: Label = null
	if r.penalty > 0:
		banner = UiKit.text("Ball dropped safely", 22, UiKit.C_WARN, HORIZONTAL_ALIGNMENT_CENTER)
		_result_box.add_child(banner)
	var details := UiKit.text(r.diagnostic_text(), 16, UiKit.C_MUTED)
	details.visible = false
	var row := UiKit.hbox(10)
	row.add_child(UiKit.button("Details", func() -> void: details.visible = not details.visible, 76, 22))
	if session.can_mulligan():
		var left := session.round_state.mulligans_remaining()
		var retry := UiKit.button("Mulligan%s" % ("" if left < 0 else " · %d" % left),
			func() -> void: session.use_mulligan(), 76, 22)
		row.add_child(retry)
	var cont := UiKit.button("Continue", func() -> void: session.acknowledge_result(), 76, 30)
	if holed_done:
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			cont.add_theme_stylebox_override(st, UiKit.skin("lime" if st != "pressed" and st != "hover_pressed" else "lime", 6, 16, 10))
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			cont.add_theme_color_override(c, Color("#0E2A07"))
	else:
		UiKit.primary(cont)
	UiKit.expand(cont)
	row.add_child(cont)
	_result_box.add_child(details)
	_result_box.add_child(row)
	refresh()
	# --- reveal animation: count the stat up, then fade the breakdown in (tap the card to skip it)
	var later: Array = [sub, grid, extra_l, banner]
	for n in later:
		if n != null:
			(n as Control).modulate.a = 0.0
	_skippable = later.duplicate()
	_result_box.modulate.a = 0.0
	var tw := create_tween()
	_reveal = tw
	tw.tween_property(_result_box, "modulate:a", 1.0, 0.2)
	if holed_done:
		_show_hole_banner()
		big.pivot_offset = big.size * 0.5
		big.scale = Vector2(0.6, 0.6)
		big.modulate.a = 0.0
		tw.tween_interval(0.45)
		tw.tween_property(big, "modulate:a", 1.0, 0.2)
		tw.parallel().tween_property(big, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_skippable.append(big)
	else:
		var target := r.stat_value
		tw.tween_method(func(v: float) -> void:
			if is_instance_valid(big):
				big.text = "%d %s" % [int(round(v)), unit], 0.0, float(target), clampf(0.25 + target * 0.004, 0.3, 1.1)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for n in later:
		if n != null:
			tw.tween_property(n, "modulate:a", 1.0, 0.18)


func _divider() -> VSeparator:
	var d := VSeparator.new()
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.modulate = Color(1, 1, 1, 0.35)
	return d


func _lie_phrase(lie: int) -> String:
	match lie:
		Surface.Type.FAIRWAY: return "ON THE FAIRWAY"
		Surface.Type.GREEN: return "ON THE GREEN"
		Surface.Type.ROUGH: return "IN THE ROUGH"
		Surface.Type.BUNKER: return "IN THE BUNKER"
		Surface.Type.FRINGE: return "ON THE FRINGE"
		Surface.Type.TEE: return "ON THE TEE"
		_: return Surface.name_of(lie).to_upper()


## Short, non-blocking "HOLE COMPLETE" banner in the play area; fades itself out. Runs once per hole-out.
func _show_hole_banner() -> void:
	if _hole_banner == null or not is_instance_valid(_hole_banner):
		_hole_banner = UiKit.label("HOLE COMPLETE", 44, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		_hole_banner.add_theme_font_override("font", UiKit.font_semi())
		_hole_banner.add_theme_constant_override("outline_size", 10)
		_hole_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		_hole_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hole_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_hole_banner.anchor_left = 0.0
		_hole_banner.anchor_right = 1.0
		_hole_banner.offset_left = 0.0
		_hole_banner.offset_right = 0.0
		_hole_banner.offset_top = 340.0
		add_child(_hole_banner)
	_hole_banner.modulate.a = 0.0
	_hole_banner.visible = true
	var bt := create_tween()
	bt.tween_interval(0.25)
	bt.tween_property(_hole_banner, "modulate:a", 1.0, 0.2)
	bt.tween_interval(0.8)
	bt.tween_property(_hole_banner, "modulate:a", 0.0, 0.4)
	bt.tween_callback(func() -> void: _hole_banner.visible = false)


func _on_result_card_input(event: InputEvent) -> void:
	var tap := (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not tap or _reveal == null or not _reveal.is_valid() or not _reveal.is_running():
		return
	_reveal.kill()
	_result_box.modulate.a = 1.0
	for n in _skippable:
		if n != null and is_instance_valid(n):
			(n as Control).modulate.a = 1.0
			(n as Control).scale = Vector2.ONE
	if _hole_banner != null and is_instance_valid(_hole_banner):
		_hole_banner.visible = false


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
	return String(names.get(hs.relative_to_par(), RoundState.fmt_relative(hs.relative_to_par()) if hs.relative_to_par() > 0 else "%d UNDER PAR" % -hs.relative_to_par()))


func _strip_cell(caption: String, value: String) -> VBoxContainer:
	var v := UiKit.vbox(0)
	v.custom_minimum_size = Vector2(78, 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_num(value, 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_tag(caption, 14, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	return v


## Hole complete: summary strip, scorecard board (only the holes in this round), and the
## "up next" tile with loading progress and the Next hole button pinned at the bottom.
func _on_hole_completed(hs: HoleState) -> void:
	var rs := session.round_state
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_meta("keep_hud", true)
	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.06, 0.12, 0.40)
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
	var col := UiKit.vbox(GAP + 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	# 1. summary strip: kicker + headline, four stats
	var longest := 0.0
	for r in hs.shots:
		if r is ShotResult:
			longest = maxf(longest, (r as ShotResult).total_m)
	var strip := _plate(18, 12)
	var sr := UiKit.hbox(8)
	sr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := UiKit.vbox(0)
	UiKit.expand(left)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_tag("HOLE %d COMPLETE" % (rs.current_index + 1), 17, UiKit.C_CYAN))
	var name_txt := _score_name(hs).to_upper()
	var headline := UiKit.label(name_txt, 46 if name_txt.length() <= 7 else 34, Color.WHITE)
	headline.add_theme_font_override("font", UiKit.font_semi())
	headline.add_theme_color_override("font_shadow_color", Color(0.45, 0.80, 1.0, 0.40))
	headline.add_theme_constant_override("shadow_outline_size", 8)
	headline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	left.add_child(headline)
	sr.add_child(left)
	sr.add_child(_strip_cell("SHOTS", str(hs.strokes)))
	sr.add_child(_strip_cell("PENALTY", str(hs.penalties)))
	sr.add_child(_strip_cell("LONGEST", Units.fmt_yards(longest)))
	sr.add_child(_strip_cell("ROUND", RoundState.fmt_relative(rs.relative_to_par())))
	strip.add_child(sr)
	col.add_child(strip)
	# 2. scorecard board
	var board_panel := _plate(14, 14)
	board_panel.add_child(_scorecard_board())
	col.add_child(board_panel)
	if session.player_count() > 1:
		col.add_child(_standings_panel())
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	# 3. up next + loading + button, pinned at the bottom for the thumb
	var last := rs.current_index >= rs.holes.size() - 1 or rs.all_complete()
	var upcoming := rs.upcoming_index()
	_next_bar = null
	_next_status = null
	_next_progress_seen = false
	var up := _plate(18, 14)
	var uv := UiKit.vbox(10)
	uv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if upcoming >= 0 and upcoming < session.hole_defs.size():
		var nh: HoleDefinition = session.hole_defs[upcoming]
		var ur := UiKit.hbox(14)
		ur.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tile := PanelContainer.new()
		tile.add_theme_stylebox_override("panel", UiKit.skin("header", 6, 0, 0))
		tile.custom_minimum_size = Vector2(76, 76)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tc := CenterContainer.new()
		tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tc.add_child(_num("%02d" % (upcoming + 1), 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
		tile.add_child(tc)
		ur.add_child(tile)
		var uinfo := UiKit.vbox(0)
		UiKit.expand(uinfo)
		uinfo.alignment = BoxContainer.ALIGNMENT_CENTER
		uinfo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		uinfo.add_child(_tag("UP NEXT · HOLE %d" % (upcoming + 1), 17, UiKit.C_CYAN))
		var nn := UiKit.label(nh.display_name, 32, Color.WHITE)
		nn.add_theme_font_override("font", UiKit.font_semi())
		nn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		uinfo.add_child(nn)
		uinfo.add_child(_num("Par %d · %d yd" % [nh.par, int(nh.yards)], 21, UiKit.C_MUTED))
		ur.add_child(uinfo)
		uv.add_child(ur)
		_next_bar = ProgressBar.new()
		_next_bar.min_value = 0.0
		_next_bar.max_value = 1.0
		_next_bar.step = 0.0
		_next_bar.show_percentage = false
		_next_bar.custom_minimum_size = Vector2(0, 10)
		_next_bar.add_theme_stylebox_override("background", UiKit.box(Color(1, 1, 1, 0.14), 4, 0))
		_next_bar.add_theme_stylebox_override("fill", UiKit.box(UiKit.C_CYAN, 4, 0))
		_next_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		uv.add_child(_next_bar)
		_next_status = UiKit.label("Preparing course…", 18, UiKit.C_MUTED)
		uv.add_child(_next_status)
	_next_btn = UiKit.primary(UiKit.button("WAITING FOR HOST" if session is OnlineSession and App.online.seat != 0 else ("FINISH ROUND" if last else "NEXT HOLE"), func() -> void:
		if session is OnlineSession and App.online.seat != 0: return
		_remove_overlay(root)
		session.next_hole(), 90, 32))
	_next_btn.add_theme_font_override("font", UiKit.font_caps())
	uv.add_child(_next_btn)
	if _next_bar != null:
		_next_btn.disabled = true
		# safety net: if no loader ever reports in, never leave the button greyed
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if not _next_progress_seen:
				set_next_hole_progress(1.0))
	up.add_child(uv)
	col.add_child(up)
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
	var rs := session.round_state
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.set_meta("keep_hud", true)
	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.06, 0.12, 0.40)
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
	var col := UiKit.vbox(GAP + 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	# summary strip: ROUND COMPLETE + final score, with par / holes / footballers
	var strip := _plate(18, 12)
	var sr := UiKit.hbox(8)
	sr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := UiKit.vbox(0)
	UiKit.expand(left)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_tag("ROUND COMPLETE", 17, UiKit.C_CYAN))
	var headline := UiKit.label("%d  (%s)" % [rs.total_score(), RoundState.fmt_relative(rs.relative_to_par())], 46, Color.WHITE)
	headline.add_theme_font_override("font", UiKit.font_semi())
	left.add_child(headline)
	sr.add_child(left)
	sr.add_child(_strip_cell("PAR", str(rs.total_par())))
	sr.add_child(_strip_cell("HOLES", str(rs.holes.size())))
	sr.add_child(_strip_cell("PLAYERS", str(session.pool.used_count())))
	strip.add_child(sr)
	col.add_child(strip)
	var board_panel := _plate(14, 14)
	board_panel.add_child(_scorecard_board())
	col.add_child(board_panel)
	if session.player_count() > 1:
		col.add_child(_standings_panel())
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)
	var bottom := _plate(18, 14)
	var bv := UiKit.vbox(10)
	bv.add_child(UiKit.primary(UiKit.button("PLAY AGAIN", func() -> void:
		_remove_overlay(root)
		session.start_round(session.hole_defs, -1, session.pool.reuse_rule, session.round_state.mulligans_allowed, session.player_count()), 90, 32)))
	bv.add_child(UiKit.button("Main menu", func() -> void: main_menu_requested.emit(), 76, 26))
	bottom.add_child(bv)
	col.add_child(bottom)
	push_overlay(root)


func _scorecard_grid() -> Control:
	return _scorecard_board()


const BOARD_ROW_HOLES := 9


## Broadcast-style scorecard: one block per nine holes, only the holes in this round. Under par
## is ringed (cyan circle), over par boxed (sand square), the hole being played is highlighted.
func _scorecard_board() -> VBoxContainer:
	var rs := session.round_state
	var board := UiKit.vbox(12)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var start := 0
	while start < rs.holes.size():
		var end := mini(start + BOARD_ROW_HOLES, rs.holes.size())
		board.add_child(_board_chunk(start, end))
		start = end
	var legend := UiKit.hbox(10)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	legend.add_child(_shape_swatch(true, UiKit.C_CYAN))
	legend.add_child(_board_label("UNDER PAR", 15))
	legend.add_child(_shape_swatch(false, UiKit.C_WARN))
	legend.add_child(_board_label("OVER PAR", 15))
	board.add_child(legend)
	var total := _board_label("ROUND  ·  PAR %d  ·  SCORE %d  ·  %s  ·  PEN %d" % [rs.total_par(), rs.total_score(),
		RoundState.fmt_relative(rs.relative_to_par()), rs.total_penalties()], 16, UiKit.C_TEXT)
	board.add_child(total)
	return board


func _board_label(text: String, size: int = 17, color: Color = UiKit.C_MUTED, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(text, size, color, align)
	l.add_theme_font_override("font", UiKit.font_caps())
	return l


func _board_value(text: String, size: int = 22, color: Color = UiKit.C_TEXT, bold: bool = false) -> Label:
	var l := UiKit.label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", UiKit.font_semi() if bold else UiKit.font_num())
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _board_head(text: String, current: bool, first: bool) -> Control:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UiKit.skin("lime" if current else "header", 3, 4, 7))
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if first:
		pc.custom_minimum_size.x = 88
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(text, 18, C_LIME_TXT if current else Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT if first else HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", UiKit.font_caps() if first else UiKit.font_semi())
	pc.add_child(l)
	return pc


func _board_score(hs: HoleState, current: bool) -> Control:
	var played := hs.complete or hs.raw_total() > 0
	if not played:
		return _board_value("–", 22, UiKit.C_MUTED)
	var rel := hs.relative_to_par()
	var l := _board_value(str(hs.score()), 22, UiKit.C_TEXT, true)
	if rel == 0 and not current:
		return l
	var cc := CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()  # own instance: the shared skins must never be mutated
	sb.bg_color = Color(UiKit.C_CYAN, 0.22) if current else Color(0, 0, 0, 0)
	sb.set_border_width_all(2 if rel != 0 else 0)
	sb.border_color = UiKit.C_CYAN if rel < 0 else UiKit.C_WARN
	sb.set_corner_radius_all(22 if rel < 0 else 5)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(40, 40)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.add_child(l)
	cc.add_child(pc)
	return cc


func _shape_swatch(circle: bool, color: Color) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(2)
	sb.border_color = color
	sb.set_corner_radius_all(11 if circle else 3)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(22, 22)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pc


func _board_chunk(start: int, end: int) -> Control:
	var rs := session.round_state
	var g := GridContainer.new()
	g.columns = (end - start) + 2
	g.add_theme_constant_override("h_separation", 2)
	g.add_theme_constant_override("v_separation", 8)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var par_sum := 0
	var score_sum := 0
	var rel_sum := 0
	var pen_sum := 0
	var any_played := false
	for i in range(start, end):
		var hs: HoleState = rs.holes[i]
		par_sum += hs.par
		pen_sum += hs.penalties
		if hs.complete or hs.raw_total() > 0:
			any_played = true
			score_sum += hs.score()
			rel_sum += hs.relative_to_par()
	g.add_child(_board_head("HOLE", false, true))
	for i in range(start, end):
		g.add_child(_board_head(str(i + 1), i == rs.current_index, false))
	g.add_child(_board_head("TOT", false, false))
	g.add_child(_board_label("PAR", 16))
	for i in range(start, end):
		g.add_child(_board_value(str((rs.holes[i] as HoleState).par)))
	g.add_child(_board_value(str(par_sum), 22, UiKit.C_TEXT, true))
	g.add_child(_board_label("SCORE", 16))
	for i in range(start, end):
		g.add_child(_board_score(rs.holes[i] as HoleState, i == rs.current_index))
	g.add_child(_board_value(str(score_sum) if any_played else "–", 22, UiKit.C_TEXT, true))
	g.add_child(_board_label("+/−", 16))
	for i in range(start, end):
		var hs2: HoleState = rs.holes[i]
		var played := hs2.complete or hs2.raw_total() > 0
		var rel := hs2.relative_to_par()
		var col := UiKit.C_MUTED if not played else (UiKit.C_CYAN if rel < 0 else (UiKit.C_WARN if rel > 0 else UiKit.C_TEXT))
		g.add_child(_board_value(RoundState.fmt_relative(rel) if played else "–", 21, col))
	g.add_child(_board_value(RoundState.fmt_relative(rel_sum) if any_played else "–", 21, UiKit.C_TEXT, true))
	g.add_child(_board_label("PEN", 16))
	for i in range(start, end):
		var pen: int = (rs.holes[i] as HoleState).penalties
		g.add_child(_board_value(str(pen) if pen > 0 else "–", 21, UiKit.C_WARN if pen > 0 else UiKit.C_MUTED))
	g.add_child(_board_value(str(pen_sum) if pen_sum > 0 else "–", 21, UiKit.C_TEXT, true))
	return g


const SC_LINE := Color(0.72, 0.88, 1.0, 0.22)
const SC_MUTED := Color(0.72, 0.82, 0.95, 0.55)
const SC_ROW_H := 58


func _sc_cell(text: String, size: int, color: Color, fill: Color, header: bool = false) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()  # own instance: the shared skins must never be mutated
	sb.bg_color = fill
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = SC_LINE
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.custom_minimum_size = Vector2(0, SC_ROW_H)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _num(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", UiKit.font_caps() if header else UiKit.font_semi())
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc.add_child(l)
	return pc


## Hole / Par / Score / To par. The hole in play shows its live strokes in muted text (no
## brackets); completed holes show the final score in white; future holes show dashes.
func _scorecard_table() -> Control:
	var rs := session.round_state
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 0)
	g.add_theme_constant_override("v_separation", 0)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in ["HOLE", "PAR", "SCORE", "TO PAR"]:
		g.add_child(_sc_cell(t, 20, Color.WHITE, Color(0.16, 0.36, 0.66, 0.55), true))
	for i in rs.holes.size():
		var hs: HoleState = rs.holes[i]
		var current := i == rs.current_index
		var fill := Color(UiKit.C_CYAN, 0.16) if current else Color(0, 0, 0, 0)
		var score_txt := "—"
		var rel_txt := "—"
		var col := Color(SC_MUTED, 0.5)
		if hs.complete:
			score_txt = str(hs.score())
			rel_txt = RoundState.fmt_relative(hs.relative_to_par())
			col = Color.WHITE
		elif current and hs.raw_total() > 0:
			score_txt = str(hs.raw_total())
			rel_txt = RoundState.fmt_relative(hs.raw_total() - hs.par)
			col = SC_MUTED
		g.add_child(_sc_cell(str(i + 1), 30, Color.WHITE, fill))
		g.add_child(_sc_cell(str(hs.par), 30, Color.WHITE, fill))
		g.add_child(_sc_cell(score_txt, 30, col, fill))
		g.add_child(_sc_cell(rel_txt, 30, col, fill))
	var any_done := rs.holes_completed() > 0
	var tot_fill := Color(1, 1, 1, 0.07)
	g.add_child(_sc_cell("TOTAL", 20, Color.WHITE, tot_fill, true))
	g.add_child(_sc_cell(str(rs.total_par_played()), 30, Color.WHITE, tot_fill))
	g.add_child(_sc_cell(str(rs.total_score()) if any_done else "—", 30, Color.WHITE if any_done else Color(SC_MUTED, 0.5), tot_fill))
	g.add_child(_sc_cell(RoundState.fmt_relative(rs.relative_to_par()) if any_done else "—", 30, Color.WHITE if any_done else Color(SC_MUTED, 0.5), tot_fill))
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiKit.skin("recess", 6, 0, 0))
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(g)
	return frame


## Near-full-screen modal: fixed header and Back button, a table that scrolls on its own (many
## holes) and a shot history that scrolls on its own. The HUD behind it is hidden by refresh().
func show_scorecard() -> void:
	var rs := session.round_state
	var root := UiKit.overlay(0.58)  # dims the course; blocks gestures behind it
	var sm := UiKit.safe_margins(get_viewport()) if is_inside_tree() else [32.0, 32.0, 32.0, 32.0]
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", int(sm[0]))
	m.add_theme_constant_override("margin_right", int(sm[2]))
	m.add_theme_constant_override("margin_top", int(sm[1]) + 8)
	m.add_theme_constant_override("margin_bottom", int(sm[3]) + 8)
	root.add_child(m)
	var panel := _plate(18, 16)
	m.add_child(panel)
	var v := UiKit.vbox(12)
	panel.add_child(v)
	# header (fixed)
	var head := UiKit.hbox(14)
	var tro := LineIcon.make("trophy", 56, Color("#E9F4FF"))
	tro.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tro)
	var hv := UiKit.vbox(0)
	UiKit.expand(hv)
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UiKit.label("Scorecard", 40, Color.WHITE)
	title.add_theme_font_override("font", UiKit.font_semi())
	hv.add_child(title)
	hv.add_child(UiKit.label(session.hole.display_name if session.hole != null else "", 22, UiKit.C_CYAN))
	head.add_child(hv)
	head.add_child(_icon_btn("close", "", func() -> void: _remove_overlay(root), "close_scorecard", 72, 72))
	v.add_child(head)
	# table (scrolls on its own when the round is long)
	var tsc := ScrollContainer.new()
	tsc.scroll_deadzone = 14
	tsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vh := get_viewport_rect().size.y
	var table_h := float((rs.holes.size() + 2) * SC_ROW_H + 2)
	tsc.custom_minimum_size = Vector2(0, minf(table_h, vh * 0.42))
	var table := _scorecard_table()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tsc.add_child(table)
	v.add_child(tsc)
	# shot history (scrolls on its own), current hole first then newest holes
	var hsc := ScrollContainer.new()
	hsc.scroll_deadzone = 14
	hsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(hsc)
	var body := UiKit.vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsc.add_child(body)
	if session.history.is_empty():
		body.add_child(_history_title("Shot History"))
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
		body.add_child(_history_title("Shot History  •  Hole %d" % (hi + 1)))
		for r in hs2.shots:
			body.add_child(_history_row(r))
	# bottom action (fixed)
	var back := UiKit.primary(Button.new())
	back.custom_minimum_size = Vector2(0, 90)
	back.set_meta("ui_id", "back_to_round")
	back.set("accessibility_name", "Back to round")
	back.pressed.connect(func() -> void: _remove_overlay(root))
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UiKit.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(LineIcon.make("chevron_left", 34, Color.WHITE))
	var bl := UiKit.label("Back to round", 32, Color.WHITE)
	bl.add_theme_font_override("font", UiKit.font_semi())
	h.add_child(bl)
	cc.add_child(h)
	back.add_child(cc)
	v.add_child(back)
	_scorecard_root = root
	push_overlay(root)


## Pass-and-play standings: each player's total strokes and score to par (completed holes), leader first.
func _standings_panel() -> Control:
	var pc := _plate(16, 10)
	var v := UiKit.vbox(4)
	v.add_child(_tag("STANDINGS", 16, UiKit.C_CYAN))
	var order: Array = []
	for i in session.player_count():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return session.slot_round_state(a).relative_to_par() < session.slot_round_state(b).relative_to_par())
	for i in order:
		var rs := session.slot_round_state(i)
		var row := UiKit.hbox(10)
		var nm := UiKit.label(String(session.player_names[i]) + ("  •  to play" if i == session.turn and session.state != ShotTypes.State.HOLE_COMPLETE and session.state != ShotTypes.State.ROUND_COMPLETE else ""), 22, Color.WHITE)
		nm.add_theme_font_override("font", UiKit.font_semi())
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		row.add_child(_num("%d  (%s)" % [rs.total_score(), RoundState.fmt_relative(rs.relative_to_par())], 22, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(row)
	pc.add_child(v)
	return pc


func _history_title(text: String) -> Control:
	var h := UiKit.hbox(12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fi := LineIcon.make("flag", 34, Color("#E9F4FF"))
	fi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(fi)
	var l := UiKit.label(text, 28, Color.WHITE)
	l.add_theme_font_override("font", UiKit.font_semi())
	h.add_child(l)
	return h


func _rule() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(0.72, 0.88, 1.0, 0.22)
	c.custom_minimum_size = Vector2(0, 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## One aligned table row (hole / par / score / relative). The current hole gets a muted selected
## fill with a slim sage edge marker; unplayed holes show an em dash, never zero.
func _score_row(a: String, b: String, c: String, d: String, header: bool, current: bool) -> Control:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()  # own instance: the shared skins must never be mutated
	sb.bg_color = Color(0.18, 0.36, 0.62, 0.55) if current else Color(0, 0, 0, 0)
	sb.content_margin_left = 16
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if current:
		sb.border_width_left = 6
		sb.border_color = UiKit.C_CYAN
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
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiKit.skin("btn", 6, 16, 10))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := UiKit.hbox(16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := _num(str(r.shot_id), 34, Color(0.62, 0.85, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	n.custom_minimum_size.x = 46
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(n)
	var mid := UiKit.vbox(0)
	UiKit.expand(mid)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := UiKit.label(r.footballer_name, 28, Color.WHITE)
	nm.add_theme_font_override("font", UiKit.font_semi())
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # long names truncate, never cover the distance
	nm.clip_text = true
	mid.add_child(nm)
	var mode_txt := "CAPS" if r.mode == ShotTypes.Mode.CAPS else "GOALS"
	mid.add_child(_tag("%s  •  %d  •  %s" % [mode_txt, r.stat_value, ShotTypes.style_name(r.style)], 17, Color(0.62, 0.85, 1.0, 0.9)))
	row.add_child(mid)
	var dv := UiKit.vbox(2)
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	dv.custom_minimum_size.x = 150
	dv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var measured := r.carry_m if r.style == ShotTypes.Style.FLIGHT else r.total_m
	var dist := ("%d yd" % int(round(Units.m_to_yards(measured)))) if r.mode == ShotTypes.Mode.CAPS else ("%.1f ft" % Units.m_to_feet(measured))
	var dl := _num(dist, 30, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	dl.add_theme_font_override("font", UiKit.font_semi())
	dv.add_child(dl)
	if r.holed:
		dv.add_child(_status_tag("HOLED", UiKit.C_ACCENT))
	elif r.penalty > 0:
		dv.add_child(_status_tag("+%d PEN · %s" % [r.penalty, r.hazard], UiKit.C_WARN))
	row.add_child(dv)
	card.add_child(row)
	return card


## Small muted status label (e.g. HOLED in sage) right-aligned under a value.
func _status_tag(text: String, color: Color) -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_SHRINK_END
	var sb := StyleBoxFlat.new()  # own instance: the shared skins must never be mutated
	sb.bg_color = Color(color, 0.22)
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
	v.add_child(_rule())
	var resume := UiKit.primary(UiKit.button("Resume", func() -> void: _remove_overlay(root), 90, 30))
	v.add_child(resume)
	v.add_child(UiKit.button("Scorecard", func() -> void:
		_remove_overlay(root)
		show_scorecard(), 80, 26))
	v.add_child(UiKit.button("Restart round", func() -> void:
		_remove_overlay(root)
		confirm("Restart the round?", "Your score and used footballers for this round will be lost.", "Restart", func() -> void:
			close_all_overlays()
			session.start_round(session.hole_defs, -1, session.pool.reuse_rule, session.round_state.mulligans_allowed, session.player_count())), 80, 26))
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

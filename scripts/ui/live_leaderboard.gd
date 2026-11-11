class_name LiveLeaderboard
extends PanelContainer
## Live tournament leaderboard for Career rounds (presentation only: it reads LiveProgress, never writes the save).
## Compact, collapsible: a 48dp header (your position + change) toggles the table (top 5 + you +-1, projected cut
## line) and a short ticker of field news. Updates after each completed hole. Respects Reduced motion / Larger text.
## Sits in the HUD's left column under the wind chip, so it never covers the shot controls.

const HIT := 96                # 48 logical units (same rule as GameUI.HIT)
const W := 340                 # fixed width: the 3D view and the right-hand buttons stay clear
const TICKER_LINES := 2
const C_ME := Color("#A0F344")
const C_UP := Color("#3FE07A")
const C_DOWN := Color("#FF7A7A")
const C_UNDER := Color("#FF8A8A")  # under par in golf red

static var expanded := true    # remembered while the app runs

var lp: LiveProgress
var session: GameSession
var reduced_motion := false
var text_scale := 1.0
var _step := -1
var _last_pos := 0
var _move := 0                 # positions gained (+) / lost (-) on the last hole
var _ticker: Array = []

var _head: Button
var _head_pos: Label
var _head_move: Label
var _head_rel: Label
var _body: VBoxContainer
var _table: VBoxContainer
var _tick_box: VBoxContainer


## Adds the board to a Career round HUD. Null when there is no live tournament round.
static func attach_to(ui: Control, career: CareerManager, p_session: GameSession) -> LiveLeaderboard:
	var p := career.live_progress()
	if p == null or ui == null or p_session == null:
		return null
	var b := LiveLeaderboard.new()
	b.lp = p
	b.session = p_session
	b.reduced_motion = App.settings.reduced_motion
	b.text_scale = App.settings.text_scale()
	var host: Control = ui.get("hud_left") if ui.get("hud_left") is Control else ui
	host.add_child(b)
	p_session.hole_completed.connect(func(_h: HoleState) -> void: b.update())
	p_session.state_changed.connect(func(_s: int) -> void: b.update())  # catches developer undo / resume
	b.update()
	return b


func _ready() -> void:
	name = "LiveLeaderboard"
	add_theme_stylebox_override("panel", UiKit.skin("glass", 6, 10, 8))
	custom_minimum_size.x = _w()
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UiKit.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	_head = Button.new()
	_head.flat = true
	_head.custom_minimum_size = Vector2(_w() - 20, HIT)
	_head.set_meta("ui_id", "live_board_toggle")
	_head.tooltip_text = "Show or hide the live leaderboard"
	_head.pressed.connect(toggle)
	var hr := UiKit.hbox(10)
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var live := _l("LIVE", 18, Color("#FF5A5A"))
	live.add_theme_font_override("font", UiKit.font_caps())
	hr.add_child(live)
	_head_pos = _l("", 30, UiKit.C_TEXT)
	_head_pos.add_theme_font_override("font", UiKit.font_semi())
	hr.add_child(_head_pos)
	_head_move = _l("", 22, C_UP)
	hr.add_child(_head_move)
	var sp := Control.new()
	UiKit.expand(sp)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hr.add_child(sp)
	_head_rel = _l("", 26, UiKit.C_TEXT)
	hr.add_child(_head_rel)
	_head.add_child(hr)
	v.add_child(_head)
	_body = UiKit.vbox(2)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table = UiKit.vbox(0)
	_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_table)
	_tick_box = UiKit.vbox(2)
	_tick_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_tick_box)
	v.add_child(_body)
	_body.visible = expanded


func _w() -> float:
	return minf(W * text_scale, 400.0)  # larger text widens the board a little; the right-hand buttons stay clear


func _l(t: String, size: int, color: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := UiKit.label(t, int(round(size * text_scale)), color, align)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	return l


func toggle() -> void:
	expanded = not expanded
	_body.visible = expanded


## Player progress from the session (completed holes, to par this round).
func _player() -> Array:
	var rs := session.slot_round_state(0)
	return [rs.holes_completed(), rs.relative_to_par()]


func update() -> void:
	if lp == null or session == null or not is_inside_tree():
		return
	var pr := _player()
	var step := int(pr[0])
	if step == _step:
		return
	var b := lp.board(step, int(pr[1]))
	var me: Dictionary = b["rows"][int(b["player_index"])]
	if _step >= 0 and step > _step:
		_move = _last_pos - int(me["pos"])
		for line in lp.events_between(_step, step, int(pr[1])):
			_ticker.push_front(String(line))
		if _move != 0:
			_ticker.push_front("You move %s to %s" % ["up" if _move > 0 else "down", LiveProgress.fmt_pos(me)])
		_ticker = _ticker.slice(0, TICKER_LINES)
	else:
		_move = 0
	_step = step
	_last_pos = int(me["pos"])
	_render(b, me)


func _render(b: Dictionary, me: Dictionary) -> void:
	_head_pos.text = LiveProgress.fmt_pos(me)
	_head_rel.text = LiveProgress.fmt_rel(int(me["rel"]))
	_head_rel.add_theme_color_override("font_color", C_UNDER if int(me["rel"]) < 0 else UiKit.C_TEXT)
	_head_move.text = "" if _move == 0 else ("▲%d" % _move if _move > 0 else "▼%d" % -_move)
	_head_move.add_theme_color_override("font_color", C_UP if _move > 0 else C_DOWN)
	UiKit.clear(_table)
	var rows: Array = b["rows"]
	var cut_drawn := false
	_table.add_child(_row({"pos": 0, "name": "PLAYER", "rel": 0, "thru": 0, "is_human": false}, true))
	for k in LiveProgress.visible_rows(rows, int(b["player_index"])):
		if k < 0:
			_table.add_child(_l("···", 18, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
			continue
		var r: Dictionary = rows[k]
		if bool(b["has_cut"]) and not cut_drawn and bool(r["below_cut"]):
			_table.add_child(_cut_line(int(b["cut_line"])))
			cut_drawn = true
		_table.add_child(_row(r))
	UiKit.clear(_tick_box)
	for i in _ticker.size():
		var t := _l(String(_ticker[i]), 17, UiKit.C_TEXT if i == 0 else UiKit.C_MUTED)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size.x = _w() - 24
		_tick_box.add_child(t)
	if _move != 0 and not reduced_motion:
		_head_move.modulate.a = 0.0
		create_tween().tween_property(_head_move, "modulate:a", 1.0, 0.35)
		if not _ticker.is_empty():
			var first: Control = _tick_box.get_child(0)
			first.modulate.a = 0.0
			create_tween().tween_property(first, "modulate:a", 1.0, 0.45)


func _row(r: Dictionary, header: bool = false) -> Control:
	var me := bool(r["is_human"])
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(C_ME.r, C_ME.g, C_ME.b, 0.22) if me else Color(0, 0, 0, 0)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	if me:
		sb.border_width_left = 4
		sb.border_color = C_ME
	p.add_theme_stylebox_override("panel", sb)
	var h := UiKit.hbox(8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := 15 if header else 20
	var pos := _l("POS" if header else LiveProgress.fmt_pos(r), fs, UiKit.C_MUTED)
	pos.custom_minimum_size.x = 44 * text_scale
	h.add_child(pos)
	var nm := _l("You" if me else String(r["name"]), fs, UiKit.C_MUTED if header else (C_ME if me else UiKit.C_TEXT))
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiKit.expand(nm)
	h.add_child(nm)
	var rel := _l("TOT" if header else LiveProgress.fmt_rel(int(r["rel"])), fs, UiKit.C_MUTED if header else (C_UNDER if int(r["rel"]) < 0 else UiKit.C_TEXT), HORIZONTAL_ALIGNMENT_RIGHT)
	rel.custom_minimum_size.x = 44 * text_scale
	h.add_child(rel)
	var th := _l("THRU" if header else LiveProgress.fmt_thru(int(r["thru"]), lp.holes), 15 if header else 18, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	th.custom_minimum_size.x = 40 * text_scale
	h.add_child(th)
	p.add_child(h)
	return p


func _cut_line(line: int) -> Control:
	var h := UiKit.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 2:
		var c := ColorRect.new()
		c.color = UiKit.C_WARN
		c.custom_minimum_size = Vector2(0, 2)
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		UiKit.expand(c)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(c)
		if i == 0:
			h.add_child(_l("Projected cut %s" % LiveProgress.fmt_rel(line), 16, UiKit.C_WARN))
	return h

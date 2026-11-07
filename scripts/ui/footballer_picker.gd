class_name FootballerPicker
extends Control
## Normal-play footballer selector: name search + nationality filter, used/available state.
## NEVER shows caps/goals and never orders by stats (alphabetical only).

signal picked(id: String)
signal closed

var session: GameSession
var _search: LineEdit
var _nation: OptionButton
var _list: VBoxContainer
var _nations: Array[String] = []
## Test mode: reveal caps/goals before the shot (normal rules hide them).
var show_stats := false


func setup(s: GameSession) -> void:
	session = s
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := UiKit.overlay(0.6)
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sm := UiKit.safe_margins(get_viewport()) if is_inside_tree() else [16.0, 16.0, 16.0, 16.0]
	m.add_theme_constant_override("margin_left", int(sm[0]) + 8)
	m.add_theme_constant_override("margin_right", int(sm[2]) + 8)
	m.add_theme_constant_override("margin_top", int(sm[1]) + 40)
	m.add_theme_constant_override("margin_bottom", int(sm[3]) + 24)
	add_child(m)
	var p := UiKit.panel(UiKit.C_PANEL_SOLID)
	m.add_child(p)
	var v := UiKit.vbox(12)
	p.add_child(v)
	var head := UiKit.hbox()
	head.add_child(UiKit.expand(UiKit.label("Choose footballer", 34)))
	head.add_child(UiKit.button("Close", func() -> void: closed.emit(), 64, 24))
	v.add_child(head)
	if show_stats:
		v.add_child(UiKit.text("TEST MODE: caps & goals shown before the shot (turn off in Settings for normal rules)", 21, UiKit.C_WARN))
	else:
		v.add_child(UiKit.text("Synthetic test players · caps & goals stay hidden until the ball stops", 20, UiKit.C_MUTED))
	_search = LineEdit.new()
	_search.placeholder_text = "Search name…"
	_search.custom_minimum_size = Vector2(0, 64)
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	v.add_child(_search)
	_nation = OptionButton.new()
	_nation.custom_minimum_size = Vector2(0, 60)
	_nation.add_item("All nationalities")
	_nations = session.repo.nationalities()
	for n in _nations:
		_nation.add_item(n)
	_nation.item_selected.connect(func(_i: int) -> void: _rebuild())
	v.add_child(_nation)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_list = UiKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	_rebuild()


func _rebuild() -> void:
	UiKit.clear(_list)
	var nat := ""
	if _nation.selected > 0:
		nat = _nations[_nation.selected - 1]
	var results := session.repo.search(_search.text, nat)
	var available := 0
	for fb in results:
		var used := session.pool.is_used(fb.id)
		var txt := fb.display_label()
		if show_stats:
			txt = "%s (%s)   ·   %d caps  ·  %d goals" % [fb.name, fb.nationality, fb.caps, fb.goals]
		if used:
			txt += "   · USED"
		var b := UiKit.button(txt, func() -> void: _on_pick(fb.id), 68, 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.disabled = used
		if fb.id == session.selected_id:
			UiKit.primary(b, UiKit.C_ACCENT_DARK)
		_list.add_child(b)
		if not used:
			available += 1
	if results.is_empty():
		_list.add_child(UiKit.text("No footballers match.", 24, UiKit.C_MUTED))
	_list.add_child(UiKit.text("%d available of %d shown · %d used this match" % [available, results.size(), session.pool.used_count()], 20, UiKit.C_MUTED))


func _on_pick(id: String) -> void:
	if session.select_footballer(id):
		picked.emit(id)

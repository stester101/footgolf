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
var _sc: ScrollContainer
var _press_scroll := 0


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
	var debounce := Timer.new()
	debounce.one_shot = true
	debounce.wait_time = 0.2
	debounce.timeout.connect(_rebuild)
	add_child(debounce)
	_search.text_changed.connect(func(_t: String) -> void: debounce.start())
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
	_sc = sc
	sc.scroll_deadzone = 14
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_list = UiKit.vbox(8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	_rebuild()


const PAGE := 60
var _limit := PAGE


func _rebuild() -> void:
	_limit = PAGE
	_render()


## Only the first _limit matches are built as buttons (the real database has thousands).
func _render() -> void:
	UiKit.clear(_list)
	var nat := ""
	if _nation.selected > 0:
		nat = _nations[_nation.selected - 1]
	var all_matches := session.repo.search(_search.text, nat)
	var total := all_matches.size()
	var available := 0
	for i in mini(_limit, total):
		var fb: Footballer = all_matches[i]
		var used := session.pool.is_used(fb.id)
		var b := UiKit.player_button(fb, show_stats, used, fb.id == session.selected_id, func() -> void: _on_pick(fb.id))
		# Let drags reach the ScrollContainer (touch scrolling); a press only picks if the list didn't scroll.
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		b.button_down.connect(func() -> void: _press_scroll = _sc.scroll_vertical)
		_list.add_child(b)
		if not used:
			available += 1
	if total == 0:
		_list.add_child(UiKit.text("No footballers match.", 24, UiKit.C_MUTED))
	if total > _limit:
		var more := UiKit.button("Show more (%d of %d shown)" % [_limit, total], func() -> void:
			_limit += PAGE
			var keep := _sc.scroll_vertical
			_render()
			_sc.set_deferred("scroll_vertical", keep), 64, 22)
		more.mouse_filter = Control.MOUSE_FILTER_PASS
		_list.add_child(more)
	_list.add_child(UiKit.text("%d matches · %d used this match · type a name or pick a country to narrow" % [total, session.pool.used_count()], 19, UiKit.C_MUTED))


func _on_pick(id: String) -> void:
	if absi(_sc.scroll_vertical - _press_scroll) > 6:
		return
	if session.select_footballer(id):
		picked.emit(id)

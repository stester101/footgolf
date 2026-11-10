class_name Tutorial
extends Control
## Short paged "How to play" overlay.

signal finished

const PAGES := [
	["Pick a footballer, not a club", "Every shot is a real international footballer. Choose CAPS or GOALS, then pick a player. Each player can be used only once per round, across every hole."],
	["Choose distance", "CAPS give 1 yard per cap. GOALS give 1 foot per goal. Either can be played as a flight or a roll."],
	["Choose flight or roll", "A flight's distance is measured to its first landing; a roll's distance is measured when it stops. Wind and lies affect flight. Greens and slopes change the roll."],
	["Trajectory and spin", "Four trajectories (Punch, Low, Standard, High) change the flight shape, not the carry. Caps shots can also take top or back spin. Spin and trajectory reset after every shot."],
	["Aim and shoot", "Drag the course left or right to aim (full 360°). Use MAP for a top-down view: pinch to zoom, tap to measure. Then press TAKE SHOT."],
	["Scoring", "Stroke play: fewest shots wins. Water or out of bounds costs +1. Stop within 5 ft of the hole and it's holed. There is no maximum score: keep going until you hole out."],
]

var _page := 0
var _title: Label
var _body: Label
var _dots: Label
var _next: Button
var _back: Button


func setup() -> void:
	theme = UiKit.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(UiKit.overlay(0.7))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := UiKit.panel(UiKit.C_PANEL_SOLID)
	p.custom_minimum_size = Vector2(620, 560)
	center.add_child(p)
	var v := UiKit.vbox(18)
	p.add_child(v)
	var cap := UiKit.label("HOW TO PLAY", 20, UiKit.C_CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	cap.add_theme_font_override("font", UiKit.font_caps())
	v.add_child(cap)
	_title = UiKit.text("", 38, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_title.add_theme_font_override("font", UiKit.font_semi())
	v.add_child(_title)
	var rule := ColorRect.new()
	rule.color = Color(0.72, 0.88, 1.0, 0.22)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rule)
	_body = UiKit.text("", 26, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	v.add_child(_body)
	_dots = UiKit.label("", 28, UiKit.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_dots)
	var row := UiKit.hbox(10)
	_back = UiKit.button("Back", func() -> void: _go(-1), 80, 26)
	UiKit.expand(_back)
	_next = UiKit.primary(UiKit.button("Next", func() -> void: _go(1), 80, 28))
	_next.add_theme_font_override("font", UiKit.font_semi())
	UiKit.expand(_next)
	row.add_child(_back)
	row.add_child(_next)
	v.add_child(row)
	var skip := UiKit.button("Skip tutorial", func() -> void: finished.emit(), 60, 22)
	skip.set_meta("ui_id", "tutorial_skip")
	v.add_child(skip)
	_show()


func _go(d: int) -> void:
	if _page + d >= PAGES.size():
		finished.emit()
		return
	_page = clampi(_page + d, 0, PAGES.size() - 1)
	_show()


func _show() -> void:
	_title.text = PAGES[_page][0]
	_body.text = PAGES[_page][1]
	var dots := ""
	for i in PAGES.size():
		dots += "● " if i == _page else "○ "
	_dots.text = dots.strip_edges()
	_back.disabled = _page == 0
	_next.text = "Let's play" if _page == PAGES.size() - 1 else "Next"

class_name CourseComboPicker
extends VBoxContainer
## Multi-select of courses from data/courses.json with an editable play order. Used by Course Select
## ("Build your own" / mini season) and the online host lobby. Pure view: it only tracks the chosen ids.

signal changed(ids: Array)

## true (mini season): the same course may be added more than once. false (one combined round): once each.
var allow_repeat := false
var max_courses := CourseCombo.MAX_COURSES
var ids: Array = []

var _courses: Array = []
var _avail: VBoxContainer
var _order: VBoxContainer
var _summary: Label


func setup(courses: Array, repeat: bool) -> void:
	_courses = courses
	allow_repeat = repeat
	max_courses = Season.MAX_COURSES if repeat else CourseCombo.MAX_COURSES
	add_theme_constant_override("separation", 8)
	var cap := UiKit.label("ADD COURSES  (tap to add in play order)", 17, UiKit.C_MUTED)
	cap.add_theme_font_override("font", UiKit.font_caps())
	add_child(cap)
	_avail = UiKit.vbox(6)
	add_child(_avail)
	var cap2 := UiKit.label("YOUR ORDER", 17, UiKit.C_MUTED)
	cap2.add_theme_font_override("font", UiKit.font_caps())
	add_child(cap2)
	_order = UiKit.vbox(6)
	add_child(_order)
	_summary = UiKit.label("", 20, UiKit.C_CYAN)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	rebuild()


## Switches between combined-round (no repeats) and season (repeats) behaviour, keeping a valid selection.
func set_allow_repeat(repeat: bool) -> void:
	allow_repeat = repeat
	max_courses = Season.MAX_COURSES if repeat else CourseCombo.MAX_COURSES
	if not repeat:
		var seen := {}
		var kept: Array = []
		for c in ids:
			if not seen.has(c):
				seen[c] = true
				kept.append(c)
		ids = kept.slice(0, max_courses)
	rebuild()
	changed.emit(ids)


func _name_of(cid: String) -> String:
	for c in _courses:
		if String(c.get("id", "")) == cid:
			return String(c.get("name", cid))
	return cid


func rebuild() -> void:
	UiKit.clear(_avail)
	UiKit.clear(_order)
	for c in _courses:
		var cid := String(c.get("id", ""))
		var n := (c.get("holes", []) as Array).size()
		var b := UiKit.button("+  %s   ·   %d holes" % [String(c.get("name", cid)), n], func() -> void: _add(cid), 56, 22)
		b.set_meta("ui_id", "combo_add_" + cid)
		b.disabled = ids.size() >= max_courses or (not allow_repeat and ids.has(cid))
		_avail.add_child(b)
	if ids.is_empty():
		_order.add_child(UiKit.label("Nothing chosen yet.", 20, UiKit.C_MUTED))
	for i in ids.size():
		var idx := i
		var row := UiKit.hbox(6)
		var nm := UiKit.label("%d.  %s" % [i + 1, _name_of(String(ids[i]))], 23, Color.WHITE)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(nm)
		for spec in [["up", "▲", -1], ["dn", "▼", 1], ["rm", "✕", 0]]:
			var dir := int(spec[2])
			var kind := String(spec[0])
			var bb := UiKit.button(String(spec[1]), func() -> void: _move(idx, dir), 52, 22)
			bb.custom_minimum_size.x = 62
			bb.set_meta("ui_id", "combo_%s_%d" % [kind, i])
			bb.disabled = (dir == -1 and i == 0) or (dir == 1 and i == ids.size() - 1)
			row.add_child(bb)
		_order.add_child(row)
	var holes := 0
	var shown := {}
	for cid in ids:
		var info := CourseComboPicker.holes_of(_courses, String(cid))
		for h in info:
			if allow_repeat or not shown.has(h):
				shown[h] = true
				holes += 1
	_summary.text = "%d course%s  ·  %d holes in total" % [ids.size(), "" if ids.size() == 1 else "s", holes] if not ids.is_empty() else ""


static func holes_of(courses: Array, cid: String) -> Array:
	for c in courses:
		if String(c.get("id", "")) == cid:
			return c.get("holes", [])
	return []


func _add(cid: String) -> void:
	if ids.size() >= max_courses or (not allow_repeat and ids.has(cid)):
		return
	ids.append(cid)
	rebuild()
	changed.emit(ids)


## dir -1 up, +1 down, 0 remove.
func _move(i: int, dir: int) -> void:
	if i < 0 or i >= ids.size():
		return
	if dir == 0:
		ids.remove_at(i)
	else:
		var j := i + dir
		if j < 0 or j >= ids.size():
			return
		var t = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	rebuild()
	changed.emit(ids)

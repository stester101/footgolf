class_name MainMenu
extends Control
## Main menu: course select, Developer Test, Settings, How to play, version/build info.

signal play_requested(course_id: String, dev: bool)

var _settings_box: VBoxContainer
var _main_box: VBoxContainer


func setup() -> void:
	theme = UiKit.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = UiKit.C_BG  # flat matte, no gradient
	add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sm := UiKit.safe_margins(get_viewport())
	m.add_theme_constant_override("margin_left", int(sm[0]) + 40)
	m.add_theme_constant_override("margin_right", int(sm[2]) + 40)
	m.add_theme_constant_override("margin_top", int(sm[1]) + 80)
	m.add_theme_constant_override("margin_bottom", int(sm[3]) + 40)
	add_child(m)
	var v := UiKit.vbox(18)
	m.add_child(v)
	var logo := TextureRect.new()
	logo.texture = load("res://icon.svg")
	logo.custom_minimum_size = Vector2(180, 180)
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	v.add_child(logo)
	var ttl := UiKit.text("Football Golf", 54, UiKit.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	ttl.add_theme_font_override("font", UiKit.font_semi())
	v.add_child(ttl)
	v.add_child(UiKit.text("Pick a footballer. Caps fly, goals roll.", 26, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("1 cap = 1 yard carry · 1 goal = 1 foot ground", 22, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	_main_box = UiKit.vbox(16)
	_main_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_main_box)
	# Courses come from data/courses.json; the list scrolls when it does not fit (bottom-aligned otherwise).
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 14
	_main_box.add_child(sc)
	var list := UiKit.vbox(16)
	list.alignment = BoxContainer.ALIGNMENT_END
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	var current: Control = null
	for c in App.courses():
		var cid: String = c["id"]
		var cb := UiKit.button("%s\n%s · par %d" % [c["name"], c["blurb"], App.course_par(cid)], func() -> void: play_requested.emit(cid, false), 96, 28)
		if cid == App.settings.last_course:
			UiKit.primary(cb)
			current = cb
		list.add_child(cb)
	if current != null:
		sc.ensure_control_visible.call_deferred(current)
	var dev := UiKit.button("Developer Test", func() -> void: play_requested.emit("all", true), 70, 24)
	dev.add_theme_color_override("font_color", UiKit.C_DEV)
	_main_box.add_child(dev)
	var row := UiKit.hbox(12)
	var how := UiKit.button("How to play", show_tutorial, 80, 26)
	UiKit.expand(how)
	row.add_child(how)
	var set_b := UiKit.button("Settings", _show_settings, 80, 26)
	UiKit.expand(set_b)
	row.add_child(set_b)
	_main_box.add_child(row)
	_settings_box = UiKit.vbox(12)
	_settings_box.visible = false
	v.add_child(_settings_box)
	if not App.settings.tutorial_seen and not OS.get_cmdline_user_args().has("--smoke-test"):
		show_tutorial.call_deferred()
	v.add_child(UiKit.text("Offline prototype · %s\n%s" % [App.dataset_label(), App.build_label()], 18, UiKit.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))


func _show_settings() -> void:
	_main_box.visible = false
	_settings_box.visible = true
	UiKit.clear(_settings_box)
	var p := UiKit.panel()
	_settings_box.add_child(p)
	var v := UiKit.vbox(12)
	p.add_child(v)
	v.add_child(UiKit.text("Settings", 32))
	var st: SettingsStore = App.settings
	var row := UiKit.hbox()
	row.add_child(UiKit.expand(UiKit.label("Auto hole-out radius (ft)", 24)))
	row.add_child(UiKit.spin(0, 10, 0.5, st.holeout_radius_ft, func(val: float) -> void:
		st.holeout_radius_ft = ScoringService.clamp_radius_ft(val)
		st.save()))
	v.add_child(row)
	var cup_row := UiKit.hbox()
	cup_row.add_child(UiKit.expand(UiKit.label("Hole size (diameter, inches)", 24)))
	cup_row.add_child(UiKit.spin(4.25, 40, 0.25, st.physics.cup_diameter_in(), func(val: float) -> void:
		st.physics.set_cup_diameter_in(val)
		st.save()))
	v.add_child(cup_row)
	v.add_child(UiKit.text("Regulation is 4.25 in. The game default is a friendlier 12 in.", 18, UiKit.C_MUTED))
	v.add_child(UiKit.button("Edit hole pars…", _show_par_editor, 70, 22))
	var trail := CheckButton.new()
	trail.text = "Show ball trail"
	trail.button_pressed = st.show_trail
	trail.toggled.connect(func(on: bool) -> void:
		st.show_trail = on
		st.save())
	v.add_child(trail)
	var stats := CheckButton.new()
	stats.text = "TEST MODE: show caps/goals before shot"
	stats.button_pressed = st.show_stats
	stats.toggled.connect(func(on: bool) -> void:
		st.show_stats = on
		st.save())
	v.add_child(stats)
	var ds := CheckButton.new()
	ds.text = "Use real footballers (off = synthetic test set)"
	ds.button_pressed = st.dataset == "real"
	var ds_label := UiKit.text(App.dataset_label(), 20, UiKit.C_MUTED)
	ds.toggled.connect(func(on: bool) -> void:
		st.dataset = "real" if on else "test"
		st.save()
		App.load_dataset()
		ds_label.text = App.dataset_label())
	v.add_child(ds)
	v.add_child(ds_label)
	v.add_child(UiKit.text("Audio: none in V0.1 (silent).", 20, UiKit.C_MUTED))
	v.add_child(UiKit.button("Reset footballer database to seed", func() -> void: App.repo.reset_to_seed(), 70, 22))
	v.add_child(UiKit.button("Back", _hide_settings, 76, 26))


func _hide_settings() -> void:
	_settings_box.visible = false
	_main_box.visible = true


func handle_back() -> bool:
	if _tutorial != null and is_instance_valid(_tutorial):
		_tutorial.finished.emit()
		return true
	if _settings_box.visible:
		_hide_settings()
		return true
	return false


var _tutorial: Tutorial


func show_tutorial() -> void:
	if _tutorial != null and is_instance_valid(_tutorial):
		return
	_tutorial = Tutorial.new()
	add_child(_tutorial)
	_tutorial.setup()
	_tutorial.finished.connect(func() -> void:
		App.settings.tutorial_seen = true
		App.settings.save()
		_tutorial.queue_free()
		_tutorial = null)


## Per-hole par editor (3/4/5 or anything 2-8). Applies to rounds started afterwards.
func _show_par_editor() -> void:
	var root := UiKit.overlay(0.7)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 32)
	root.add_child(m)
	var p := UiKit.panel(UiKit.C_SURFACE)
	m.add_child(p)
	var v := UiKit.vbox(12)
	p.add_child(v)
	v.add_child(UiKit.label("Hole pars", 34))
	v.add_child(UiKit.text("Set each hole's par. Scores have no maximum; par only changes the +/- shown. Applies to the next round.", 19, UiKit.C_MUTED))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.scroll_deadzone = 14
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var list := UiKit.vbox(8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)
	for info in App.all_hole_infos():
		var hid: String = info["id"]
		var row := UiKit.hbox(10)
		var nm := UiKit.label("%s\n%d yd" % [info["name"], info["yards"]], 22)
		UiKit.expand(nm)
		row.add_child(nm)
		var sp := UiKit.spin(2, 8, 1, App.par_for(hid, info["base_par"]), func(val: float) -> void:
			var pv := int(val)
			if pv == int(info["base_par"]):
				App.settings.par_overrides.erase(hid)
			else:
				App.settings.par_overrides[hid] = pv
			App.settings.save())
		row.add_child(sp)
		list.add_child(row)
	v.add_child(UiKit.button("Reset all to defaults", func() -> void:
		App.settings.par_overrides.clear()
		App.settings.save()
		root.queue_free()
		_show_par_editor(), 64, 22))
	v.add_child(UiKit.primary(UiKit.button("Done", func() -> void: root.queue_free(), 84, 28)))
	add_child(root)

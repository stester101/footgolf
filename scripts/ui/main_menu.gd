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
	bg.color = Color(0.09, 0.27, 0.15)
	add_child(bg)
	var grad := TextureRect.new()
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.32, 0.58, 0.85))
	g.set_color(1, Color(0.12, 0.42, 0.2))
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	grad.texture = gt
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(grad)
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
	v.add_child(UiKit.text("FOOTBALL GOLF", 60, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("Pick a footballer. Caps fly, goals roll.", 26, Color(0.9, 0.95, 0.9), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.text("1 cap = 1 yard carry · 1 goal = 1 foot ground", 22, Color(0.85, 0.92, 0.85), HORIZONTAL_ALIGNMENT_CENTER))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	_main_box = UiKit.vbox(16)
	v.add_child(_main_box)
	for c in App.courses():
		var cid: String = c["id"]
		var cb := UiKit.button("%s\n%s" % [c["name"], c["blurb"]], func() -> void: play_requested.emit(cid, false), 96, 28)
		if cid == App.settings.last_course:
			UiKit.primary(cb)
		_main_box.add_child(cb)
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
	v.add_child(UiKit.text("Offline prototype · %s\n%s" % [App.dataset_label(), App.build_label()], 18, Color(0.85, 0.9, 0.85), HORIZONTAL_ALIGNMENT_CENTER))


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

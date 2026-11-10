extends Node
## Root: main menu <-> round scene.

const ROUND_SCENE := preload("res://scenes/round.tscn")

var _menu: Control
var _round: Node
var _canvas: CanvasLayer
## Mini season in progress (null otherwise). Lives here so it survives the per-course round scenes.
var _season: Season
var _keep_season := false
## Career round in progress / page to reopen when returning to the menu ("" = ordinary menu).
var _career_return := ""
var _last_back_ms := -100000


func _ready() -> void:
	get_tree().quit_on_go_back = false
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	App.online.round_started.connect(_start_online)
	App.online.event.connect(_on_online_event)
	App.online.ended.connect(func(reason: String) -> void:
		show_menu()
		_menu._open_placeholder("Online round ended", reason, "Notice"))
	show_menu()
	if OS.get_cmdline_user_args().has("--smoke-test") or OS.get_cmdline_user_args().has("--smoke-career"):
		var d := SmokeDriver.new()
		d.main = self
		add_child(d)


func show_menu() -> void:
	if App.online.started:
		App.online.leave()
	_season = null
	if _round != null:
		_round.queue_free()
		_round = null
	if _menu != null:
		_menu.queue_free()
	_menu = MainMenu.new()
	_canvas.add_child(_menu)
	_menu.setup()
	_menu.career_round_requested.connect(_start_career_round)
	_menu.play_requested.connect(func(course_id: String, dev: bool, mulligans: int, players: int, rules: RoundConfig) -> void: start_round(course_id, dev, mulligans, players, rules))
	_menu.resume_requested.connect(_resume_round)
	if _career_return != "":
		var page := _career_return
		_career_return = ""
		_menu.open_career(page)


## Resumes a saved offline round with its frozen rules, player count and mulligan setting.
func _resume_round(save_id: String) -> void:
	var sv := RoundSave.load_save(save_id)
	if sv.is_empty():
		return
	start_round(String(sv.get("course_id", "")), false, RoundSave.mulligans_of(sv), RoundSave.players_of(sv), RoundSave.rules_of(sv), save_id)


func start_round(course_id: String, dev: bool = false, mulligans: int = 0, players: int = 1, rules: RoundConfig = null, resume_id: String = "", career_run: CareerRoundRun = null) -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	if App.online.active and not App.online.started:
		App.online.leave()
	if _round != null:  # next course of a season: drop the finished round first
		remove_child(_round)
		_round.queue_free()
		_round = null
	if not _keep_season:
		_season = null
		if rules != null and not dev and not rules.season_courses.is_empty():
			_season = Season.create(rules.season_courses)
			course_id = _season.current_course()
	_keep_season = false
	App.dev_mode = dev
	_round = ROUND_SCENE.instantiate()
	_round.open_dev_on_start = dev
	_round.course_id = "all" if dev else course_id
	_round.mulligans = mulligans
	_round.players = players
	_round.rules = rules if rules != null else RoundConfig.from_settings(App.settings)
	_round.resume_id = resume_id
	_round.career_run = career_run
	App.settings.last_course = course_id
	App.settings.save()
	_round.exit_to_menu.connect(show_menu)
	_round.season = _season
	_round.next_course_requested.connect(_next_season_course)
	add_child(_round)


## Career Mode: plays (or resumes) the active tournament's current round from its frozen course snapshot.
func _start_career_round() -> void:
	var career := CareerManager.active
	if career == null or not career.has_active_tournament():
		return
	var run := CareerRoundRun.new(career)
	if run.hole_defs().is_empty():
		_menu._open_placeholder("Career course unavailable", "This tournament's saved course could not be rebuilt. Your career data is untouched; nothing was replaced with newer course data.", "Notice")
		return
	_career_return = "hub"
	run.finished.connect(func() -> void:
		run.detach()
		_career_return = "tournament"
		show_menu())
	start_round(run.course_id(), false, run.mulligans(), 1, run.rules(), "", run)


func _next_season_course(course_id: String) -> void:
	_keep_season = true
	start_round(course_id, false, _round.mulligans, _round.players, _round.rules)


## Host-driven: the host's "season_next" event carries the course, its pars and the host's season state.
func _on_online_event(data: Dictionary) -> void:
	if data.get("kind") != "season_next" or _season == null or _round == null or not App.online.started:
		return
	if not data.get("season") is Dictionary:
		return
	var incoming := Season.from_dict(data.season)
	if incoming.courses != _season.courses or incoming.current_course() != String(data.get("course", "")):
		return
	_season = incoming
	App.online.apply_season_course(incoming.current_course(), data.get("pars", {}) if data.get("pars") is Dictionary else {})
	_keep_season = true
	_start_online()


func _start_online() -> void:
	if not _keep_season:
		var rc := RoundConfig.from_dict(App.online.setup.get("rules", {}))
		_season = Season.create(rc.season_courses) if not rc.season_courses.is_empty() else null
		_keep_season = _season != null
		if _season != null:
			App.online.setup["course"] = _season.current_course()
	start_round(String(App.online.setup.course), false, int(App.online.setup.mulligans), App.online.players.size())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _round == null:
		if _menu != null and _menu.has_method("handle_back") and _menu.handle_back():
			return
		# Home screen: the first Back asks for confirmation, a second one within 2 s exits (avoids accidental exits).
		var now := Time.get_ticks_msec()
		if now - _last_back_ms <= 2000:
			get_tree().quit()
		else:
			_last_back_ms = now
			if _menu != null and _menu.has_method("show_exit_hint"):
				_menu.show_exit_hint()
	elif what == NOTIFICATION_APPLICATION_PAUSED:
		App.settings.save()  # the OS may kill a backgrounded app

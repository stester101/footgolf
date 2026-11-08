extends Node
## Root: main menu <-> round scene.

const ROUND_SCENE := preload("res://scenes/round.tscn")

var _menu: Control
var _round: Node
var _canvas: CanvasLayer
## Mini season in progress (null otherwise). Lives here so it survives the per-course round scenes.
var _season: Season
var _keep_season := false


func _ready() -> void:
	get_tree().quit_on_go_back = false
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	App.online.round_started.connect(_start_online)
	App.online.event.connect(_on_online_event)
	App.online.ended.connect(func(reason: String) -> void:
		show_menu()
		_menu._open_placeholder("Online round ended", reason))
	show_menu()
	if OS.get_cmdline_user_args().has("--smoke-test"):
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
	_menu.play_requested.connect(func(course_id: String, dev: bool, mulligans: int, players: int, rules: RoundConfig) -> void: start_round(course_id, dev, mulligans, players, rules))


func start_round(course_id: String, dev: bool = false, mulligans: int = 0, players: int = 1, rules: RoundConfig = null) -> void:
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
	App.settings.last_course = course_id
	App.settings.save()
	_round.exit_to_menu.connect(show_menu)
	_round.season = _season
	_round.next_course_requested.connect(_next_season_course)
	add_child(_round)


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
		get_tree().quit()

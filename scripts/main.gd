extends Node
## Root: main menu <-> round scene.

const ROUND_SCENE := preload("res://scenes/round.tscn")

var _menu: Control
var _round: Node
var _canvas: CanvasLayer


func _ready() -> void:
	get_tree().quit_on_go_back = false
	_canvas = CanvasLayer.new()
	add_child(_canvas)
	App.online.round_started.connect(_start_online)
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
	if _round != null:
		_round.queue_free()
		_round = null
	if _menu != null:
		_menu.queue_free()
	_menu = MainMenu.new()
	_canvas.add_child(_menu)
	_menu.setup()
	_menu.play_requested.connect(func(course_id: String, dev: bool, mulligans: int, players: int) -> void: start_round(course_id, dev, mulligans, players))
	_menu.resume_requested.connect(func(save_id: String) -> void: start_round(String(RoundSave.load_save(save_id).get("course_id", "")), false, 0, 1, save_id))


func start_round(course_id: String, dev: bool = false, mulligans: int = 0, players: int = 1, resume_id: String = "") -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	if App.online.active and not App.online.started:
		App.online.leave()
	App.dev_mode = dev
	_round = ROUND_SCENE.instantiate()
	_round.open_dev_on_start = dev
	_round.course_id = "all" if dev else course_id
	_round.mulligans = mulligans
	_round.players = players
	_round.resume_id = resume_id
	App.settings.last_course = course_id
	App.settings.save()
	_round.exit_to_menu.connect(show_menu)
	add_child(_round)


func _start_online() -> void:
	start_round(String(App.online.setup.course), false, int(App.online.setup.mulligans), App.online.players.size())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _round == null:
		if _menu != null and _menu.has_method("handle_back") and _menu.handle_back():
			return
		get_tree().quit()

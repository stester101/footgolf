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
	show_menu()
	if OS.get_cmdline_user_args().has("--smoke-test"):
		var d := SmokeDriver.new()
		d.main = self
		add_child(d)


func show_menu() -> void:
	if _round != null:
		_round.queue_free()
		_round = null
	if _menu != null:
		_menu.queue_free()
	_menu = MainMenu.new()
	_canvas.add_child(_menu)
	_menu.setup()
	_menu.play_requested.connect(func(course_id: String, dev: bool) -> void: start_round(course_id, dev))


func start_round(course_id: String, dev: bool = false) -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	App.dev_mode = dev
	_round = ROUND_SCENE.instantiate()
	_round.open_dev_on_start = dev
	_round.course_id = "all" if dev else course_id
	App.settings.last_course = course_id
	App.settings.save()
	_round.exit_to_menu.connect(show_menu)
	add_child(_round)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _round == null:
		if _menu != null and _menu.has_method("handle_back") and _menu.handle_back():
			return
		get_tree().quit()

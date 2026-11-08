class_name OnlineRoom
extends Node

signal changed
signal error(message: String)
signal round_started
signal ended(message: String)
signal intent(seat: int, command: Dictionary)
signal event(data: Dictionary)
signal resync(seat: int)

var app: Node
var transport: NetTransport
var seat := -1
var code := ""
var token := ""
var players: Array = []
var setup: Dictionary = {}
var active := false
var paused := true
var started := false
var url := ""
var player_name := "Player"
var status := "Not connected"
var fingerprint := ""
var _hello: Dictionary = {}
var _retry_at := 0
var _lost_at := 0

func _ready() -> void:
	app = get_node("/root/App")
	transport = NetTransport.new()
	add_child(transport)
	transport.connected.connect(func() -> void: transport.send(_hello))
	transport.received.connect(_receive)
	transport.failed.connect(func(reason: String) -> void:
		transport.close()
		_disconnected()
		status = reason
		error.emit(reason)
		changed.emit())
	transport.disconnected.connect(_disconnected)

func content_fingerprint() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(JSON.stringify(app.build_info).to_utf8_buffer())
	ctx.update(String(Engine.get_version_info()["string"]).to_utf8_buffer())
	_hash_dir(ctx, "res://scripts")
	_hash_dir(ctx, "res://data")
	# Include local footballer edits without transmitting the full database.
	for footballer in app.repo.all_sorted():
		ctx.update(JSON.stringify(footballer.to_dict()).to_utf8_buffer())
	return ctx.finish().hex_encode()

func _hash_dir(ctx: HashingContext, path: String) -> void:
	var files := DirAccess.get_files_at(path)
	files.sort()
	for file in files:
		if file.ends_with(".gd.remap"):
			var remap := ConfigFile.new()
			if remap.load(path.path_join(file)) == OK:
				ctx.update(file.to_utf8_buffer())
				ctx.update(FileAccess.get_file_as_bytes(String(remap.get_value("remap", "path", ""))))
		elif file.ends_with(".gd") or file.ends_with(".json") or file.ends_with(".gdc"):
			ctx.update(file.to_utf8_buffer())
			ctx.update(FileAccess.get_file_as_bytes(path.path_join(file)))
	var dirs := DirAccess.get_directories_at(path)
	dirs.sort()
	for dir in dirs:
		_hash_dir(ctx, path.path_join(dir))

func connect_room(address: String, nickname: String, room_code: String = "") -> void:
	leave()
	url = address.strip_edges()
	player_name = nickname.strip_edges().left(24)
	if player_name.is_empty(): player_name = "Player"
	fingerprint = content_fingerprint()
	active = true
	status = "Connecting…"
	_hello = {"type": "host" if room_code.is_empty() else "join", "code": room_code.to_upper(),
		"protocol": 1, "name": player_name, "fingerprint": fingerprint}
	transport.open(url)
	changed.emit()

func _disconnected() -> void:
	if not active: return
	paused = true
	status = "Connection lost — reconnecting…"
	if token.is_empty():
		active = false
		status = "Could not connect to relay."
		error.emit(status)
	else:
		if _lost_at == 0: _lost_at = Time.get_ticks_msec()
		_retry_at = Time.get_ticks_msec() + 2000
	changed.emit()

func _process(_delta: float) -> void:
	if _retry_at > 0 and Time.get_ticks_msec() >= _retry_at:
		_retry_at = 0
		if Time.get_ticks_msec() - _lost_at > 60000:
			_finish("Reconnection timed out. Round ended.")
			return
		_hello = {"type": "resume", "code": code, "token": token,
			"protocol": 1, "name": player_name, "fingerprint": fingerprint}
		transport.open(url)

func _receive(data: Dictionary) -> void:
	match String(data.get("type", "")):
		"welcome":
			seat = int(data.seat)
			code = String(data.code)
			token = String(data.token)
			_lost_at = 0
		"lobby":
			players = data.players
			paused = bool(data.paused)
			status = "Waiting for a player to reconnect (60 seconds)" if paused else "Connected · %s" % code
			changed.emit()
		"error":
			status = String(data.message)
			if token.is_empty():
				active = false
				transport.close()
			error.emit(status)
			changed.emit()
		"start":
			setup = data.setup
			players = data.players
			started = true
			paused = false
			round_started.emit()
		"intent": intent.emit(int(data.seat), data.command)
		"event": event.emit(data.event)
		"resync": resync.emit(int(data.seat))
		"ended": _finish(String(data.message))

func _finish(reason: String) -> void:
	leave()
	status = reason
	ended.emit(reason)
	changed.emit()

func leave() -> void:
	if transport != null:
		if active: transport.send({"type": "leave"})
		transport.close()
	active = false
	started = false
	paused = true
	seat = -1
	code = ""
	token = ""
	players = []
	setup = {}
	_retry_at = 0
	_lost_at = 0

func set_ready(value: bool) -> void:
	transport.send({"type": "ready", "ready": value})

func start_game(course_id: String, mulligans: int) -> void:
	if seat != 0: return
	var pars := {}
	for h in app.load_holes(course_id): pars[h.id] = h.par
	transport.send({"type": "start", "setup": {"course": course_id, "mulligans": mulligans,
		"seed": randi() & 0x7fffffff, "physics": app.settings.physics.to_dict(),
		"holeout": app.settings.holeout_radius_ft, "wind_custom": app.settings.wind_custom,
		"wind_speed": app.settings.wind_speed, "wind_bearing": app.settings.wind_bearing,
		"show_stats": app.settings.show_stats, "pars": pars}})

func send_intent(command: Dictionary) -> void:
	transport.send({"type": "intent", "command": command})

func send_event(data: Dictionary, target: int = -1) -> void:
	transport.send({"type": "event", "event": data, "target": target})

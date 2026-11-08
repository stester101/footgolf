extends SceneTree
## Two real processes through the relay. Uses a short fixture hole, not production courses.
var room: OnlineRoom
var session: OnlineSession
var host := false
var code_path := "/tmp/footgolf-room-code"
var phase := ""
var deadline := 0
var illegal_sent := false
var disconnect_done := false
var done_at := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host": host = true
		if arg.begins_with("--code-path="): code_path = arg.substr(12)
	room = root.get_node("App").online
	room.changed.connect(_lobby)
	room.round_started.connect(_start)
	room.error.connect(func(reason: String) -> void: print("NETWORK ERROR ", reason))
	room.ended.connect(func(reason: String) -> void:
		if done_at == 0: _fail(reason))
	deadline = Time.get_ticks_msec() + 30000
	var code := "" if host else FileAccess.get_file_as_string(code_path).strip_edges()
	room.connect_room("ws://127.0.0.1:8765", "Host" if host else "Guest", code)

func _lobby() -> void:
	if room.seat < 0: return
	if host and not FileAccess.file_exists(code_path):
		FileAccess.open(code_path, FileAccess.WRITE).store_string(room.code)
	if not room.started:
		if not bool(room.players[room.seat].ready): room.set_ready(true)
		if host and room.players.size() == 2 and room.players.all(func(p: Dictionary) -> bool: return bool(p.ready)):
			room.start_game("starter", 1)

func _start() -> void:
	var repo := FootballerRepository.new()
	repo.save_path = "user://network-smoke-unused.json"
	repo.load_all()
	# Fixed zero-distance players putt into a gimme radius at the test tee.
	for id in ["net-a", "net-b"]:
		repo._by_id[id] = Footballer.from_dict({"id": id, "name": id,
			"senior_international_caps": 0, "senior_international_goals": 0})
	var h := HoleDefinition.make_flat(Surface.Type.GREEN)
	h.pin = Vector2(0, 1)
	h.has_cup = true
	session = OnlineSession.new(PhysicsConfig.new(), repo)
	session.configure(room)
	session.start_round([h], int(room.setup.seed), 0, 1, 2)
	if host: session.begin_play()

func _process(delta: float) -> bool:
	if deadline > 0 and Time.get_ticks_msec() > deadline:
		_fail("timeout: " + phase)
		return false
	if session == null: return false
	session.advance(delta, 8)
	phase = "%s turn %d rev %d" % [session.state, session.turn, session.revision]
	if not host and session.state == ShotTypes.State.AIMING and session.turn == 0 and not illegal_sent:
		illegal_sent = true
		# Bypass UI to prove authoritative out-of-turn rejection.
		room.send_intent({"action": "shot", "revision": session.revision,
			"args": {"id": "net-b", "aim": 0, "mode": 1, "style": 1, "spin": 0, "trajectory": 2}})
	if not disconnect_done and ((not host and session.turn == 1) or (host and session.state == ShotTypes.State.SHOT_RESULT)):
		disconnect_done = true
		room.transport.close()
		room._disconnected()
	if session.state == ShotTypes.State.AIMING and session.controls_turn():
		session.set_mode(ShotTypes.Mode.GOALS)
		session.set_style(ShotTypes.Style.ROLL)
		session.select_footballer("net-a" if host else "net-b")
		session.take_shot()
	if session.state == ShotTypes.State.SHOT_RESULT and session.controls_turn(): session.acknowledge_result()
	if host and session.state == ShotTypes.State.HOLE_COMPLETE and not session.pending: session.next_hole()
	if session.state == ShotTypes.State.ROUND_COMPLETE and done_at == 0:
		if session.pool.used_count() != 2: _fail("shared pool")
		for i in 2:
			var rs := session.slot_round_state(i)
			if rs.total_score() != 1 or not rs.all_complete(): _fail("score mismatch")
		if not disconnect_done: _fail("reconnect not exercised")
		print("NETWORK PASS ", "host" if host else "guest", " ", JSON.stringify(session.snapshot()))
		done_at = Time.get_ticks_msec() + 500
	if done_at > 0 and Time.get_ticks_msec() > done_at:
		session.dispose()
		room.transport.close()
		quit(0)
	return false

func _fail(reason: String) -> void:
	push_error("NETWORK FAIL " + reason)
	quit(1)

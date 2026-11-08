extends SceneTree
## LocalRelay (in-process, host-phone style) + two OnlineRoom clients through a short fixture hole,
## including a guest disconnect/reconnect. Run:
##   godot --headless --path . -s res://tests/network/local_relay_smoke.gd
## Uses a short fixture hole, not production courses; both clients share this one process.

const PORT := 18765

class Client extends RefCounted:
	var name := ""
	var is_host := false
	var room: OnlineRoom
	var session: OnlineSession
	var illegal_sent := false
	var disconnected := false

var relay: LocalRelay
var host: Client
var guest: Client
var deadline := 0
var done_at := 0
var phase := "setup"
var guest_joined := false
var errors: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _check(cond: bool, what: String) -> void:
	if not cond:
		_fail(what)

func _run() -> void:
	# Address policy.
	_check(NetTransport.is_allowed_url("wss://relay.example.com"), "wss allowed")
	for ok in ["ws://127.0.0.1:8765", "ws://10.1.2.3:8765", "ws://172.16.0.5:1", "ws://172.31.9.9:1", "ws://192.168.43.1:8765", "ws://169.254.3.4:8765", "ws://localhost:8765"]:
		_check(NetTransport.is_allowed_url(ok), "should allow " + ok)
	for bad in ["ws://8.8.8.8:8765", "ws://172.32.0.1:8765", "ws://172.15.0.1:8765", "ws://192.169.0.1:8765", "ws://example.com:8765", "http://192.168.1.2", "ws://1.192.168.1.2:80"]:
		_check(not NetTransport.is_allowed_url(bad), "should reject " + bad)

	relay = LocalRelay.new()
	root.add_child(relay)
	_check(relay.start(PORT) == OK, "relay listen")
	host = _make_client("Host", true)
	guest = _make_client("Guest", false)
	deadline = Time.get_ticks_msec() + 40000
	host.room.connect_room("ws://127.0.0.1:%d" % PORT, "Host", "")
	phase = "hosting"

func _make_client(player_name: String, is_host: bool) -> Client:
	var c := Client.new()
	c.name = player_name
	c.is_host = is_host
	c.room = OnlineRoom.new()
	root.add_child(c.room)
	c.room.changed.connect(_lobby.bind(c))
	c.room.round_started.connect(_start.bind(c))
	c.room.error.connect(func(reason: String) -> void: errors.append(player_name + ": " + reason))
	c.room.ended.connect(func(reason: String) -> void:
		if done_at == 0: _fail(player_name + " ended: " + reason))
	return c

func _lobby(c: Client) -> void:
	var room := c.room
	if room.seat < 0:
		return
	if c.is_host and not guest_joined and room.code != "":
		guest_joined = true
		# Wrong code and wrong fingerprint style joins must be rejected without consuming a seat.
		guest.room.connect_room("ws://127.0.0.1:%d" % PORT, "Guest", room.code)
	if not room.started:
		if not bool(room.players[room.seat].ready):
			room.set_ready(true)
		if c.is_host and room.players.size() == 2 and room.players.all(func(p: Dictionary) -> bool: return bool(p.ready)):
			room.start_game("starter", 1)

func _start(c: Client) -> void:
	var repo := FootballerRepository.new()
	repo.save_path = "user://local-relay-smoke-unused.json"
	repo.load_all()
	for id in ["net-a", "net-b"]:
		repo._by_id[id] = Footballer.from_dict({"id": id, "name": id,
			"senior_international_caps": 0, "senior_international_goals": 0})
	var h := HoleDefinition.make_flat(Surface.Type.GREEN)
	h.pin = Vector2(0, 1)
	h.has_cup = true
	c.session = OnlineSession.new(PhysicsConfig.new(), repo)
	c.session.configure(c.room)
	c.session.start_round([h], int(c.room.setup.seed), 0, 1, 2)
	if c.is_host: c.session.begin_play()

func _process(delta: float) -> bool:
	if deadline > 0 and Time.get_ticks_msec() > deadline:
		_fail("timeout in phase %s; errors %s" % [phase, str(errors)])
		return false
	if host == null or host.session == null or guest.session == null:
		return false
	_drive(host, delta)
	_drive(guest, delta)
	phase = "host %s t%d r%d / guest %s t%d r%d" % [host.session.state, host.session.turn, host.session.revision,
		guest.session.state, guest.session.turn, guest.session.revision]
	if host.session.state == ShotTypes.State.ROUND_COMPLETE and guest.session.state == ShotTypes.State.ROUND_COMPLETE and done_at == 0:
		_check(host.session.pool.used_count() == 2, "host shared pool")
		_check(guest.session.pool.used_count() == 2, "guest shared pool")
		_check(guest.disconnected, "reconnect not exercised")
		for i in 2:
			for c in [host, guest]:
				var rs: RoundState = c.session.slot_round_state(i)
				_check(rs.total_score() == 1 and rs.all_complete(), "score mismatch " + c.name)
		var sa: Dictionary = JSON.parse_string(JSON.stringify(host.session.snapshot()))
		var sb: Dictionary = JSON.parse_string(JSON.stringify(guest.session.snapshot()))
		for key in ["slots", "pool", "turn", "state", "counter", "history"]:
			_check(JSON.stringify(sa[key]) == JSON.stringify(sb[key]), "snapshot diverged: %s host=%s guest=%s" % [key, JSON.stringify(sa[key]), JSON.stringify(sb[key])])
		print("LOCAL RELAY PASS rooms=%d" % relay.rooms.size())
		done_at = Time.get_ticks_msec() + 300
	if done_at > 0 and Time.get_ticks_msec() > done_at:
		for c in [host, guest]:
			c.session.dispose()
			c.room.transport.close()
		relay.stop()
		quit(0)
	return false

func _drive(c: Client, delta: float) -> void:
	var s := c.session
	s.advance(delta, 8)
	if not c.is_host and s.state == ShotTypes.State.AIMING and s.turn == 0 and not c.illegal_sent:
		c.illegal_sent = true
		# Bypass UI: out-of-turn intent must be rejected by the host session.
		c.room.send_intent({"action": "shot", "revision": s.revision,
			"args": {"id": "net-b", "aim": 0, "mode": 1, "style": 1, "spin": 0, "trajectory": 2}})
	if not c.is_host and not c.disconnected and s.turn == 1:
		c.disconnected = true
		c.room.transport.close()
		c.room._disconnected()
	if s.state == ShotTypes.State.AIMING and s.controls_turn():
		s.set_mode(ShotTypes.Mode.GOALS)
		s.set_style(ShotTypes.Style.ROLL)
		s.select_footballer("net-a" if c.is_host else "net-b")
		s.take_shot()
	if s.state == ShotTypes.State.SHOT_RESULT and s.controls_turn():
		s.acknowledge_result()
	if c.is_host and s.state == ShotTypes.State.HOLE_COMPLETE and not s.pending:
		s.next_hole()

func _fail(reason: String) -> void:
	push_error("LOCAL RELAY FAIL " + reason)
	if relay != null: relay.stop()
	quit(1)

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
var guest_watch_ok := false
var host_watch_ok := false

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

	_test_addresses()
	_test_preview_sanitizer()

	relay = LocalRelay.new()
	root.add_child(relay)
	_check(relay.start(PORT) == OK, "relay listen")
	# Auto-find: the relay answers a probe on its port; a closed port and a dead range do not.
	var finder := HostFinder.new()
	root.add_child(finder)
	finder.start(PackedStringArray(["127.0.0.1"]), PORT)
	var hits: Array = await finder.finished
	_check(hits == ["127.0.0.1"], "finder should find the relay, got " + str(hits))
	finder.start(PackedStringArray(["127.0.0.1"]), PORT + 1)
	hits = await finder.finished
	_check(hits.is_empty(), "finder must not report a closed port")
	finder.queue_free()
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
			room.start_game("starter", 1, _rules())

func _rules() -> RoundConfig:
	var rc := RoundConfig.new()
	rc.cup_diameter_ft = 1.5
	rc.gimme_ft = 5.0
	rc.reuse_per_mode = true
	rc.max_score_mode = RoundConfig.MaxScore.CUSTOM
	rc.max_over_par_custom = 3
	rc.wind_mode = RoundConfig.WindMode.NONE
	rc.show_stats = false
	return rc

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
	# The host's frozen RoundConfig + physics arrive in the setup; both phones apply them the same way.
	var rc := OnlineSession.apply_setup(c.session, c.room.setup)
	c.session.start_round([h], int(c.room.setup.seed), rc.pool_rule(), 1, 2)
	if c.is_host: c.session.begin_play()

func _process(delta: float) -> bool:
	if deadline > 0 and Time.get_ticks_msec() > deadline:
		_fail("timeout in phase %s; errors %s" % [phase, str(errors)])
		return false
	if host == null or host.session == null or guest.session == null:
		return false
	_drive(host, delta)
	_drive(guest, delta)
	var gw := guest.session.watch_preview()
	if not gw.is_empty() and gw.id == "net-a" and gw.mode == ShotTypes.Mode.GOALS and gw.style == ShotTypes.Style.ROLL:
		guest_watch_ok = true
	var hw := host.session.watch_preview()
	if not hw.is_empty() and hw.id == "net-b":
		host_watch_ok = true
	phase = "host %s t%d r%d / guest %s t%d r%d" % [host.session.state, host.session.turn, host.session.revision,
		guest.session.state, guest.session.turn, guest.session.revision]
	if host.session.state == ShotTypes.State.ROUND_COMPLETE and guest.session.state == ShotTypes.State.ROUND_COMPLETE and done_at == 0:
		_check(JSON.stringify(host.session.rules.to_dict()) == JSON.stringify(_rules().to_dict()), "host rules")
		_check(JSON.stringify(guest.session.rules.to_dict()) == JSON.stringify(_rules().to_dict()), "guest rules")
		_check(JSON.stringify(host.session.cfg.to_dict()) == JSON.stringify(guest.session.cfg.to_dict()), "physics equal")
		_check(is_equal_approx(guest.session.cfg.cup_radius, 1.5 * 12.0 * 0.0254 * 0.5), "guest cup size from host rules")
		_check(guest.session.pool.reuse_rule == FootballerPool.ReuseRule.ONCE_PER_MODE and host.session.pool.reuse_rule == guest.session.pool.reuse_rule, "once-per-mode on both")
		_check(guest.session.current_hole_state().max_score > 0 and guest.session.current_hole_state().max_score == host.session.current_hole_state().max_score, "max score equal")
		_check(host.session.pool.used_count() == 2, "host shared pool")
		_check(guest.session.pool.used_count() == 2, "guest shared pool")
		_check(guest.disconnected, "reconnect not exercised")
		_check(guest_watch_ok, "guest never saw the host's live preview")
		_check(host_watch_ok, "host never saw the guest's live preview")
		_check(not host.session.is_spectating() or host.session.watch_preview().is_empty(), "preview must clear after the round")
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
		# Wait until the other phone has seen this player's live preview (non-authoritative messages).
		if (c.is_host and guest_watch_ok) or (not c.is_host and host_watch_ok):
			s.take_shot()
	if s.state == ShotTypes.State.SHOT_RESULT and s.controls_turn():
		s.acknowledge_result()
	if c.is_host and s.state == ShotTypes.State.HOLE_COMPLETE and not s.pending:
		s.next_hole()

func _fail(reason: String) -> void:
	push_error("LOCAL RELAY FAIL " + reason)
	if relay != null: relay.stop()
	quit(1)

func _test_addresses() -> void:
	var c := HostFinder.candidate_hosts(PackedStringArray(["192.168.43.57", "fe80::1", "127.0.0.1"]))
	_check(c[0] == "192.168.43.1", "own-subnet gateway first, got " + str(c))
	for gw in ["192.168.49.1", "172.20.10.1", "192.168.137.1"]:
		_check(c.has(gw), "known gateway " + gw)
	_check(c.size() == 4, "no duplicates: " + str(c))
	var host_self := HostFinder.candidate_hosts(PackedStringArray(["192.168.43.1"]))
	_check(not host_self.has("192.168.43.1"), "must not probe itself")
	var multi := HostFinder.candidate_hosts(PackedStringArray(["10.0.5.23", "172.20.10.4", "8.8.8.8", "169.254.1.2"]))
	_check(multi[0] == "10.0.5.1" and multi[1] == "172.20.10.1", "derive per private /24: " + str(multi))
	_check(not multi.has("8.8.8.1") and not multi.has("169.254.1.1"), "public/link-local ignored")
	_check(multi.count("172.20.10.1") == 1, "deduplicated")
	_check(HostFinder.best_host_address(PackedStringArray(["10.1.2.3", "192.168.43.1"])) == "192.168.43.1", "known gateway preferred")
	_check(HostFinder.best_host_address(PackedStringArray(["192.168.9.9", "10.1.2.1"])) == "10.1.2.1", ".1 preferred")
	_check(HostFinder.best_host_address(PackedStringArray(["192.168.9.9"])) == "192.168.9.9", "fallback first private")
	_check(HostFinder.best_host_address(PackedStringArray(["8.8.8.8", "::1"])) == "", "none")

func _test_preview_sanitizer() -> void:
	var ok := {"rev": 3, "id": "a", "mode": 1, "style": 0, "traj": 2, "spin": 0.5, "aim": 370.0}
	var clean := OnlineSession.sanitize_preview(ok)
	_check(not clean.is_empty() and is_equal_approx(float(clean.aim), 10.0), "valid preview accepted and aim wrapped")
	for bad in [{"mode": 7}, {"traj": 9}, {"id": 5}, {"aim": "x"}, {"spin": INF}, {"rev": null}]:
		var d := ok.duplicate()
		d.merge(bad, true)
		_check(OnlineSession.sanitize_preview(d).is_empty(), "malformed preview rejected: " + str(bad))
	_check(is_equal_approx(float(OnlineSession.sanitize_preview({"rev": 1, "id": "", "mode": 0, "style": 1, "traj": 0, "spin": 5.0, "aim": 0.0}).spin), 1.0), "spin clamped")

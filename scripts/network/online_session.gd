class_name OnlineSession
extends GameSession
## Host commits all gameplay. Client sessions are read-only mirrors with local previews.
var room: OnlineRoom
var revision := 0
var pending := false
var _applying := false
var _pending_ms := 0  # when the current request was sent; a reply that never arrives must not lock this phone forever
var _host := false
var _remote_mulligan_available := false
## Live view of the active player's pre-shot choices (spectators only). Cosmetic and non-authoritative:
## never read by any rule, never saved in snapshots, ignored when stale or out of turn.
const PREVIEW_INTERVAL_MS := 220
const PREVIEW_HEARTBEAT_MS := 1500
const PREVIEW_STALE_MS := 5000
var _preview := {}
var _preview_at := 0
var _sent_preview := {}
var _sent_at := 0

## "Refresh" button: the host re-sends the state to every guest; a guest asks the host to re-send it.
func refresh_state() -> void:
	if room == null or not room.active:
		return
	if _host:
		for s in range(1, room.players.size()):
			_on_resync(s)
	else:
		room.request_resync()
	message.emit("Refreshing...")


## Applies the host's frozen setup dictionary to a session (identically on every phone) and returns the
## decoded RoundConfig. Call before start_round; use rules.pool_rule() for the footballer reuse rule.
static func apply_setup(net: GameSession, setup: Dictionary) -> RoundConfig:
	var rc: RoundConfig
	if setup.get("rules") is Dictionary:
		rc = RoundConfig.from_dict(setup.rules)
	else:  # setup from an older host build
		rc = RoundConfig.new()
		rc.show_stats = bool(setup.get("show_stats", false))
		rc.gimme_ft = ScoringService.clamp_radius_ft(float(setup.get("holeout", rc.gimme_ft)))
	if setup.get("physics") is Dictionary:
		net.cfg.apply_dict(setup.physics)
	net.apply_rules(rc)  # gimme, wind multiplier, cup size (cup also arrives in the physics dict)
	net.wind_custom = bool(setup.get("wind_custom", false))
	net.wind_custom_speed = float(setup.get("wind_speed", net.wind_custom_speed))
	net.wind_custom_bearing = float(setup.get("wind_bearing", net.wind_custom_bearing))
	return rc


func configure(value: OnlineRoom) -> void:
	room = value
	_host = room.seat == 0
	room.intent.connect(_on_intent)
	room.event.connect(_on_event)
	room.resync.connect(_on_resync)
	room.preview.connect(_on_preview)
	room.error.connect(func(text: String) -> void:
		pending = false
		message.emit(text))
	room.changed.connect(func() -> void:
		if _host and not room.paused: pending = false
		selection_changed.emit())

func dispose() -> void:
	# Lambda connections capture the session; disconnect all connections owned by this session.
	for sig in [room.intent, room.event, room.resync, room.preview, room.error, room.changed]:
		for connection in sig.get_connections():
			if connection.callable.get_object() == self:
				sig.disconnect(connection.callable)

## Guest's own pre-pick (local, never sent): survives host updates while it is still available.
var _preselect := ""


func select_footballer(id: String) -> bool:
	var ok := super.select_footballer(id)
	if ok and not _host:
		_preselect = id
	return ok


func clear_selection() -> void:
	_preselect = ""
	super.clear_selection()


func controls_turn() -> bool:
	return room != null and room.active and not room.paused and not pending and room.seat == turn

func can_take_shot() -> String:
	if not _applying and not controls_turn():
		return "Waiting for connection" if room.paused else "Waiting for %s" % active_name()
	return super.can_take_shot()

func _request(action: String, args: Dictionary = {}) -> bool:
	if room.paused or pending or not room.active: return false
	var owner := 0 if action in ["begin", "next"] else turn
	if room.seat != owner:
		message.emit("Waiting for host" if owner == 0 else "Waiting for %s" % active_name())
		return false
	pending = true
	_pending_ms = Time.get_ticks_msec()
	room.send_intent({"action": action, "revision": revision, "args": args})
	return true

func take_shot() -> bool:
	if _applying: return super.take_shot()
	if can_take_shot() != "":
		message.emit(can_take_shot())
		return false
	return _request("shot", {"id": selected_id, "aim": aim_bearing_deg,
		"mode": mode, "style": style, "spin": spin, "trajectory": trajectory})

func begin_play() -> void:
	if _applying:
		super.begin_play()
	elif _host:
		# The host is the authority: apply Tee off locally and broadcast, with no relay round trip that can be
		# dropped (that left the host on the overhead intro with no button left to press).
		if state == ShotTypes.State.HOLE_INTRO and room != null and room.active and not room.paused:
			super.begin_play()
			revision += 1
			room.send_event({"kind": "state", "snapshot": snapshot()})
	else:
		_request("begin")

func acknowledge_result() -> void:
	if _applying: super.acknowledge_result()
	else: _request("ack")

func next_hole() -> void:
	if _applying: super.next_hole()
	else: _request("next")

func use_mulligan() -> bool:
	if _applying: return super.use_mulligan()
	return _request("mulligan")

func can_mulligan() -> bool:
	return (_applying or controls_turn()) and (super.can_mulligan() if _host else _remote_mulligan_available)

## Every frame: if a request got no answer for 4 s (dropped or ignored reply) release the lock and ask for the
## state again, the same recovery as leaving to the menu and coming back.
func advance(delta: float, speed_mult: float = 1.0) -> void:
	if pending and room != null and room.active and Time.get_ticks_msec() - _pending_ms > 4000:
		pending = false
		refresh_state()
		selection_changed.emit()
	if room.paused: return
	super.advance(delta, speed_mult)
	_send_preview()

func skip_motion() -> void:
	# Local skip only speeds up animation; the host still decides the result.
	if not room.paused: super.skip_motion()

func _resolve() -> void:
	if _host:
		super._resolve()
		revision += 1
		room.send_event({"kind": "state", "snapshot": snapshot()})
	else:
		# Hold the rendered resting position until the authoritative result arrives.
		ball_pos = sim.pos
		sim = null

func _on_intent(seat: int, command: Dictionary) -> void:
	if not _host: return
	var action := String(command.get("action", ""))
	var owner := 0 if action in ["begin", "next"] else turn
	if room.paused or seat != owner or int(command.get("revision", -1)) != revision:
		_reject(seat, "Turn changed or connection paused. Try again.")
		return
	var valid := false
	_applying = true
	match action:
		"begin":
			valid = state == ShotTypes.State.HOLE_INTRO
			if valid: super.begin_play()
		"next":
			valid = state == ShotTypes.State.HOLE_COMPLETE
			if valid: super.next_hole()
		"ack":
			valid = state == ShotTypes.State.SHOT_RESULT
			if valid: super.acknowledge_result()
		"mulligan": valid = super.use_mulligan()
		"shot":
			var a = command.get("args", {})
			if a is Dictionary and _valid_shot_args(a) and state == ShotTypes.State.AIMING:
				set_mode(int(a.mode))
				set_style(int(a.style))
				set_trajectory(int(a.trajectory))
				set_spin(float(a.spin))
				set_aim(float(a.aim))
				# Never retain the host's previous selection when the requested player is unavailable.
				clear_selection()
				if select_footballer(String(a.id)): valid = super.take_shot()
	_applying = false
	pending = false
	if not valid:
		_reject(seat, "Action rejected; no stroke or footballer was consumed.")
		return
	revision += 1
	room.send_event({"kind": "shot" if action == "shot" else "state", "snapshot": snapshot()})

func _valid_shot_args(a: Dictionary) -> bool:
	for key in ["aim", "mode", "style", "spin", "trajectory"]:
		if not (a.get(key) is float or a.get(key) is int): return false
		if not is_finite(float(a[key])): return false
	return a.get("id") is String and int(a.mode) in [0, 1] and int(a.style) in [0, 1] \
		and int(a.trajectory) in [0, 1, 2, 3] and absf(float(a.spin)) <= 1.0

func _reject(seat: int, reason: String) -> void:
	if seat == room.seat:
		pending = false
		message.emit(reason)
	else:
		room.send_event({"kind": "rejected", "message": reason}, seat)

func _on_resync(seat: int) -> void:
	if _host:
		room.send_event({"kind": "shot" if is_ball_moving() else "state", "snapshot": snapshot(), "resync": true}, -1 if seat == 0 else seat)

func _on_event(data: Dictionary) -> void:
	if _host: return
	if data.get("kind") == "rejected":
		pending = false
		message.emit(String(data.get("message", "Action rejected")))
		return
	var snap = data.get("snapshot")
	if not snap is Dictionary: return
	if int(snap.get("revision", -1)) <= revision and not bool(data.get("resync", false)): return
	apply_snapshot(snap, data.get("kind") == "shot")

func snapshot() -> Dictionary:
	_save_active()
	var saved: Array = []
	for sl in slots:
		saved.append({"round": NetCodec.encode(sl.round_state), "ball": NetCodec.encode(sl.ball_pos),
			"safe": NetCodec.encode(sl.last_safe_pos), "aim": sl.aim})
	return {"revision": revision, "mulligan_available": super.can_mulligan(), "slots": saved, "turn": turn, "state": state,
		"pool": pool.snapshot(), "counter": shot_counter, "version": state_version,
		"history": NetCodec.encode(history), "last_result": NetCodec.encode(last_result),
		"last_request": NetCodec.encode(last_request), "request": NetCodec.encode(current_request),
		"mode": mode, "style": style, "spin": spin, "trajectory": trajectory,
		"selected": selected_id, "replacement": _next_is_replacement}

func apply_snapshot(data: Dictionary, animate: bool) -> void:
	var old_hole := round_state.current_index
	var old_state := state
	revision = int(data.revision)
	_remote_mulligan_available = bool(data.get("mulligan_available", false))
	pending = false
	var saved: Array = data.slots
	for i in saved.size():
		var sl: PlayerSlot = slots[i]
		sl.round_state = NetCodec.decode(saved[i].round)
		sl.ball_pos = NetCodec.decode(saved[i].ball)
		sl.last_safe_pos = NetCodec.decode(saved[i].safe)
		sl.aim = float(saved[i].aim)
	_switch_to(int(data.turn))
	hole = hole_defs[round_state.current_index]
	pool.restore(data.pool)
	shot_counter = int(data.counter)
	state_version = int(data.version)
	history = NetCodec.decode(data.history)
	last_result = NetCodec.decode(data.last_result)
	last_request = NetCodec.decode(data.last_request)
	current_request = NetCodec.decode(data.request)
	mode = int(data.mode)
	style = int(data.style)
	spin = float(data.spin)
	trajectory = int(data.trajectory)
	# The host's selection belongs to the active player. A guest keeps its own pre-pick across updates: it stays
	# selected while the footballer is still free, and is dropped (the player re-picks) once someone else uses them.
	selected_id = String(data.selected) if _host else ""
	if not _host and _preselect != "" and repo.has(_preselect) and pool.is_available(_preselect, mode):
		selected_id = _preselect
	elif not _host:
		_preselect = ""
	_next_is_replacement = bool(data.replacement)
	sim = null
	if old_hole != round_state.current_index:
		hole_started.emit(round_state.current_index)
	if animate and current_request != null:
		var fb := repo.get_by_id(current_request.footballer_id)
		var plan := _plan_shot(current_request, fb.caps, fb.goals)
		plan["footballer"] = fb.copy()
		plan["replacement"] = false
		_launch(current_request, plan)
	else:
		_set_state(int(data.state))
		if state == ShotTypes.State.SHOT_RESULT and last_result != null:
			shot_resolved.emit(last_result)
		if state == ShotTypes.State.HOLE_COMPLETE and old_state != state:
			hole_completed.emit(current_hole_state())
		if state == ShotTypes.State.ROUND_COMPLETE and old_state != state:
			round_completed.emit()
	ball_placed.emit()
	selection_changed.emit()

# ---- live aim preview (non-authoritative)

## What the active player is choosing right now. Pure so it can be unit-tested.
func preview_payload() -> Dictionary:
	return {"rev": revision, "id": selected_id, "mode": mode, "style": style,
		"traj": trajectory, "spin": spin, "aim": aim_bearing_deg}

func _send_preview() -> void:
	if state != ShotTypes.State.AIMING or not controls_turn():
		_sent_preview = {}
		return
	var now := Time.get_ticks_msec()
	var payload := preview_payload()
	var changed := JSON.stringify(payload) != JSON.stringify(_sent_preview)
	if (changed and now - _sent_at >= PREVIEW_INTERVAL_MS) or now - _sent_at >= PREVIEW_HEARTBEAT_MS:
		_sent_preview = payload
		_sent_at = now
		room.send_preview(payload)

## Returns a clean preview or {} when the data is malformed.
static func sanitize_preview(d: Dictionary) -> Dictionary:
	for key in ["rev", "mode", "style", "traj", "spin", "aim"]:
		if not (d.get(key) is float or d.get(key) is int) or not is_finite(float(d[key])):
			return {}
	if not d.get("id") is String or String(d.id).length() > 80:
		return {}
	var out := {"rev": int(d.rev), "id": String(d.id), "mode": int(d.mode), "style": int(d.style),
		"traj": int(d.traj), "spin": clampf(float(d.spin), -1.0, 1.0), "aim": fposmod(float(d.aim), 360.0)}
	if not (out.mode in [0, 1] and out.style in [0, 1] and out.traj in [0, 1, 2, 3]):
		return {}
	return out

func _on_preview(seat: int, data: Dictionary) -> void:
	if seat != turn or seat == room.seat:
		return
	var clean := sanitize_preview(data)
	if clean.is_empty() or int(clean.rev) != revision:
		return
	_preview = clean
	_preview_at = Time.get_ticks_msec()
	selection_changed.emit()  # UI refresh only

## The active player's current choices as seen by a waiting phone, or {} (not waiting, stale, or out of turn).
func watch_preview() -> Dictionary:
	if _preview.is_empty() or state != ShotTypes.State.AIMING or not is_spectating():
		return {}
	if int(_preview.rev) != revision or Time.get_ticks_msec() - _preview_at > PREVIEW_STALE_MS:
		return {}
	return _preview

## True on a phone that is watching somebody else's turn.
func is_spectating() -> bool:
	return room != null and room.active and room.seat >= 0 and room.seat != turn

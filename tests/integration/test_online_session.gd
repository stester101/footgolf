extends TestCase

class FakeRoom extends OnlineRoom:
	var events: Array = []
	func send_event(data: Dictionary, target: int = -1) -> void:
		events.append({"data": data, "target": target})

func test_online_authority_duplicate_pool_and_mulligan() -> void:
	var host_room := FakeRoom.new()
	host_room.seat = 0
	host_room.active = true
	host_room.paused = false
	var guest_room := FakeRoom.new()
	guest_room.seat = 1
	guest_room.active = true
	guest_room.paused = false
	var repo := TestHelpers.make_repo()
	var host := OnlineSession.new(PhysicsConfig.new(), repo)
	var guest := OnlineSession.new(PhysicsConfig.new(), repo)
	host.configure(host_room)
	guest.configure(guest_room)
	var hole := HoleDefinition.make_flat(Surface.Type.FAIRWAY)
	hole.pin = Vector2(0, 100)
	host.start_round([hole], 12345, 0, 1, 2)
	guest.start_round([hole], 12345, 0, 1, 2)
	host._on_intent(0, {"action": "begin", "revision": host.revision})
	var args := {"id": "fb-001", "aim": 0.0, "mode": 1, "style": 1, "spin": 0, "trajectory": 2}
	var command := {"action": "shot", "revision": host.revision, "args": args}
	host._on_intent(1, command)
	assert_eq(host.pool.used_count(), 0, "out of turn consumes nothing")
	host._on_intent(0, command)
	host._on_intent(0, command)
	assert_eq(host.current_hole_state().strokes, 1, "duplicate commits only once")
	assert_eq(host.pool.used_count(), 1)
	host.skip_motion()
	host._on_intent(0, {"action": "ack", "revision": host.revision})
	assert_eq(host.turn, 1)
	host._on_intent(1, {"action": "shot", "revision": host.revision, "args": args})
	assert_eq(host.current_hole_state().strokes, 0, "spent player rejected")
	args = args.duplicate()
	args.id = "fb-002"
	host._on_intent(1, {"action": "shot", "revision": host.revision, "args": args})
	host.skip_motion()
	var wire: Dictionary = JSON.parse_string(JSON.stringify(host.snapshot()))
	guest.apply_snapshot(wire, false)
	assert_true(guest.can_mulligan(), "guest sees own mulligan allowance")
	assert_eq(guest.pool.used_count(), 2)
	host._on_intent(1, {"action": "mulligan", "revision": host.revision})
	assert_eq(host.current_hole_state().strokes, 0, "mulligan restores stroke")
	assert_eq(host.pool.used_count(), 2, "mulligan keeps footballer consumed")
	guest.apply_snapshot(JSON.parse_string(JSON.stringify(host.snapshot())), false)
	assert_eq(guest.current_hole_state().strokes, 0)
	assert_eq(guest.round_state.mulligans_used, 1)
	assert_eq(guest.round_state.mulligan_audit.size(), 1)
	assert_false(guest.can_mulligan())
	host_room.paused = true
	args.id = "fb-003"
	host._on_intent(1, {"action": "shot", "revision": host.revision, "args": args})
	assert_eq(host.pool.used_count(), 2, "paused round cannot consume")
	host.dispose()
	guest.dispose()
	host_room.free()
	guest_room.free()
	TestHelpers.cleanup_repo(repo)

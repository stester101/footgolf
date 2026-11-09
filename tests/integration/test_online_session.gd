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


## The host's RoundConfig + physics travel through JSON; two phones end with identical rules.
func test_online_setup_freezes_round_config_and_physics() -> void:
	var rc := RoundConfig.new()
	rc.cup_diameter_ft = 2.5
	rc.gimme_ft = 3.5
	rc.reuse_per_mode = true
	rc.wind_mode = RoundConfig.WindMode.SCALED
	rc.wind_scale = 0.5
	rc.max_score_mode = RoundConfig.MaxScore.CUSTOM
	rc.max_over_par_custom = 2
	rc.show_aim_arrow = false
	rc.show_trail = false
	rc.lie_exact = true
	rc.show_stats = false
	var host_cfg := PhysicsConfig.new()
	host_cfg.cup_wall_restitution = 0.37
	host_cfg.pin_restitution = 0.21
	host_cfg.cup_floor_restitution = 0.33
	host_cfg.cup_depth_min = 0.12
	host_cfg.set_cup_diameter_in(rc.cup_diameter_ft * 12.0)
	var setup: Dictionary = JSON.parse_string(JSON.stringify({"physics": host_cfg.to_dict(), "rules": rc.to_dict(),
		"wind_custom": false, "wind_speed": 0.0, "wind_bearing": 0.0}))
	var repo := TestHelpers.make_repo()
	for i in 2:
		var s := OnlineSession.new(PhysicsConfig.new(), repo)
		var got := OnlineSession.apply_setup(s, setup)
		assert_eq(JSON.stringify(got.to_dict()), JSON.stringify(rc.to_dict()), "rules decode identically")
		assert_eq(JSON.stringify(s.cfg.to_dict()), JSON.stringify(host_cfg.to_dict()), "physics decode identically")
		assert_true(is_equal_approx(s.cfg.cup_wall_restitution, 0.37), "cup_wall_restitution travels")
		assert_true(is_equal_approx(s.cfg.cup_radius, 2.5 * 12.0 * 0.0254 * 0.5), "cup size from rules")
		assert_true(is_equal_approx(s.holeout_radius_ft, 3.5))
		assert_true(is_equal_approx(s.wind_scale, 0.5))
		var hole := HoleDefinition.make_flat(Surface.Type.FAIRWAY)
		hole.par = 3
		s.start_round([hole], 7, got.pool_rule(), 0, 2)
		assert_eq(s.pool.reuse_rule, FootballerPool.ReuseRule.ONCE_PER_MODE)
		assert_eq(s.current_hole_state().max_score, 5, "par 3 + 2")
		assert_false(s.rules.show_stats)
		assert_true(s.rules.lie_exact)
	TestHelpers.cleanup_repo(repo)

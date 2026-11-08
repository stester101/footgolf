extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var app: Node = root.get_node("App")
	app.settings.tutorial_seen = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main._menu._open_online()
	await process_frame
	assert(main._menu._stack.size() == 2)
	var room: OnlineRoom = app.online
	room.active = true
	room.seat = 0
	room.code = "TEST42"
	room.players = [{"name": "Host", "ready": true, "connected": true}, {"name": "Guest", "ready": true, "connected": true}]
	room.paused = false
	main._menu._open_online_lobby()
	await process_frame
	assert(main._menu._stack.size() == 3)
	room.setup = {"course": "starter", "mulligans": 1, "seed": 1234,
		"physics": app.settings.physics.to_dict(), "holeout": 5, "wind_custom": false,
		"wind_speed": 0, "wind_bearing": 0, "show_stats": false, "pars": {}}
	room.started = true
	room.round_started.emit()
	await process_frame
	assert(main._round.session is OnlineSession)
	assert(main._round.session.player_count() == 2)
	assert(main._round.session.player_names[1] == "Guest")
	main._round.session._on_intent(0, {"action": "begin", "revision": 0})
	await process_frame
	assert(not main._round.ui.has_overlay())
	main.show_menu()
	await process_frame
	main.start_round("starter", false, 0, 2)
	await process_frame
	assert(not main._round.session is OnlineSession)
	assert(main._round.session.player_count() == 2)
	main.show_menu()
	await process_frame
	main.start_round("starter", false, 0, 1)
	await process_frame
	assert(not main._round.session is OnlineSession)
	assert(main._round.session.player_count() == 1)
	main.queue_free()
	await process_frame
	print("UI PASS — connection page, lobby, online start, offline pass-and-play and solo start")
	quit(0)

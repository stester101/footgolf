extends SceneTree
## Monte-Carlo hole calibration: bots with different "football knowledge" play holes on the real
## physics and the real footballer database. Used to choose hole lengths per par.
##   godot --headless --path . -s res://tools/scripts/sim_holes.gd -- --holes=a.json,b.json --n=100 --seed=1
## Strategies (all aim at the pin, Goals within --goal_ft of it or on the green, otherwise Caps):
##   random : a random available player each shot (no knowledge)
##   best3  : best of 3 random candidates for the distance needed (a little knowledge)
##   best10 : best of 10 random candidates (good knowledge)
##   oracle : the single best available player (perfect knowledge, upper bound)
## Output: one JSON line per (hole, strategy) with mean strokes, histogram, mean caps/goals shots.

var _repo: FootballerRepository
var _players: Array[Footballer] = []
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	var holes: PackedStringArray = []
	var n := 100
	var seed_v := 1
	var goal_ft := 15.0
	var strategies := ["random", "best3", "best10", "oracle"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--holes="):
			holes = a.substr(8).split(",")
		elif a.begins_with("--n="):
			n = int(a.substr(4))
		elif a.begins_with("--seed="):
			seed_v = int(a.substr(7))
		elif a.begins_with("--goal_ft="):
			goal_ft = float(a.substr(10))
		elif a.begins_with("--strategies="):
			strategies = a.substr(13).split(",")
	_repo = FootballerRepository.new()
	_repo.seed_path = FootballerRepository.REAL_PATH
	_repo.save_path = "user://sim_none.json"
	_repo.load_all()
	_players = _repo.all_sorted()
	var cfg := PhysicsConfig.new()
	for path in holes:
		var hole := HoleDefinition.load_from_file(path)
		if hole == null:
			continue
		for strat in strategies:
			_rng.seed = seed_v * 7919 + hash(path + strat)
			var strokes: Array[int] = []
			var caps_shots := 0
			var goal_shots := 0
			var penalties := 0
			var holed := 0
			for i in n:
				var s := GameSession.new(cfg, _repo)
				s.start_round([hole], i + 1)
				s.begin_play()
				s.wind_custom = true
				s.wind_custom_speed = 0.0
				var guard := 40
				while s.state == ShotTypes.State.AIMING and guard > 0:
					guard -= 1
					s.aim_at_pin()
					var d_ft := Units.m_to_feet(s.distance_to_pin_m())
					var use_goals := s.current_lie() == Surface.Type.GREEN or d_ft <= goal_ft
					var mode := ShotTypes.Mode.GOALS if use_goals else ShotTypes.Mode.CAPS
					var need := d_ft if use_goals else Units.m_to_yards(s.distance_to_pin_m())
					var fb := _choose(s, strat, use_goals, need)
					s.set_mode(mode)
					s.select_footballer(fb.id)
					if not s.take_shot():
						break
					s.skip_motion()
					if use_goals:
						goal_shots += 1
					else:
						caps_shots += 1
					s.acknowledge_result()
				var hs := s.current_hole_state()
				strokes.append(hs.score())
				penalties += hs.penalties
				if hs.completion == ShotTypes.COMPLETION_HOLED:
					holed += 1
			var mean := 0.0
			var hist := {}
			for k in strokes:
				mean += k
				hist[str(k)] = int(hist.get(str(k), 0)) + 1
			mean /= float(maxi(strokes.size(), 1))
			print(JSON.stringify({"hole": path.get_file(), "par": hole.par, "yards": hole.yards, "strategy": strat, "n": n,
				"mean_strokes": snappedf(mean, 0.01), "vs_par": snappedf(mean - hole.par, 0.01),
				"holed_pct": snappedf(100.0 * holed / n, 0.1), "max_score_pct": snappedf(100.0 * (n - holed) / n, 0.1),
				"caps_shots": snappedf(float(caps_shots) / n, 0.01), "goal_shots": snappedf(float(goal_shots) / n, 0.01),
				"penalties": snappedf(float(penalties) / n, 0.01), "hist": hist}))
	quit()


func _choose(s: GameSession, strat: String, goals: bool, need: float) -> Footballer:
	var k := 1
	match strat:
		"best3":
			k = 3
		"best10":
			k = 10
		"oracle":
			k = 0
	var best: Footballer = null
	var best_err := INF
	if k == 0:
		for fb in _players:
			if not s.pool.is_available(fb.id):
				continue
			var err := absf(float(fb.goals if goals else fb.caps) - need)
			if err < best_err:
				best_err = err
				best = fb
		return best
	var tries := 0
	var got := 0
	while got < k and tries < 200:
		tries += 1
		var fb: Footballer = _players[_rng.randi() % _players.size()]
		if not s.pool.is_available(fb.id):
			continue
		got += 1
		var err2 := absf(float(fb.goals if goals else fb.caps) - need)
		if err2 < best_err:
			best_err = err2
			best = fb
	return best

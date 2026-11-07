class_name TestHelpers
extends RefCounted

const HOLE_PATHS := ["res://data/holes/hole_01.json", "res://data/holes/hole_02.json", "res://data/holes/hole_03.json"]
const RIDGE_PATHS := ["res://data/holes/hole_04.json", "res://data/holes/hole_05.json", "res://data/holes/hole_06.json",
	"res://data/holes/hole_07.json", "res://data/holes/hole_08.json", "res://data/holes/hole_09.json"]


static func make_repo() -> FootballerRepository:
	var repo := FootballerRepository.new()
	repo.save_path = "user://test_footballers_%d.json" % (randi() % 1000000)
	if FileAccess.file_exists(repo.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(repo.save_path))
	repo.load_all()
	return repo


static func cleanup_repo(repo: FootballerRepository) -> void:
	if FileAccess.file_exists(repo.save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(repo.save_path))


static func load_holes() -> Array:
	var out: Array = []
	for p in HOLE_PATHS:
		out.append(HoleDefinition.load_from_file(p))
	return out


static func load_ridge_holes() -> Array:
	var out: Array = []
	for p in RIDGE_PATHS:
		out.append(HoleDefinition.load_from_file(p))
	return out


static func make_session(defs: Array = []) -> GameSession:
	var s := GameSession.new(PhysicsConfig.new(), make_repo())
	s.start_round(defs if not defs.is_empty() else load_holes(), 12345)
	s.begin_play()
	return s


## Add a dev footballer with explicit stats and return its id.
static func add_player(repo: FootballerRepository, caps: int, goals: int) -> String:
	var id := repo.new_id()
	var err := repo.add_record({"id": id, "name": "Probe %s" % id, "nationality": "Test",
		"senior_international_caps": caps, "senior_international_goals": goals})
	assert(err == "", err)
	return id


static func shoot(s: GameSession, mode: int, caps: int, goals: int, bearing: float = -999.0) -> ShotResult:
	var id := add_player(s.repo, caps, goals)
	s.set_mode(mode)
	if bearing > -900.0:
		s.set_aim(bearing)
	if not s.select_footballer(id):
		return null
	if not s.take_shot():
		return null
	s.skip_motion()
	var r := s.last_result
	s.acknowledge_result()
	return r


## Greedy bot shot used by round-completion tests: aim at pin, Caps when far, Goals when near.
## If the ball made no progress (blocked by trees / relief at the same spot), it tries escape
## angles and ground shots like a real player would, since there is no maximum score.
static func bot_shot(s: GameSession, stuck: int, caps_far_m: float = 25.0) -> ShotResult:
	var d := s.distance_to_pin_m()
	s.aim_at_pin()
	if stuck > 0:
		var offs := [35.0, -35.0, 70.0, -70.0, 100.0, -100.0, 15.0, -15.0]
		s.set_aim(s.aim_bearing_deg + float(offs[(stuck - 1) % offs.size()]))
		if stuck % 2 == 0:
			return shoot(s, ShotTypes.Mode.GOALS, 0, int(Units.m_to_feet(minf(d, 40.0))))
		return shoot(s, ShotTypes.Mode.CAPS, int(Units.m_to_yards(minf(d * 0.5, 80.0))), 0)
	if s.current_lie() == Surface.Type.GREEN or d <= caps_far_m:
		return shoot(s, ShotTypes.Mode.GOALS, 0, maxi(1, int(Units.m_to_feet(d))))
	return shoot(s, ShotTypes.Mode.CAPS, int(Units.m_to_yards(minf(d, 200.0)) * 0.9), 0)


## Plays a whole round with bot_shot. Returns true when the round completes within the guard.
static func bot_round(s: GameSession, guard: int = 4000) -> bool:
	var stuck := 0
	var last := Vector3.INF
	while not s.is_round_complete() and guard > 0:
		guard -= 1
		match s.state:
			ShotTypes.State.HOLE_INTRO:
				s.begin_play()
				stuck = 0
				last = Vector3.INF
			ShotTypes.State.AIMING:
				var before := s.ball_pos
				stuck = stuck + 1 if before.distance_to(last) < 3.0 else 0
				bot_shot(s, stuck)
				last = before
			ShotTypes.State.SHOT_RESULT:
				s.acknowledge_result()
			ShotTypes.State.HOLE_COMPLETE:
				s.next_hole()
	return s.is_round_complete()


static func flat_sim(surface: int) -> BallSim:
	return BallSim.new(HoleDefinition.make_flat(surface), PhysicsConfig.new())

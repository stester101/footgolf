class_name TestHelpers
extends RefCounted

const HOLE_PATHS := ["res://data/holes/hole_01.json", "res://data/holes/hole_02.json", "res://data/holes/hole_03.json"]
const RIDGE_PATHS := ["res://data/holes/hole_04.json", "res://data/holes/hole_05.json", "res://data/holes/hole_06.json",
	"res://data/holes/hole_07.json", "res://data/holes/hole_08.json", "res://data/holes/hole_09.json"]
const COASTAL_IDS := ["hole_10", "hole_11", "hole_12", "hole_13"]
const LAKESIDE_IDS := ["hole_14", "hole_15", "hole_16", "hole_17"]


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


## Load holes by id (res://data/holes/<id>.json).
static func load_hole_ids(ids: Array) -> Array:
	var out: Array = []
	for hid in ids:
		out.append(HoleDefinition.load_from_file("res://data/holes/%s.json" % hid))
	return out


## Every hole referenced by data/courses.json (deduplicated, in course order).
static func load_all_course_holes() -> Array:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/courses.json"))
	var ids: Array = []
	for c in d["courses"]:
		for hid in c["holes"]:
			if not ids.has(hid):
				ids.append(hid)
	return load_hole_ids(ids)


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


static func flat_sim(surface: int) -> BallSim:
	return BallSim.new(HoleDefinition.make_flat(surface), PhysicsConfig.new())

class_name CareerSaveManager
extends RefCounted
## Atomic, versioned, checksummed career storage in user://career/ (one career, no slots).
##
## Write path: serialise -> write career.json.tmp -> read it back and verify checksum + parse -> keep the
## current file as career.bak (the last good save) -> rename tmp over career.json. A failure at any step leaves
## the previous good files untouched.
## FAIL-CLOSED: commit() that fails keeps the data in memory (`pending`), sets `failed` and emits save_failed;
## play code must stop (is_blocked()) until retry() succeeds.
## Envelope: {schema_version, checksum, saved_at, payload}; payload is the career JSON as TEXT so the checksum
## is exact (JSON would turn ints into floats and change a re-serialisation).

signal save_failed(reason: String)
signal save_recovered

const FILE := "career.json"
const BACKUP := "career.bak"
const TMP := "career.json.tmp"
const IMPORT_BACKUP := "career.before_import.bak"

var dir := "user://career"
var failed := false
var last_error := ""
## The newest data that could not be saved (kept in memory so nothing is lost while the player retries).
var pending: Dictionary = {}
## Test hook: make every write fail (simulates a full / unavailable disk).
var simulate_failure := false
var last_saved_at := 0
## Set when load() had to use the backup.
var recovered_from_backup := false


func _init(p_dir: String = "user://career") -> void:
	dir = p_dir


func _p(name: String) -> String:
	return "%s/%s" % [dir, name]


func is_blocked() -> bool:
	return failed


func exists() -> bool:
	return FileAccess.file_exists(_p(FILE)) or FileAccess.file_exists(_p(BACKUP))


static func checksum_of(text: String) -> String:
	return text.sha256_text()


## JSON text of the envelope for `data`.
static func encode(data: Dictionary) -> String:
	var payload := JSON.stringify(data)
	return JSON.stringify({"schema_version": CareerConfig.SCHEMA_VERSION, "checksum": checksum_of(payload),
		"saved_at": int(Time.get_unix_time_from_system()), "payload": payload})


## {ok, data, error, version}. Validates structure + checksum; does NOT migrate.
static func decode(text: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) != OK or typeof(j.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Not a career file (unreadable)."}
	var env: Dictionary = j.data
	for k in ["schema_version", "checksum", "payload"]:
		if not env.has(k):
			return {"ok": false, "error": "Not a career file (missing %s)." % k}
	if typeof(env["payload"]) != TYPE_STRING:
		return {"ok": false, "error": "Not a career file (bad payload)."}
	if checksum_of(String(env["payload"])) != String(env["checksum"]):
		return {"ok": false, "error": "Career file is corrupt (checksum mismatch)."}
	var version := int(env["schema_version"])
	if version < 1 or version > CareerConfig.SCHEMA_VERSION:
		return {"ok": false, "error": "Career file is from an incompatible version (%d)." % version}
	var pj := JSON.new()
	if pj.parse(String(env["payload"])) != OK or typeof(pj.data) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Career file is corrupt (payload)."}
	var data: Dictionary = pj.data
	var mig := migrate(data, version)
	if mig.is_empty():
		return {"ok": false, "error": "Career file could not be migrated."}
	var why := validate(mig)
	if why != "":
		return {"ok": false, "error": "Career file is invalid: %s" % why}
	return {"ok": true, "data": mig, "version": version, "saved_at": int(env.get("saved_at", 0))}


## Explicit, idempotent migrations: each step upgrades exactly one version and never recomputes results.
## Empty Dictionary = failure.
static func migrate(data: Dictionary, from_version: int) -> Dictionary:
	var d := data.duplicate(true)
	var v := from_version
	if v < 2:
		if not (d.has("calendar") and d.has("golfers") and d.has("player") and d.has("season") and d.has("economy")):
			return {}
		d = CareerMigration.v1_to_v2(d)
		v = 2
	d["schema_version"] = CareerConfig.SCHEMA_VERSION
	return d


## "" when the data has the fields the rest of the code relies on.
static func validate(d: Dictionary) -> String:
	for k in ["career_id", "player", "season", "calendar", "economy", "golfers", "season_standings", "options", "season_footballers"]:
		if not d.has(k):
			return "missing %s" % k
	if typeof(d["calendar"]) != TYPE_ARRAY or (d["calendar"] as Array).is_empty():
		return "empty calendar"
	if typeof(d["player"]) != TYPE_DICTIONARY or typeof(d["season"]) != TYPE_DICTIONARY:
		return "bad player/season"
	return ""


# ------------------------------------------------------------------ writing

func _fail(reason: String) -> bool:
	failed = true
	last_error = reason
	save_failed.emit(reason)
	return false


## Writes `data` atomically. Returns true when durable. On failure the data stays in `pending`, `failed` is set
## and the previous good save is untouched.
func commit(data: Dictionary) -> bool:
	pending = data
	if simulate_failure:
		return _fail("Storage is not available.")
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		return _fail("Could not create the career folder.")
	var text := encode(data)
	var f := FileAccess.open(_p(TMP), FileAccess.WRITE)
	if f == null:
		return _fail("Could not write the save file.")
	f.store_string(text)
	f.close()
	var back := FileAccess.get_file_as_string(_p(TMP))
	if back != text or not bool(decode(back).get("ok", false)):
		DirAccess.remove_absolute(_p(TMP))
		return _fail("The save file did not verify after writing.")
	if FileAccess.file_exists(_p(FILE)) and bool(decode(FileAccess.get_file_as_string(_p(FILE))).get("ok", false)):
		# keep the last good file: copy (not move) so a crash before the rename still leaves career.json valid
		if DirAccess.copy_absolute(_p(FILE), _p(BACKUP)) != OK:
			DirAccess.remove_absolute(_p(TMP))
			return _fail("Could not keep a backup of the last good save.")
	if DirAccess.rename_absolute(_p(TMP), _p(FILE)) != OK:
		DirAccess.remove_absolute(_p(TMP))
		return _fail("Could not finish writing the save file.")
	var was_failed := failed
	failed = false
	last_error = ""
	pending = {}
	last_saved_at = int(Time.get_unix_time_from_system())
	if was_failed:
		save_recovered.emit()
	return true


## Retry the data that failed to save. True = saved (play may continue).
func retry() -> bool:
	if not failed or pending.is_empty():
		return not failed
	return commit(pending)


# ------------------------------------------------------------------ reading

## {ok, data, error}. Falls back to career.bak when career.json is missing or bad.
func load_career() -> Dictionary:
	recovered_from_backup = false
	var first := {"ok": false, "error": "No career saved."}
	if FileAccess.file_exists(_p(FILE)):
		first = decode(FileAccess.get_file_as_string(_p(FILE)))
		if bool(first.ok):
			return first
	if FileAccess.file_exists(_p(BACKUP)):
		var b := decode(FileAccess.get_file_as_string(_p(BACKUP)))
		if bool(b.ok):
			recovered_from_backup = true
			return b
	return first


func delete_career() -> void:
	for n in [FILE, BACKUP, TMP, IMPORT_BACKUP]:
		if FileAccess.file_exists(_p(n)):
			DirAccess.remove_absolute(_p(n))


# ------------------------------------------------------------------ export / import

## Copies the complete current career to `path` (user chooses; e.g. user://exports/x.json). True on success.
func export_to(path: String) -> bool:
	var r := load_career()
	if not bool(r.ok):
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(encode(r.data))
	f.close()
	return true


## Validates `path` completely first; only then backs up the current career and activates the import.
## Returns {ok, error, data}. A corrupt / incompatible file never touches the existing career.
func import_from(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "File not found."}
	var r := decode(FileAccess.get_file_as_string(path))
	if not bool(r.ok):
		return r
	if FileAccess.file_exists(_p(FILE)):
		DirAccess.make_dir_recursive_absolute(dir)
		DirAccess.copy_absolute(_p(FILE), _p(IMPORT_BACKUP))
	var before_exists := FileAccess.file_exists(_p(FILE))
	if not commit(r.data):
		return {"ok": false, "error": "Could not activate the imported career (the existing one is unchanged)." if before_exists else "Could not save the imported career."}
	return {"ok": true, "data": r.data}

class_name FootballerRepository
extends RefCounted
## Local, offline footballer database. Bundled datasets: res://data/footballers_real.json (Wikidata
## snapshot) and res://data/footballers_seed.json (synthetic test players). Edits are persisted to
## user://footballers.json, tagged with the dataset they belong to, and survive restarts. If the
## bundled dataset changes (e.g. a new snapshot), stale edits are backed up and not applied.

const SEED_PATH := "res://data/footballers_seed.json"
const REAL_PATH := "res://data/footballers_real.json"
const USER_PATH := "user://footballers.json"

signal changed

var _by_id: Dictionary = {}
var save_path := USER_PATH
var seed_path := SEED_PATH
var last_error := ""
var dataset_id := ""
var _sorted_cache: Array[Footballer] = []
var _sorted_dirty := true
var _nat_cache: Array[String] = []


func load_all() -> void:
	if not _load_file(seed_path):
		push_error("FootballerRepository: cannot load bundled dataset %s" % seed_path)
	var seed_ds := dataset_id
	if FileAccess.file_exists(save_path):
		var user_ds := _peek_dataset(save_path)
		if user_ds == seed_ds:
			if _load_file(save_path):
				dataset_id = seed_ds
				return
			push_warning("FootballerRepository: user database invalid (%s); using bundled data" % last_error)
		else:
			# Edits belong to a different dataset: keep a backup, do not apply them.
			var backup := save_path.get_basename() + "_backup_%s.json" % (user_ds if user_ds != "" else "old")
			DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(backup))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
			push_warning("FootballerRepository: edits for dataset '%s' backed up to %s" % [user_ds, backup])
	dataset_id = seed_ds


func _peek_dataset(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		return String((parsed as Dictionary).get("dataset", ""))
	return ""


func reset_to_seed() -> void:
	_load_file(seed_path)
	save()
	changed.emit()


func _load_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "cannot open %s" % path
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	var list: Array = []
	if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("footballers"):
		list = parsed["footballers"]
		dataset_id = String((parsed as Dictionary).get("dataset", "synthetic-v1"))
	elif typeof(parsed) == TYPE_ARRAY:
		list = parsed
	else:
		last_error = "invalid JSON in %s" % path
		return false
	var tmp: Dictionary = {}
	for item in list:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var err := Footballer.validate_dict(item)
		if err != "":
			push_warning("Skipping invalid footballer record: %s" % err)
			continue
		var fb := Footballer.from_dict(item)
		if tmp.has(fb.id):
			push_warning("Skipping duplicate footballer id %s" % fb.id)
			continue
		tmp[fb.id] = fb
	_by_id = tmp
	_invalidate()
	return true


func _invalidate() -> void:
	_sorted_dirty = true
	_nat_cache.clear()


func save() -> bool:
	var list: Array = []
	for fb in all_sorted():
		list.append(fb.to_dict())
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		last_error = "cannot write %s" % save_path
		return false
	f.store_string(JSON.stringify({"version": 1, "dataset": dataset_id, "footballers": list}))
	return true


func count() -> int:
	return _by_id.size()


func has(id: String) -> bool:
	return _by_id.has(id)


func get_by_id(id: String) -> Footballer:
	return _by_id.get(id)


## Stable alphabetical order (name, nationality, birth year, id). Never ordered by stats.
func all_sorted() -> Array[Footballer]:
	if _sorted_dirty:
		_sorted_cache.clear()
		for fb in _by_id.values():
			_sorted_cache.append(fb)
		_sorted_cache.sort_custom(_compare)
		_sorted_dirty = false
	return _sorted_cache


static func _compare(a: Footballer, b: Footballer) -> bool:
	var an := a.name.to_lower()
	var bn := b.name.to_lower()
	if an != bn:
		return an < bn
	if a.nationality != b.nationality:
		return a.nationality < b.nationality
	if a.birth_year != b.birth_year:
		return a.birth_year < b.birth_year
	return a.id < b.id


## Name search + optional nationality filter. No stat-based filtering/sorting.
## limit < 0 = no limit. Matching is accent/case-insensitive on name.
func search(query: String, nationality: String = "", limit: int = -1) -> Array[Footballer]:
	var q := fold(query.strip_edges())
	var out: Array[Footballer] = []
	for fb in all_sorted():
		if nationality != "" and fb.nationality != nationality:
			continue
		if q != "" and not fold(fb.name).contains(q):
			continue
		out.append(fb)
		if limit >= 0 and out.size() >= limit:
			break
	return out


func count_matches(query: String, nationality: String = "") -> int:
	return search(query, nationality).size()


## Lower-case and strip common accents so "muller" finds "Müller".
static func fold(s: String) -> String:
	var t := s.to_lower()
	const FROM := "áàâäãåāăąçćčďđéèêëēėęěğíìîïīįıłñńňóòôöõøōőřśšşșťțúùûüūůűųýÿžźżæœß"
	const TO := "aaaaaaaaacccddeeeeeeeegiiiiiiilnnnoooooooorssssttuuuuuuuuyyzzzaos"
	for i in FROM.length():
		t = t.replace(FROM[i], TO[i])
	return t


func nationalities() -> Array[String]:
	if not _nat_cache.is_empty():
		return _nat_cache
	var seen := {}
	for fb in _by_id.values():
		seen[(fb as Footballer).nationality] = true
	var out: Array[String] = []
	for k in seen.keys():
		out.append(String(k))
	out.sort()
	_nat_cache = out
	return out


## Add a validated record. Returns "" on success or an error message.
func add_record(d: Dictionary) -> String:
	var err := Footballer.validate_dict(d)
	if err != "":
		return err
	if _by_id.has(String(d["id"])):
		return "duplicate id %s" % d["id"]
	var clean := d.duplicate()
	clean["senior_international_caps"] = Footballer.parse_stat(d["senior_international_caps"])
	clean["senior_international_goals"] = Footballer.parse_stat(d["senior_international_goals"])
	var fb := Footballer.from_dict(clean)
	_by_id[fb.id] = fb
	_invalidate()
	save()
	changed.emit()
	return ""


func update_record(id: String, d: Dictionary) -> String:
	if not _by_id.has(id):
		return "unknown id %s" % id
	var merged: Dictionary = (_by_id[id] as Footballer).to_dict()
	for k in d.keys():
		merged[k] = d[k]
	merged["id"] = id
	var err := Footballer.validate_dict(merged)
	if err != "":
		return err
	merged["senior_international_caps"] = Footballer.parse_stat(merged["senior_international_caps"])
	merged["senior_international_goals"] = Footballer.parse_stat(merged["senior_international_goals"])
	_by_id[id] = Footballer.from_dict(merged)
	_invalidate()
	save()
	changed.emit()
	return ""


func duplicate_record(id: String) -> String:
	if not _by_id.has(id):
		return ""
	var d: Dictionary = (_by_id[id] as Footballer).to_dict()
	d["id"] = new_id()
	d["name"] = "%s (copy)" % d["name"]
	if add_record(d) != "":
		return ""
	return String(d["id"])


func delete_record(id: String) -> bool:
	if not _by_id.has(id):
		return false
	_by_id.erase(id)
	_invalidate()
	save()
	changed.emit()
	return true


func new_id() -> String:
	var n := _by_id.size() + 1
	while _by_id.has("dev-%04d" % n):
		n += 1
	return "dev-%04d" % n

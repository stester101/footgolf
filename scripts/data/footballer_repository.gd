class_name FootballerRepository
extends RefCounted
## Local, offline footballer database. Seed data lives in res://data/footballers_seed.json;
## edits are persisted to user://footballers.json and survive restarts.

const SEED_PATH := "res://data/footballers_seed.json"
const USER_PATH := "user://footballers.json"

signal changed

var _by_id: Dictionary = {}
var save_path := USER_PATH
var seed_path := SEED_PATH
var last_error := ""


func load_all() -> void:
	if FileAccess.file_exists(save_path):
		if _load_file(save_path):
			return
		push_warning("FootballerRepository: user database invalid (%s); falling back to seed" % last_error)
	_load_file(seed_path)


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
	return true


func save() -> bool:
	var list: Array = []
	for fb in all_sorted():
		list.append(fb.to_dict())
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		last_error = "cannot write %s" % save_path
		return false
	f.store_string(JSON.stringify({"version": 1, "footballers": list}, "  "))
	return true


func count() -> int:
	return _by_id.size()


func has(id: String) -> bool:
	return _by_id.has(id)


func get_by_id(id: String) -> Footballer:
	return _by_id.get(id)


## Stable alphabetical order (name, nationality, birth year, id). Never ordered by stats.
func all_sorted() -> Array[Footballer]:
	var out: Array[Footballer] = []
	for fb in _by_id.values():
		out.append(fb)
	out.sort_custom(_compare)
	return out


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
func search(query: String, nationality: String = "") -> Array[Footballer]:
	var q := query.strip_edges().to_lower()
	var out: Array[Footballer] = []
	for fb in all_sorted():
		if nationality != "" and fb.nationality != nationality:
			continue
		if q != "" and not fb.name.to_lower().contains(q):
			continue
		out.append(fb)
	return out


func nationalities() -> Array[String]:
	var seen := {}
	for fb in _by_id.values():
		seen[(fb as Footballer).nationality] = true
	var out: Array[String] = []
	for k in seen.keys():
		out.append(String(k))
	out.sort()
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
	save()
	changed.emit()
	return true


func new_id() -> String:
	var n := _by_id.size() + 1
	while _by_id.has("dev-%04d" % n):
		n += 1
	return "dev-%04d" % n

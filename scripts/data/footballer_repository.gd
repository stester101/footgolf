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
var _folded_names := PackedStringArray()  # parallel to _sorted_cache
var _sorted_dirty := true
var _nat_cache: Array[String] = []
var _sort_cache: Dictionary = {}

const SORT_LABELS := [["name_az", "Name A–Z"], ["name_za", "Name Z–A"], ["country", "Country"],
	["born_old", "Born: oldest first"], ["born_new", "Born: youngest first"]]
## Stat-based sorting/filtering is a TEST-MODE aid only (normal play never ranks by hidden stats).
const STAT_SORT_LABELS := [["caps_hi", "Caps: most first"], ["caps_lo", "Caps: fewest first"],
	["goals_hi", "Goals: most first"], ["goals_lo", "Goals: fewest first"]]
const ERAS := [["Pre-1950", 0, 1949], ["1950s", 1950, 1959], ["1960s", 1960, 1969], ["1970s", 1970, 1979],
	["1980s", 1980, 1989], ["1990s", 1990, 1999], ["2000+", 2000, 9999]]
const CAPS_BANDS := [["Any caps", -1, -1], ["1 cap", 1, 1], ["2–9", 2, 9], ["10–49", 10, 49], ["50–99", 50, 99], ["100+", 100, 999999]]
const GOALS_BANDS := [["Any goals", -1, -1], ["0 goals", 0, 0], ["1–4", 1, 4], ["5–19", 5, 19], ["20–49", 20, 49], ["50+", 50, 999999]]


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
	_sort_cache.clear()


func save() -> bool:
	var list: Array = []
	for fb in all_sorted():
		list.append(fb.to_dict())
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "cannot write %s" % save_path
		return false
	f.store_string(JSON.stringify({"version": 1, "dataset": dataset_id, "footballers": list}))
	f.close()
	# Write-then-rename keeps the previous file intact if the app dies mid-save.
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(save_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		last_error = "cannot replace %s" % save_path
		return false
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
		_folded_names.resize(_sorted_cache.size())
		for i in _sorted_cache.size():
			_folded_names[i] = fold(_sorted_cache[i].name)
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
## All players in a given sort order (cached per key; built lazily on first use).
func sorted_by(key: String) -> Array[Footballer]:
	var base := all_sorted()
	if key == "name_az" or key == "":
		return base
	if _sort_cache.has(key):
		return _sort_cache[key]
	var arr: Array[Footballer] = base.duplicate()
	match key:
		"name_za":
			arr.reverse()
		"country":
			arr.sort_custom(func(a: Footballer, b: Footballer) -> bool:
				return _compare(a, b) if a.nationality == b.nationality else a.nationality < b.nationality)
		"born_old":
			arr.sort_custom(func(a: Footballer, b: Footballer) -> bool:
				var ya := a.birth_year if a.birth_year > 0 else 9999
				var yb := b.birth_year if b.birth_year > 0 else 9999
				return _compare(a, b) if ya == yb else ya < yb)
		"born_new":
			arr.sort_custom(func(a: Footballer, b: Footballer) -> bool:
				return _compare(a, b) if a.birth_year == b.birth_year else a.birth_year > b.birth_year)
		"caps_hi":
			arr.sort_custom(func(a: Footballer, b: Footballer) -> bool:
				return _compare(a, b) if a.caps == b.caps else a.caps > b.caps)
		"caps_lo":
			arr.sort_custom(func(a: Footballer, b: Footballer) -> bool:
				return _compare(a, b) if a.caps == b.caps else a.caps < b.caps)
		"goals_hi":
			arr.sort_custom(func(a: Footballer, b: Footballer) -> bool:
				return _compare(a, b) if a.goals == b.goals else a.goals > b.goals)
		"goals_lo":
			arr.sort_custom(func(a: Footballer, b: Footballer) -> bool:
				return _compare(a, b) if a.goals == b.goals else a.goals < b.goals)
		_:
			return base
	_sort_cache[key] = arr
	return arr


## Filtered + sorted query. Options: q (name text), nations {name:true}, eras {index:true} (see ERAS),
## available_only (needs pool), caps_band / goals_band (index into CAPS_BANDS / GOALS_BANDS),
## sort (see SORT_LABELS), limit (<0 = all).
func query(o: Dictionary, pool: FootballerPool = null) -> Array[Footballer]:
	var out: Array[Footballer] = []
	var limit := int(o.get("limit", -1))
	for fb in sorted_by(String(o.get("sort", "name_az"))):
		if _passes(fb, o, pool, true):
			out.append(fb)
			if limit >= 0 and out.size() >= limit:
				break
	return out


## Per-nationality match counts for the current filters, ignoring the nationality filter itself
## (so country chips can show "how many would I get if I picked this").
func facet_counts(o: Dictionary, pool: FootballerPool = null) -> Dictionary:
	var counts := {}
	for fb in all_sorted():
		if _passes(fb, o, pool, false):
			counts[fb.nationality] = int(counts.get(fb.nationality, 0)) + 1
	return counts


func _passes(fb: Footballer, o: Dictionary, pool: FootballerPool, use_nations: bool) -> bool:
	if use_nations:
		var nations: Dictionary = o.get("nations", {})
		if not nations.is_empty() and not nations.has(fb.nationality):
			return false
	var q := fold(String(o.get("q", "")).strip_edges())
	if q != "" and not fb.folded().contains(q):
		return false
	if bool(o.get("available_only", false)) and pool != null and pool.is_used(fb.id, int(o.get("mode", -1))):
		return false
	var eras: Dictionary = o.get("eras", {})
	if not eras.is_empty():
		var ok := false
		for idx in eras.keys():
			var e: Array = ERAS[int(idx)]
			if fb.birth_year > 0 and fb.birth_year >= int(e[1]) and fb.birth_year <= int(e[2]):
				ok = true
				break
		if not ok:
			return false
	var cb := int(o.get("caps_band", 0))
	if cb > 0:
		var b: Array = CAPS_BANDS[cb]
		if fb.caps < int(b[1]) or fb.caps > int(b[2]):
			return false
	var gb := int(o.get("goals_band", 0))
	if gb > 0:
		var b2: Array = GOALS_BANDS[gb]
		if fb.goals < int(b2[1]) or fb.goals > int(b2[2]):
			return false
	return true


## limit < 0 = no limit. Matching is accent/case-insensitive on name.
func search(query: String, nationality: String = "", limit: int = -1) -> Array[Footballer]:
	var q := fold(query.strip_edges())
	var out: Array[Footballer] = []
	var all := all_sorted()
	for i in all.size():
		var fb: Footballer = all[i]
		if nationality != "" and fb.nationality != nationality:
			continue
		if q != "" and not _folded_names[i].contains(q):
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

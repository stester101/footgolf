class_name PlayerProfileStore
extends RefCounted
## Device-local identities and per-profile favourite footballers.

const PATH := "user://player_profiles.json"
const VERSION := 1
const MAX_PROFILES := 8
const MAX_NAME_LEN := 14

var save_path := PATH
var last_error := ""
var _profiles: Array[Dictionary] = []


## legacy_favourites: the old global favourites list (settings.json). On the very first run (no profile
## file yet) it is migrated into the first profile, "Player 1".
func load_profiles(legacy_favourites: Array = []) -> bool:
	last_error = ""
	_profiles.clear()
	if not FileAccess.file_exists(save_path):
		var first := create_profile("Player 1")
		if first == "":
			return false
		for fid in legacy_favourites:
			if fid is String and fid != "":
				set_favourite(first, fid, true)
		return true
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		last_error = "Cannot read profiles"
		return false
	var parser := JSON.new()
	if parser.parse(f.get_as_text()) != OK:
		last_error = "Invalid profile file"
		return false
	var data = parser.data
	if not data is Dictionary or int(data.get("version", -1)) != VERSION or not data.get("profiles") is Array:
		last_error = "Invalid profile file"
		return false
	var seen := {}
	for item in data["profiles"]:
		if not item is Dictionary:
			last_error = "Invalid profile entry"
			_profiles.clear()
			return false
		var id := String(item.get("id", ""))
		var name := String(item.get("name", "")).strip_edges()
		if id == "" or name == "" or seen.has(id) or not item.get("favourites", []) is Array:
			last_error = "Invalid or duplicate profile"
			_profiles.clear()
			return false
		seen[id] = true
		var favourites: Array[String] = []
		for favourite in item["favourites"]:
			if favourite is String and favourite != "" and not favourites.has(favourite):
				favourites.append(favourite)
		_profiles.append({"id": id, "name": name, "favourites": favourites})
	return true


func all_profiles() -> Array[Dictionary]:
	return _profiles.duplicate(true)


func get_profile(id: String) -> Dictionary:
	for profile in _profiles:
		if profile["id"] == id:
			return profile.duplicate(true)
	return {}


func create_profile(display_name: String) -> String:
	var name := display_name.strip_edges().left(MAX_NAME_LEN)
	if name == "" or _profiles.size() >= MAX_PROFILES:
		return ""
	var id := "local-%d-%d" % [Time.get_ticks_usec(), randi()]
	while not get_profile(id).is_empty():
		id = "local-%d-%d" % [Time.get_ticks_usec(), randi()]
	_profiles.append({"id": id, "name": name, "favourites": []})
	if not save():
		_profiles.pop_back()
		return ""
	return id


func rename_profile(id: String, display_name: String) -> bool:
	var name := display_name.strip_edges().left(MAX_NAME_LEN)
	if name == "":
		return false
	for profile in _profiles:
		if profile["id"] == id:
			var previous: String = profile["name"]
			profile["name"] = name
			if save():
				return true
			profile["name"] = previous
			return false
	return false


## Deletes a profile and its favourites. The last remaining profile cannot be deleted.
func delete_profile(id: String) -> bool:
	if _profiles.size() <= 1:
		return false
	for i in _profiles.size():
		if _profiles[i]["id"] == id:
			var removed: Dictionary = _profiles[i]
			_profiles.remove_at(i)
			if save():
				return true
			_profiles.insert(i, removed)
			return false
	return false


## The profile whose favourites apply for this id: itself when it exists, else the first profile
## ("" is a guest slot), else "" when there are no profiles at all.
func resolve_id(id: String) -> String:
	if id != "" and not get_profile(id).is_empty():
		return id
	return String(_profiles[0]["id"]) if not _profiles.is_empty() else ""


func favourites_of(profile_id: String) -> Array:
	return (get_profile(resolve_id(profile_id)).get("favourites", []) as Array).duplicate()


func is_favourite(profile_id: String, footballer_id: String) -> bool:
	var profile := get_profile(profile_id)
	return not profile.is_empty() and (profile["favourites"] as Array).has(footballer_id)


func set_favourite(profile_id: String, footballer_id: String, favourite: bool) -> bool:
	if footballer_id == "":
		return false
	for profile in _profiles:
		if profile["id"] == profile_id:
			var ids: Array = profile["favourites"]
			var old := ids.duplicate()
			if favourite and not ids.has(footballer_id):
				ids.append(footballer_id)
			elif not favourite:
				ids.erase(footballer_id)
			if save():
				return true
			profile["favourites"] = old
			return false
	return false


func save() -> bool:
	last_error = ""
	var tmp_path := save_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		last_error = "Cannot write profiles"
		return false
	f.store_string(JSON.stringify({"version": VERSION, "profiles": _profiles}, "  "))
	f.flush()
	f.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(save_path)) != OK:
		last_error = "Cannot replace profile file"
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
		return false
	return true

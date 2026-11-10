class_name FootballerPool
extends RefCounted
## One shared eligibility pool for every participant and hole in a local round.

signal changed

enum ReuseRule { ONCE_PER_ROUND, ONCE_PER_MODE }

## id -> {"all": order} or {"caps": order, "goals": order}.
var used_footballer_ids: Dictionary = {}
var reuse_rule: int = ReuseRule.ONCE_PER_ROUND
var _order := 0
## Career "once per season" rule (opt-in, default off everywhere else): while season_id != "" the ids in
## season_locked cannot be used, whatever the per-round / per-mode rule says. The caller owns the id list
## (the career save keys it by season id) and re-applies it with set_season_lock(); it is not part of snapshot().
var season_id := ""
var season_locked: Dictionary = {}


static func _mode_key(mode: int) -> String:
	if mode == ShotTypes.Mode.CAPS:
		return "caps"
	if mode == ShotTypes.Mode.GOALS:
		return "goals"
	return ""


## Round setup may choose a different rule before any shots have been committed.
func set_reuse_rule(new_rule: int) -> bool:
	if new_rule != ReuseRule.ONCE_PER_ROUND and new_rule != ReuseRule.ONCE_PER_MODE:
		return false
	if used_count() > 0 and new_rule != reuse_rule:
		return false
	reuse_rule = new_rule
	changed.emit()
	return true


## Activates the season rule for `p_season_id` with the ids already used that season ("" disables it).
func set_season_lock(p_season_id: String, ids: Array) -> void:
	season_id = p_season_id
	season_locked.clear()
	if p_season_id != "":
		for i in ids:
			season_locked[String(i)] = true
	changed.emit()


func lock_for_season(id: String) -> void:
	if season_id != "" and id != "":
		season_locked[id] = true


func season_rule_active() -> bool:
	return season_id != ""


func is_available(id: String, mode: int = -1) -> bool:
	if id == "":
		return false
	if season_locked.has(id):
		return false
	if not used_footballer_ids.has(id):
		return true
	if reuse_rule == ReuseRule.ONCE_PER_ROUND:
		return false
	var used: Dictionary = used_footballer_ids[id]
	if mode == -1:
		return not used.has("caps") or not used.has("goals")
	var key := _mode_key(mode)
	return key != "" and not used.has(key)


func is_used(id: String, mode: int = -1) -> bool:
	return not is_available(id, mode)


## Commit one use. Under ONCE_PER_MODE the shot mode is mandatory.
func consume(id: String, mode: int = -1) -> bool:
	if reuse_rule == ReuseRule.ONCE_PER_MODE and _mode_key(mode) == "":
		return false
	if not is_available(id, mode):
		return false
	_order += 1
	var used: Dictionary = used_footballer_ids.get(id, {})
	used["all" if reuse_rule == ReuseRule.ONCE_PER_ROUND else _mode_key(mode)] = _order
	used_footballer_ids[id] = used
	changed.emit()
	return true


## Developer-only rollback for the exact mode used by a shot.
func release(id: String, mode: int = -1) -> bool:
	if not used_footballer_ids.has(id):
		return false
	var used: Dictionary = used_footballer_ids[id]
	var key := "all" if reuse_rule == ReuseRule.ONCE_PER_ROUND else _mode_key(mode)
	if key == "" or not used.has(key):
		return false
	used.erase(key)
	if used.is_empty():
		used_footballer_ids.erase(id)
	else:
		used_footballer_ids[id] = used
	changed.emit()
	return true


func reset() -> void:
	used_footballer_ids.clear()
	_order = 0
	changed.emit()


func used_count() -> int:
	var count := 0
	for used in used_footballer_ids.values():
		count += (used as Dictionary).size()
	return count


func used_ids_in_order() -> Array[String]:
	var entries: Array = []
	for id in used_footballer_ids:
		for order in (used_footballer_ids[id] as Dictionary).values():
			entries.append({"id": String(id), "order": int(order)})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["order"] < b["order"])
	var ids: Array[String] = []
	for entry in entries:
		ids.append(entry["id"])
	return ids


func snapshot() -> Dictionary:
	return {"used": used_footballer_ids.duplicate(true), "order": _order, "reuse_rule": reuse_rule}


func restore(snap: Dictionary) -> void:
	var new_rule := int(snap.get("reuse_rule", ReuseRule.ONCE_PER_ROUND))
	if new_rule != ReuseRule.ONCE_PER_ROUND and new_rule != ReuseRule.ONCE_PER_MODE:
		return
	reuse_rule = new_rule
	used_footballer_ids.clear()
	var saved: Dictionary = snap.get("used", {})
	for id in saved:
		var entry = saved[id]
		# Accept the original version's id -> integer snapshots for developer undo.
		used_footballer_ids[id] = (entry as Dictionary).duplicate() if entry is Dictionary else {"all": int(entry)}
	_order = int(snap.get("order", 0))
	changed.emit()

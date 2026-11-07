class_name FootballerPool
extends RefCounted
## Consumed-footballer set for ONE match (all holes). Each footballer may be used once per
## match. Written around a used_footballer_ids set so a future server-authoritative shared
## pool can replace it without changing the mechanic.

signal changed

var used_footballer_ids: Dictionary = {}  # id -> shot order (int)
var _order := 0


func is_available(id: String) -> bool:
	return not used_footballer_ids.has(id)


func is_used(id: String) -> bool:
	return used_footballer_ids.has(id)


## Consume on a committed shot. Returns false if already used (no state change).
func consume(id: String) -> bool:
	if id == "" or used_footballer_ids.has(id):
		return false
	_order += 1
	used_footballer_ids[id] = _order
	changed.emit()
	return true


## New match / developer "Reset Pool".
func reset() -> void:
	used_footballer_ids.clear()
	_order = 0
	changed.emit()


func used_count() -> int:
	return used_footballer_ids.size()


func used_ids_in_order() -> Array[String]:
	var ids: Array[String] = []
	for k in used_footballer_ids.keys():
		ids.append(String(k))
	ids.sort_custom(func(a: String, b: String) -> bool: return int(used_footballer_ids[a]) < int(used_footballer_ids[b]))
	return ids


func snapshot() -> Dictionary:
	return {"used": used_footballer_ids.duplicate(), "order": _order}


func restore(snap: Dictionary) -> void:
	used_footballer_ids = (snap.get("used", {}) as Dictionary).duplicate()
	_order = int(snap.get("order", 0))
	changed.emit()

class_name ShopManager
extends RefCounted
## Career shop: COSMETICS ONLY (ball colours / trails, flag colours, outfit colours, scorecard themes, celebration
## effects; career/data/shop_items.json). No item changes physics, scoring, footballers or any rule.
## Pure helpers on the career save Dictionary (the caller commits). A purchase is atomic (balance check, ledger entry
## and ownership change together, or nothing) and idempotent: the ledger id "shop:<item_id>" is stable, so a retry
## after a failed save never charges twice and the balance can never go negative.
## Save shape: see CareerDefaultsSponsorsShop (cosmetics {owned, equipped}).

const PATH := "res://career/data/shop_items.json"

static var _cache: Dictionary = {}


static func _load() -> Dictionary:
	if _cache.is_empty():
		var d = CourseSource.read_json(PATH)
		_cache = d if typeof(d) == TYPE_DICTIONARY else {"slots": {}, "items": []}
	return _cache


static func items() -> Array:
	return _load().get("items", [])


static func slots() -> Dictionary:
	return _load().get("slots", {})


static func item(id: String) -> Dictionary:
	for it in items():
		if String(it["id"]) == id:
			return it
	return {}


static func items_in_slot(slot: String) -> Array:
	return items().filter(func(it: Dictionary) -> bool: return String(it["slot"]) == slot)


static func is_owned(data: Dictionary, id: String) -> bool:
	CareerDefaultsSponsorsShop.ensure_defaults(data)
	return (data["cosmetics"]["owned"] as Dictionary).has(id)


## {ok:bool, label:String}: whether the item's lock (sponsor / world rank / trophies) is satisfied.
static func lock_state(data: Dictionary, it: Dictionary) -> Dictionary:
	var lock: Dictionary = it.get("lock", {})
	if lock.is_empty():
		return {"ok": true, "label": ""}
	CareerDefaultsSponsorsShop.ensure_defaults(data)
	var ok := false
	match String(lock["type"]):
		"sponsor":
			ok = (data["sponsorships"]["history"] as Array).has(String(lock["id"]))
		"best_world_rank":
			var best := int((data.get("records", {}) as Dictionary).get("best_world_rank", 0))
			ok = best > 0 and best <= int(lock["x"])
		"trophies":
			ok = (data.get("trophies", []) as Array).size() >= int(lock["n"])
	return {"ok": ok, "label": String(lock.get("label", "Locked"))}


## "" when the item can be bought now, otherwise the reason.
static func why_not(data: Dictionary, id: String) -> String:
	var it := item(id)
	if it.is_empty():
		return "Unknown item."
	if is_owned(data, id):
		return "You already own this."
	var ls := lock_state(data, it)
	if not bool(ls["ok"]):
		return "Locked: %s." % String(ls["label"])
	if int((data["economy"] as Dictionary)["balance"]) < int(it["price"]):
		return "Not enough money."
	return ""


## Buys an item. {ok, reason}. Re-buying an owned item is a no-op that reports ok=false / "already own".
## A ledger entry that exists without ownership (an interrupted earlier attempt) is completed without a second charge.
static func buy(data: Dictionary, id: String, season: int) -> Dictionary:
	CareerDefaultsSponsorsShop.ensure_defaults(data)
	var it := item(id)
	if it.is_empty():
		return {"ok": false, "reason": "Unknown item."}
	var owned: Dictionary = data["cosmetics"]["owned"]
	if owned.has(id):
		return {"ok": false, "reason": "You already own this."}
	var lid := "shop:%s" % id
	var charged := (data["ledger"] as Array).any(func(t: Dictionary) -> bool: return String(t["id"]) == lid)
	if not charged:
		var why := why_not(data, id)
		if why != "":
			return {"ok": false, "reason": why}
		CareerRecords.ledger_add(data, lid, "shop", "Shop: %s" % String(it["name"]), -int(it["price"]), "", season)
	owned[id] = {"season": season, "seen": false}
	return {"ok": true, "reason": ""}


static func equip(data: Dictionary, id: String) -> bool:
	if not is_owned(data, id):
		return false
	(data["cosmetics"]["equipped"] as Dictionary)[String(item(id)["slot"])] = id
	return true


static func unequip(data: Dictionary, slot: String) -> void:
	CareerDefaultsSponsorsShop.ensure_defaults(data)
	(data["cosmetics"]["equipped"] as Dictionary).erase(slot)


static func equipped_id(data: Dictionary, slot: String) -> String:
	CareerDefaultsSponsorsShop.ensure_defaults(data)
	var id := String((data["cosmetics"]["equipped"] as Dictionary).get(slot, ""))
	return id if is_owned(data, id) else ""


## Equipped colour of a slot, or Color.TRANSPARENT when nothing (or nothing with a colour) is equipped.
static func equipped_color(data: Dictionary, slot: String) -> Color:
	var id := equipped_id(data, slot)
	if id == "":
		return Color.TRANSPARENT
	var it := item(id)
	return Color(String(it["color"])) if it.has("color") else Color.TRANSPARENT


static func new_count(data: Dictionary) -> int:
	CareerDefaultsSponsorsShop.ensure_defaults(data)
	var n := 0
	for id in data["cosmetics"]["owned"]:
		if not bool((data["cosmetics"]["owned"][id] as Dictionary).get("seen", true)):
			n += 1
	return n


static func mark_all_seen(data: Dictionary) -> void:
	CareerDefaultsSponsorsShop.ensure_defaults(data)
	for id in data["cosmetics"]["owned"]:
		(data["cosmetics"]["owned"][id] as Dictionary)["seen"] = true

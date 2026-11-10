class_name CareerRecords
extends RefCounted
## Pure helpers on the career save Dictionary for the "extras": the transaction ledger, the trophy cabinet and
## career records, and rivals / head-to-head. Every writer is idempotent (stable ids / applied markers), so a
## repeated finalize after a failed save never pays or counts anything twice.
## Shapes (career/models/README.md): ledger [{id,kind,label,amount,event_id,season,balance_after}],
## trophies [{id,kind,name,season,event_id,place}], records {...}, head_to_head {applied:{}, records:{id:{...}}},
## rivalries [{id,name,meetings,wins,losses,ties,close}] (best rivals first).

const PLAYER := "player"


# ------------------------------------------------------------------ ledger

static func default_records() -> Dictionary:
	return {"wins": 0, "majors": 0, "starts": 0, "cuts_made": 0, "top10s": 0, "best_finish": {}, "best_world_rank": 0,
		"biggest_cheque": {}, "applied": {}}


## Adds a transaction once per id and moves the balance and earnings with it. Returns true when it was added.
static func ledger_add(data: Dictionary, id: String, kind: String, label: String, amount: int, event_id: String, season: int) -> bool:
	var ledger: Array = data["ledger"]
	for t in ledger:
		if String(t["id"]) == id:
			return false
	var eco: Dictionary = data["economy"]
	eco["balance"] = int(eco["balance"]) + amount
	if amount > 0:
		eco["season_earnings"] = int(eco["season_earnings"]) + amount
		eco["career_earnings"] = int(eco["career_earnings"]) + amount
	ledger.append({"id": id, "kind": kind, "label": label, "amount": amount, "event_id": event_id, "season": season,
		"balance_after": int(eco["balance"])})
	return true


static func ledger_recent(data: Dictionary, n: int) -> Array:
	var l: Array = data.get("ledger", [])
	if l.is_empty():
		return []
	return l.slice(maxi(0, l.size() - n)).duplicate(true)


static func ledger_for_event(data: Dictionary, event_id: String) -> Array:
	var out: Array = []
	for t in data.get("ledger", []):
		if String(t["event_id"]) == event_id:
			out.append(t)
	return out


# ------------------------------------------------------------------ trophies and records

static func trophy_add(data: Dictionary, id: String, kind: String, p_name: String, season: int, event_id: String, place: int = 1) -> bool:
	var tr: Array = data["trophies"]
	for t in tr:
		if String(t["id"]) == id:
			return false
	tr.append({"id": id, "kind": kind, "name": p_name, "season": season, "event_id": event_id, "place": place})
	return true


static func win_kind(category: String) -> String:
	return {"major": "major", "flagship": "flagship", "finale": "tour_championship"}.get(category, "event_win")


static func trophies_of(data: Dictionary, kind: String) -> Array:
	return (data.get("trophies", []) as Array).filter(func(t: Dictionary) -> bool: return String(t["kind"]) == kind)


## Updates records and trophies from a finished event the human played (once per event id).
## `row` = the human leaderboard entry, `world_rank` = the rank after the event.
static func apply_human_event(data: Dictionary, ev: Dictionary, row: Dictionary, season: int, world_rank: int) -> void:
	var rec: Dictionary = data["records"]
	var eid := String(ev["id"])
	if (rec["applied"] as Dictionary).has(eid):
		return
	rec["applied"][eid] = true
	var place := int(row["position"])
	rec["starts"] = int(rec["starts"]) + 1
	if String(row["status"]) == "made_cut":
		rec["cuts_made"] = int(rec["cuts_made"]) + 1
		if place <= 10:
			rec["top10s"] = int(rec["top10s"]) + 1
		var best: Dictionary = rec["best_finish"]
		if best.is_empty() or place < int(best["place"]):
			rec["best_finish"] = {"place": place, "event": String(ev["name"]), "season": season}
	var pay := int(row.get("payout", 0))
	var cheque: Dictionary = rec["biggest_cheque"]
	if pay > 0 and (cheque.is_empty() or pay > int(cheque.get("amount", 0))):
		rec["biggest_cheque"] = {"amount": pay, "event": String(ev["name"]), "season": season}
	if place == 1 and String(row["status"]) == "made_cut":
		rec["wins"] = int(rec["wins"]) + 1
		var cat := String(ev["category"])
		if cat == "major":
			rec["majors"] = int(rec["majors"]) + 1
		trophy_add(data, "win:%s" % eid, win_kind(cat), String(ev["name"]), season, eid, 1)
	note_world_rank(data, world_rank)


static func note_world_rank(data: Dictionary, world_rank: int) -> void:
	var rec: Dictionary = data["records"]
	if world_rank > 0 and (int(rec["best_world_rank"]) == 0 or world_rank < int(rec["best_world_rank"])):
		rec["best_world_rank"] = world_rank


# ------------------------------------------------------------------ rivals / head-to-head

## Compares the human with every other finisher of the event (once per event id) and refreshes `rivalries`.
## Result per opponent: win / loss / tie by finishing position (a cut player ranks below everyone who made it).
static func update_head_to_head(data: Dictionary, ev: Dictionary, leaderboard: Array) -> void:
	var h2h: Dictionary = data["head_to_head"]
	var eid := String(ev["id"])
	if (h2h["applied"] as Dictionary).has(eid):
		return
	h2h["applied"][eid] = true
	var me: Dictionary = {}
	for r in leaderboard:
		if bool(r["is_human"]):
			me = r
	if me.is_empty() or String(me["status"]) == "incomplete":
		return
	var recs: Dictionary = h2h["records"]
	for r in leaderboard:
		if bool(r["is_human"]) or String(r["status"]) == "incomplete":
			continue
		var id := String(r["id"])
		var rec: Dictionary = recs.get(id, {"w": 0, "l": 0, "t": 0, "close": 0, "last_event": ""})
		var mine := int(me["position"])
		var theirs := int(r["position"])
		if mine < theirs:
			rec["w"] = int(rec["w"]) + 1
		elif mine > theirs:
			rec["l"] = int(rec["l"]) + 1
		else:
			rec["t"] = int(rec["t"]) + 1
		if String(me["status"]) == String(r["status"]) and (me["rounds"] as Array).size() == (r["rounds"] as Array).size() \
				and absi(int(me["total"]) - int(r["total"])) <= CareerConfig.RIVAL_CLOSE_STROKES:
			rec["close"] = int(rec["close"]) + 1
		rec["last_event"] = eid
		recs[id] = rec
	refresh_rivalries(data)


static func refresh_rivalries(data: Dictionary) -> void:
	var names := {}
	for g in data["golfers"]:
		names[String(g["id"])] = String(g.get("name", g["id"]))
	var list: Array = []
	for id in (data["head_to_head"]["records"] as Dictionary):
		var r: Dictionary = data["head_to_head"]["records"][id]
		if int(r["close"]) >= CareerConfig.RIVAL_MIN_CLOSE:
			list.append({"id": id, "name": String(names.get(id, id)), "meetings": int(r["w"]) + int(r["l"]) + int(r["t"]),
				"wins": int(r["w"]), "losses": int(r["l"]), "ties": int(r["t"]), "close": int(r["close"])})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["close"] != b["close"]:
			return a["close"] > b["close"]
		if a["meetings"] != b["meetings"]:
			return a["meetings"] > b["meetings"]
		return String(a["id"]) < String(b["id"]))
	data["rivalries"] = list.slice(0, CareerConfig.RIVAL_MAX_LISTED)


static func featured_rivals(data: Dictionary) -> Array:
	return (data.get("rivalries", []) as Array).slice(0, CareerConfig.RIVAL_MAX_FEATURED)


## Head-to-head record of the human against one golfer: {w,l,t,close} (zeros when they never met).
static func record_against(data: Dictionary, id: String) -> Dictionary:
	return (data["head_to_head"]["records"] as Dictionary).get(id, {"w": 0, "l": 0, "t": 0, "close": 0})

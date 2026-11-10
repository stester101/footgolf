class_name AdaptiveDifficulty
extends RefCounted
## Adaptive difficulty (owner decision 2026-11-10). Affects OPPONENTS ONLY: a rating offset added to every AI golfer
## in the events the player plays. It never touches the player's physics, footballer stats or shots.
## State (`data.adaptive`): {mode: "off"|"balanced"|"hard", offset: float, window: [{event_id, score}], applied: {event_id: true}}.
## Per played event the player's result is compared with the finish expected from the world rank
## (score = expected percentile - actual percentile; positive = better than expected). The mean of the last
## CareerConfig.ADAPTIVE_WINDOW scores moves the offset by +-ADAPTIVE_STEP (capped by ADAPTIVE_CAP). Pure
## arithmetic, no RNG, applied once per event id (`applied`), so a retried save or replay never double-applies.
## Every number is in CareerConfig (PROPOSED DEFAULT - OWNER APPROVAL REQUIRED).


static func default_state() -> Dictionary:
	return {"mode": "balanced", "offset": 0.0, "window": [], "applied": {}}


static func mode(data: Dictionary) -> String:
	var m := String((data.get("adaptive", {}) as Dictionary).get("mode", "balanced"))
	return m if CareerConfig.ADAPTIVE_MODES.has(m) else "balanced"


## The opponent rating offset in force for the NEXT event entered.
static func current_offset(data: Dictionary) -> float:
	match mode(data):
		"off":
			return 0.0
		"hard":
			return CareerConfig.ADAPTIVE_HARD_LOCK_OFFSET
	return clampf(float((data.get("adaptive", {}) as Dictionary).get("offset", 0.0)), -CareerConfig.ADAPTIVE_CAP, CareerConfig.ADAPTIVE_CAP)


## Expected finish percentile (0 = winning, 1 = last) of a player with world rank `player_rank` in a field whose
## golfers have the world ranks `field_ranks` (the player excluded).
static func expected_percentile(player_rank: int, field_ranks: Array) -> float:
	var better := 0
	for r in field_ranks:
		if int(r) < player_rank:
			better += 1
	return float(better) / float(maxi(1, field_ranks.size()))


static func actual_percentile(place: int, field_size: int) -> float:
	return float(clampi(place, 1, maxi(1, field_size)) - 1) / float(maxi(1, field_size - 1))


static func score_of(expected_pct: float, place: int, field_size: int) -> float:
	return expected_pct - actual_percentile(place, field_size)


## Records one played event (idempotent per event id) and recomputes the offset. Returns true when applied now.
static func record(data: Dictionary, event_id: String, score: float) -> bool:
	if not data.has("adaptive"):
		data["adaptive"] = default_state()
	var a: Dictionary = data["adaptive"]
	var applied: Dictionary = a["applied"]
	if applied.has(event_id):
		return false
	applied[event_id] = true
	var w: Array = a["window"]
	w.append({"event_id": event_id, "score": snappedf(score, 0.0001)})
	while w.size() > CareerConfig.ADAPTIVE_WINDOW:
		w.pop_front()
	if mode(data) == "balanced":
		var sum := 0.0
		for x in w:
			sum += float((x as Dictionary)["score"])
		var mean := sum / float(w.size())
		var off := float(a.get("offset", 0.0))
		if mean > CareerConfig.ADAPTIVE_HOT_ABOVE:
			off += CareerConfig.ADAPTIVE_STEP
		elif mean < CareerConfig.ADAPTIVE_COOL_BELOW:
			off -= CareerConfig.ADAPTIVE_STEP
		a["offset"] = clampf(off, -CareerConfig.ADAPTIVE_CAP, CareerConfig.ADAPTIVE_CAP)
	return true


static func set_mode(data: Dictionary, m: String) -> bool:
	if not CareerConfig.ADAPTIVE_MODES.has(m):
		return false
	if not data.has("adaptive"):
		data["adaptive"] = default_state()
	(data["adaptive"] as Dictionary)["mode"] = m
	return true


## Plain-language hint for the player: hot (rivals are in form), steady, cooling.
static func hint(data: Dictionary) -> String:
	var o := current_offset(data)
	if o >= CareerConfig.ADAPTIVE_HINT_AT:
		return "hot"
	if o <= -CareerConfig.ADAPTIVE_HINT_AT:
		return "cooling"
	return "steady"


static func hint_text(data: Dictionary) -> String:
	return {"hot": "Rivals form: hot (the field is playing well)", "cooling": "Rivals form: cooling (the field is struggling)",
		"steady": "Rivals form: steady"}[hint(data)]


## Copy of the id->golfer map with every AI golfer's rating shifted by `offset` (the human is untouched).
static func shifted(golfers_by_id: Dictionary, offset: float) -> Dictionary:
	if offset == 0.0:
		return golfers_by_id
	var out := {}
	for id in golfers_by_id:
		var g: Dictionary = golfers_by_id[id]
		if bool(g.get("is_human", false)):
			out[id] = g
		else:
			var c := g.duplicate()
			c["rating"] = clampf(float(g.get("rating", 70.0)) + offset, CareerConfig.RATING_MIN, CareerConfig.RATING_MAX)
			out[id] = c
	return out

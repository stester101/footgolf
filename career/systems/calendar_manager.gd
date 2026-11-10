class_name CalendarManager
extends RefCounted
## Builds the season calendar (events as Dictionaries, see career/models/README.md) from CareerConfig, and
## answers eligibility questions. Pure logic. Event names / course assignment are provisional (CareerConfig).

const REGULAR_SUFFIX := ["Open", "Invitational", "Classic", "Challenge", "Trophy"]
const FLAGSHIP_NAMES := ["Aurora Championship", "Meridian Cup", "Harbour Players Championship", "Summit Invitational", "Crown Cup", "Cascade Championship", "Beacon Cup"]
const MAJOR_NAMES := ["Highland Grand Championship", "Sovereign Open", "Heritage Classic Major", "Pinnacle Championship"]
const FINALE_NAME := "Tour Championship"


## season_number: 1-based. Event ids are "s<season>_e<serial>".
static func build(length: String, season_number: int) -> Array:
	if not CareerConfig.EVENT_COUNTS.has(length):
		return []
	var counts: Dictionary = CareerConfig.EVENT_COUNTS[length]
	var total := CareerConfig.total_events(length)
	var n := total - 1  # the finale is always last
	var slots: Array = []
	slots.resize(n)
	slots.fill("regular")
	var majors := int(counts["major"])
	for k in majors:  # evenly through the season
		_place(slots, int(round(float(k + 1) * n / float(majors + 1))) - 1, "major")
	var fl := int(counts["flagship"])
	for k in fl:
		_place(slots, int(round((float(k) + 0.5) * n / float(fl))), "flagship")
	slots.append("finale")
	var events: Array = []
	var per_cat := {"regular": 0, "flagship": 0, "major": 0, "finale": 0}
	for i in slots.size():
		var cat: String = slots[i]
		var idx := int(per_cat[cat])
		per_cat[cat] = idx + 1
		events.append(_make_event(season_number, i + 1, cat, idx))
	return events


## Put `cat` at `pos`, or at the nearest free slot.
static func _place(slots: Array, pos: int, cat: String) -> void:
	pos = clampi(pos, 0, slots.size() - 1)
	for d in slots.size():
		for cand in [pos + d, pos - d]:
			if cand >= 0 and cand < slots.size() and slots[cand] == "regular":
				slots[cand] = cat
				return


static func _course_for(cat: String, idx: int) -> String:
	var list: Array = CareerConfig.REGULAR_COURSES
	match cat:
		"flagship":
			list = CareerConfig.FLAGSHIP_COURSES
		"major":
			list = CareerConfig.MAJOR_COURSES
		"finale":
			return CareerConfig.FINALE_COURSE
	return String(list[idx % list.size()])


static func cut_for(cat: String, idx: int) -> Dictionary:
	match cat:
		"major":
			return {"type": "percent", "after_round": CareerConfig.CUT_AFTER_ROUND, "percent": CareerConfig.CUT_PERCENT}
		"flagship":
			if idx % CareerConfig.FLAGSHIP_CUT_EVERY == CareerConfig.FLAGSHIP_CUT_EVERY - 1:
				return {"type": "percent", "after_round": CareerConfig.CUT_AFTER_ROUND, "percent": CareerConfig.CUT_PERCENT}
	return {"type": "none", "after_round": 0}


static func _make_event(season_number: int, serial: int, cat: String, idx: int) -> Dictionary:
	var course_id := _course_for(cat, idx)
	var course_name := String(CourseSource.course_info(course_id).get("name", course_id))
	var title := ""
	match cat:
		"regular":
			title = "%s %s" % [course_name, REGULAR_SUFFIX[idx % REGULAR_SUFFIX.size()]]
		"flagship":
			title = FLAGSHIP_NAMES[idx % FLAGSHIP_NAMES.size()]
		"major":
			title = MAJOR_NAMES[idx % MAJOR_NAMES.size()]
		_:
			title = FINALE_NAME
	return {
		"id": "s%d_e%02d" % [season_number, serial], "serial": serial, "category": cat, "name": title,
		"course_id": course_id, "rounds": int(CareerConfig.ROUNDS[cat]), "cut": cut_for(cat, idx),
		"purse": int(CareerConfig.PURSE[cat]), "field_size": int(CareerConfig.FIELD_SIZE[cat]),
		"points": {"winner": int(CareerConfig.SEASON_WINNER_POINTS[cat])},
		"world_points": {"winner": int(CareerConfig.WINNER_POINTS[cat])},
		"status": "upcoming", "result": {},
	}


static func count_by_category(events: Array) -> Dictionary:
	var c := {"regular": 0, "flagship": 0, "major": 0, "finale": 0}
	for e in events:
		c[String(e["category"])] = int(c[String(e["category"])]) + 1
	return c


## status of the player for eligibility: {world_rank, season_rank, season_wins:Array[category], }
## Returns {eligible:bool, requirement:String}. The requirement text always states what is needed (and yours).
static func eligibility(event: Dictionary, st: Dictionary) -> Dictionary:
	var rank := int(st.get("world_rank", CareerConfig.START_WORLD_RANK))
	var wins: Array = st.get("season_wins", [])
	var cat := String(event["category"])
	match cat:
		"flagship":
			var ok := rank <= CareerConfig.FLAGSHIP_MAX_WORLD_RANK or not wins.is_empty()
			return {"eligible": ok, "requirement": "World Ranking top %d (yours: %d) or a win earlier this season" % [CareerConfig.FLAGSHIP_MAX_WORLD_RANK, rank]}
		"major":
			var ok2 := rank <= CareerConfig.MAJOR_MAX_WORLD_RANK or wins.has("flagship") or wins.has("major")
			return {"eligible": ok2, "requirement": "World Ranking top %d (yours: %d) or a flagship/major win this season" % [CareerConfig.MAJOR_MAX_WORLD_RANK, rank]}
		"finale":
			var sr := int(st.get("season_rank", 9999))
			return {"eligible": sr <= CareerConfig.FINALE_QUALIFIERS, "requirement": "Top %d in the season standings (yours: %s)" % [CareerConfig.FINALE_QUALIFIERS, str(sr) if sr < 9999 else "unranked"]}
	return {"eligible": true, "requirement": "Open to all tour-card holders"}


static func category_label(cat: String) -> String:
	return {"regular": "Regular", "flagship": "Flagship", "major": "Major", "finale": "Tour Championship"}.get(cat, cat)


static func cut_text(cut: Dictionary) -> String:
	match String(cut.get("type", "none")):
		"percent":
			return "Cut after round %d: top %d%% and ties" % [int(cut["after_round"]), int(cut["percent"])]
		"top_n":
			return "Cut after round %d: top %d and ties" % [int(cut["after_round"]), int(cut["n"])]
	return "No cut"

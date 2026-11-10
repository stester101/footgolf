class_name QualificationManager
extends RefCounted
## Entry eligibility, exemptions (with explanations) and field construction.
## ctx = build_context(...): {season, world_rank:{id:rank}, standings_rank:{id:rank}, prev_standings_rank:{id:rank},
##   standings_started: bool}. Optional golfer fields: tour_card (default true), injured_until (event order),
## honours [{season, category, event_id}]. Optional event field: order (monotonic event counter, default 0).


static func build_context(world: Dictionary, standings: Dictionary, golfers: Array, season: int, prev_standings_rank: Dictionary = {}) -> Dictionary:
	var wr := RankingManager.rank_map(RankingManager.world_table(world, golfers, season))
	var st := RankingManager.rank_map(RankingManager.standings_table(standings, golfers, wr))
	var started: bool = not standings["applied"].is_empty()
	return {"season": season, "world_rank": wr, "standings_rank": st, "prev_standings_rank": prev_standings_rank, "standings_started": started}


static func requirement_text(category: String) -> String:
	match category:
		"regular":
			return "Open to LBT card holders."
		"flagship":
			return "Top %d in the World Ranking, or an exemption (%s)." % [CareerConfig.FLAGSHIP_MAX_WORLD_RANK, _exemption_summary("flagship")]
		"major":
			return "Top %d in the World Ranking, or an exemption (%s)." % [CareerConfig.MAJOR_MAX_WORLD_RANK, _exemption_summary("major")]
		"finale":
			return "Top %d in the Season Standings." % CareerConfig.FINALE_QUALIFIERS
	return "Unknown event category."


static func _exemption_summary(category: String) -> String:
	var parts: Array = [
		"major champion in the last %d seasons" % CareerConfig.EXEMPT_MAJOR_WIN_SEASONS,
		"reigning season champion",
		"top %d of last season's standings" % CareerConfig.EXEMPT_PREV_STANDINGS_TOP,
		"top %d of this season's standings" % CareerConfig.EXEMPT_CURRENT_STANDINGS_TOP,
	]
	if category == "flagship":
		parts.append("LBT event winner this or last season")
	else:
		parts.append("flagship winner this or last season")
	return ", ".join(parts)


static func is_available(golfer: Dictionary, event: Dictionary) -> bool:
	if str(golfer.get("status", "active")) == "retired":
		return false
	return int(event.get("order", 0)) >= int(golfer.get("injured_until", 0))


## Why (and whether) this golfer may enter this event.
## Returns {eligible, via ("rank"|"exemption"|"open"|"standings"|""), reason, requirement, exemptions[], world_rank, standings_rank}.
static func check(golfer: Dictionary, event: Dictionary, ctx: Dictionary) -> Dictionary:
	var category: String = str(event.get("category", "regular"))
	var id := str(golfer.get("id", ""))
	var wr: int = int(ctx["world_rank"].get(id, 0))
	var sr: int = int(ctx["standings_rank"].get(id, 0))
	var out := {"eligible": false, "via": "", "reason": "", "requirement": requirement_text(category), "exemptions": [], "world_rank": wr, "standings_rank": sr}
	if str(golfer.get("status", "active")) == "retired":
		out["reason"] = "Not eligible: retired."
		return out
	if int(event.get("order", 0)) < int(golfer.get("injured_until", 0)):
		out["reason"] = "Not eligible: injured, unavailable until event %d." % int(golfer["injured_until"])
		return out
	if category != "finale" and not bool(golfer.get("tour_card", true)):
		out["reason"] = "Not eligible: no LBT card (use a sponsor wildcard, or earn the card back). Requirement: %s" % out["requirement"]
		return out
	match category:
		"regular":
			out["eligible"] = true
			out["via"] = "open"
			out["reason"] = "Eligible: LBT card holder.""
		"finale":
			if sr > 0 and sr <= CareerConfig.FINALE_QUALIFIERS:
				out["eligible"] = true
				out["via"] = "standings"
				out["reason"] = "Eligible: %s in the Season Standings (top %d qualify)." % [_ord(sr), CareerConfig.FINALE_QUALIFIERS]
			else:
				out["reason"] = "Not eligible: %s in the Season Standings. Requires top %d." % [_ord(sr) if sr > 0 else "unranked", CareerConfig.FINALE_QUALIFIERS]
		_:
			var limit: int = CareerConfig.FLAGSHIP_MAX_WORLD_RANK if category == "flagship" else CareerConfig.MAJOR_MAX_WORLD_RANK
			var ex := exemptions(golfer, category, ctx)
			out["exemptions"] = ex
			if wr > 0 and wr <= limit:
				out["eligible"] = true
				out["via"] = "rank"
				out["reason"] = "Eligible: World Ranking %d is inside the top %d." % [wr, limit]
			elif not ex.is_empty():
				out["eligible"] = true
				out["via"] = "exemption"
				out["reason"] = "Eligible by exemption: %s. (World Ranking %s; top %d otherwise required.)" % ["; ".join(ex), str(wr) if wr > 0 else "unranked", limit]
			else:
				out["reason"] = "Not eligible: World Ranking %s and no exemption. Requirement: %s" % [str(wr) if wr > 0 else "unranked", out["requirement"]]
	return out


static func exemptions(golfer: Dictionary, category: String, ctx: Dictionary) -> Array:
	var id := str(golfer.get("id", ""))
	var season: int = int(ctx["season"])
	var res: Array = []
	if category != "flagship" and category != "major":
		return res
	var major_year := -999
	var champ_year := -999
	var win_year := -999   # regular/flagship wins (flagship wins only count for majors)
	for h in golfer.get("honours", []):
		var s: int = int(h.get("season", -999))
		var c: String = str(h.get("category", ""))
		if c == "major":
			major_year = maxi(major_year, s)
		elif c == "finale":
			champ_year = maxi(champ_year, s)
		elif c == "flagship" or (c == "regular" and category == "flagship"):
			win_year = maxi(win_year, s)
	if major_year > -999 and season - major_year < CareerConfig.EXEMPT_MAJOR_WIN_SEASONS:
		res.append("major champion (%d)" % major_year)
	if champ_year > -999 and season - champ_year <= 1:
		res.append("season champion (%d)" % champ_year)
	var ps: int = int(ctx["prev_standings_rank"].get(id, 0))
	if ps > 0 and ps <= CareerConfig.EXEMPT_PREV_STANDINGS_TOP:
		res.append("finished %s in last season's standings" % _ord(ps))
	var cs: int = int(ctx["standings_rank"].get(id, 0))
	if bool(ctx.get("standings_started", false)) and cs > 0 and cs <= CareerConfig.EXEMPT_CURRENT_STANDINGS_TOP:
		res.append("%s in this season's standings" % _ord(cs))
	if win_year > -999 and season - win_year < CareerConfig.EXEMPT_WIN_SEASONS:
		res.append("%s winner (%d)" % ["LBT event" if category == "flagship" else "flagship", win_year])
	return res


## Build the field. Returns {field: Array of golfer dicts, ids, player_in, invited (ids filled by invitation),
## shortfall, player_check}. The human entity (is_human) is included when eligible; AI fill the remaining places
## by priority (world rank minus form bonus; finale = season standings order). When fewer AI qualify than there
## are places (e.g. majors), the next-ranked available golfers are invited (listed in `invited`).
static func build_field(event: Dictionary, golfers: Array, ctx: Dictionary) -> Dictionary:
	var category: String = str(event.get("category", "regular"))
	var size: int = int(event.get("field_size", CareerConfig.FIELD_SIZE.get(category, 72)))
	var human: Dictionary = {}
	var ai_eligible: Array = []
	var ai_other: Array = []
	for g in golfers:
		if bool(g.get("is_human", false)):
			human = g
			continue
		if not is_available(g, event):
			continue
		var chk := check(g, event, ctx)
		(ai_eligible if chk["eligible"] else ai_other).append(g)
	var field: Array = []
	var player_in := false
	var player_check := {}
	if not human.is_empty():
		player_check = check(human, event, ctx)
		if player_check["eligible"]:
			field.append(human)
			player_in = true
	var key := "standings_rank" if category == "finale" else "world_rank"
	var pri := func(g: Dictionary) -> float:
		var r: float = float(ctx[key].get(str(g["id"]), 9999))
		return r - CareerConfig.FIELD_FORM_RANK_BONUS * float(g.get("form", 0.0))
	var less := func(a: Dictionary, b: Dictionary) -> bool:
		var pa: float = pri.call(a)
		var pb: float = pri.call(b)
		if pa != pb:
			return pa < pb
		return str(a["id"]) < str(b["id"])
	ai_eligible.sort_custom(less)
	ai_other.sort_custom(less)
	var invited: Array = []
	for g in ai_eligible:
		if field.size() >= size:
			break
		field.append(g)
	for g in ai_other:
		if field.size() >= size:
			break
		field.append(g)
		invited.append(str(g["id"]))
	var ids: Array = []
	for g in field:
		ids.append(str(g["id"]))
	return {"field": field, "ids": ids, "player_in": player_in, "invited": invited, "shortfall": maxi(0, size - field.size()), "player_check": player_check}


## Season-standings ids that qualify for the finale (top 30 of the table).
static func finale_qualifiers(standings_table_rows: Array) -> Array:
	var ids: Array = []
	for r in standings_table_rows:
		if int(r["rank"]) <= CareerConfig.FINALE_QUALIFIERS:
			ids.append(r["id"])
	return ids


static func _ord(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [n, suffix]

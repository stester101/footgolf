class_name RoundText
extends RefCounted
## Plain-text round summary for copy/share (pure; presentation only, never decides scoring).


## Short label for a hole score against par: "Hole-in-one", "Eagle", "Birdie", "Par", "Bogey", ...
static func score_name(strokes: int, par: int) -> String:
	if strokes <= 0:
		return "-"
	if strokes == 1:
		return "Hole-in-one"
	match strokes - par:
		-3: return "Albatross"
		-2: return "Eagle"
		-1: return "Birdie"
		0: return "Par"
		1: return "Bogey"
		2: return "Double bogey"
	return "%+d" % (strokes - par)


## Multi-line summary of a finished (or partly played) RoundState.
static func build(rs: RoundState, title: String, player: String = "") -> String:
	var lines: Array[String] = []
	lines.append("Foot Golf - %s" % title if title != "" else "Foot Golf")
	if player != "":
		lines.append("Player: %s" % player)
	lines.append("Score %d (%s) · par %d · %d of %d holes" % [rs.total_score(), RoundState.fmt_relative(rs.relative_to_par()),
		rs.total_par_played(), rs.holes_completed(), rs.holes.size()])
	for h in rs.holes:
		var hs: HoleState = h
		if not hs.complete:
			continue
		var pen := " (+%d pen)" % hs.penalties if hs.penalties > 0 else ""
		lines.append("%s  par %d  %d  %s%s" % [hs.hole_name, hs.par, hs.score(), score_name(hs.score(), hs.par), pen])
	return "\n".join(lines)

class_name CareerConfig
extends RefCounted
## EVERY numeric/default value of Career Mode that the owner has not approved lives in this one file.
##
## ###########################################################################################
## # PROPOSED DEFAULT - OWNER APPROVAL REQUIRED                                              #
## # Figures come from the Career spec, Appendix A (sections 3 and 8). Not owner-approved.   #
## # Do not copy them into docs/DECISIONS.md as approved until the owner signs them off.     #
## ###########################################################################################
## Items marked [A: <section>] cite the Appendix. Items marked [INVENTED] are the implementer's provisional
## choice where the Appendix gives no figure (they are equally unapproved).

const SCHEMA_VERSION := 1

# --- start state [A: section 3 Career setup; section 8 item 1]
const START_WORLD_RANK := 180
const START_BALANCE := 0
const CURRENCY := "GBP"

# --- calendar [A: Calendar and events; section 8 item 2]
const SEASON_LENGTHS := ["short", "standard", "full"]
const EVENT_COUNTS := {
	"short": {"regular": 5, "flagship": 2, "major": 4, "finale": 1},
	"standard": {"regular": 13, "flagship": 5, "major": 4, "finale": 1},
	"full": {"regular": 29, "flagship": 7, "major": 4, "finale": 1},
}
const ROUNDS := {"regular": 2, "flagship": 3, "major": 4, "finale": 3}  # [A] regular 2, flagship 3, major 4, finale 3
const FIELD_SIZE := {"regular": 72, "flagship": 60, "major": 96, "finale": 30}  # [A section 8 item 3]
const FINALE_QUALIFIERS := 30  # CONFIRMED by the owner (decision 13), listed for completeness

# --- cuts [A: Cuts and playoffs; section 8 item 4]. type: none | top_n | percent (always "and ties")
const CUT_PERCENT := 50          # qualifying cut: top 50% and ties
const CUT_AFTER_ROUND := 2
## Every Nth flagship (1-based, counting from the first) has a cut; the others are no-cut. [INVENTED: "selected"]
const FLAGSHIP_CUT_EVERY := 2
## Majors: cut after round 2 [A]. Regular and finale: no cut [A].

# --- courses used per event category [INVENTED mapping onto the existing courses; 3-17 holes, never 18]
const REGULAR_COURSES := ["starter", "ridge", "coastal", "lakeside", "jizzy", "mesa"]
const FLAGSHIP_COURSES := ["jizzy", "mesa", "lakeside", "full9"]
const MAJOR_COURSES := ["jizzy", "full9", "mesa", "ridge"]
const FINALE_COURSE := "jizzy"

# --- eligibility [A: Rankings and eligibility; section 8 item 6]
const FLAGSHIP_MAX_WORLD_RANK := 100
const MAJOR_MAX_WORLD_RANK := 75
const TOUR_CARD_RETENTION_RANK := 125   # [A item 7] (retention review is a later phase)

# --- ranking [A: item 5] / points [INVENTED: decay shape and strength factor]
const WORLD_WINDOW_SEASONS := 2
const WORLD_AGE_WEIGHTS := [1.0, 0.5]   # weight of results this season / last season
const WINNER_POINTS := {"regular": 500, "flagship": 750, "major": 1000, "finale": 1000}  # [A] (finale world points INVENTED)
const SEASON_WINNER_POINTS := {"regular": 500, "flagship": 750, "major": 1000, "finale": 0}  # finale does not feed standings
const POINTS_DECAY_PER_PLACE := 0.93    # points(place) = winner * decay^(place-1), ties share the average
const FIELD_STRENGTH_BLEND := 0.4       # points *= (1 - blend) + blend * (field strength / REFERENCE)
const FIELD_STRENGTH_REFERENCE := 70.0
const BASELINE_POINTS_TOP := 4000.0     # initial ranking points of rank 1 ...
const BASELINE_POINTS_SCALE := 40.0     # ... falling off as exp(-(rank-1)/scale)

# --- opponent simulation [A: item 9 ratings 40-100; variance calibration INVENTED]
const RATING_MIN := 40.0
const RATING_MAX := 100.0
const MEAN_PER_HOLE_BEST := -0.30       # strokes vs par per hole at rating 100 on a neutral course
const MEAN_PER_HOLE_WORST := 0.45       # ... at rating 40
const FORM_EFFECT_PER_HOLE := 0.12      # form in [-1, 1]; positive form lowers the score
const FORM_RETAIN := 0.7                # form after an event = RETAIN * old + (1 - RETAIN) * performance
const EVENT_DIFFICULTY_PER_HOLE := {"regular": 0.0, "flagship": 0.03, "major": 0.08, "finale": 0.05}
const SD_PER_SQRT_HOLE := 0.62          # round score sd = SD * sqrt(holes) * (1.5 - consistency)
const ADAPTIVE_MAX_ADJUST_PER_HOLE := 0.05  # [A item 10] cap for the later adaptive-difficulty phase (unused: 0)

# --- prize money [A item 11: tables not given; ALL INVENTED]
const PURSE := {"regular": 400000, "flagship": 900000, "major": 2000000, "finale": 3000000}
const PAYOUT_DECAY := 0.88              # share(place) proportional to decay^(place-1) among players who made the cut
const MAX_SAVED_ACTIVE_SHOTS_INFO := 0

# --- save [A: Save/resume]
const KEEP_BACKUPS := 1


static func baseline_points(initial_rank: int) -> float:
	return BASELINE_POINTS_TOP * exp(-float(maxi(1, initial_rank) - 1) / BASELINE_POINTS_SCALE)


static func season_label(length: String) -> String:
	return {"short": "Short", "standard": "Standard", "full": "Full"}.get(length, length)


static func total_events(length: String) -> int:
	var t := 0
	for k in EVENT_COUNTS[length]:
		t += int(EVENT_COUNTS[length][k])
	return t

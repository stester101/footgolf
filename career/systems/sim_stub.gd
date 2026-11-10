class_name CareerSimStub
extends RefCounted
## STAND-IN for the opponent simulation (career/simulation/*). Same call shape as career/models/README.md:
##   simulate_round(field, event, round_index, course, seed, adaptive) -> {golfer_id: strokes}
## Deterministic per (seed, golfer id, round). Uses only CareerConfig numbers. The master swaps CareerManager.sim.


static func simulate_round(field: Array, event: Dictionary, round_index: int, course: Dictionary, p_seed: int, adaptive: float = 0.0) -> Dictionary:
	var holes := int(course.get("holes", 3))
	var par := int(course.get("par", holes * 4))
	var diff := float(course.get("difficulty", 0.0))
	var cat := String(event.get("category", "regular"))
	var out := {}
	for g in field:
		var rating := clampf(float(g.get("rating", 60.0)), CareerConfig.RATING_MIN, CareerConfig.RATING_MAX)
		var t := (rating - CareerConfig.RATING_MIN) / (CareerConfig.RATING_MAX - CareerConfig.RATING_MIN)
		var per_hole := lerpf(CareerConfig.MEAN_PER_HOLE_WORST, CareerConfig.MEAN_PER_HOLE_BEST, t)
		per_hole += float(CareerConfig.EVENT_DIFFICULTY_PER_HOLE.get(cat, 0.0)) + diff
		per_hole -= CareerConfig.FORM_EFFECT_PER_HOLE * clampf(float(g.get("form", 0.0)), -1.0, 1.0)
		per_hole += adaptive
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%d:%s:%d" % [p_seed, String(g["id"]), round_index])
		var sd := CareerConfig.SD_PER_SQRT_HOLE * sqrt(float(holes)) * (1.5 - clampf(float(g.get("consistency", 0.5)), 0.0, 1.0))
		out[String(g["id"])] = maxi(holes, int(round(par + per_hole * holes + rng.randfn(0.0, sd))))
	return out

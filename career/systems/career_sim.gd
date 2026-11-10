class_name CareerSim
extends RefCounted
## The live opponent simulation seen by TournamentManager (CareerManager.sim): adapts the call shape of
## career/models/README.md to OpponentSimulation, one golfer at a time. The field strength is frozen in
## event["field_strength"] when the event is entered, so a partial field (after the cut) scores exactly like the
## whole-field simulation OpponentSimulation.simulate_event_field used for the final result.


static func simulate_round(field: Array, event: Dictionary, round_index: int, course: Dictionary, p_seed: int, _adaptive: float = 0.0) -> Dictionary:
	var strength := float(event.get("field_strength", -1.0))
	var out := {}
	for g in field:
		out[String(g["id"])] = int(OpponentSimulation.simulate_round(g, course, event, round_index, p_seed, strength)["strokes"])
	return out

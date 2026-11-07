class_name HazardResolver
extends RefCounted
## Automatic, deterministic water / out-of-bounds relief (V0.1 simplified rule).
##
## Algorithm (engineering default):
##  1. Walk the recorded ball path BACKWARDS from the hazard entry point in 0.5 m steps and
##     take the first point that is in bounds, dry, clear of tree trunks, with a 1.5 m margin
##     ("line of entry" relief, i.e. near where the ball crossed into the hazard/boundary).
##  2. Otherwise fall back to the last validated safe ball position (the shot's start).
##  3. Otherwise the hole's relief_points, then the tee.
## The ball is placed at rest on the terrain surface. The +1 penalty is applied by scoring.

const MARGIN_M := 1.5
const STEP_M := 0.5


static func find_relief(hole: HoleDefinition, trail: PackedVector3Array, fallbacks: Array, radius: float) -> Dictionary:
	var n := trail.size()
	var i := n - 1
	while i >= 1:
		var a := trail[i]
		var b := trail[i - 1]
		var seg := Units.horizontal_distance(a, b)
		var steps := maxi(1, int(ceil(seg / STEP_M)))
		for k in steps + 1:
			var p := a.lerp(b, float(k) / float(steps))
			if hole.is_safe_spot(p.x, p.z, MARGIN_M):
				return {"pos": _on_ground(hole, p.x, p.z, radius), "method": "line_of_entry"}
		i -= 1
	for fb in fallbacks:
		var p: Vector3 = fb
		if hole.is_safe_spot(p.x, p.z, 0.0):
			return {"pos": _on_ground(hole, p.x, p.z, radius), "method": "last_safe_position"}
	for rp in hole.relief_points:
		var q: Vector2 = rp
		if hole.is_safe_spot(q.x, q.y, 0.0):
			return {"pos": _on_ground(hole, q.x, q.y, radius), "method": "hole_relief_point"}
	return {"pos": hole.tee_position(radius), "method": "tee"}


static func _on_ground(hole: HoleDefinition, x: float, z: float, radius: float) -> Vector3:
	return Vector3(x, hole.terrain_height(x, z) + radius, z)

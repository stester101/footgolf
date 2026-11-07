class_name TerrainBuilder
extends RefCounted
## Builds the visual terrain mesh from the SAME HoleDefinition height and surface functions
## used by physics, so visual surface regions correspond to physics lies.

const COLORS := {
	Surface.Type.TEE: Color(0.36, 0.62, 0.24),
	Surface.Type.FAIRWAY: Color(0.36, 0.60, 0.22),
	Surface.Type.FRINGE: Color(0.33, 0.58, 0.22),
	Surface.Type.GREEN: Color(0.38, 0.68, 0.27),
	Surface.Type.ROUGH: Color(0.23, 0.42, 0.14),
	Surface.Type.BUNKER: Color(0.86, 0.79, 0.60),
	Surface.Type.WATER: Color(0.18, 0.22, 0.13),
	Surface.Type.OOB: Color(0.20, 0.36, 0.12),
}
const MOWN := [Surface.Type.TEE, Surface.Type.FAIRWAY, Surface.Type.GREEN]
const EDGE_BLEND := 22.0


static func outer_height(hole: HoleDefinition) -> float:
	var r := hole.bounds
	var s := 0.0
	var n := 0
	for i in 9:
		var t := float(i) / 8.0
		for p in [Vector2(r.position.x + r.size.x * t, r.position.y), Vector2(r.position.x + r.size.x * t, r.end.y),
				Vector2(r.position.x, r.position.y + r.size.y * t), Vector2(r.end.x, r.position.y + r.size.y * t)]:
			s += hole.terrain_height(p.x, p.y)
			n += 1
	return s / float(n)


static func build_mesh(hole: HoleDefinition, spacing: float) -> ArrayMesh:
	var r := hole.bounds
	var nx := int(ceil(r.size.x / spacing)) + 1
	var nz := int(ceil(r.size.y / spacing)) + 1
	var outer_h := outer_height(hole)
	var count := nx * nz
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var norms := PackedVector3Array()
	verts.resize(count)
	cols.resize(count)
	norms.resize(count)
	var heights := PackedFloat32Array()
	heights.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(hole.id)
	for iz in nz:
		var z := r.position.y + iz * spacing
		for ix in nx:
			var x := r.position.x + ix * spacing
			var h := hole.terrain_height(x, z)
			var edge := minf(minf(x - r.position.x, r.end.x - x), minf(z - r.position.y, r.end.y - z))
			var w := 1.0 - smoothstep(0.0, EDGE_BLEND, edge)
			if w > 0.0 and not hole.in_bounds(x, z):
				h = lerpf(h, outer_h, w)
			var idx := iz * nx + ix
			heights[idx] = h
			verts[idx] = Vector3(x, h, z)
			var surf := hole.surface_at(x, z)
			var c: Color = COLORS.get(surf, COLORS[Surface.Type.ROUGH])
			var jitter := rng.randf_range(-0.025, 0.025)
			c = Color(c.r + jitter, c.g + jitter * 1.2, c.b + jitter * 0.5)
			var lc := c.srgb_to_linear()
			lc.a = 1.0 if MOWN.has(surf) else 0.0
			cols[idx] = lc
	for iz in nz:
		for ix in nx:
			var idx := iz * nx + ix
			var hl := heights[iz * nx + maxi(ix - 1, 0)]
			var hr := heights[iz * nx + mini(ix + 1, nx - 1)]
			var hd := heights[maxi(iz - 1, 0) * nx + ix]
			var hu := heights[mini(iz + 1, nz - 1) * nx + ix]
			norms[idx] = Vector3(hl - hr, 2.0 * spacing, hd - hu).normalized()
	var idxs := PackedInt32Array()
	idxs.resize((nx - 1) * (nz - 1) * 6)
	var k := 0
	for iz in nz - 1:
		for ix in nx - 1:
			var a := iz * nx + ix
			var b := a + 1
			var c2 := a + nx
			var d := c2 + 1
			idxs[k] = a
			idxs[k + 1] = b
			idxs[k + 2] = c2
			idxs[k + 3] = b
			idxs[k + 4] = d
			idxs[k + 5] = c2
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func ellipse_mesh(e: HoleDefinition.Ellipse, y: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idxs := PackedInt32Array()
	verts.append(Vector3(e.cx, y, e.cz))
	norms.append(Vector3.UP)
	for i in segments:
		var p := e.point_at(TAU * float(i) / float(segments))
		verts.append(Vector3(p.x, y, p.y))
		norms.append(Vector3.UP)
	for i in segments:
		idxs.append(0)
		idxs.append(1 + i)
		idxs.append(1 + (i + 1) % segments)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

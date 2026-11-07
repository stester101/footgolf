class_name TerrainBuilder
extends RefCounted
## Builds the visual terrain mesh from the SAME HoleDefinition height and surface functions
## used by physics, so visual surface regions correspond to physics lies.

## sRGB base colours. Alpha in the surface map: 1 = mown stripes, 0.5 = clumpy rough, 0 = none.
const COLORS := {
	Surface.Type.TEE: Color(0.42, 0.66, 0.22),
	Surface.Type.FAIRWAY: Color(0.40, 0.64, 0.20),
	Surface.Type.FRINGE: Color(0.36, 0.60, 0.20),
	Surface.Type.GREEN: Color(0.46, 0.74, 0.26),
	Surface.Type.ROUGH: Color(0.30, 0.50, 0.16),
	Surface.Type.BUNKER: Color(0.90, 0.83, 0.64),
	Surface.Type.WATER: Color(0.22, 0.24, 0.14),
	Surface.Type.OOB: Color(0.21, 0.37, 0.12),
}
const SURFACE_ALPHA := {
	Surface.Type.TEE: 1.0, Surface.Type.FAIRWAY: 1.0, Surface.Type.GREEN: 1.0,
	Surface.Type.FRINGE: 0.9, Surface.Type.ROUGH: 0.5, Surface.Type.OOB: 0.5,
	Surface.Type.BUNKER: 0.0, Surface.Type.WATER: 0.0,
}
const MAP_M_PER_PX := 1.0


## Per-pixel surface colour map covering hole.bounds (same classifier as physics).
static func build_surface_texture(hole: HoleDefinition) -> ImageTexture:
	var r := hole.bounds
	var w := int(ceil(r.size.x / MAP_M_PER_PX))
	var h := int(ceil(r.size.y / MAP_M_PER_PX))
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var k := 0
	var cache := {}
	for t in COLORS.keys():
		var c: Color = COLORS[t]
		cache[t] = PackedByteArray([c.r8, c.g8, c.b8, int(float(SURFACE_ALPHA[t]) * 255.0)])
	for iy in h:
		var z := r.position.y + (iy + 0.5) * MAP_M_PER_PX
		for ix in w:
			var x := r.position.x + (ix + 0.5) * MAP_M_PER_PX
			var px: PackedByteArray = cache[hole.surface_at(x, z)]
			data[k] = px[0]
			data[k + 1] = px[1]
			data[k + 2] = px[2]
			data[k + 3] = px[3]
			k += 4
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
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
	var uvs := PackedVector2Array()
	verts.resize(count)
	cols.resize(count)
	norms.resize(count)
	uvs.resize(count)
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
			if w > 0.0:
				h = lerpf(h, outer_h, w)
			var idx := iz * nx + ix
			heights[idx] = h
			verts[idx] = Vector3(x, h, z)
			uvs[idx] = Vector2((x - r.position.x) / r.size.x, (z - r.position.y) / r.size.y)
			cols[idx] = Color(1, 1, 1, 1)
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
	arrays[Mesh.ARRAY_TEX_UV] = uvs
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

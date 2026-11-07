class_name TerrainBuilder
extends RefCounted
## Builds the visual terrain mesh from the SAME HoleDefinition height and surface functions
## used by physics, so visual surface regions correspond to physics lies.
## Work is incremental (row by row against a time deadline) so a hole can be prepared over
## several frames while a loading bar runs; the static helpers build everything in one go.

## sRGB base colours (the turf shader adds stripes, clumps, grain and tint variation on top).
const COLORS := {
	Surface.Type.TEE: Color(0.40, 0.62, 0.22),
	Surface.Type.FAIRWAY: Color(0.38, 0.60, 0.20),
	Surface.Type.FRINGE: Color(0.36, 0.58, 0.21),
	Surface.Type.GREEN: Color(0.42, 0.66, 0.25),
	Surface.Type.ROUGH: Color(0.29, 0.46, 0.15),
	Surface.Type.BUNKER: Color(0.88, 0.80, 0.62),
	Surface.Type.WATER: Color(0.22, 0.24, 0.14),
	Surface.Type.OOB: Color(0.25, 0.41, 0.14),
}
## Surface "kind" weights for the turf shader: R = mown fairway/tee/fringe, G = putting green,
## B = rough/long grass, A = sand. Stored in a second map texture.
const KINDS := {
	Surface.Type.TEE: Color(1.0, 0.0, 0.0, 0.0),
	Surface.Type.FAIRWAY: Color(1.0, 0.0, 0.0, 0.0),
	Surface.Type.FRINGE: Color(0.45, 0.0, 0.25, 0.0),
	Surface.Type.GREEN: Color(0.0, 1.0, 0.0, 0.0),
	Surface.Type.ROUGH: Color(0.0, 0.0, 1.0, 0.0),
	Surface.Type.OOB: Color(0.0, 0.0, 1.0, 0.0),
	Surface.Type.BUNKER: Color(0.0, 0.0, 0.0, 1.0),
	Surface.Type.WATER: Color(0.0, 0.0, 0.0, 0.0),
}
const MAP_M_PER_PX := 1.0
const MAP_MAX_PIXELS := 120000.0
const MESH_TARGET_VERTS := 45000.0
const EDGE_BLEND := 22.0

var hole: HoleDefinition
var spacing := 2.0
var nx := 0
var nz := 0
var outer_h := 0.0
var heights := PackedFloat32Array()
# surface maps
var map_w := 0
var map_h := 0
var map_mpp := 1.0
var color_bytes := PackedByteArray()
var kind_bytes := PackedByteArray()

var _row := 0
var _nrow := 0
var _map_row := 0
var _verts := PackedVector3Array()
var _norms := PackedVector3Array()
var _uvs := PackedVector2Array()


func _init(p_hole: HoleDefinition, p_spacing: float = -1.0) -> void:
	hole = p_hole
	spacing = p_spacing if p_spacing > 0.0 else mesh_spacing(p_hole)
	var r := hole.bounds
	nx = int(ceil(r.size.x / spacing)) + 1
	nz = int(ceil(r.size.y / spacing)) + 1
	outer_h = outer_height(hole)
	var count := nx * nz
	heights.resize(count)
	_verts.resize(count)
	_norms.resize(count)
	_uvs.resize(count)
	map_mpp = map_scale(hole)
	map_w = int(ceil(r.size.x / map_mpp))
	map_h = int(ceil(r.size.y / map_mpp))
	color_bytes.resize(map_w * map_h * 4)
	kind_bytes.resize(map_w * map_h * 4)


## Metres per surface-map pixel: 1 m, coarser on very large holes (keeps load time bounded).
static func map_scale(p_hole: HoleDefinition) -> float:
	return maxf(MAP_M_PER_PX, sqrt(p_hole.bounds.get_area() / MAP_MAX_PIXELS))


static func mesh_spacing(p_hole: HoleDefinition) -> float:
	return clampf(sqrt(p_hole.bounds.get_area() / MESH_TARGET_VERTS), 2.0, 3.2)


static func outer_height(p_hole: HoleDefinition) -> float:
	var r := p_hole.bounds
	var s := 0.0
	var n := 0
	for i in 9:
		var t := float(i) / 8.0
		for p in [Vector2(r.position.x + r.size.x * t, r.position.y), Vector2(r.position.x + r.size.x * t, r.end.y),
				Vector2(r.position.x, r.position.y + r.size.y * t), Vector2(r.end.x, r.position.y + r.size.y * t)]:
			s += p_hole.terrain_height(p.x, p.y)
			n += 1
	return s / float(n)


## Relative cost of the remaining work units (for a loading bar).
func total_work() -> float:
	return float(nx * nz) * 1.2 + float(map_w * map_h) * 0.25


func done_work() -> float:
	return float(_row * nx) + float(_nrow * nx) * 0.2 + float(_map_row * map_w) * 0.25


func is_done() -> bool:
	return _row >= nz and _nrow >= nz and _map_row >= map_h


## Advance height rows, then normal rows, then surface-map rows until `deadline_usec`.
func step(deadline_usec: int) -> bool:
	var r := hole.bounds
	while _row < nz:
		var z := r.position.y + _row * spacing
		for ix in nx:
			var x := r.position.x + ix * spacing
			var h := hole.terrain_height(x, z)
			var edge := minf(minf(x - r.position.x, r.end.x - x), minf(z - r.position.y, r.end.y - z))
			var w := 1.0 - smoothstep(0.0, EDGE_BLEND, edge)
			if w > 0.0:
				h = lerpf(h, outer_h, w)
			var idx := _row * nx + ix
			heights[idx] = h
			_verts[idx] = Vector3(x, h, z)
			_uvs[idx] = Vector2((x - r.position.x) / r.size.x, (z - r.position.y) / r.size.y)
		_row += 1
		if Time.get_ticks_usec() > deadline_usec:
			return false
	while _nrow < nz:
		var iz := _nrow
		for ix in nx:
			var hl := heights[iz * nx + maxi(ix - 1, 0)]
			var hr := heights[iz * nx + mini(ix + 1, nx - 1)]
			var hd := heights[maxi(iz - 1, 0) * nx + ix]
			var hu := heights[mini(iz + 1, nz - 1) * nx + ix]
			_norms[iz * nx + ix] = Vector3(hl - hr, 2.0 * spacing, hd - hu).normalized()
		_nrow += 1
		if _nrow % 8 == 0 and Time.get_ticks_usec() > deadline_usec:
			return false
	var cache_c := {}
	var cache_k := {}
	for t in COLORS.keys():
		var c: Color = COLORS[t]
		cache_c[t] = PackedByteArray([c.r8, c.g8, c.b8, 255])
		var kc: Color = KINDS[t]
		cache_k[t] = PackedByteArray([kc.r8, kc.g8, kc.b8, kc.a8])
	while _map_row < map_h:
		var z := r.position.y + (_map_row + 0.5) * map_mpp
		var k := _map_row * map_w * 4
		for ix in map_w:
			var x := r.position.x + (ix + 0.5) * map_mpp
			var s := hole.surface_at(x, z)
			var pc: PackedByteArray = cache_c[s]
			var pk: PackedByteArray = cache_k[s]
			color_bytes[k] = pc[0]
			color_bytes[k + 1] = pc[1]
			color_bytes[k + 2] = pc[2]
			color_bytes[k + 3] = 255
			kind_bytes[k] = pk[0]
			kind_bytes[k + 1] = pk[1]
			kind_bytes[k + 2] = pk[2]
			kind_bytes[k + 3] = pk[3]
			k += 4
		_map_row += 1
		if _map_row % 4 == 0 and Time.get_ticks_usec() > deadline_usec:
			return false
	return true


func build_all() -> void:
	while not step(Time.get_ticks_usec() + 1000000000):
		pass


func commit_mesh() -> ArrayMesh:
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
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _norms
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func color_texture() -> ImageTexture:
	var img := Image.create_from_data(map_w, map_h, false, Image.FORMAT_RGBA8, color_bytes)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func kind_texture() -> ImageTexture:
	var img := Image.create_from_data(map_w, map_h, false, Image.FORMAT_RGBA8, kind_bytes)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Height of the RENDERED terrain surface (same grid, edge blend and triangulation as the mesh).
func mesh_height_at(x: float, z: float) -> float:
	var r := hole.bounds
	var fx := clampf((x - r.position.x) / spacing, 0.0, nx - 1.001)
	var fz := clampf((z - r.position.y) / spacing, 0.0, nz - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var u := fx - ix
	var v := fz - iz
	var ha := heights[iz * nx + ix]
	var hb := heights[iz * nx + ix + 1]
	var hc := heights[(iz + 1) * nx + ix]
	var hd := heights[(iz + 1) * nx + ix + 1]
	# triangles (a, b, c) and (b, d, c): split along the b-c diagonal
	if u + v <= 1.0:
		return ha + (hb - ha) * u + (hc - ha) * v
	return hd + (hc - hd) * (1.0 - u) + (hb - hd) * (1.0 - v)


## Surface kind weights (RGBA as in KINDS) of the surface map at a world point (nearest pixel).
func kind_at(x: float, z: float) -> Color:
	var r := hole.bounds
	var px := clampi(int((x - r.position.x) / map_mpp), 0, map_w - 1)
	var pz := clampi(int((z - r.position.y) / map_mpp), 0, map_h - 1)
	var k := (pz * map_w + px) * 4
	return Color8(kind_bytes[k], kind_bytes[k + 1], kind_bytes[k + 2], kind_bytes[k + 3])


static func build_mesh(p_hole: HoleDefinition, p_spacing: float) -> ArrayMesh:
	var tb := TerrainBuilder.new(p_hole, p_spacing)
	tb.build_all()
	return tb.commit_mesh()


static func ellipse_mesh(e: HoleDefinition.Ellipse, y: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idxs := PackedInt32Array()
	verts.append(Vector3(e.cx, y, e.cz))
	norms.append(Vector3.UP)
	uvs.append(Vector2(0.0, 0.0))
	# two rings so the shore band (UV.x -> 1) gets its own gradient
	for ring in [0.82, 1.0]:
		for i in segments:
			var p := e.point_at(TAU * float(i) / float(segments))
			var q := Vector2(e.cx, e.cz).lerp(p, ring)
			verts.append(Vector3(q.x, y, q.y))
			norms.append(Vector3.UP)
			uvs.append(Vector2(ring, 0.0))
	for i in segments:
		idxs.append(0)
		idxs.append(1 + i)
		idxs.append(1 + (i + 1) % segments)
	for i in segments:
		var a := 1 + i
		var b := 1 + (i + 1) % segments
		var c := a + segments
		var d := b + segments
		idxs.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idxs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

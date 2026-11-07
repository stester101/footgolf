class_name TreeMeshes
extends RefCounted
## Procedural tree meshes (visual only; collision proxies stay the trunk cylinder + canopy
## ellipsoid from HoleDefinition). Vertex colours carry baked ambient occlusion (grey), the
## MultiMesh instance colour supplies the per-tree tint.
##
## Unit spaces:
##  - canopy_cluster: fills the unit sphere (|x|,|z| <= ~1, y in ~[-0.95, 0.95]) -> scaled by
##    (canopy_r, canopy_ry, canopy_r) around canopy_y, i.e. the physics ellipsoid.
##  - conifer: y in [0, 1], rim radius 1 at the bottom tier.
##  - trunk: y in [0, 1] (scaled by trunk height), radius 1 = trunk radius near the ground.


class _Builder:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idxs := PackedInt32Array()

	func add(v: Vector3, n: Vector3, ao: float, uv: Vector2 = Vector2.ZERO) -> int:
		verts.append(v)
		norms.append(n)
		cols.append(Color(ao, ao, ao, 1.0))
		uvs.append(uv)
		return verts.size() - 1

	func tri(a: int, b: int, c: int) -> void:
		idxs.append(a)
		idxs.append(b)
		idxs.append(c)

	func commit() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = idxs
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m


static func _noise(seed_val: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_val
	n.frequency = freq
	n.fractal_octaves = 2
	return n


## One lumpy UV-sphere lobe. Normals are blended towards the crown's radial direction so the
## whole canopy shades as one soft volume instead of a pile of balls.
static func _blob(b: _Builder, center: Vector3, rad: float, rings: int, segs: int, noise: FastNoiseLite, amp: float) -> void:
	var base := b.verts.size()
	for i in rings + 1:
		var th := PI * float(i) / float(rings)
		for j in segs:
			var ph := TAU * float(j) / float(segs)
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var p0 := center + d * rad
			var disp := noise.get_noise_3dv(p0 * 3.0) * amp
			var p := center + d * rad * (1.0 + disp)
			var radial := p.normalized() if p.length() > 0.01 else d
			var n := (d * 0.45 + radial * 0.55).normalized()
			var ao := clampf(0.42 + 0.32 * (p.y * 0.5 + 0.5) + 0.45 * (p.length() - 0.5), 0.38, 1.0)
			b.add(p, n, ao)
	for i in rings:
		for j in segs:
			var a := base + i * segs + j
			var c := base + i * segs + (j + 1) % segs
			var d2 := a + segs
			var e := c + segs
			b.tri(a, c, d2)
			b.tri(c, e, d2)


## Deciduous crown: a core lobe plus a ring of lobes and a top lobe, filling the unit ellipsoid.
static func canopy_cluster(seed_val: int, low_poly: bool = false) -> ArrayMesh:
	var b := _Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var noise := _noise(seed_val, 0.9)
	if low_poly:
		_blob(b, Vector3(0, 0, 0), 0.95, 5, 9, noise, 0.22)
		return b.commit()
	var rings := 6
	var segs := 10
	_blob(b, Vector3(0, -0.02, 0), 0.66, rings, segs, noise, 0.16)
	var n_side := 6
	var a0 := rng.randf() * TAU
	for k in n_side:
		var a := a0 + TAU * float(k) / float(n_side) + rng.randf_range(-0.3, 0.3)
		var dist := rng.randf_range(0.40, 0.50)
		var y := rng.randf_range(-0.42, 0.30)
		var r := rng.randf_range(0.42, 0.52)
		_blob(b, Vector3(cos(a) * dist, y, sin(a) * dist), r, 5, 8, noise, 0.2)
	_blob(b, Vector3(rng.randf_range(-0.1, 0.1), 0.46, rng.randf_range(-0.1, 0.1)), 0.46, 5, 8, noise, 0.2)
	return b.commit()


## Conifer: stacked drooping star-shaped skirts (jagged branch tips), narrowing to a leader tip.
static func conifer(seed_val: int, low_poly: bool = false) -> ArrayMesh:
	var b := _Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var tiers := 3 if low_poly else 6
	var points := 5 if low_poly else 7
	for i in tiers:
		var t := float(i) / float(tiers - 1)
		var rim_y := 0.78 * t
		var apex_y := rim_y + lerpf(0.34, 0.22, t)
		var radius := lerpf(1.0, 0.24, t) * rng.randf_range(0.94, 1.04)
		var rot := rng.randf() * TAU
		var ao_rim := lerpf(0.55, 0.85, t)
		var apex := b.add(Vector3(rng.randf_range(-0.02, 0.02), apex_y, rng.randf_range(-0.02, 0.02)), Vector3.UP, 1.0)
		var n := points * 2
		var first := b.verts.size()
		for j in n:
			var a := rot + TAU * float(j) / float(n) + rng.randf_range(-0.12, 0.12)
			var tip := j % 2 == 0
			var rr := radius * (rng.randf_range(0.95, 1.08) if tip else rng.randf_range(0.62, 0.72))
			var y := rim_y - (0.035 if tip else 0.0) * (1.0 - t * 0.5)
			var nrm := Vector3(cos(a) * 0.7, 0.72, sin(a) * 0.7).normalized()
			b.add(Vector3(cos(a) * rr, y, sin(a) * rr), nrm, ao_rim * (1.0 if tip else 0.86))
		for j in n:
			b.tri(apex, first + (j + 1) % n, first + j)
	return b.commit()


## Trunk with root flare and slight wobble; deciduous trunks get three limbs into the crown.
static func trunk(limbs: bool) -> ArrayMesh:
	var b := _Builder.new()
	var sides := 8
	var prof_y := [0.0, 0.05, 0.14, 0.5, 1.0]
	var prof_r := [1.5, 1.12, 1.0, 0.86, 0.6]
	for i in prof_y.size():
		var y: float = prof_y[i]
		for j in sides + 1:
			var a := TAU * float(j) / float(sides)
			var wob := 1.0 + 0.07 * sin(3.0 * a + y * 7.0) + 0.04 * sin(5.0 * a + 1.3)
			var r: float = prof_r[i] * wob
			b.add(Vector3(cos(a) * r, y, sin(a) * r), Vector3(cos(a), 0.15, sin(a)).normalized(), lerpf(0.7, 1.0, y), Vector2(float(j) / sides, y))
	for i in prof_y.size() - 1:
		for j in sides:
			var a := i * (sides + 1) + j
			var c := a + sides + 1
			b.tri(a, a + 1, c)
			b.tri(a + 1, c + 1, c)
	if limbs:
		for k in 3:
			var ang := 0.6 + TAU * float(k) / 3.0
			_tube(b, Vector3(0, 0.62, 0), Vector3(cos(ang) * 3.0, 1.05, sin(ang) * 3.0), 0.34, 0.14, 5)
	return b.commit()


static func _tube(b: _Builder, p0: Vector3, p1: Vector3, r0: float, r1: float, sides: int) -> void:
	var dir := (p1 - p0).normalized()
	var u := dir.cross(Vector3.UP)
	if u.length() < 0.01:
		u = Vector3.RIGHT
	u = u.normalized()
	var w := dir.cross(u).normalized()
	var base := b.verts.size()
	for e in 2:
		var c := p0 if e == 0 else p1
		var r := r0 if e == 0 else r1
		for j in sides:
			var a := TAU * float(j) / float(sides)
			var off := (u * cos(a) + w * sin(a))
			b.add(c + off * r, off, 0.8, Vector2(float(j) / sides, c.y))
	for j in sides:
		var a := base + j
		var c := base + (j + 1) % sides
		b.tri(a, c, a + sides)
		b.tri(c, c + sides, a + sides)


## Grass tuft: a few tapered, slightly curved blades fanned around the root (height 1, UV.y =
## 0 root .. 1 tip). Scaled per instance.
static func grass_tuft(seed_val: int, blades: int) -> ArrayMesh:
	var b := _Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for k in blades:
		var a := TAU * float(k) / float(blades) + rng.randf_range(-0.4, 0.4)
		var lean := rng.randf_range(0.15, 0.45)
		var h := rng.randf_range(0.65, 1.0)
		var w := rng.randf_range(0.05, 0.08)
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x)
		var root := dir * rng.randf_range(0.0, 0.12)
		var n := (dir * 0.3 + Vector3.UP).normalized()
		# root pair, mid pair, tip
		var mid := root + dir * lean * 0.35 * h + Vector3.UP * 0.55 * h
		var tip := root + dir * lean * h + Vector3.UP * h
		var i0 := b.add(root - side * w, n, 1.0, Vector2(0, 0))
		var i1 := b.add(root + side * w, n, 1.0, Vector2(1, 0))
		var i2 := b.add(mid - side * w * 0.65, n, 1.0, Vector2(0, 0.55))
		var i3 := b.add(mid + side * w * 0.65, n, 1.0, Vector2(1, 0.55))
		var i4 := b.add(tip, n, 1.0, Vector2(0.5, 1.0))
		b.tri(i0, i1, i2)
		b.tri(i1, i3, i2)
		b.tri(i2, i3, i4)
	return b.commit()

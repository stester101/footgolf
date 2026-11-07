class_name CourseView
extends Node3D
## Visual scene for one hole, generated from its HoleDefinition (terrain, water, trees with
## matching collision proxies in the simulation, pin, cup, tee markers, OOB stakes).

const TERRAIN_SPACING := 2.0

var hole: HoleDefinition
var pin_label: Label3D
var _terrain_shader: Shader = preload("res://assets/shaders/terrain.gdshader")
var _water_shader: Shader = preload("res://assets/shaders/water.gdshader")
var _flag_shader: Shader = preload("res://assets/shaders/flag.gdshader")
var _foliage_shader: Shader = preload("res://assets/shaders/foliage.gdshader")


func build(p_hole: HoleDefinition) -> void:
	hole = p_hole
	for c in get_children():
		c.queue_free()
	_build_terrain()
	_build_outer_ground()
	_build_water()
	_build_trees()
	_build_pin()
	_build_tee_markers()
	_build_oob_stakes()


func _build_terrain() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = TerrainBuilder.build_mesh(hole, TERRAIN_SPACING)
	var mat := ShaderMaterial.new()
	mat.shader = _terrain_shader
	var d := (hole.pin - hole.tee).normalized()
	mat.set_shader_parameter("stripe_dir", Vector2(-d.y, d.x))
	mat.set_shader_parameter("surface_tex", TerrainBuilder.build_surface_texture(hole))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Ground OUTSIDE the terrain mesh only (a frame around hole.bounds), at the height the terrain
## edges blend to. A full plane would poke through low parts of the course (greens, lake shores).
func _build_outer_ground() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.34, 0.12)
	mat.roughness = 1.0
	var y := TerrainBuilder.outer_height(hole) - 0.05
	var r := hole.bounds.grow(-1.0)
	var big := 1500.0
	var rects := [
		Rect2(-big, -big, r.position.x + big, 2.0 * big),
		Rect2(r.end.x, -big, big - r.end.x, 2.0 * big),
		Rect2(r.position.x, -big, r.size.x, r.position.y + big),
		Rect2(r.position.x, r.end.y, r.size.x, big - r.end.y),
	]
	for i in rects.size():
		var rc: Rect2 = rects[i]
		var mi := MeshInstance3D.new()
		mi.name = "OuterGround%d" % i
		var pm := PlaneMesh.new()
		pm.size = rc.size
		mi.mesh = pm
		mi.position = Vector3(rc.get_center().x, y, rc.get_center().y)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


func _build_water() -> void:
	for i in hole.waters.size():
		var mi := MeshInstance3D.new()
		mi.name = "Water%d" % i
		mi.mesh = TerrainBuilder.ellipse_mesh(hole.waters[i], float(hole.water_level[i]), 64)
		var mat := ShaderMaterial.new()
		mat.shader = _water_shader
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## Lumpy low-poly canopy blob (deterministic), unit radius.
static func _blob_mesh(seed_val: int) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 14
	sm.rings = 9
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		var v := verts[i]
		var key := Vector3i(roundi(v.x * 50.0), roundi(v.y * 50.0), roundi(v.z * 50.0))
		var hsh := float(hash(str(key) + str(seed_val)) % 1000) / 1000.0
		verts[i] = v * (0.86 + 0.24 * hsh)
	arr[Mesh.ARRAY_VERTEX] = verts
	var st := SurfaceTool.new()
	var tmp := ArrayMesh.new()
	arr[Mesh.ARRAY_NORMAL] = null
	arr[Mesh.ARRAY_TANGENT] = null
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	st.create_from(tmp, 0)
	st.generate_normals()
	return st.commit()


func _canopy_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _foliage_shader
	return m


func _build_trees() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.6
	trunk_mesh.bottom_radius = 1.0
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.30, 0.22, 0.15)
	trunk_mat.roughness = 1.0
	trunk_mesh.material = trunk_mat
	var blob := _blob_mesh(hash(hole.id))
	blob.surface_set_material(0, _canopy_material())
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 9
	cone.rings = 1
	cone.material = _canopy_material()
	var decid: Array = []
	var conif: Array = []
	for t in hole.trees:
		if int(t["kind"]) == 0:
			decid.append(t)
		else:
			conif.append(t)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(hole.id + "trees")
	var trunk_x: Array[Transform3D] = []
	var blob_x: Array[Transform3D] = []
	var blob_c: Array[Color] = []
	var cone_x: Array[Transform3D] = []
	var cone_c: Array[Color] = []
	for t in hole.trees:
		var x: float = t["x"]
		var z: float = t["z"]
		var base_y: float = t["base_y"]
		var tr: float = t["trunk_r"]
		var th: float = t["trunk_h"]
		trunk_x.append(Transform3D(Basis.from_scale(Vector3(tr, th + 0.6, tr)), Vector3(x, base_y + th * 0.5 - 0.3, z)))
	# Deciduous: 3 blobs filling the physics canopy ellipsoid.
	for t in decid:
		var x: float = t["x"]
		var z: float = t["z"]
		var cr: float = t["canopy_r"]
		var cry: float = t["canopy_ry"]
		var cy: float = t["canopy_y"]
		var g := rng.randf()
		var col := Color(0.20 + 0.08 * g, 0.36 + 0.12 * g, 0.12 + 0.03 * g)
		for k in 3:
			var ang := rng.randf() * TAU
			var off := Vector3(cos(ang), 0, sin(ang)) * cr * 0.28 if k > 0 else Vector3.ZERO
			var sc := (0.92 if k == 0 else 0.68) * Vector3(cr, cry, cr)
			var yoff := 0.0 if k == 0 else cry * rng.randf_range(0.15, 0.45)
			blob_x.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(sc), Vector3(x, cy + yoff, z) + off))
			blob_c.append(col.lightened(0.06 * k))
	# Conifers: stacked cones inside the same ellipsoid footprint.
	for t in conif:
		var x: float = t["x"]
		var z: float = t["z"]
		var cr: float = t["canopy_r"]
		var cry: float = t["canopy_ry"]
		var cy: float = t["canopy_y"]
		var g2 := rng.randf()
		var col2 := Color(0.12 + 0.05 * g2, 0.27 + 0.08 * g2, 0.14 + 0.04 * g2)
		for k in 3:
			var w := cr * (1.0 - 0.27 * k)
			var hgt := cry * 1.1
			var y := cy - cry * 0.85 + k * cry * 0.62 + hgt * 0.5
			cone_x.append(Transform3D(Basis.from_scale(Vector3(w, hgt, w)), Vector3(x, y, z)))
			cone_c.append(col2.lightened(0.05 * k))
	_add_multimesh("Trunks", trunk_mesh, trunk_x, [])
	_add_multimesh("Canopies", blob, blob_x, blob_c)
	_add_multimesh("Conifers", cone, cone_x, cone_c)
	_build_backdrop(blob)


func _add_multimesh(n: String, mesh: Mesh, xforms: Array, colors: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = n
	mmi.multimesh = mm
	add_child(mmi)


## Decorative tree belt well beyond the out-of-bounds line (visual only; any ball out there
## is already out of bounds). Fills the horizon so the course doesn't float in empty space.
func _build_backdrop(blob: Mesh) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(hole.id + "backdrop")
	var r := hole.bounds.grow(25.0)
	var outer_h := TerrainBuilder.outer_height(hole)
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	var per := r.size.x * 2.0 + r.size.y * 2.0
	var n := int(per / 7.0)
	for i in n:
		var t := float(i) / float(n) * per
		var p := Vector2.ZERO
		if t < r.size.x:
			p = Vector2(r.position.x + t, r.position.y)
		elif t < r.size.x + r.size.y:
			p = Vector2(r.end.x, r.position.y + t - r.size.x)
		elif t < r.size.x * 2.0 + r.size.y:
			p = Vector2(r.end.x - (t - r.size.x - r.size.y), r.end.y)
		else:
			p = Vector2(r.position.x, r.end.y - (t - 2.0 * r.size.x - r.size.y))
		for row in 3:
			var q := p + Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5)) + (p - r.get_center()).normalized() * row * 12.0
			var hgt := rng.randf_range(11.0, 19.0)
			var cr := hgt * 0.32
			var g := rng.randf()
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(cr, cr * 1.15, cr)), Vector3(q.x, outer_h + hgt * 0.58, q.y)))
			cs.append(Color(0.16 + 0.06 * g, 0.31 + 0.1 * g, 0.12 + 0.03 * g))
	_add_multimesh("Backdrop", blob, xs, cs)


func _build_pin() -> void:
	var cup := hole.cup_position()
	var cup_mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.054
	cm.bottom_radius = 0.054
	cm.height = 0.01
	cm.radial_segments = 16
	cup_mi.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.03, 0.03, 0.03)
	cup_mi.material_override = cmat
	cup_mi.position = cup + Vector3(0, 0.006, 0)
	add_child(cup_mi)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.054
	tm.outer_radius = 0.075
	tm.rings = 16
	tm.ring_segments = 4
	ring.mesh = tm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.95, 0.95, 0.95)
	ring.material_override = rmat
	ring.scale = Vector3(1, 0.1, 1)
	ring.position = cup + Vector3(0, 0.004, 0)
	add_child(ring)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.012
	pm.bottom_radius = 0.012
	pm.height = 2.3
	pm.radial_segments = 6
	pole.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.97, 0.97, 0.95)
	pole.material_override = pmat
	pole.position = cup + Vector3(0, 1.15, 0)
	add_child(pole)
	var flag := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.62, 0.42)
	qm.subdivide_width = 8
	flag.mesh = qm
	var fmat := ShaderMaterial.new()
	fmat.shader = _flag_shader
	flag.material_override = fmat
	flag.position = cup + Vector3(0.32, 2.05, 0)
	add_child(flag)
	pin_label = Label3D.new()
	pin_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pin_label.fixed_size = true
	pin_label.pixel_size = 0.0016
	pin_label.font_size = 28
	pin_label.outline_size = 8
	pin_label.no_depth_test = true
	pin_label.modulate = Color(1, 1, 1)
	pin_label.position = cup + Vector3(0, 3.0, 0)
	add_child(pin_label)


func _build_tee_markers() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.35, 0.85)
	var d := (hole.pin - hole.tee).normalized()
	var side := Vector2(-d.y, d.x)
	for sgn in [-1.0, 1.0]:
		var p: Vector2 = hole.tee + side * 2.6 * float(sgn) + d * 0.8
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		mi.mesh = sm
		mi.material_override = mat
		mi.position = Vector3(p.x, hole.terrain_height(p.x, p.y) + 0.07, p.y)
		add_child(mi)


func _build_oob_stakes() -> void:
	if hole.boundary.size() < 3:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.04
	mesh.height = 1.0
	mesh.radial_segments = 5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.96, 0.96)
	mesh.material = mat
	var xforms: Array[Transform3D] = []
	for i in hole.boundary.size():
		var a := hole.boundary[i]
		var b := hole.boundary[(i + 1) % hole.boundary.size()]
		var n := int(a.distance_to(b) / 12.0)
		for k in n:
			var p := a.lerp(b, float(k) / float(maxi(n, 1)))
			xforms.append(Transform3D(Basis(), Vector3(p.x, hole.terrain_height(p.x, p.y) + 0.5, p.y)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "OOBStakes"
	mmi.multimesh = mm
	add_child(mmi)

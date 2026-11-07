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
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_outer_ground() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "OuterGround"
	var pm := PlaneMesh.new()
	pm.size = Vector2(3000, 3000)
	mi.mesh = pm
	var c := hole.bounds.get_center()
	mi.position = Vector3(c.x, TerrainBuilder.outer_height(hole) - 0.05, c.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.17, 0.32, 0.11)
	mat.roughness = 1.0
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


func _build_trees() -> void:
	if hole.trees.is_empty():
		return
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.7
	trunk_mesh.bottom_radius = 1.0
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 6
	trunk_mesh.rings = 1
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.33, 0.24, 0.16)
	trunk_mat.roughness = 1.0
	trunk_mesh.material = trunk_mat
	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 1.0
	canopy_mesh.height = 2.0
	canopy_mesh.radial_segments = 10
	canopy_mesh.rings = 6
	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.vertex_color_use_as_albedo = true
	canopy_mat.albedo_color = Color.WHITE
	canopy_mat.roughness = 1.0
	canopy_mesh.material = canopy_mat
	var n := hole.trees.size()
	var trunks := MultiMesh.new()
	trunks.transform_format = MultiMesh.TRANSFORM_3D
	trunks.mesh = trunk_mesh
	trunks.instance_count = n
	var canopies := MultiMesh.new()
	canopies.transform_format = MultiMesh.TRANSFORM_3D
	canopies.use_colors = true
	canopies.mesh = canopy_mesh
	canopies.instance_count = n * 2
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(hole.id + "trees")
	for i in n:
		var t: Dictionary = hole.trees[i]
		var x: float = t["x"]
		var z: float = t["z"]
		var base_y: float = t["base_y"]
		var tr: float = t["trunk_r"]
		var th: float = t["trunk_h"]
		trunks.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(tr, th + 0.6, tr)), Vector3(x, base_y + th * 0.5 - 0.3, z)))
		var cr: float = t["canopy_r"]
		var cry: float = t["canopy_ry"]
		var cy: float = t["canopy_y"]
		var rot := Basis(Vector3.UP, rng.randf() * TAU)
		canopies.set_instance_transform(i * 2, Transform3D(rot.scaled(Vector3(cr, cry, cr)), Vector3(x, cy, z)))
		canopies.set_instance_transform(i * 2 + 1, Transform3D(rot.scaled(Vector3(cr, cry, cr) * 0.62), Vector3(x + cr * 0.15, cy + cry * 0.75, z - cr * 0.1)))
		var g := rng.randf_range(0.0, 1.0)
		var col := Color(0.13 + 0.06 * g, 0.30 + 0.10 * g, 0.10 + 0.03 * g) if int(t["kind"]) == 0 else Color(0.10, 0.25 + 0.06 * g, 0.12)
		canopies.set_instance_color(i * 2, col)
		canopies.set_instance_color(i * 2 + 1, col.lightened(0.08))
	var tmi := MultiMeshInstance3D.new()
	tmi.name = "Trunks"
	tmi.multimesh = trunks
	add_child(tmi)
	var cmi := MultiMeshInstance3D.new()
	cmi.name = "Canopies"
	cmi.multimesh = canopies
	add_child(cmi)


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

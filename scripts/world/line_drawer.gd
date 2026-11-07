class_name LineDrawer
extends MeshInstance3D
## Simple unshaded ribbon/line helper (aim guide, ball trail, measuring line).

var _im := ImmediateMesh.new()
var _mat := StandardMaterial3D.new()


func _init(color: Color = Color.WHITE) -> void:
	mesh = _im
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = color
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func clear() -> void:
	_im.clear_surfaces()


## Flat ribbon through points (each point gets a horizontal half-width offset).
func draw_ribbon(points: PackedVector3Array, width: float, color: Color, fade: bool = false) -> void:
	_im.clear_surfaces()
	if points.size() < 2:
		return
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var d := b - a
		var side := Vector3(-d.z, 0.0, d.x)
		if side.length() < 1e-6:
			side = d.cross(Vector3.FORWARD)
		if side.length() < 1e-6:
			continue
		side = side.normalized() * width * 0.5
		var ca := color
		var cb := color
		if fade:
			ca.a = color.a * (1.0 - float(i) / float(points.size()))
			cb.a = color.a * (1.0 - float(i + 1) / float(points.size()))
		verts.append_array([a - side, b - side, a + side, a + side, b - side, b + side])
		cols.append_array([ca, cb, ca, ca, cb, cb])
	if verts.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in verts.size():
		_im.surface_set_color(cols[k])
		_im.surface_add_vertex(verts[k])
	_im.surface_end()


## Dashed chevron guide along the ground.
func draw_dashes(segments: Array, width: float, color: Color) -> void:
	_im.clear_surfaces()
	if segments.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for seg in segments:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var d := b - a
		var side := Vector3(-d.z, 0.0, d.x).normalized() * width * 0.5
		_im.surface_set_color(color)
		for v in [a - side, b, a + side, a - side, a - side * 0.2 + d * 0.3, b]:
			_im.surface_add_vertex(v)
		for v2 in [a + side, a + side * 0.2 + d * 0.3, b]:
			_im.surface_add_vertex(v2)
	_im.surface_end()

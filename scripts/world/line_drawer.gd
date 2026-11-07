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


## One camera-facing arrow: a narrow shaft and a single triangular head.
func draw_arrow(start: Vector3, finish: Vector3, cam_pos: Vector3, width: float, color: Color) -> void:
	_im.clear_surfaces()
	var v := finish - start
	if v.length() < 1e-4:
		return
	var forward := v.normalized()
	var side := forward.cross(cam_pos - start).normalized()
	if side.length() < 1e-5:
		side = forward.cross(Vector3.UP).normalized()
	var head := minf(v.length() * 0.26, width * 2.7)
	var neck := finish - forward * head
	var half := side * width * 0.5
	var wing := side * width * 1.2
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in [start - half, neck - half, start + half,
			start + half, neck - half, neck + half,
			neck - wing, finish, neck + wing]:
		_im.surface_set_color(color)
		_im.surface_add_vertex(vertex)
	_im.surface_end()


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


## Camera-facing tapered trail: width grows with distance to camera so it reads as a thin line
## everywhere (never a wall when it passes near the camera).
func draw_trail(points: PackedVector3Array, cam_pos: Vector3, px_factor: float, color: Color) -> void:
	_im.clear_surfaces()
	var n := points.size()
	if n < 2:
		return
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i in n - 1:
		var a := points[i]
		var b := points[i + 1]
		var d := b - a
		if d.length() < 1e-5:
			continue
		var sa := d.cross(a - cam_pos)
		var sb := d.cross(b - cam_pos)
		if sa.length() < 1e-6 or sb.length() < 1e-6:
			continue
		var wa := clampf(a.distance_to(cam_pos) * px_factor, 0.01, 0.6)
		var wb := clampf(b.distance_to(cam_pos) * px_factor, 0.01, 0.6)
		sa = sa.normalized() * wa
		sb = sb.normalized() * wb
		var ca := color
		var cb := color
		ca.a *= 0.25 + 0.75 * float(i) / float(n)
		cb.a *= 0.25 + 0.75 * float(i + 1) / float(n)
		# hide segments very close to the camera
		ca.a *= smoothstep(1.5, 6.0, a.distance_to(cam_pos))
		cb.a *= smoothstep(1.5, 6.0, b.distance_to(cam_pos))
		verts.append_array([a - sa, b - sb, a + sa, a + sa, b - sb, b + sb])
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

shader_type spatial;
// The hole opening: invisible, but marks its pixels (stencil 1) so the pit and a ball inside it can be drawn
// "through" the green. Depth-tested, so the flag pole or anything in front still hides it.
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;
stencil_mode write, compare_always, 1;
void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}

shader_type spatial;
// The ball while it is inside the hole: drawn at its real depth, only through the hole opening (stencil 1),
// so the near rim hides it as it drops and it never shows on top of the turf.
render_mode depth_test_disabled, depth_draw_never, shadows_disabled;
stencil_mode read, compare_equal, 1;
uniform float shade = 1.0;
void fragment() {
	ALBEDO = vec3(0.97) * shade;
	ROUGHNESS = 0.35;
	ALPHA = 1.0;
}

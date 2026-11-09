shader_type spatial;
// Inside of the hole (wall + floor), drawn only where the opening is (stencil 1), ignoring the turf's depth.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_front, shadows_disabled;
stencil_mode read, compare_equal, 1;
uniform float rim_y = 0.0;
uniform float depth = 0.1;
varying float wy;
void vertex() { wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y; }
void fragment() {
	float k = clamp((rim_y - wy) / max(depth, 0.01), 0.0, 1.0);
	ALBEDO = mix(vec3(0.22, 0.16, 0.10), vec3(0.02, 0.02, 0.02), smoothstep(0.0, 0.85, k));
	ALPHA = 1.0;
}

shader_type spatial;
// MOCKUP ONLY: jet contrail streak; UV.x runs along the trail (0 = plane, 1 = tail).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;
	float a = (1.0 - smoothstep(0.0, 1.0, across)) * (1.0 - UV.x) * smoothstep(0.0, 0.04, UV.x);
	ALBEDO = vec3(1.0);
	ALPHA = a * 0.75;
}

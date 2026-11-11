shader_type spatial;
// Soft blob contact shadow for small props (yardage posts, tee markers): a flat disc on the ground,
// UV centred at 0.5, darkens what is below with a smooth radial falloff. Unshaded, no depth write.
render_mode unshaded, blend_mul, depth_draw_never, cull_back, shadows_disabled;

uniform float strength = 0.45;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float s = (1.0 - smoothstep(0.15, 1.0, d)) * strength;
	ALBEDO = vec3(1.0 - s);
}

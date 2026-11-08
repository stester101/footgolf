shader_type spatial;
// MOCKUP ONLY: camera-facing cumulus puff from one noise texture. Flat-ish base, bright top,
// blue-grey underside, alpha-blended, no depth write, ignores fog (placed beyond the fog range).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 lit : source_color = vec3(1.0);
uniform vec3 shade : source_color = vec3(0.66, 0.74, 0.86);
uniform float seed = 0.0;
uniform float opacity = 0.92;

void vertex() {
	mat4 m = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	m[0] *= length(MODEL_MATRIX[0].xyz);
	m[1] *= length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * m;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	p.y = -p.y; // +y = up on screen
	float n1 = texture(noise_tex, UV * 0.9 + seed).r;
	float n2 = texture(noise_tex, UV * 2.3 + seed * 1.7).g;
	float body = length(p * vec2(0.85, 1.7)) - (n1 - 0.5) * 0.9 - (n2 - 0.5) * 0.35;
	float a = 1.0 - smoothstep(0.35, 0.78, body);
	a *= smoothstep(-0.45, -0.15, p.y + (n2 - 0.5) * 0.3); // flat base
	a *= 1.0 - smoothstep(0.8, 1.0, length(p));
	float tone = clamp(0.5 + p.y * 0.55 + (n2 - 0.5) * 0.6, 0.0, 1.0);
	ALBEDO = mix(shade, lit, tone);
	ALPHA = a * opacity;
}

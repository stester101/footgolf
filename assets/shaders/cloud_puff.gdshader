shader_type spatial;
// High graphics: distant camera-facing cumulus puffs (MultiMesh, INSTANCE_CUSTOM.x = per-puff seed).
// Built analytically from soft overlapping lobes with a flat base: no noise texture, so edges are
// smooth rather than mottled. Alpha-blended, no depth write, not fogged (placed beyond the fog).
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform vec3 lit : source_color = vec3(1.0);
uniform vec3 shade : source_color = vec3(0.70, 0.78, 0.90);
uniform float opacity = 0.85;

varying float seed;

float dens(vec2 p, float s) {
	float d = 0.0;
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float x = (fi - 3.0) * 0.26 + sin(s * 9.3 + fi * 4.1) * 0.07;
		float dome = max(1.0 - (x * x) / 0.72, 0.0);
		float rnd = 0.5 + 0.5 * sin(s * 5.7 + fi * 2.7);
		float y = -0.06 + 0.30 * dome * (0.55 + 0.45 * rnd);
		float r = 0.15 + 0.12 * dome * (0.4 + 0.6 * (0.5 + 0.5 * sin(s * 3.1 + fi * 1.7)));
		vec2 q = (p - vec2(x, y)) / r;
		d += exp(-dot(q, q) * 1.5);
	}
	return d;
}

void vertex() {
	seed = INSTANCE_CUSTOM.x;
	mat4 m = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	m[0] *= length(MODEL_MATRIX[0].xyz);
	m[1] *= length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * m;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 * vec2(1.0, -0.6);  // true proportions (quad is 1 : 0.6)
	float d = dens(p, seed);
	float a = smoothstep(0.30, 1.05, d);
	a *= smoothstep(-0.20, -0.07, p.y);  // soft flat base
	a *= 1.0 - smoothstep(0.80, 0.98, abs(p.x));
	float up = dens(p + vec2(0.0, 0.07), seed) - d;  // lighter where density falls off upward
	float tone = clamp(0.58 - up * 1.2 + p.y * 0.9, 0.0, 1.0);
	ALBEDO = mix(shade, lit, tone);
	ALPHA = a * opacity;
}

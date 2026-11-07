shader_type spatial;
// Pond water: three scrolling ripple layers (shared noise texture) perturb the normal; a
// Fresnel-weighted analytic sky reflection (matching the procedural sky, with a dark tree line
// near the horizon), sharp sun glints from the real directional light, and a lighter shallow
// band towards the shore (UV.x = 0 centre .. 1 shore).
render_mode blend_mix, cull_disabled, depth_draw_opaque;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.035, 0.11, 0.13);
uniform vec3 shallow_color : source_color = vec3(0.16, 0.30, 0.25);
uniform vec3 sky_top : source_color = vec3(0.20, 0.42, 0.78);
uniform vec3 sky_horizon : source_color = vec3(0.66, 0.78, 0.90);
uniform vec3 treeline : source_color = vec3(0.13, 0.20, 0.10);
uniform float ripple = 1.0;

varying vec3 wpos;
varying float shore;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	shore = UV.x;
}

void fragment() {
	vec2 p = wpos.xz;
	float t = TIME;
	vec4 a = texture(noise_tex, p / 26.0 + vec2(t * 0.010, t * 0.006));
	vec4 b = texture(noise_tex, p / 9.5 + vec2(-t * 0.018, t * 0.014));
	vec4 c = texture(noise_tex, p / 3.3 + vec2(t * 0.031, -t * 0.027));
	vec2 slope = ((a.rg - 0.5) * 0.24 + (b.gr - 0.5) * 0.16 + (c.br - 0.5) * 0.10) * ripple;
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 v = normalize(cam - wpos);
	// ripples flatten out with distance (and grazing angles) to avoid noisy sparkle
	float dist = length(cam - wpos);
	slope *= mix(1.0, 0.35, smoothstep(30.0, 160.0, dist));
	vec3 nw = normalize(vec3(slope.x, 1.0, slope.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	vec3 r = reflect(-v, nw);
	float ndv = clamp(dot(nw, v), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	float ry = clamp(r.y, 0.0, 1.0);
	vec3 sky = mix(sky_horizon, sky_top, pow(ry, 0.6));
	sky = mix(treeline, sky, smoothstep(0.015, 0.11, ry + (b.r - 0.5) * 0.04));
	float shallow = smoothstep(0.55, 1.0, shore);
	vec3 body = mix(deep_color, shallow_color, shallow);
	ALBEDO = body * (1.0 - fres);
	EMISSION = sky * fres * 0.7;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	ALPHA = clamp(mix(0.86, 1.0, fres) * (1.0 - smoothstep(0.94, 1.0, shore) * 0.45), 0.0, 1.0);
}

void light() {
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;
	if (LIGHT_IS_DIRECTIONAL) {
		vec3 h = normalize(VIEW + LIGHT);
		float nh = clamp(dot(NORMAL, h), 0.0, 1.0);
		float glint = pow(nh, 450.0) * 5.0 + pow(nh, 60.0) * 0.12;
		SPECULAR_LIGHT += glint * ATTENUATION * LIGHT_COLOR;
	}
}

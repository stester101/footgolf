shader_type spatial;
// MOCKUP ONLY: current terrain.gdshader + (a) 260/620 m-scale hue/brightness drift (macro variation),
// (b) drifting cloud shadows, (c) distance-faded mottling that survives mip filtering.
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://assets/shaders/turf.gdshaderinc"

uniform float macro_amt = 1.0;
uniform float cloud_shadow = 0.0;
uniform vec2 shadow_wind = vec2(0.0);
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float rough_w;
	float sand_w;
	vec3 c = turf_albedo(wpos.xz, cam - wpos, rough_w, sand_w);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float graze = pow(1.0 - ndv, 4.0) * (1.0 - sand_w);
	c = mix(c, c * 1.18 + vec3(0.015, 0.02, 0.0), graze * 0.55);
	// (a) macro variation: very large patches in brightness AND hue (hides tiling, adds scale)
	vec4 m1 = texture(noise_tex, wpos.xz / 620.0 + 0.37);
	vec4 m2 = texture(noise_tex, wpos.xz / 260.0);
	float m = m1.r * 0.6 + m2.g * 0.4;
	vec3 warm = vec3(1.16, 1.04, 0.72);
	vec3 cool = vec3(0.80, 0.98, 1.00);
	vec3 tint = mix(cool, warm, smoothstep(0.3, 0.7, m)) * mix(0.9, 1.08, m1.b);
	c *= mix(vec3(1.0), tint, macro_amt * (1.0 - sand_w));
	// (c) mid-distance mottling
	float d = length(cam - wpos);
	vec4 f = texture(noise_tex, wpos.xz / 2.9);
	c *= 1.0 + (f.a - 0.5) * 0.35 * smoothstep(25.0, 90.0, d) * (1.0 - sand_w);
	// (b) cloud shadows
	vec4 cs = texture(noise_tex, wpos.xz / 380.0 + shadow_wind);
	float sh = smoothstep(0.52, 0.72, cs.r * 0.7 + cs.g * 0.3);
	c *= 1.0 - sh * cloud_shadow;
	vec4 n = texture(noise_tex, wpos.xz / 2.1);
	float h = (n.a * 0.6 + n.b * 0.4) * (0.05 * rough_w + 0.02 * sand_w);
	vec3 dpx = dFdx(VERTEX);
	vec3 dpy = dFdy(VERTEX);
	vec3 r1 = cross(dpy, NORMAL);
	vec3 r2 = cross(NORMAL, dpx);
	float det = dot(dpx, r1);
	vec3 grad = (dFdx(h) * r1 + dFdy(h) * r2) * sign(det);
	NORMAL = normalize(abs(det) * NORMAL - grad);
	ALBEDO = c;
	ROUGHNESS = mix(0.86, 0.95, max(rough_w, sand_w));
	SPECULAR = mix(0.28, 0.12, max(rough_w, sand_w));
}

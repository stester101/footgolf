shader_type spatial;
// Procedural golf turf over the analytic terrain mesh (see turf.gdshaderinc).
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://assets/shaders/turf.gdshaderinc"

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float rough_w;
	float sand_w;
	vec3 c = turf_albedo(wpos.xz, cam - wpos, rough_w, sand_w);
	// grass gets lighter and slightly desaturated at grazing angles (blade sides catch the sky)
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float graze = pow(1.0 - ndv, 4.0) * (1.0 - sand_w);
	c = mix(c, c * 1.18 + vec3(0.015, 0.02, 0.0), graze * 0.55);
	// subtle micro relief in long grass / sand
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

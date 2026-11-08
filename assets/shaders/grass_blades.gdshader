shader_type spatial;
// Grass tufts around the resting ball (MultiMesh). Each blade's root takes the exact turf colour
// of the ground below it (shared turf.gdshaderinc), darkening towards the base and catching light
// at the tip. Blades bend gently in the wind; lighting uses the ground normal so tufts never look
// like separate cards.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

#include "res://assets/shaders/turf.gdshaderinc"

uniform float sway = 1.0;
// High graphics (wind_on = 1): blades lean downwind and flutter harder in stronger wind.
uniform float wind_on = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_amt = 0.3;

varying vec3 root;
varying float hfrac;

void vertex() {
	root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	hfrac = UV.y;
	float t = TIME;
	float w = sin(t * 1.6 + root.x * 0.45 + root.z * 0.31) * 0.6 + sin(t * 3.7 + root.x * 1.9 - root.z * 1.3) * 0.25;
	float bend = hfrac * hfrac;
	float sw = sway;
	if (wind_on > 0.5) {
		sw *= 0.6 + 1.4 * wind_amt;
		float gust = 0.5 + 0.5 * sin(t * (0.8 + wind_amt) - dot(root.xz, wind_dir) * 0.08);
		vec3 dw = vec3(wind_dir.x, 0.0, wind_dir.y) * wind_amt * (0.05 + 0.10 * gust) * bend;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * dw;
	}
	VERTEX.x += w * 0.16 * bend * sw;
	VERTEX.z += w * 0.07 * bend * sw;
	NORMAL = normalize(mix(NORMAL, normalize(transpose(mat3(MODEL_MATRIX)) * vec3(0.0, 1.0, 0.0)), 0.75));
}

void fragment() {
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float rough_w;
	float sand_w;
	vec3 g = turf_albedo(root.xz, cam - root, rough_w, sand_w);
	vec3 c = g * COLOR.rgb * mix(0.78, 1.15, hfrac);
	c = mix(c, c * vec3(1.15, 1.1, 0.75), smoothstep(0.75, 1.0, hfrac) * 0.35);
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ALBEDO = c;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	BACKLIGHT = c * 0.35;
}

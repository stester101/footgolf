shader_type spatial;
render_mode blend_mix, diffuse_lambert, specular_schlick_ggx, cull_disabled;

uniform vec3 deep_color : source_color = vec3(0.06, 0.20, 0.27);
uniform vec3 shallow_color : source_color = vec3(0.16, 0.42, 0.45);

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz * 0.35;
	float t = TIME * 0.4;
	float nx = vnoise(p + vec2(t, 0.0)) - vnoise(p + vec2(0.0, t) + 5.3);
	float nz = vnoise(p * 1.7 - vec2(t, t * 0.5) + 2.1) - vnoise(p * 1.7 + 9.7);
	NORMAL = normalize((VIEW_MATRIX * vec4(nx * 0.25, 1.0, nz * 0.25, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_color, shallow_color, 0.35 + 0.3 * vnoise(p * 0.3));
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = clamp(0.82 + fres * 0.18, 0.0, 1.0);
}

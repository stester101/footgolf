shader_type spatial;
// Procedural golf turf. Vertex colour = surface base colour (linear); COLOR.a = mown flag.
render_mode diffuse_lambert, specular_schlick_ggx;

uniform vec2 stripe_dir = vec2(1.0, 0.0);
uniform float stripe_width = 6.0;

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
	vec2 p = wpos.xz;
	float n = vnoise(p * 0.08) * 0.45 + vnoise(p * 0.6) * 0.35 + vnoise(p * 3.1) * 0.2;
	float stripe = step(0.5, fract(dot(p, stripe_dir) / stripe_width)) - 0.5;
	vec3 c = COLOR.rgb * (0.86 + 0.28 * n);
	c *= 1.0 + 0.11 * stripe * COLOR.a;
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}

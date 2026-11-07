shader_type spatial;
// Procedural golf turf. surface_tex: per-pixel surface colour (sRGB) + alpha
// (1 = mown stripes, 0.5 = clumpy rough, 0 = sand/bed). UV spans the hole bounds.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D surface_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 stripe_dir = vec2(1.0, 0.0);
uniform float stripe_width = 8.0;
uniform float detail_fade = 60.0;
// Size of the hole bounds in metres (for warping the 1 m surface map into organic edges).
uniform vec2 map_size = vec2(200.0, 300.0);

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
	vec2 warp = vec2(vnoise(p * 0.9) - 0.5, vnoise(p * 0.9 + 17.3) - 0.5) * 1.1
		+ vec2(vnoise(p * 3.1) - 0.5, vnoise(p * 3.1 + 5.1) - 0.5) * 0.35;
	vec4 s = texture(surface_tex, UV + warp / map_size);
	vec3 base = s.rgb;
	float kind = s.a;
	float dist = length(wpos - (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float near = 1.0 - smoothstep(detail_fade * 0.3, detail_fade, dist);

	// large patches (soil moisture / wear)
	float patches = vnoise(p * 0.035) * 0.6 + vnoise(p * 0.11) * 0.4;
	vec3 c = base * mix(0.82, 1.12, patches);
	// warm/dry tint variation
	c = mix(c, c * vec3(1.10, 1.02, 0.80), vnoise(p * 0.02 + 7.0) * 0.35);

	float mown = smoothstep(0.8, 1.0, kind);
	float rough = smoothstep(0.3, 0.5, kind) * (1.0 - mown);
	float sand = 1.0 - smoothstep(0.0, 0.3, kind);

	// mowing stripes (fairway/green/tee)
	float st = step(0.5, fract(dot(p, stripe_dir) / stripe_width));
	c *= mix(1.0, mix(0.90, 1.10, st), mown);
	// clumpy rough
	float clump = vnoise(p * 0.7) * 0.6 + vnoise(p * 2.3) * 0.4;
	c *= mix(1.0, mix(0.80, 1.10, clump), rough);
	// grass grain / sand grain close to camera
	float grain = vnoise(p * 9.0) * 0.6 + vnoise(p * 23.0) * 0.4;
	c *= mix(1.0, mix(0.86, 1.10, grain), near * (1.0 - sand * 0.6));

	ALBEDO = c;
	ROUGHNESS = mix(0.88, 0.97, sand);
	SPECULAR = mix(0.35, 0.15, rough);
}

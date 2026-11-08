// Shared procedural turf colouring (terrain mesh AND grass-blade tufts use the same function so
// blades blend into the ground they grow from). All detail comes from one tileable noise texture
// generated in code (WorldTextures) sampled at several world-space scales; mipmaps filter it.
//
// surface_tex: per-pixel base colour (sRGB) over the hole bounds (same classifier as physics)
// kind_tex:    surface weights  R = mown fairway/tee/fringe, G = green, B = rough, A = sand

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D surface_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D kind_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 map_origin = vec2(-100.0, -100.0);
uniform vec2 map_size = vec2(200.0, 300.0);
// Unit vector ACROSS the hole (stripes run tee -> pin).
uniform vec2 stripe_dir = vec2(1.0, 0.0);
uniform float stripe_width = 9.0;
uniform float green_stripe_width = 2.4;
// 0 = Low graphics (original look, no extra texture taps); 1 = High (macro variation).
uniform float macro_amt = 0.0;

vec4 turf_noise(vec2 p, float tile) {
	return texture(noise_tex, p / tile);
}

// Soft, anti-aliased +-1 square-ish wave.
float turf_band(float x) {
	float w = fwidth(x) * 2.0 + 0.02;
	float s = sin(x * 6.2831853);
	return clamp(s / (w * 6.2831853), -1.0, 1.0) * clamp(1.0 - w * 1.5, 0.0, 1.0);
}

// p: world xz; to_cam: world vector from the point to the camera.
// Returns albedo; outputs the rough and sand weights for material response.
vec3 turf_albedo(vec2 p, vec3 to_cam, out float rough_w, out float sand_w) {
	vec4 big = turf_noise(p, 170.0);
	vec4 mid = turf_noise(p, 41.0);
	vec4 fine = turf_noise(p, 7.3);
	vec4 micro = turf_noise(p, 1.37);
	// organic boundaries: warp the 1 m surface map lookup
	vec4 wq = turf_noise(p, 19.0);
	vec2 warp = (wq.rg - 0.5) * 2.4 + (fine.rg - 0.5) * 0.5;
	vec2 uv = (p + warp - map_origin) / map_size;
	vec3 base = texture(surface_tex, uv).rgb;
	vec4 kind = texture(kind_tex, uv);
	float mown = kind.r;
	float green = kind.g;
	float rough = kind.b;
	float sand = smoothstep(0.3, 0.7, kind.a);
	rough_w = rough;
	sand_w = sand;

	vec3 c = base;
	// broad soil-moisture / wear patches, weaker on the manicured green
	float patches = big.r * 0.6 + mid.g * 0.4;
	c *= mix(1.0, mix(0.70, 1.20, smoothstep(0.2, 0.8, patches)), 1.0 - green * 0.6);
	// dry (warm) vs lush (cool) tint drift
	c = mix(c, c * vec3(1.14, 1.05, 0.70), smoothstep(0.45, 0.85, big.g) * 0.5 * (1.0 - green));
	c = mix(c, c * vec3(0.86, 0.98, 1.05), smoothstep(0.5, 0.9, mid.b) * 0.35);

	// mowing stripes: alternate mow direction, brightness depends on viewing direction
	vec2 along = vec2(-stripe_dir.y, stripe_dir.x);
	float view_along = dot(to_cam.xz, along) / max(length(to_cam), 0.001);
	float sheen = 0.5 + 0.5 * abs(view_along);
	float sgn = view_along >= 0.0 ? 1.0 : -1.0;
	float fw_band = turf_band(dot(p, stripe_dir) / stripe_width + (wq.b - 0.5) * 0.04);
	c *= 1.0 + mown * fw_band * sgn * 0.30 * sheen;
	float g_band = turf_band(dot(p, stripe_dir) / green_stripe_width);
	float g_cross = turf_band(dot(p, along) / green_stripe_width);
	c *= 1.0 + green * (g_band * sgn * 0.16 * sheen + g_cross * 0.05);

	// rough: clumps, darker hollows and a few seed heads
	float clump = mid.a * 0.5 + fine.a * 0.3 + fine.b * 0.2;
	c *= mix(1.0, mix(0.5, 1.2, smoothstep(0.15, 0.85, clump)), rough);
	c = mix(c, c * vec3(1.22, 1.12, 0.72), smoothstep(0.72, 0.9, fine.r) * 0.35 * rough);

	// close-up blade grain (mip-filtered -> fades out cleanly with distance)
	float grain = micro.b * 0.65 + micro.a * 0.35;
	float grain_amt = mix(0.24, 0.10, green) + rough * 0.12;
	c *= mix(1.0 - grain_amt, 1.0 + grain_amt * 0.7, smoothstep(0.2, 0.8, grain));

	// sand: fine grain, faint rake ripples and a darker lip where turf meets sand
	float lip = smoothstep(0.05, 0.4, kind.a) * (1.0 - smoothstep(0.55, 0.95, kind.a));
	float rake = sin(dot(p, stripe_dir) * 9.0 + fine.g * 6.0) * 0.5 + 0.5;
	vec3 sandc = base * mix(0.9, 1.06, micro.g) * mix(0.97, 1.02, rake);
	c = mix(c, sandc, sand);
	c *= 1.0 - lip * 0.28;

	// High graphics only (macro_amt > 0): very large hue/brightness drift plus distance mottling.
	// Multiplicative and subtle, weakest on green/tee/fairway so lie colours and mowing stripes stay
	// readable, strongest in the rough; sand is untouched.
	if (macro_amt > 0.0) {
		vec4 m1 = turf_noise(p, 620.0);
		vec4 m2 = turf_noise(p, 260.0);
		float m = m1.r * 0.6 + m2.g * 0.4;
		vec3 tint = mix(vec3(0.90, 0.99, 1.0), vec3(1.10, 1.03, 0.82), smoothstep(0.3, 0.7, m)) * mix(0.93, 1.06, m1.b);
		float w = macro_amt * (1.0 - sand) * (1.0 - green * 0.85) * mix(1.0, 0.45, mown);
		c *= mix(vec3(1.0), tint, w);
		float dist = length(to_cam);
		vec4 mot = turf_noise(p, 2.9);
		c *= 1.0 + (mot.a - 0.5) * 0.30 * smoothstep(25.0, 90.0, dist) * (1.0 - sand) * (1.0 - green) * macro_amt * mix(1.0, 0.4, mown);
	}
	return c;
}

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
	c *= mix(1.0, mix(0.80, 1.14, patches), 1.0 - green * 0.6);
	// dry (warm) vs lush (cool) tint drift
	c = mix(c, c * vec3(1.14, 1.05, 0.70), smoothstep(0.45, 0.85, big.g) * 0.5 * (1.0 - green));
	c = mix(c, c * vec3(0.86, 0.98, 1.05), smoothstep(0.5, 0.9, mid.b) * 0.35);

	// mowing stripes: alternate mow direction, brightness depends on viewing direction
	vec2 along = vec2(-stripe_dir.y, stripe_dir.x);
	float view_along = dot(to_cam.xz, along) / max(length(to_cam), 0.001);
	float sheen = 0.45 + 0.55 * abs(view_along);
	float sgn = view_along >= 0.0 ? 1.0 : -1.0;
	float fw_band = turf_band(dot(p, stripe_dir) / stripe_width + (wq.b - 0.5) * 0.04);
	c *= 1.0 + mown * fw_band * sgn * 0.085 * sheen;
	float g_band = turf_band(dot(p, stripe_dir) / green_stripe_width);
	float g_cross = turf_band(dot(p, along) / green_stripe_width);
	c *= 1.0 + green * (g_band * sgn * 0.05 * sheen + g_cross * 0.018);

	// rough: clumps, darker hollows and a few seed heads
	float clump = mid.a * 0.5 + fine.a * 0.3 + fine.b * 0.2;
	c *= mix(1.0, mix(0.66, 1.14, clump), rough);
	c = mix(c, c * vec3(1.22, 1.12, 0.72), smoothstep(0.72, 0.9, fine.r) * 0.35 * rough);

	// close-up blade grain (mip-filtered -> fades out cleanly with distance)
	float grain = micro.b * 0.65 + micro.a * 0.35;
	float grain_amt = mix(0.16, 0.08, green) + rough * 0.10;
	c *= mix(1.0 - grain_amt, 1.0 + grain_amt * 0.7, grain);

	// sand: fine grain, faint rake ripples and a darker lip where turf meets sand
	float lip = smoothstep(0.05, 0.4, kind.a) * (1.0 - smoothstep(0.55, 0.95, kind.a));
	float rake = sin(dot(p, stripe_dir) * 9.0 + fine.g * 6.0) * 0.5 + 0.5;
	vec3 sandc = base * mix(0.9, 1.06, micro.g) * mix(0.97, 1.02, rake);
	c = mix(c, sandc, sand);
	c *= 1.0 - lip * 0.28;
	return c;
}

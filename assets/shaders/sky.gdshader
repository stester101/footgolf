shader_type sky;
// Tier-1 sky: 3-stop gradient, sun halo and soft planar-projected clouds (one noise texture).
// No TIME use -> Godot renders it once into the sky cubemap (not every frame). The sun direction
// is a uniform (set per hole by HoleAtmosphere) so the halo always matches the DirectionalLight3D.
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 sun_dir = vec3(0.4, 0.6, 0.6);
uniform vec3 top_color : source_color = vec3(0.13, 0.33, 0.70);
uniform vec3 mid_color : source_color = vec3(0.35, 0.58, 0.86);
uniform vec3 horizon_color : source_color = vec3(0.74, 0.84, 0.93);
uniform vec3 ground_color : source_color = vec3(0.45, 0.55, 0.42);
uniform vec3 sun_color : source_color = vec3(1.0, 0.93, 0.78);
uniform vec3 cloud_lit : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shade : source_color = vec3(0.62, 0.70, 0.82);
uniform float cover = 0.5;
uniform vec2 offset = vec2(0.0);

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * texture(noise_tex, p).r;
		p = p * 2.03 + vec2(0.31, 0.17);
		a *= 0.5;
	}
	return s;
}

void sky() {
	vec3 d = EYEDIR;
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		float k = pow(h, 0.5);
		col = mix(horizon_color, mid_color, smoothstep(0.0, 0.35, k));
		col = mix(col, top_color, smoothstep(0.3, 1.0, k));
	} else {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.08, -h));
	}
	vec3 sd = normalize(sun_dir);
	float s = max(dot(d, sd), 0.0);
	col += sun_color * (pow(s, 6.0) * 0.16 + pow(s, 40.0) * 0.26 + pow(s, 400.0) * 0.8);
	if (h > 0.0) {
		vec2 uv = d.xz / (h + 0.10) * 0.085 + offset;
		float n = fbm(uv);
		float c = smoothstep(1.0 - cover, 1.0 - cover + 0.28, n);
		// cheap self-shadow: compare density with a sample shifted towards the sun
		vec2 toward = normalize(sd.xz + vec2(0.0001)) * 0.03;
		float lit = clamp(0.55 + (n - fbm(uv + toward)) * 5.0, 0.0, 1.0);
		vec3 cc = mix(cloud_shade, cloud_lit, lit);
		cc += sun_color * pow(s, 8.0) * 0.30 * (1.0 - c * 0.4);
		col = mix(col, cc, c * smoothstep(0.0, 0.10, h) * 0.95);
	}
	COLOR = col;
}

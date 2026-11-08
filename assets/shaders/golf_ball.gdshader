shader_type canvas_item;
// Small rendered golf ball for the spin control: lit sphere, hex dimple pattern that tightens
// towards the rim, specular highlight upper-left, soft drop shadow. No textures, no extra viewport.
void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * 1.28;   // ball radius is 1.0, the margin holds the shadow
	float rr = length(p);
	vec3 l = normalize(vec3(-0.55, -0.65, 0.55));
	// soft shadow, offset down-right
	float sh = (1.0 - smoothstep(0.80, 1.20, length(p - vec2(0.07, 0.11)))) * 0.38;
	vec4 col = vec4(0.0, 0.0, 0.0, sh);
	if (rr < 1.0) {
		float z = sqrt(max(1.0 - rr * rr, 0.0));
		vec3 n = vec3(p, z);
		float diff = clamp(dot(n, l), 0.0, 1.0);
		vec2 q = n.xy / (z * 0.55 + 0.45) * 6.5;
		vec2 r2 = vec2(1.0, 1.7320508);
		vec2 h = r2 * 0.5;
		vec2 a = mod(q, r2) - h;
		vec2 b = mod(q - h, r2) - h;
		vec2 gv = dot(a, a) < dot(b, b) ? a : b;
		float d = length(gv);
		float dimple = smoothstep(0.40, 0.10, d);
		float lit_side = dot(normalize(gv + vec2(0.0001)), l.xy);
		vec3 base = vec3(0.97, 0.975, 1.0);
		vec3 c = base * (0.50 + 0.62 * diff);
		c -= dimple * (0.10 + 0.07 * lit_side);
		float spec = pow(max(dot(reflect(-l, n), vec3(0.0, 0.0, 1.0)), 0.0), 26.0) * 0.55;
		c += spec;
		c *= 1.0 - smoothstep(0.72, 1.0, rr) * 0.30;   // darker towards the rim
		float edge = 1.0 - smoothstep(0.975, 1.0, rr);
		col = mix(col, vec4(clamp(c, 0.0, 1.0), 1.0), edge);
	}
	COLOR = col;
}

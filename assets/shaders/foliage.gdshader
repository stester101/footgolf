shader_type spatial;
// Tree foliage (deciduous clusters and conifer tiers). COLOR = per-instance tint x baked vertex AO.
// Triplanar procedural leaf clumps, darker hollows, warm sunlit tips, translucency and a gentle
// wind sway that grows with height in the crown.
render_mode diffuse_burley, specular_disabled, cull_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float leaf_scale = 2.2;
uniform float sway = 0.022;

varying vec3 wpos;
varying vec3 wn;

void vertex() {
	vec3 rootw = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float w = sin(TIME * 0.9 + rootw.x * 0.13 + rootw.z * 0.17) + 0.35 * sin(TIME * 2.3 + rootw.z * 0.4);
	VERTEX.xz += vec2(w, w * 0.6) * sway * (VERTEX.y + 1.0);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 bl = abs(wn) + 0.001;
	bl /= (bl.x + bl.y + bl.z);
	vec4 n = texture(noise_tex, wpos.zy / leaf_scale) * bl.x
		+ texture(noise_tex, wpos.xz / leaf_scale) * bl.y
		+ texture(noise_tex, wpos.xy / leaf_scale) * bl.z;
	float leaves = n.a * 0.65 + n.b * 0.35;
	float up = clamp(wn.y * 0.5 + 0.6, 0.0, 1.0);
	vec3 c = COLOR.rgb;
	c *= mix(0.55, 1.18, smoothstep(0.25, 0.8, leaves));
	c *= mix(0.6, 1.0, up);
	c = mix(c, c * vec3(1.18, 1.14, 0.78), smoothstep(0.55, 0.9, n.r) * 0.45 * up);
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	if (dot(cam - wpos, wn) < 0.0) {
		// underside of skirts / inner crown: shaded, and keep the sky ambient from tinting it blue
		c *= 0.4;
		NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
	BACKLIGHT = c * 0.55;
}

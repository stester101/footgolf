shader_type spatial;
// Grandstand spectators (MultiMesh). Instance COLOR = shirt colour; UV.y = 1 marks head vertices,
// which take a per-instance skin tone. Each spectator fidgets / bobs on its own phase and now and
// then rises for a cheer (vertex only, no textures). Presentation only, High graphics only.
render_mode diffuse_burley, specular_disabled;

uniform float cheer = 0.0;  // 0..1 extra excitement (optional, set by script)

varying float head;
varying float skin_k;

float hash11(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	float id = float(INSTANCE_ID);
	float ph = hash11(id) * 6.2831853;
	float rate = 0.6 + hash11(id + 3.1) * 0.9;
	float bob = sin(TIME * rate * 2.0 + ph) * 0.025;
	// occasional cheer: a short rise with arms-up stretch
	float wave = smoothstep(0.92, 1.0, sin(TIME * 0.35 + ph * 0.5 + id * 0.013) * 0.5 + 0.5 + cheer * 0.2);
	VERTEX.y += bob + wave * 0.18 * step(0.5, VERTEX.y);
	VERTEX.y *= 1.0 + wave * 0.12;
	head = UV.y;
	skin_k = hash11(id + 7.7);
}

void fragment() {
	vec3 skin = mix(vec3(0.93, 0.74, 0.60), vec3(0.36, 0.22, 0.14), skin_k);
	vec3 c = mix(COLOR.rgb, skin, step(0.5, head));
	ALBEDO = c;
	ROUGHNESS = 0.9;
}

shader_type spatial;
// Tree canopy: instance colour, fake ambient occlusion (darker underneath/inside), leaf speckle.
render_mode diffuse_burley, specular_disabled;

varying vec3 wnormal;
varying vec3 lpos;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lpos = VERTEX;
}

void fragment() {
	float ao = mix(0.45, 1.0, clamp(wnormal.y * 0.5 + 0.55, 0.0, 1.0));
	float speck = hash(floor(lpos * 9.0));
	vec3 c = COLOR.rgb * ao * mix(0.82, 1.12, speck);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.12, 0.18, 0.06);
}

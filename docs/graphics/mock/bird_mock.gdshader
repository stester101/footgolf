shader_type spatial;
// MOCKUP ONLY: flapping bird silhouette. UV.y = 0 at the body, 1 at wing tips; wing tips flap
// with a phase derived from the instance position.
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec3 color : source_color = vec3(0.09, 0.09, 0.11);

void vertex() {
	float ph = MODEL_MATRIX[3].x * 0.7 + MODEL_MATRIX[3].z * 0.3;
	VERTEX.y += sin(TIME * 9.0 + ph) * 0.45 * UV.y;
}

void fragment() {
	ALBEDO = color;
}

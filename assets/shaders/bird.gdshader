shader_type spatial;
// High graphics: flapping bird silhouettes. One mesh holds a whole flock. UV.y = 0 at the body and 1
// at the wing tips; COLOR.r = per-bird flap phase, COLOR.g = per-bird flap speed variation.
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec3 color : source_color = vec3(0.10, 0.10, 0.12);

void vertex() {
	float s = TIME * (8.0 + COLOR.g * 3.0) + COLOR.r * 6.2831;
	VERTEX.y += sin(s) * 0.5 * UV.y;
	VERTEX.z += cos(s) * 0.12 * UV.y;
}

void fragment() {
	ALBEDO = color;
}

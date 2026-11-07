shader_type spatial;
render_mode cull_disabled, diffuse_lambert;

uniform vec3 color : source_color = vec3(0.9, 0.12, 0.1);

void vertex() {
	float k = clamp(UV.x, 0.0, 1.0);
	VERTEX.z += sin(TIME * 5.0 + UV.x * 6.0) * 0.06 * k;
}

void fragment() {
	ALBEDO = color;
	ROUGHNESS = 0.8;
}

shader_type spatial;
// Pin flag: waving cloth with a white hoist band, soft folds and a little self-illumination so
// it reads against trees and sky from the tee.
render_mode cull_disabled, diffuse_lambert;

uniform vec3 color : source_color = vec3(0.92, 0.10, 0.08);
uniform vec3 band_color : source_color = vec3(0.97, 0.97, 0.95);
uniform float glow = 0.22;

varying float fold;

void vertex() {
	float k = clamp(UV.x, 0.0, 1.0);
	float w = sin(TIME * 5.0 + UV.x * 6.0) * 0.06 + sin(TIME * 8.3 + UV.x * 11.0 + UV.y * 2.0) * 0.02;
	VERTEX.z += w * k;
	fold = cos(TIME * 5.0 + UV.x * 6.0) * k;
}

void fragment() {
	vec3 c = mix(band_color, color, step(0.1, UV.x));
	c *= 0.88 + 0.12 * fold;
	ALBEDO = c;
	EMISSION = c * glow;
	ROUGHNESS = 0.75;
}

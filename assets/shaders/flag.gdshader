shader_type spatial;
// Pin flag: waving cloth with a white hoist band, soft folds and a little self-illumination so
// it reads against trees and sky from the tee.
// High graphics (wind_on = 1): the cloth follows the hole's wind VISUALLY (the node is yawed
// downwind by CourseView): calm = it hangs and ripples slowly, strong wind = it streams out and
// flutters fast. Presentation only.
render_mode cull_disabled, diffuse_lambert;

uniform vec3 color : source_color = vec3(0.92, 0.10, 0.08);
uniform vec3 band_color : source_color = vec3(0.97, 0.97, 0.95);
uniform float glow = 0.22;
uniform float wind_on = 0.0;
uniform float wind_amt = 0.4;  // 0..1 (wind speed / 7 m/s)

varying float fold;

void vertex() {
	float k = clamp(UV.x, 0.0, 1.0);
	float amp = 1.0;
	float spd = 1.0;
	if (wind_on > 0.5) {
		amp = 0.3 + 1.5 * wind_amt;
		spd = 0.55 + 1.15 * wind_amt;
		float lift = smoothstep(0.0, 0.5, wind_amt);
		VERTEX.y -= (1.0 - lift) * k * k * 0.30;
		VERTEX.x *= mix(0.84, 1.0, lift);
	}
	float w = (sin(TIME * 5.0 * spd + UV.x * 6.0) * 0.06 + sin(TIME * 8.3 * spd + UV.x * 11.0 + UV.y * 2.0) * 0.02) * amp;
	VERTEX.z += w * k;
	fold = cos(TIME * 5.0 * spd + UV.x * 6.0) * k;
}

void fragment() {
	vec3 c = mix(band_color, color, step(0.1, UV.x));
	c *= 0.88 + 0.12 * fold;
	ALBEDO = c;
	EMISSION = c * glow;
	ROUGHNESS = 0.75;
}

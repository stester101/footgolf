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

// Cloth wave height (local +Z) at (u along the flag from the pole, v down the flag), time t.
float cloth(float u, float v, float t, float spd, float amp) {
	float k = u * u * (3.0 - 2.0 * u) * 0.65 + u * 0.35;  // pinned at the pole, freest at the fly end
	float w = sin(t * 5.2 * spd - u * 7.5 + v * 0.8) * 0.055
		+ sin(t * 8.9 * spd - u * 13.0 + v * 2.6) * 0.022
		+ sin(t * 2.3 * spd - u * 3.1 - v * 1.7) * 0.03;
	return w * k * amp;
}

void vertex() {
	float k = clamp(UV.x, 0.0, 1.0);
	if (wind_on > 0.5) {
		// High: travelling cloth ripples with analytic normals (folds shade like fabric), the fly end
		// droops in calm air and streams out in wind.
		float amp = 0.45 + 1.4 * wind_amt;
		float spd = 0.55 + 1.15 * wind_amt;
		float lift = smoothstep(0.0, 0.5, wind_amt);
		float u = k;
		float v = clamp(UV.y, 0.0, 1.0);
		float e = 0.02;
		float z0 = cloth(u, v, TIME, spd, amp);
		float zu = cloth(u + e, v, TIME, spd, amp);
		float zv = cloth(u, v + e, TIME, spd, amp);
		VERTEX.z += z0;
		VERTEX.y -= (1.0 - lift) * k * k * 0.30 + k * v * 0.04 * (1.0 - lift);
		VERTEX.x *= mix(0.84, 1.0, lift) * (1.0 - abs(z0) * 0.6);
		// d/dx in mesh units (0.72 m wide, 0.48 m tall)
		float dzdx = (zu - z0) / (e * 0.72);
		float dzdy = -(zv - z0) / (e * 0.48);
		NORMAL = normalize(vec3(-dzdx, -dzdy, 1.0));
		fold = clamp(-dzdx * 1.5, -1.0, 1.0);
	} else {
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
}

void fragment() {
	vec3 c = mix(band_color, color, step(0.1, UV.x));
	c *= (wind_on > 0.5) ? (0.92 + 0.08 * fold) : (0.88 + 0.12 * fold);
	ALBEDO = c;
	EMISSION = c * glow;
	ROUGHNESS = 0.75;
}

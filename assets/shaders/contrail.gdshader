shader_type spatial;
// High graphics: jet plus condensation trail on one long camera-facing quad. UV.x = 1 at the
// aircraft (head), 0 at the far end of the trail.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled;
uniform float length_m = 700.0;
uniform float fade = 1.0;

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;
	float behind = (1.0 - UV.x) * length_m;  // metres behind the aircraft
	float width = mix(0.35, 1.0, smoothstep(0.0, 160.0, behind));
	float a = (1.0 - smoothstep(0.2, 1.0, across / width)) * pow(UV.x, 1.4) * smoothstep(14.0, 40.0, behind);
	vec3 c = vec3(1.0);
	// the aircraft: a short bright fuselage with a little swept wing
	float ax = behind / 26.0;
	float body = (1.0 - smoothstep(0.08, 0.2, across)) * step(0.0, ax) * (1.0 - smoothstep(0.85, 1.0, ax));
	float wing = (1.0 - smoothstep(0.0, 0.1, abs(ax - 0.45 - across * 0.5))) * (1.0 - smoothstep(0.5, 0.9, across));
	float plane = max(body, wing * 0.9);
	c = mix(c, vec3(0.93, 0.95, 0.98), plane);
	a = max(a * 0.7, plane * 0.95);
	ALBEDO = c;
	ALPHA = a * fade;
}

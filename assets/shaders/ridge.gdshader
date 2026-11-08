shader_type spatial;
// High graphics: far hill/ridge silhouette wall. Unshaded, ignores fog (its own colour is already
// hazed towards the horizon); the foot fades into the haze colour so it melts into the ground.
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque;
uniform vec3 col : source_color = vec3(0.3, 0.45, 0.4);
uniform vec3 haze : source_color = vec3(0.8, 0.88, 0.95);

void fragment() {
	float up = smoothstep(0.0, 0.85, UV.y);
	ALBEDO = mix(haze, col, up);
}

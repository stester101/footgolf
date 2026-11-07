shader_type spatial;
// Tree trunks and limbs: vertical bark furrows from the shared noise texture, darker damp base
// with a hint of moss, per-instance tint (COLOR).
render_mode diffuse_burley, specular_disabled, cull_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 lpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lpos = VERTEX;
}

void fragment() {
	float ang = atan(lpos.z, lpos.x) / 6.2831853;
	// furrows: stretched noise (fine around, coarse along the trunk)
	vec4 n = texture(noise_tex, vec2(ang * 3.0, wpos.y / 3.5));
	vec4 m = texture(noise_tex, vec2(ang * 1.0 + 0.37, wpos.y / 9.0));
	float furrow = smoothstep(0.3, 0.75, n.b * 0.7 + n.a * 0.3);
	vec3 c = COLOR.rgb * mix(0.55, 1.15, furrow) * mix(0.85, 1.1, m.r);
	float base = 1.0 - smoothstep(0.0, 0.18, lpos.y);
	c = mix(c, c * vec3(0.75, 0.95, 0.6), base * smoothstep(0.4, 0.7, m.g) * 0.8);
	c *= mix(1.0, 0.7, base);
	ALBEDO = c;
	ROUGHNESS = 0.95;
}

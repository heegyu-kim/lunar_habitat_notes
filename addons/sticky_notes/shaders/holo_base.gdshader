// Holonote ghost: the glowing ring on the floor under the body (the "projector").
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.45, 0.9, 0.65);
uniform float alpha = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ring = smoothstep(0.07, 0.0, abs(r - 0.82));
	float inner = smoothstep(0.035, 0.0, abs(r - 0.55)) * 0.45;
	float glow = smoothstep(1.0, 0.0, r) * 0.22;
	float pulse = 0.5 + 0.5 * sin(TIME * 2.0 - r * 10.0);
	float v = ring + inner + glow * (0.6 + 0.4 * pulse);
	ALBEDO = tint * v * 1.3;
	ALPHA = clamp(v, 0.0, 1.0) * alpha;
}

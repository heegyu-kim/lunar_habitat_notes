// Holonote ghost: the pointing ray from a hand. Bright at the hand, fading to nothing at the tip.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.45, 0.9, 0.65);
uniform float alpha = 1.0;
uniform bool hand_at_top = false;          // which end of the cylinder is the hand

void fragment() {
	// CylinderMesh maps its side to the upper half of the texture: v = 0 at the top, 0.5 at the bottom.
	float v = clamp(UV.y * 2.0, 0.0, 1.0);
	float along = hand_at_top ? v : 1.0 - v;            // 0 at the hand, 1 at the tip
	float fade = pow(1.0 - clamp(along, 0.0, 1.0), 1.6);
	float dash = 0.75 + 0.25 * sin(along * 40.0 - TIME * 9.0);
	ALBEDO = (tint * 1.4 + vec3(0.25)) * fade * dash;
	ALPHA = fade * alpha;
}

// Holonote ghost: depth-only pass. Adds nothing to the picture (additive black) but writes depth,
// so the colour pass (next_pass, holo_body.gdshader) only draws the surface nearest to you.
// StandardMaterial3D's "depth pre-pass" cannot do this for a translucent body: it only writes depth
// where alpha is above 0.99.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_always, cull_back, shadows_disabled;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}

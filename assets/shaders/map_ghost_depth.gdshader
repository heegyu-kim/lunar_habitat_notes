// Handheld deck map, decks you are not on: first pass. Writes depth only, so the colour pass
// (map_ghost.gdshader, next_pass) blends just the nearest surface instead of every layer behind it.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_always, cull_disabled, shadows_disabled;

instance uniform vec4 src_y = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 tone = vec4(1.0, 1.0, 1.0, 0.0);

uniform float cut_lo = -0.2;
uniform float cut_hi = 1.4;

varying float h;

void vertex() {
	h = dot(src_y.xyz, VERTEX) + src_y.w;
}

void fragment() {
	if (h < cut_lo || h > cut_hi) {
		discard;
	}
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}

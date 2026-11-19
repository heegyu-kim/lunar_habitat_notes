// Handheld deck map, decks you are not on: colour pass. A faint see-through copy of the deck with
// brighter edges, drawn after map_ghost_depth.gdshader has written the nearest surface.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

instance uniform vec4 src_y = vec4(0.0, 1.0, 0.0, 0.0);
instance uniform vec4 tone = vec4(1.0, 1.0, 1.0, 0.0);

uniform float floor_y = 0.0;
uniform float cut_lo = -0.2;
uniform float cut_hi = 1.4;
uniform vec3 color : source_color = vec3(0.2, 0.62, 0.72);
uniform float core_alpha = 0.16;
uniform float rim_alpha = 0.6;
uniform float alpha = 1.0;

varying float h;
varying float up;

void vertex() {
	h = dot(src_y.xyz, VERTEX) + src_y.w;
	up = dot(normalize(src_y.xyz), NORMAL);
}

void fragment() {
	if (h < cut_lo || h > cut_hi) {
		discard;
	}
	float k = clamp((h - floor_y) / max(cut_hi - floor_y, 0.01), 0.0, 1.0);
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - ndv, 2.0);
	float edge = smoothstep(0.07, 0.0, cut_hi - h);
	ALBEDO = color * (0.55 + 0.45 * k) * mix(0.75, 1.0, clamp(up, 0.0, 1.0)) + color * (rim + edge) * 0.5;
	ALPHA = clamp(mix(core_alpha, rim_alpha, max(rim, edge)), 0.0, 1.0) * alpha;
}

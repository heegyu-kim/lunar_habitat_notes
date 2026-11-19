// Handheld deck map: the real habitat meshes drawn small, cut open above one deck.
// Everything outside cut_lo..cut_hi (metres, habitat height) is discarded, so one deck shows as a
// slice you look into from above. Colour goes from dark at the floor to light at the cut; faces that
// look up are lighter than walls; the inside of anything the cut opened shows in cap_color.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Height of a model vertex in the habitat: dot(src_y.xyz, VERTEX) + src_y.w. Set per mesh by XRMinimap.
instance uniform vec4 src_y = vec4(0.0, 1.0, 0.0, 0.0);
// rgb multiplies the colour (structure darker, equipment lighter); a is how far a numbered landmark
// is pushed towards mark_color. Set per mesh by XRMinimap.
instance uniform vec4 tone = vec4(1.0, 1.0, 1.0, 0.0);

uniform float floor_y = 0.0;
uniform float cut_lo = -0.2;
uniform float cut_hi = 1.4;
uniform vec3 floor_color : source_color = vec3(0.03, 0.2, 0.26);
uniform vec3 top_color : source_color = vec3(0.3, 0.86, 0.94);
uniform vec3 cap_color : source_color = vec3(0.72, 0.97, 1.0);
uniform vec3 mark_color : source_color = vec3(0.86, 0.95, 1.0);

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
	float rim = pow(1.0 - ndv, 2.5);
	vec3 col = mix(floor_color, top_color, 0.12 + 0.88 * k) * tone.rgb;
	col = mix(col, mark_color * (0.45 + 0.55 * k), tone.a);
	col *= mix(0.5, 1.0, clamp(up, 0.0, 1.0));
	col += top_color * rim * 0.18;
	// A line just under the cut, so the opened walls read as a section.
	col = mix(col, cap_color, smoothstep(0.06, 0.0, cut_hi - h) * 0.85);
	if (!FRONT_FACING) {
		col = cap_color * mix(0.55, 1.0, k);
	}
	ALBEDO = col;
}

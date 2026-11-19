// Holonote ghost: colour pass. Drawn after holo_depth.gdshader has written the body's depth, so only
// the nearest surface is blended (an arm in front of the chest does not show the chest through it).
// Bright rim, dim translucent core, fine scan lines drifting up, a slow bright band, feet fading out.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.45, 0.9, 0.65);
uniform float alpha = 1.0;                 // fade in / out, set by HoloPlayer
uniform float brightness = 1.0;
uniform float core_alpha = 0.34;           // opacity where the surface faces you
uniform float rim_power = 2.0;
uniform float scan_per_metre = 520.0;      // one line every 1.2 cm
uniform float scan_strength = 0.22;
uniform float floor_y = -1000.0;           // world height of the floor under the ghost
uniform float feet_fade = 0.22;            // metres over which the feet fade into the floor

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float ndv = clamp(dot(n, normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_power);
	// Soft shading from above and in front of the viewer, so the body reads as a volume.
	float form = 0.5 + 0.5 * dot(n, normalize(vec3(0.25, 0.85, 0.45)));
	// Scan lines: fine close up, faded out with distance so they do not shimmer in the headset.
	float near = 1.0 - smoothstep(2.5, 6.0, length(VERTEX));
	float scan = 0.5 + 0.5 * sin(world_pos.y * scan_per_metre - TIME * 3.0);
	float lines = 1.0 - scan_strength * near * (1.0 - scan);
	float band = smoothstep(0.985, 1.0, sin(world_pos.y * 1.7 - TIME * 1.1));
	float flicker = 0.96 + 0.04 * sin(TIME * 21.0) * sin(TIME * 6.7);
	float feet = smoothstep(0.0, feet_fade, world_pos.y - floor_y);

	vec3 col = tint * (0.36 + 0.46 * form) * brightness;
	col += tint * rim * 1.0 + vec3(rim * rim * rim) * 0.14;
	col *= mix(1.0, lines, 0.5);
	col += tint * band * 0.7;
	ALBEDO = col * flicker;
	float a = mix(core_alpha, 0.96, rim);
	a = a * lines + band * 0.25;
	ALPHA = clamp(a, 0.0, 1.0) * alpha * mix(0.25, 1.0, feet);
}

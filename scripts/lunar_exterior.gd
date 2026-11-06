## The Moon outside the windows: black star sky with Earth low on the horizon, a sun a couple of
## degrees above the horizon (lunar south pole), grey regolith terrain and a faint blue Earth-light.
## Everything is built in code so there is nothing to keep in sync in the .tscn.
##
## Session tab -> Sun azimuth slider calls set_sun_azimuth(); the long shadows are the point.
class_name LunarExterior
extends Node3D

@export_range(0.0, 15.0) var sun_elevation_deg := 2.0
@export_range(-180.0, 180.0) var sun_azimuth_deg := -35.0
@export var sun_energy := 3.2
## Flat, fixed ambient so the inside stays readable until every room has its own lights.
@export var ambient_energy := 0.30
@export var terrain_size := 4000.0
@export var flat_radius := 70.0

var sun: DirectionalLight3D
var earth_light: DirectionalLight3D
var environment: Environment
var _sky_material: ShaderMaterial
var _terrain: MeshInstance3D

const EARTH_DIR := Vector3(0.35, 0.09, -0.93)   # unit-ish, ~5 degrees above the horizon


func _ready() -> void:
	add_to_group("lunar_exterior")
	_build_environment()
	_build_lights()
	_build_terrain()
	_apply_sun()


func set_sun_azimuth(deg: float) -> void:
	sun_azimuth_deg = deg
	_apply_sun()


func set_sun_elevation(deg: float) -> void:
	sun_elevation_deg = clampf(deg, 0.0, 15.0)
	_apply_sun()


func _apply_sun() -> void:
	if sun == null:
		return
	var el := deg_to_rad(sun_elevation_deg)
	var az := deg_to_rad(sun_azimuth_deg)
	# Direction the light travels: from the sun towards the ground.
	var to_sun := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()
	sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3(0, 20, 0))
	if _sky_material != null:
		_sky_material.set_shader_parameter("sun_dir", to_sun)


func _build_environment() -> void:
	# main.tscn keeps a WorldEnvironment node (the passthrough toggle points at it); reuse it.
	var we: WorldEnvironment = get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment if get_parent() != null else null
	if we == null:
		we = WorldEnvironment.new()
		we.name = "WorldEnvironment"
		add_child(we)
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = _sky_shader()
	_sky_material.set_shader_parameter("earth_dir", EARTH_DIR.normalized())
	sky.sky_material = _sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.80, 0.82, 0.88)
	environment.ambient_light_energy = ambient_energy
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 6.0
	# Forward+ only (ignored by the Mobile renderer): contact shadows in the corners of the rooms.
	environment.ssao_enabled = true
	environment.ssao_radius = 0.8
	environment.ssao_intensity = 1.6
	we.environment = environment


func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 300.0
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.15
	sun.directional_shadow_split_3 = 0.4
	sun.directional_shadow_blend_splits = true
	add_child(sun)

	# Earthshine: faint, blue, no shadows. Keeps the shadow side from being pure black.
	earth_light = DirectionalLight3D.new()
	earth_light.name = "EarthLight"
	earth_light.light_color = Color(0.55, 0.65, 1.0)
	earth_light.light_energy = 0.12
	earth_light.shadow_enabled = false
	earth_light.global_transform = Transform3D(Basis.looking_at(-EARTH_DIR.normalized(), Vector3.UP), Vector3(0, 20, 0))
	add_child(earth_light)


func _build_terrain() -> void:
	_terrain = MeshInstance3D.new()
	_terrain.name = "Regolith"
	var pm := PlaneMesh.new()
	pm.size = Vector2(terrain_size, terrain_size)
	pm.subdivide_width = 240
	pm.subdivide_depth = 240
	_terrain.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = _terrain_shader()
	mat.set_shader_parameter("flat_radius", flat_radius)
	_terrain.material_override = mat
	_terrain.position = Vector3(0, -0.06, 0)
	_terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_terrain.extra_cull_margin = 64.0
	add_child(_terrain)


func _sky_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type sky;

uniform vec3 earth_dir = vec3(0.35, 0.09, -0.93);
uniform vec3 sun_dir = vec3(0.0, 0.05, 1.0);
uniform float earth_radius = 0.028;   // radians, exaggerated a little (real: ~0.017)
uniform float sun_radius = 0.0047;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash13(vec3(i, 1.0));
	float b = hash13(vec3(i + vec2(1.0, 0.0), 1.0));
	float c = hash13(vec3(i + vec2(0.0, 1.0), 1.0));
	float d = hash13(vec3(i + vec2(1.0, 1.0), 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 col = vec3(0.0);
	// Stars: one candidate per cell of a 500-cell sphere, a few percent of them lit.
	vec3 cell = floor(d * 420.0);
	float r = hash13(cell);
	if (r > 0.992) {
		vec3 f = fract(d * 420.0) - 0.5;
		float m = clamp(1.0 - length(f) * 3.2, 0.0, 1.0);
		float tint = hash13(cell + 7.0);
		vec3 star = mix(vec3(0.85, 0.9, 1.0), vec3(1.0, 0.9, 0.75), tint);
		col += star * m * m * (r - 0.992) * 90.0;
	}
	// Below the horizon the terrain covers everything; keep it dark anyway.
	if (d.y < -0.01) {
		col *= 0.0;
	}
	// Earth: lit by the sun, blue with cloud noise, dark night side.
	vec3 ed = normalize(earth_dir);
	float ce = dot(d, ed);
	float ang = acos(clamp(ce, -1.0, 1.0));
	if (ang < earth_radius) {
		vec3 n = normalize(d - ed * ce);           // direction across the disk
		float rim = ang / earth_radius;            // 0 centre .. 1 edge
		vec3 sphere_n = normalize(n * rim + ed * sqrt(max(0.0, 1.0 - rim * rim)));
		float lit = clamp(dot(sphere_n, normalize(sun_dir)) * 0.9 + 0.1, 0.0, 1.0);
		vec2 uv = vec2(atan(n.x, n.z), rim) * 6.0;
		float clouds = smoothstep(0.55, 0.8, noise2(uv * 2.0 + vec2(3.1, 1.7)));
		float land = smoothstep(0.5, 0.6, noise2(uv * 1.3));
		vec3 surf = mix(vec3(0.10, 0.28, 0.75), vec3(0.20, 0.32, 0.14), land);
		surf = mix(surf, vec3(0.95), clouds);
		float edge = smoothstep(1.0, 0.92, rim);
		col = surf * lit * 1.6 * edge + vec3(0.2, 0.4, 0.9) * (1.0 - edge) * 0.4 * lit;
	}
	// Sun disk, very bright, slightly bigger halo.
	float cs = dot(d, normalize(sun_dir));
	float sang = acos(clamp(cs, -1.0, 1.0));
	if (sang < sun_radius) {
		col = vec3(60.0, 58.0, 54.0);
	} else if (sang < sun_radius * 6.0) {
		float h = 1.0 - (sang - sun_radius) / (sun_radius * 5.0);
		col += vec3(1.0, 0.95, 0.85) * h * h * 1.2;
	}
	COLOR = col;
}
"""
	return s


func _terrain_shader() -> Shader:
	var s := Shader.new()
	s.code = """
shader_type spatial;
render_mode cull_back;

uniform float flat_radius = 70.0;
uniform float amp = 7.0;
uniform float freq = 0.0045;
uniform vec3 regolith = vec3(0.16, 0.155, 0.15);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), f.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return v;
}

// A few craters: inverted cones with a raised rim, placed on a coarse grid.
float craters(vec2 p) {
	float h = 0.0;
	vec2 g = p / 180.0;
	vec2 cellp = floor(g);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cellp + vec2(float(x), float(y));
			float r = hash12(c * 3.7);
			if (r < 0.45) continue;
			vec2 centre = (c + vec2(hash12(c + 1.3), hash12(c + 5.9))) * 180.0;
			float rad = 18.0 + 40.0 * hash12(c + 9.1);
			float d = length(p - centre) / rad;
			if (d < 1.25) {
				float bowl = -(1.0 - d * d) * rad * 0.18;
				float rim = smoothstep(0.75, 1.0, d) * (1.0 - smoothstep(1.0, 1.25, d)) * rad * 0.06;
				h += (d < 1.0 ? bowl : 0.0) + rim;
			}
		}
	}
	return h;
}

float height(vec2 p) {
	float m = smoothstep(flat_radius, flat_radius * 2.2, length(p));
	float h = (fbm(p * freq) - 0.5) * amp * 2.0 + (fbm(p * freq * 7.0) - 0.5) * 0.6;
	h += craters(p);
	return h * m;
}

varying vec3 wpos;

void vertex() {
	vec2 p = VERTEX.xz;
	float h = height(p);
	float e = 1.5;
	float hx = height(p + vec2(e, 0.0));
	float hz = height(p + vec2(0.0, e));
	VERTEX.y += h;
	NORMAL = normalize(vec3(h - hx, e, h - hz));
	wpos = VERTEX;
}

void fragment() {
	float fine = fbm(wpos.xz * 0.35);
	float coarse = fbm(wpos.xz * 0.02);
	float tone = 0.75 + 0.5 * fine * 0.6 + 0.25 * coarse;
	ALBEDO = regolith * tone;
	ROUGHNESS = 0.96;
	METALLIC = 0.0;
	SPECULAR = 0.15;
}
"""
	return s

## The Moon around the habitat, from the rendering-test project: the modelled terrain with its
## Moonscape textures, the Earth, the sun, and the nebula sky.
##
## Everything you can see is a node of scenes/lunar_exterior.tscn, so it is edited in the editor:
##   Sun          DirectionalLight3D   direction, energy, shadows
##   MoonTerrain  assets/environment/moon_terrain.glb with assets/environment/moon_surface.tres
##   Earth        sphere with the Earth day map
## The look (sky, tonemap, exposure, SSR, SSAO, SSIL, SDFGI, glow) is
## assets/environment/lunar_environment.tres on the WorldEnvironment node of main.tscn.
##
## This script only adds what needs code: walkable collision on the terrain, the Session tab's
## Sun azimuth slider (set_sun_azimuth), the ground height for "Go outside", and an optional
## lighter set of effects in the headset.
class_name LunarExterior
extends Node3D

@export var sun_path := NodePath("Sun")
@export var terrain_path := NodePath("MoonTerrain")
## Bodies of the terrain join this group. VR locomotion follows the ground only on these.
@export var terrain_group := "lunar_terrain"
## In the headset, switch off the three most expensive effects (SDFGI, SSIL, SSR). The desktop
## window keeps the full look. Turn this on if the headset cannot hold its frame rate.
@export var lighter_in_vr := false

var sun: DirectionalLight3D
var environment: Environment
var sun_azimuth_deg := 0.0
var sun_elevation_deg := 5.0


func _ready() -> void:
	add_to_group("lunar_exterior")
	sun = get_node_or_null(sun_path) as DirectionalLight3D
	if sun != null:
		# A directional light shines along -Z, so +Z points at the sun.
		var to_sun := sun.global_transform.basis.z.normalized()
		sun_elevation_deg = rad_to_deg(asin(clampf(to_sun.y, -1.0, 1.0)))
		sun_azimuth_deg = rad_to_deg(atan2(to_sun.x, to_sun.z))
	var we := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment if get_parent() != null else null
	if we != null:
		environment = we.environment
	_build_terrain_collision()
	# main.gd decides between the headset and the desktop window in its own _ready, after this one.
	_apply_vr_quality.call_deferred()


## Session tab slider: turns the sun around the base, keeping its height above the horizon.
func set_sun_azimuth(deg: float) -> void:
	sun_azimuth_deg = deg
	_apply_sun()


func set_sun_elevation(deg: float) -> void:
	sun_elevation_deg = clampf(deg, 0.0, 90.0)
	_apply_sun()


func _apply_sun() -> void:
	if sun == null:
		return
	var el := deg_to_rad(sun_elevation_deg)
	var az := deg_to_rad(sun_azimuth_deg)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()
	sun.global_transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), sun.global_position)


## Height of the lunar ground under (x, z); `fallback` where there is no terrain.
func ground_y(x: float, z: float, fallback: float = 0.0) -> float:
	var space := get_world_3d().direct_space_state
	var from := Vector3(x, 200.0, z)
	var exclude: Array[RID] = []
	for i in 12:
		var q := PhysicsRayQueryParameters3D.create(from, Vector3(x, -200.0, z))
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		if (hit["collider"] as Node).is_in_group(terrain_group):
			return (hit["position"] as Vector3).y
		exclude.append(hit["rid"])
	return fallback


func _build_terrain_collision() -> void:
	var terrain := get_node_or_null(terrain_path) as Node3D
	if terrain == null:
		return
	var meshes := terrain.find_children("*", "MeshInstance3D", true, false)
	if terrain is MeshInstance3D:
		meshes.append(terrain)
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi.get_node_or_null("TerrainBody") != null:
			continue
		var shape := mi.mesh.create_trimesh_shape()
		if shape == null:
			continue
		shape.backface_collision = true
		var body := StaticBody3D.new()
		body.name = "TerrainBody"
		body.collision_mask = 0
		body.add_to_group(terrain_group)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)


func _apply_vr_quality() -> void:
	if not lighter_in_vr or environment == null or not get_viewport().use_xr:
		return
	environment.sdfgi_enabled = false
	environment.ssil_enabled = false
	environment.ssr_enabled = false
	print("LunarExterior|INFO: headset: SDFGI, SSIL and SSR switched off (lighter_in_vr)")

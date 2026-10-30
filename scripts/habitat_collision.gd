## Collision for the habitat model.
##
## Sticky notes only stick to surfaces that have collision, and the desktop player should not
## walk through walls. The imported glb has none (apart from the three deck floors added by hand
## in main.tscn), so at startup this node gives every MeshInstance3D under its parent a trimesh
## StaticBody3D named "<mesh name>_col".
##
## NoteManager strips the "_col" suffix, so a note reads "on Service access panel021",
## "on L2 | structural deck001" and so on, and conflicts are detected per part.
##
## Put this node under the LunarHabitat node (or any node that holds the model).
##
## The placers flip a hit normal that points away from the viewer, so notes always stand on the
## side you are looking at, whichever way a part's faces are wound.
class_name HabitatSurfaceCollision
extends Node

## Kill switch
@export var enabled := true
## Meshes whose largest dimension is below this (metres) are skipped: bolts, LEDs, tiny labels.
@export var min_size := 0.08
## The generated bodies join this group. The desktop ladder disables it while climbing.
@export var group_name := "habitat_surface"
@export_flags_3d_physics var collision_layer := 1
@export var log_summary := true


func _ready() -> void:
	if not enabled:
		return
	var root := get_parent()
	if root == null:
		return
	var t0 := Time.get_ticks_msec()
	var made := 0
	var skipped := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := mi as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var body_name := str(mesh_instance.name) + "_col"
		if mesh_instance.get_node_or_null(body_name) != null:
			continue
		var size := mesh_instance.get_aabb().size * mesh_instance.global_transform.basis.get_scale()
		if maxf(size.x, maxf(size.y, size.z)) < min_size:
			skipped += 1
			continue
		var shape := mesh_instance.mesh.create_trimesh_shape()
		if shape == null:
			skipped += 1
			continue
		# Parts of this model are wound the other way round from what the physics engine treats as
		# the front, so one-sided faces let rays through the visible surface and hit the far side.
		# Two-sided faces make a ray stop at the first surface it meets, which is the one you see.
		shape.backface_collision = true
		var body := StaticBody3D.new()
		body.name = body_name
		body.collision_layer = collision_layer
		body.collision_mask = 0
		body.add_to_group(group_name)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		mesh_instance.add_child(body)
		made += 1
	if log_summary:
		print("HabitatSurfaceCollision|INFO: %d collision bodies generated, %d small meshes skipped, %d ms" % [made, skipped, Time.get_ticks_msec() - t0])

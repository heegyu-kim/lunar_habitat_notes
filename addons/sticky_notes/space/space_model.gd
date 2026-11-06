## A 3D model brought in at runtime by the space-setup pipeline (Import model in the Session tab).
##
## Loads a glb/gltf with GLTFDocument, fixes units and up axis, drops the lowest point onto y = 0,
## centres it on the origin and gives every mesh a trimesh collision body (HabitatSurfaceCollision),
## so notes stick to it and the desktop player can walk on it, exactly like the built-in habitat.
##
## Nothing here depends on node names inside the model: floors, zones and noise sources live in the
## session file, not in the glb.
class_name SpaceModel
extends Node3D

const UNIT_SCALES := {"m": 1.0, "cm": 0.01, "mm": 0.001}
const UP_AXES := ["Y", "Z"]
# By path so this works before the editor has refreshed its class_name cache (headless tests).
const SurfaceCollisionScript := preload("res://scripts/habitat_collision.gd")

var file: String = ""            # file name inside NoteManager.MODELS_DIR
var unit: String = "m"
var up_axis: String = "Y"
var align_floor := true          # lowest point of the model goes to y = 0
var center_xz := true            # bounding box centre goes to x = z = 0
var bounds := AABB()             # after placement, in this node's space
var mesh_count := 0
var error: String = ""

var _scene: Node3D = null


func settings() -> Dictionary:
	return {"file": file, "unit": unit, "up_axis": up_axis, "align_floor": align_floor, "center_xz": center_xz}


## Loads `path` (absolute or user://). Returns false and fills `error` on failure.
func load_file(path: String, opts: Dictionary = {}) -> bool:
	unload()
	error = ""
	unit = str(opts.get("unit", "m"))
	if not UNIT_SCALES.has(unit):
		unit = "m"
	up_axis = str(opts.get("up_axis", "Y")).to_upper()
	if up_axis not in UP_AXES:
		up_axis = "Y"
	align_floor = bool(opts.get("align_floor", true))
	center_xz = bool(opts.get("center_xz", true))
	file = path.get_file()

	var scene := _generate(path)
	if scene == null:
		return false
	_scene = scene
	add_child(scene)

	var basis := Basis.IDENTITY
	if up_axis == "Z":
		basis = Basis(Vector3.RIGHT, -PI / 2.0)   # +Z becomes +Y
	var s: float = UNIT_SCALES[unit]
	scene.transform = Transform3D(basis.scaled(Vector3.ONE * s), Vector3.ZERO)

	bounds = _compute_bounds(scene)
	var offset := Vector3.ZERO
	if align_floor:
		offset.y = -bounds.position.y
	if center_xz:
		offset.x = -(bounds.position.x + bounds.size.x * 0.5)
		offset.z = -(bounds.position.z + bounds.size.z * 0.5)
	scene.position += offset
	bounds.position += offset

	var col: Node = SurfaceCollisionScript.new()
	col.name = "SurfaceCollision"
	col.min_size = float(opts.get("min_size", 0.08))
	scene.add_child(col)
	print("SpaceModel|INFO: loaded %s  meshes=%d  size=%.1f x %.1f x %.1f m" % [file, mesh_count, bounds.size.x, bounds.size.y, bounds.size.z])
	return true


func unload() -> void:
	if _scene != null:
		remove_child(_scene)
		_scene.queue_free()
		_scene = null
	file = ""
	bounds = AABB()
	mesh_count = 0


func is_loaded() -> bool:
	return _scene != null


func _generate(path: String) -> Node3D:
	if not FileAccess.file_exists(path):
		error = "file not found: " + path
		return null
	var ext := path.get_extension().to_lower()
	if ext != "glb" and ext != "gltf":
		error = "only .glb / .gltf are supported (got .%s)" % ext
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state, 0, path.get_base_dir())
	if err != OK:
		error = "glTF parse failed (error %d)" % err
		return null
	var node := doc.generate_scene(state)
	if node == null:
		error = "glTF has no scene"
		return null
	var scene := node as Node3D
	if scene == null:
		# Wrap a non-3D root so transforms can be applied.
		scene = Node3D.new()
		scene.add_child(node)
	scene.name = "Model"
	return scene


func _compute_bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	mesh_count = 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null:
			continue
		mesh_count += 1
		# Local to this node (SpaceModel): the root scene already has rotation and scale applied.
		var xf := global_transform.affine_inverse() * m.global_transform
		var box := xf * m.get_aabb()
		if first:
			out = box
			first = false
		else:
			out = out.merge(box)
	return out

extends Node
## Handheld deck map. Observes the XR rig and does not own locomotion.

@export var camera: XRCamera3D
@export var left: XRController3D
@export var right: XRController3D
@export var habitat: Node3D
## Floor colliders in bottom-to-top order. Each has a concave Collision child.
@export var floor_bodies: Array[StaticBody3D]
## Y of the XR origin when standing on the lowest deck. Higher decks use collider height differences.
@export var lowest_deck_origin_y := 0.0
## Optional override: XR origin Y for each deck, for rigs that use custom landing heights.
@export var deck_origin_heights := PackedFloat32Array()
## World X/Z of the central ladder, shown as a landmark only.
@export var ladder_position := Vector2(0.0, 0.46)
@export var cycle_action: StringName = &"primary_click"

enum ViewMode { CLOSED, PLAN, HOLOGRAM }

const MAP_SCALE := 0.032
const STACK_GAP := 0.041
const MAP_LIMIT := 3.52
const ACTIVE := Color("#1c9eae")
const INACTIVE := Color(0.17, 0.52, 0.60, 0.22)
const EDGE := Color("#7eedf7")
const PLAYER := Color("#ffe47b")

# Pairs are the imported model node and the concise map label.
const LANDMARKS := [
	[["Airlock | dust control mat", "Airlock"], ["Maintenance work bench", "Maintenance"], ["EVA workstation", "EVA station"],
		["Geology utilization lab", "Geology lab"], ["OGA pallet 01", "Oxygen system"]],
	[["Private hygiene compartment", "Hygiene"], ["Water processor pallet 02", "Water processing"],
		["Biology utilization lab", "Biology lab"], ["Universal waste management system", "Waste system"],
		["Potable and process water tanks", "Water tanks"]],
	[["Crew quarters 1", "Crew quarters"], ["Medical station", "Medical"], ["Physics lab", "Physics lab"],
		["Wardroom table", "Wardroom"], ["Human research lab", "Human research"]]
]
const ZONE_COLOR := Color("#135a73")
const ZONE_BORDER := Color("#abdcff")

var _owner: XRController3D
var _mode := ViewMode.CLOSED
var _origin: XROrigin3D
var _deck_heights := PackedFloat32Array()
var _device: Node3D
var _view: Node3D
var _decks: Array[Node3D] = []
var _fills: Array[StandardMaterial3D] = []
var _rims: Array[StandardMaterial3D] = []
var _marker: MeshInstance3D
var _ladder_dot: MeshInstance3D
var _title: Label3D
var _hint: Label3D
var _status: Label3D
var _legend: Label3D
var _zone_layers: Array[Node3D] = []
var _zone_keys: Array[Node3D] = []
var _legend_text: Array[String] = []


func _ready() -> void:
	_origin = get_parent() as XROrigin3D
	if not (_origin and camera and left and right and habitat) or floor_bodies.is_empty():
		push_error("Minimap: add under XROrigin3D and assign camera, controllers, habitat and floor colliders.")
		set_process(false)
		return
	if not deck_origin_heights.is_empty() and deck_origin_heights.size() != floor_bodies.size():
		push_error("Minimap: custom origin heights must include one entry per floor collider.")
		set_process(false)
		return
	for body in floor_bodies:
		var shape := body.get_node_or_null("Collision") as CollisionShape3D if body else null
		if not shape or not shape.shape is ConcavePolygonShape3D:
			push_error("Minimap: each floor needs a Collision child with a ConcavePolygonShape3D.")
			set_process(false)
			return
		_deck_heights.append(lowest_deck_origin_y + body.global_position.y - floor_bodies[0].global_position.y)
	if not deck_origin_heights.is_empty():
		_deck_heights = deck_origin_heights.duplicate()

	_device = Node3D.new()
	_device.name = "HandheldDisplay"
	left.add_child(_device)
	_device.hide()
	_box(_device, Vector3(0.382, 0.291, 0.008), Vector3.ZERO, Color("#101d2b"))
	_box(_device, Vector3(0.351, 0.0015, 0.001), Vector3(0, 0.110, 0.005), Color("#386475"))
	_title = _label("DECK 01", 38, Vector3(0, 0.127, 0.006), Color.WHITE)
	_status = _label("", 25, Vector3(0, -0.111, 0.006), PLAYER)
	_hint = _label("STICK CLICK  /  3D", 29, Vector3(0, -0.132, 0.006), EDGE)

	_legend = _label("", 32, Vector3(0.108, 0.007, 0.006), ZONE_BORDER)
	_legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_legend.line_spacing = 7.0

	_view = Node3D.new()
	_device.add_child(_view)
	_view.position = Vector3(0, -0.004, 0.020)
	var names := {}
	for node in habitat.find_children("*", "Node3D", true, false):
		names[String(node.name)] = node
	for i in floor_bodies.size():
		_build_deck(floor_bodies[i])
		_build_zones(i, names)

	var marker_mesh := ImmediateMesh.new()
	marker_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Yellow arrow in the XZ plane, forward is -Z as on the XR camera.
	for v: Vector3 in [Vector3(0, 0, -0.010), Vector3(0.006, 0, 0.006), Vector3(-0.006, 0, 0.006)]:
		marker_mesh.surface_add_vertex(v)
	marker_mesh.surface_end()
	_marker = _mesh(_view, marker_mesh, _ink(PLAYER))

	var dot := CylinderMesh.new()
	dot.top_radius = 0.004
	dot.bottom_radius = 0.004
	dot.height = 0.002
	dot.radial_segments = 12
	_ladder_dot = _mesh(_view, dot, _ink(Color.WHITE))
	_ladder_dot.position.x = ladder_position.x * MAP_SCALE
	_ladder_dot.position.z = ladder_position.y * MAP_SCALE
	left.button_pressed.connect(_on_button_pressed.bind(left))
	right.button_pressed.connect(_on_button_pressed.bind(right))
	# Run after stick locomotion so the marker uses this frame's position.
	process_priority = 10


func _process(_delta: float) -> void:
	if _mode == ViewMode.CLOSED:
		return
	if not _owner.get_is_active():
		_close_map()
		return
	_refresh_map()


func _on_button_pressed(action: StringName, hand: XRController3D) -> void:
	if action != cycle_action or not hand.get_is_active():
		return
	match _mode:
		ViewMode.CLOSED:
			_owner = hand
			if _device.get_parent() != _owner:
				_device.reparent(_owner, false)
			_device.position = Vector3(0.035 if _owner == left else -0.035, 0.065, -0.215)
			_device.rotation_degrees = Vector3(-90, 0, 0)
			_mode = ViewMode.PLAN
			_refresh_map()
			_device.show()
		ViewMode.PLAN:
			_mode = ViewMode.HOLOGRAM
			_refresh_map()
		ViewMode.HOLOGRAM:
			_close_map()


func _close_map() -> void:
	_mode = ViewMode.CLOSED
	_owner = null
	_device.hide()


func _current_deck() -> int:
	var best := 0
	var y := _origin.global_position.y
	for i in range(1, _deck_heights.size()):
		if absf(y - _deck_heights[i]) < absf(y - _deck_heights[best]):
			best = i
	return best

func _refresh_map() -> void:
	var deck := _current_deck()
	var hologram := _mode == ViewMode.HOLOGRAM
	_title.text = "DECK  %02d    /    %s" % [deck + 1, "3D" if hologram else "PLAN"]
	_hint.text = "STICK CLICK  /  CLOSE" if hologram else "STICK CLICK  /  3D"
	_view.rotation_degrees = Vector3(32, -24, 0) if hologram else Vector3(90, 0, 0)
	_view.position = Vector3(0, -0.004, 0.099) if hologram else Vector3(-0.073, 0.005, 0.012)
	_legend.visible = not hologram
	if _legend.text != _legend_text[deck]:
		_legend.text = _legend_text[deck]
	for i in _decks.size():
		_decks[i].visible = hologram or i == deck
		_decks[i].position.y = (i - (_decks.size() - 1) * 0.5) * STACK_GAP if hologram else 0.0
		_fills[i].albedo_color = ACTIVE if i == deck else INACTIVE
		_fills[i].transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if i == deck else BaseMaterial3D.TRANSPARENCY_ALPHA
		_rims[i].albedo_color = EDGE if i == deck else Color("#427687")
		_zone_layers[i].visible = i == deck
		_zone_keys[i].visible = not hologram

	var head := camera.global_position
	var heading := -camera.global_basis.z
	var xz := Vector2(head.x, head.z)
	var off_map := xz.length() > MAP_LIMIT
	xz = xz.limit_length(MAP_LIMIT)
	_marker.position = Vector3(xz.x * MAP_SCALE, _decks[deck].position.y + 0.003, xz.y * MAP_SCALE)
	if Vector2(heading.x, heading.z).length_squared() > 0.0001:
		_marker.rotation.y = atan2(-heading.x, -heading.z)
	_ladder_dot.position.y = _decks[deck].position.y + 0.002
	_status.text = "MAP EDGE  /  YOU" if off_map else "WHITE DOT: LADDER   /   YELLOW: YOU"


func _build_deck(body: StaticBody3D) -> void:
	var collision := body.get_node("Collision") as CollisionShape3D
	var faces := (collision.shape as ConcavePolygonShape3D).get_faces()
	var deck := Node3D.new()
	_view.add_child(deck)
	_decks.append(deck)
	var top := -INF
	for p in faces:
		top = maxf(top, p.y)
	var fill := ImmediateMesh.new()
	var edges := {}
	fill.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, faces.size(), 3):
		if absf(faces[i].y - top) > 0.001 or absf(faces[i + 1].y - top) > 0.001 or absf(faces[i + 2].y - top) > 0.001:
			continue
		var corners: Array[Vector3] = []
		for j in range(3):
			var world := collision.to_global(faces[i + j])
			var point := Vector3(world.x, 0, world.z) * MAP_SCALE
			corners.append(point)
			fill.surface_add_vertex(point)
		for j in range(3):
			var a := corners[j]
			var b := corners[(j + 1) % 3]
			var ka := Vector2i(roundi(a.x * 100000), roundi(a.z * 100000))
			var kb := Vector2i(roundi(b.x * 100000), roundi(b.z * 100000))
			var key := Vector4i(ka.x, ka.y, kb.x, kb.y) if ka < kb else Vector4i(kb.x, kb.y, ka.x, ka.y)
			if edges.has(key):
				edges[key][2] += 1
			else:
				edges[key] = [a, b, 1]
	fill.surface_end()
	var material := _ink(INACTIVE)
	_fills.append(material)
	_mesh(deck, fill, material)

	# Only outline perimeter edges and openings, not the collision triangulation.
	var rim := ImmediateMesh.new()
	rim.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge: Array in edges.values():
		if edge[2] != 1:
			continue
		var a: Vector3 = edge[0] + Vector3.UP * 0.001
		var b: Vector3 = edge[1] + Vector3.UP * 0.001
		var offset := (b - a).normalized().cross(Vector3.UP) * 0.00055
		for p in [a - offset, b - offset, b + offset, a - offset, b + offset, a + offset]:
			rim.surface_add_vertex(p)
	rim.surface_end()
	var rim_material := _ink(EDGE)
	_rims.append(rim_material)
	_mesh(deck, rim, rim_material)


func _build_zones(index: int, nodes: Dictionary) -> void:
	var layer := Node3D.new()
	_decks[index].add_child(layer)
	_zone_layers.append(layer)
	var keys := Node3D.new()
	layer.add_child(keys)
	_zone_keys.append(keys)
	var footprints := ImmediateMesh.new()
	var legend := PackedStringArray()
	var specs: Array = LANDMARKS[index] if index < LANDMARKS.size() else []
	for spec: Array in specs:
		var model := nodes.get(spec[0]) as Node3D
		if model == null:
			push_warning("Minimap landmark missing: " + spec[0])
			continue
		var points := PackedVector2Array()
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		if model is MeshInstance3D:
			meshes.append(model)
		for mesh: MeshInstance3D in meshes:
			var bounds := mesh.get_aabb()
			for j in 8:
				var p := mesh.to_global(bounds.get_endpoint(j))
				points.append(Vector2(p.x, p.z) * MAP_SCALE)
		if points.size() < 3:
			continue
		var hull := Geometry2D.convex_hull(points)
		# convex_hull repeats the first point at the end.
		if hull.size() < 4:
			continue
		if legend.is_empty():
			footprints.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		var center := Vector2.ZERO
		for j in hull.size() - 1:
			center += hull[j]
		center /= float(hull.size() - 1)
		for j in hull.size() - 1:
			var a := hull[j]
			var b := hull[j + 1]
			footprints.surface_set_color(ZONE_COLOR)
			for p in [center, a, b]:
				footprints.surface_add_vertex(Vector3(p.x, 0.0015, p.y))
			var inset_a := a.move_toward(center, 0.0008)
			var inset_b := b.move_toward(center, 0.0008)
			footprints.surface_set_color(ZONE_BORDER)
			for p in [a, b, inset_b, a, inset_b, inset_a]:
				footprints.surface_add_vertex(Vector3(p.x, 0.0018, p.y))
		var number := str(legend.size() + 1)
		legend.append(number + "   " + spec[1])
		var key := _label(number, 31, Vector3(center.x, 0.0024, center.y), Color.WHITE, keys)
		key.rotation_degrees.x = -90
		key.outline_size = 5
	if not legend.is_empty():
		footprints.surface_end()
		var material := _ink(Color.WHITE)
		material.vertex_color_use_as_albedo = true
		_mesh(layer, footprints, material)
	_legend_text.append("\n".join(legend))


func _ink(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat


func _mesh(parent: Node3D, shape: Mesh, material: Material) -> MeshInstance3D:
	var item := MeshInstance3D.new()
	item.mesh = shape
	item.material_override = material
	item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(item)
	return item


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = size
	_mesh(parent, box, _ink(color)).position = at


func _label(content: String, points: int, at: Vector3, color: Color, parent: Node3D = null) -> Label3D:
	var item := Label3D.new()
	item.text = content
	item.font_size = points
	item.pixel_size = 0.00042
	item.outline_size = 0
	item.modulate = color
	var container := parent if parent else _device
	container.add_child(item)
	item.position = at
	return item

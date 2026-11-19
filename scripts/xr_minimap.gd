extends Node
## Handheld deck map. Observes the XR rig and does not own locomotion.
##
## The map is the habitat model itself, drawn small: every mesh under `habitat` is shown again at
## MAP_SCALE (sharing the mesh, nothing is copied) with a material that cuts it open CUT_HEIGHT above
## each deck, so walls, hatches, the ladder and every piece of equipment sit where they really are.
##   PLAN: the deck you are on, seen from above as a shallow relief, with numbered landmarks.
##   3D:   all decks at their true spacing, standing on the display; the deck you are on is solid,
##         the others are see-through.
## A model change needs no edit here unless a LANDMARKS node is renamed or the ladder moves.

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
@export var ladder_position := Vector2(-0.44, 0.48)
@export var cycle_action: StringName = &"primary_click"
## Off = the stick click does nothing and an open map closes (the lobby turns it off).
@export var enabled := true:
	set(value):
		enabled = value
		if not enabled and _mode != ViewMode.CLOSED:
			_close_map()

enum ViewMode { CLOSED, PLAN, HOLOGRAM }

const SOLID_SHADER := preload("res://assets/shaders/map_solid.gdshader")
const GHOST_DEPTH_SHADER := preload("res://assets/shaders/map_ghost_depth.gdshader")
const GHOST_SHADER := preload("res://assets/shaders/map_ghost.gdshader")

## Metres on the map per metre of habitat.
const MAP_SCALE := 0.030
const MAP_LIMIT := 3.52
## Each deck is cut open this far above its floor (metres), below eye level so you look in over the walls.
const CUT_HEIGHT := 1.4
## How far below a deck's floor its slice starts: the floor slab, and for the lowest deck the foundation.
const SLAB := 0.14
const BASE_DROP := 0.62
## In the plan the lowest deck starts just under its walking surface, above the foundation plates.
const PLAN_SLAB := 0.05
## The map is a few centimetres across, so its meshes switch to their coarser versions (LODs) much earlier
## than the full-size habitat does. 1 would keep the habitat's own switching distances.
const PART_LOD_BIAS := 0.3
## On the headset itself (Mobile renderer) the map has to be much lighter than on the PC: coarser
## meshes, no pieces under LITE_MIN_PART metres, no small pieces with more than LITE_MAX_TRIANGLES
## triangles, and the decks you are not on show their structure only (hull, floor, rails).
const LITE_LOD_BIAS := 0.06
const LITE_MIN_PART := 0.2
const LITE_MAX_TRIANGLES := 6000
const LITE_SMALL := 0.8
## Height of the plan relative to the real thing: 1 would be the full 3D slice, 0 a flat drawing.
const PLAN_RELIEF := 0.15
## Meshes smaller than this (longest side, metres) are left off the map.
const MIN_PART := 0.05
## Meshes wider than this are structure (shell, decks, rails) and drawn darker than equipment.
const STRUCTURE_SPAN := 3.0
const STRUCTURE_TONE := Vector4(0.6, 0.7, 0.78, 0.0)
const LANDMARK_TONE := Vector4(1.0, 1.0, 1.0, 0.8)
const EDGE := Color("#7eedf7")
const PLAYER := Color("#ffe47b")
const DIM := Color("#427687")

# Pairs are the imported model node and the concise map label.
const LANDMARKS := [
	# Node names of the habitat model exported from blender/Lunar_Surface_Habitat.blend
	# (tools/export_habitat_glb.py). tests/habitat_smoke.tscn fails when one of them is gone.
	[["Airlock | floor zone", "Airlock"], ["Sketchfab_model_003", "Workbench"], ["EVA workstation", "EVA station"],
		["Astronaut | Original mesh - assigned materials_001", "EVA suit"], ["Hatch door H-1_001", "EVA hatch"]],
	[["ShowerBooth", "Shower"], ["ToiletBooth", "Toilet"], ["C-Component#1", "Exercise"],
		["Biology utilization lab", "Biology lab"], ["Air revitalization pallet 01", "Air revitalization"]],
	[["Sketchfab_model_002", "Crew quarters"], ["Sketchfab_model_001", "Medical"],
		["COLAGTRECTL6 (C-COLAGTOV1)", "Wardroom"], ["Galley | food preparation", "Galley"],
		["Human research lab", "Human research"]]
]
const ZONE_BORDER := Color("#abdcff")

var _owner: XRController3D
var _mode := ViewMode.CLOSED
var _origin: XROrigin3D
var _deck_heights := PackedFloat32Array()
## World height of each deck's walking surface.
var _floor_y := PackedFloat32Array()
var _device: Node3D
var _view: Node3D
var _decks: Array[Node3D] = []
## Per deck: the node that holds the small meshes, the meshes, and the two looks they can have.
var _models: Array[Node3D] = []
var _parts: Array[Array] = []
## Parts of _parts that are equipment (not structure): hidden on see-through decks in the light version.
var _equipment := {}
var _lite := false
var _solid: Array[ShaderMaterial] = []
var _ghost: Array[ShaderMaterial] = []
var _ghost_colour: Array[ShaderMaterial] = []
var _tags: Array[Label3D] = []
var _marker: MeshInstance3D
var _stem: MeshInstance3D
var _ladder_dot: MeshInstance3D
var _scale_bar: Node3D
var _title: Label3D
var _hint: Label3D
var _status: Label3D
var _legend: Label3D
var _zone_layers: Array[Node3D] = []
var _zone_keys: Array[Node3D] = []
var _legend_text: Array[String] = []
## What the map shows now, so the materials are only swapped when the deck or the mode changes.
var _shown_deck := -1
var _shown_mode := ViewMode.CLOSED


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
		var top := -INF
		for p in (shape.shape as ConcavePolygonShape3D).get_faces():
			top = maxf(top, shape.to_global(p).y)
		_floor_y.append(top)
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

	# One metre at map scale, bottom left of the plan.
	_scale_bar = Node3D.new()
	_device.add_child(_scale_bar)
	_scale_bar.position = Vector3(-0.180, -0.088, 0.005)
	var metre := 1.0 * MAP_SCALE
	_box(_scale_bar, Vector3(metre, 0.0012, 0.001), Vector3(metre * 0.5, 0, 0), ZONE_BORDER)
	_box(_scale_bar, Vector3(0.0012, 0.005, 0.001), Vector3(0, 0.0019, 0), ZONE_BORDER)
	_box(_scale_bar, Vector3(0.0012, 0.005, 0.001), Vector3(metre, 0.0019, 0), ZONE_BORDER)
	_label("1 m", 22, Vector3(metre * 0.5, 0.0085, 0.001), ZONE_BORDER, _scale_bar)

	# The map's axes are the habitat's: +Y of the view is up in the habitat and stands out of the display.
	_view = Node3D.new()
	_device.add_child(_view)
	_view.rotation_degrees = Vector3(90, 0, 0)
	var names := {}
	for node in habitat.find_children("*", "Node3D", true, false):
		names[String(node.name)] = node
	var marks := {}
	for specs: Array in LANDMARKS:
		for spec: Array in specs:
			if names.has(spec[0]):
				marks[names[spec[0]]] = true
	for i in floor_bodies.size():
		_build_deck(i)
	_build_model(marks)
	for i in floor_bodies.size():
		_build_zones(i, names)

	var marker_mesh := ImmediateMesh.new()
	marker_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Yellow arrow in the XZ plane, forward is -Z as on the XR camera.
	for v: Vector3 in [Vector3(0, 0, -0.010), Vector3(0.006, 0, 0.006), Vector3(-0.006, 0, 0.006)]:
		marker_mesh.surface_add_vertex(v)
	marker_mesh.surface_end()
	_marker = _mesh(_view, marker_mesh, _ink(PLAYER))
	# In 3D the arrow floats at head height; this line drops from it to where you stand.
	var stem := BoxMesh.new()
	stem.size = Vector3(0.0011, 1.0, 0.0011)
	_stem = _mesh(_view, stem, _ink(PLAYER))

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
	if not enabled or action != cycle_action or not hand.get_is_active():
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
	if deck != _shown_deck or _mode != _shown_mode:
		_show(deck, hologram)

	var head := camera.global_position
	var heading := -camera.global_basis.z
	var xz := Vector2(head.x, head.z)
	var off_map := xz.length() > MAP_LIMIT
	xz = xz.limit_length(MAP_LIMIT)
	# Above the cut, so nothing on the deck hides the arrow.
	var relief := _decks[deck].scale.y
	var lift := (CUT_HEIGHT + 0.2) * MAP_SCALE * relief
	_marker.position = Vector3(xz.x * MAP_SCALE, _decks[deck].position.y + lift, xz.y * MAP_SCALE)
	if Vector2(heading.x, heading.z).length_squared() > 0.0001:
		_marker.rotation.y = atan2(-heading.x, -heading.z)
	_stem.position = _marker.position - Vector3(0, lift * 0.5, 0)
	_stem.scale.y = lift
	_ladder_dot.position.y = _decks[deck].position.y + (CUT_HEIGHT + 0.04) * MAP_SCALE * relief
	_status.text = "MAP EDGE  /  YOU" if off_map else "WHITE DOT: LADDER   /   YELLOW: YOU"


## Lays the decks out for the mode and gives each one its look: solid for the deck you are on,
## see-through for the others.
func _show(deck: int, hologram: bool) -> void:
	_shown_deck = deck
	_shown_mode = _mode
	_title.text = "DECK  %02d    /    %s" % [deck + 1, "3D" if hologram else "PLAN"]
	_hint.text = "STICK CLICK  /  CLOSE" if hologram else "STICK CLICK  /  3D"
	# Plan: left of the legend, just above the display. 3D: in the middle, the foundation on the display.
	_view.position = Vector3(0, -0.004, 0.012 + BASE_DROP * MAP_SCALE) if hologram else Vector3(-0.073, 0.005, 0.012)
	_legend.visible = not hologram
	_scale_bar.visible = not hologram
	_stem.visible = hologram
	if _legend.text != _legend_text[deck]:
		_legend.text = _legend_text[deck]
	# The foundation under the lowest deck belongs to the 3D view only; in the plan it would hide the hull's outline.
	var bottom := _floor_y[0] - (BASE_DROP if hologram else PLAN_SLAB)
	for m: ShaderMaterial in [_solid[0], _ghost[0], _ghost_colour[0]]:
		m.set_shader_parameter(&"cut_lo", bottom)
	for i in _decks.size():
		_decks[i].visible = hologram or i == deck
		_decks[i].position.y = (_floor_y[i] - _floor_y[0]) * MAP_SCALE if hologram else 0.0
		_decks[i].scale.y = 1.0 if hologram else PLAN_RELIEF
		var look: ShaderMaterial = _solid[i] if i == deck else _ghost[i]
		for part: MeshInstance3D in _parts[i]:
			part.material_override = look
			if _lite:
				part.visible = i == deck or not _equipment.has(part)
		# Decks above you are in the way when you look down, so they are fainter.
		_ghost_colour[i].set_shader_parameter(&"alpha", 0.55 if i > deck else 1.0)
		_zone_layers[i].visible = i == deck
		_zone_keys[i].visible = not hologram
		_tags[i].visible = hologram
		_tags[i].modulate = Color.WHITE if i == deck else DIM


func _build_deck(index: int) -> void:
	var deck := Node3D.new()
	_view.add_child(deck)
	_decks.append(deck)
	# Children of this node are placed in habitat coordinates (metres); the deck's floor ends up at y = 0.
	var model := Node3D.new()
	deck.add_child(model)
	model.transform = Transform3D(Basis().scaled(Vector3.ONE * MAP_SCALE), Vector3(0, -_floor_y[index] * MAP_SCALE, 0))
	_models.append(model)
	_parts.append([])

	var lo := _slice_bottom(index)
	var hi := _floor_y[index] + CUT_HEIGHT
	var solid := ShaderMaterial.new()
	solid.shader = SOLID_SHADER
	var colour := ShaderMaterial.new()
	colour.shader = GHOST_SHADER
	colour.render_priority = 2
	var depth := ShaderMaterial.new()
	depth.shader = GHOST_DEPTH_SHADER
	depth.render_priority = 1
	depth.next_pass = colour
	for m: ShaderMaterial in [solid, colour, depth]:
		m.set_shader_parameter(&"floor_y", _floor_y[index])
		m.set_shader_parameter(&"cut_lo", lo)
		m.set_shader_parameter(&"cut_hi", hi)
	_solid.append(solid)
	_ghost.append(depth)
	_ghost_colour.append(colour)

	var tag := _label("%02d" % (index + 1), 30, Vector3(-(MAP_LIMIT * MAP_SCALE + 0.018), CUT_HEIGHT * 0.5 * MAP_SCALE, 0), Color.WHITE, deck)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.visible = false
	_tags.append(tag)


func _slice_bottom(index: int) -> float:
	return _floor_y[index] - (BASE_DROP if index == 0 else SLAB)


## Puts every mesh of the habitat on the map, once for each deck whose slice it reaches into.
func _build_model(marks: Dictionary) -> void:
	_lite = RenderingServer.get_current_rendering_method() != "forward_plus"
	var skipped := 0
	for node in habitat.find_children("*", "MeshInstance3D", true, false):
		var src := node as MeshInstance3D
		if src.mesh == null or not src.is_visible_in_tree():
			continue
		var xf := src.global_transform
		var box := xf * src.get_aabb()
		if box.get_longest_axis_size() < (LITE_MIN_PART if _lite else MIN_PART):
			skipped += 1
			continue
		var tone := _tone_of(src, box, marks)
		if _lite and tone.w == 0.0 and box.get_longest_axis_size() < LITE_SMALL and _triangles(src.mesh) > LITE_MAX_TRIANGLES:
			skipped += 1
			continue
		# Habitat height of a model vertex v is dot(row.xyz, v) + row.w.
		var row := Vector4(xf.basis.x.y, xf.basis.y.y, xf.basis.z.y, xf.origin.y)
		for i in _decks.size():
			if box.end.y < _slice_bottom(i) or box.position.y > _floor_y[i] + CUT_HEIGHT:
				continue
			var part := MeshInstance3D.new()
			part.mesh = src.mesh
			part.transform = xf
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			part.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			part.lod_bias = LITE_LOD_BIAS if _lite else PART_LOD_BIAS
			if tone != STRUCTURE_TONE:
				_equipment[part] = true
			part.set_instance_shader_parameter(&"src_y", row)
			part.set_instance_shader_parameter(&"tone", tone)
			_models[i].add_child(part)
			_parts[i].append(part)
	if _lite:
		print("Minimap|INFO: light version for the headset, %d small or heavy pieces left off" % skipped)


func _triangles(mesh: Mesh) -> int:
	var count := 0
	for s in mesh.get_surface_count():
		var indices: int = mesh.surface_get_array_index_len(s)
		count += (indices if indices > 0 else mesh.surface_get_array_len(s)) / 3
	return count


## Structure is darker, equipment lighter (each piece a slightly different shade so neighbours separate),
## the numbered landmarks nearly white.
func _tone_of(src: MeshInstance3D, box: AABB, marks: Dictionary) -> Vector4:
	var top: Node = src
	var n: Node = src
	while n != null and n != habitat:
		if marks.has(n):
			return LANDMARK_TONE
		top = n
		n = n.get_parent()
	if maxf(box.size.x, box.size.z) > STRUCTURE_SPAN:
		return STRUCTURE_TONE
	var shade := lerpf(0.84, 1.08, float(String(top.name).hash() % 100) / 99.0)
	return Vector4(shade, shade, shade, 0.0)


func _build_zones(index: int, nodes: Dictionary) -> void:
	var layer := Node3D.new()
	_decks[index].add_child(layer)
	_zone_layers.append(layer)
	var keys := Node3D.new()
	layer.add_child(keys)
	_zone_keys.append(keys)
	var legend := PackedStringArray()
	var specs: Array = LANDMARKS[index] if index < LANDMARKS.size() else []
	for spec: Array in specs:
		var model := nodes.get(spec[0]) as Node3D
		if model == null:
			push_warning("Minimap landmark missing: " + spec[0])
			continue
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		if model is MeshInstance3D:
			meshes.append(model)
		if meshes.is_empty():
			continue
		var box := AABB()
		var first := true
		for mesh: MeshInstance3D in meshes:
			var b := mesh.global_transform * mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var number := str(legend.size() + 1)
		legend.append(number + "   " + spec[1])
		# The number lies on top of the landmark, or on the cut if the landmark is taller than that.
		var c := box.get_center()
		var top := minf(box.end.y - _floor_y[index], CUT_HEIGHT) + 0.1
		var key := _label(number, 31, Vector3(c.x, top, c.z) * MAP_SCALE, Color.WHITE, keys)
		key.rotation_degrees.x = -90
		key.outline_size = 5
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

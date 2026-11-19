# Ladder climbing. Stand near the ladder and press Y or B to climb up a deck, X or A to climb down.
# Moves the XROrigin3D to the ladder, up/down it, then off onto the landing.
# Floor collision is turned off while climbing so you pass through the decks.
#############################################

extends Node
class_name XRLadder


## Kill switch
@export var enabled := true

## Climbs up: Y (left) and B (right).
@export var up_action := "by_button"
## Climbs down: X (left) and A (right).
@export var down_action := "ax_button"

## Group holding the floor StaticBody3Ds to turn off while climbing
@export var floor_group := "habitat_floor"

@export_group("Nodes")
## Head
@export_node_path("XRCamera3D") var camera: NodePath
## The two controllers (either one's buttons climb). Named up/down from when one hand went up.
@export_node_path("XRController3D") var up_controller: NodePath
@export_node_path("XRController3D") var down_controller: NodePath
## Joystick locomotion, paused while climbing
@export_node_path("Node3D") var movement: NodePath

@export_group("Ladder")
## Ladder center on the floor plan (x, z), in world space
@export var ladder_position := Vector2(-0.44, 0.48)
## Where your head goes while on the ladder (x, z). Inside the deck openings.
@export var climb_position := Vector2(0.05, 0.48)
## How close your head must be to the ladder to use it, in meters
@export var use_radius := 1.0
## Where you arrive on each deck, bottom to top. y is the deck height.
@export var landings: Array[Vector3] = [
	Vector3(0.45, 0.0, 0.48),
	Vector3(0.0, 2.6, 1.6),
	Vector3(0.0, 5.2, 1.55),
]

@export_group("Parameters")
@export var climb_speed := 1.2 ## m/s, vertical
@export var step_speed := 1.0 ## m/s, getting on and off the ladder

var _origin: XROrigin3D = null
var _camera: XRCamera3D = null
var _movement: Node3D = null

var _climbing := false

## First time you come near the ladder (each app launch), a popup says which buttons climb.
@export var show_hint := true
const HINT_SECONDS := 7.0
var _hint: Label3D = null
var _hint_left := 0.0
var _hinted := false


func _ready() -> void:
	_origin = get_parent() as XROrigin3D
	if _origin == null:
		push_error("XRLadder|FATAL: this node must be a child of an XROrigin3D")
		return

	_camera = get_node_or_null(camera) as XRCamera3D
	_movement = get_node_or_null(movement) as Node3D

	add_to_group("xr_ladder")
	for path in [up_controller, down_controller]:
		var c := get_node_or_null(path) as XRController3D
		if c:
			c.button_pressed.connect(_on_button_pressed)


## true when Y / B would climb (near the ladder, or on an imported model). B toggles passthrough
## everywhere else; XRTogglePassthrough asks this first.
func uses_buttons() -> bool:
	if not enabled or _camera == null:
		return false
	if NoteManager.has_model():
		return true
	var head := Vector2(_camera.global_position.x, _camera.global_position.z)
	return head.distance_to(ladder_position) <= use_radius


func _process(delta: float) -> void:
	if not _hinted and show_hint and uses_buttons():
		_hinted = true
		_show_hint()
	if _hint == null or not _hint.visible:
		return
	_hint_left -= delta
	# Float 0.9 m in front of the head, a little below eye level; follow the head gently.
	var fwd := -_camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var want := _camera.global_position + fwd * 0.9 + Vector3.DOWN * 0.12
	_hint.global_position = _hint.global_position.lerp(want, 1.0 - exp(-6.0 * delta))
	_hint.modulate.a = clampf(_hint_left / 0.5, 0.0, 1.0)
	_hint.outline_modulate.a = _hint.modulate.a
	if _hint_left <= 0.0:
		_hint.visible = false


func _show_hint() -> void:
	if _hint == null:
		_hint = Label3D.new()
		_hint.name = "LadderHint"
		_hint.text = "LADDER\nY or B  ▲  climb up\nX or A  ▼  climb down"
		_hint.font_size = 44
		_hint.pixel_size = 0.0008
		_hint.outline_size = 12
		_hint.outline_modulate = Color(0, 0, 0, 0.85)
		_hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_hint.no_depth_test = true
		_hint.render_priority = 50
		_hint.fixed_size = false
		get_tree().current_scene.add_child(_hint)
	var fwd := -_camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	_hint.global_position = _camera.global_position + fwd * 0.9 + Vector3.DOWN * 0.12
	_hint_left = HINT_SECONDS
	_hint.visible = true


func _on_button_pressed(action: StringName) -> void:
	var step := 1 if action == up_action else (-1 if action == down_action else 0)
	if not enabled or _climbing or step == 0 or _camera == null:
		return

	# An imported model (space-setup pipeline) has no ladder: the buttons step straight to the next
	# floor's landing, keeping your place in the play space.
	if NoteManager.has_model():
		var lands: Array[Vector3] = NoteManager.floor_landings()
		var idx := NoteManager.floor_index_at(_origin.global_position.y) + step
		if lands.size() < 2 or idx < 0 or idx >= lands.size():
			return
		var landing := lands[idx]
		var head_pos := _camera.global_position
		_origin.global_position += Vector3(landing.x - head_pos.x, landing.y - _origin.global_position.y, landing.z - head_pos.z)
		return

	var head := Vector2(_camera.global_position.x, _camera.global_position.z)
	if head.distance_to(ladder_position) > use_radius:
		return

	var target := _current_deck() + step
	if target < 0 or target >= landings.size():
		return

	_climb(landings[target])


func _climb(landing: Vector3) -> void:
	_climbing = true
	if _hint != null and _hint_left > 0.5:
		_hint_left = 0.5   # fade out: they found the buttons
	_set_floors_enabled(false)
	if _movement:
		_movement.set("enabled", false)

	# Targets are for the head. Offset them so the origin moves the head there,
	# keeping wherever you're standing in your play space.
	var head := _camera.global_position
	var offset := Vector2(_origin.global_position.x - head.x, _origin.global_position.z - head.z)

	var on_ladder := Vector3(climb_position.x + offset.x, _origin.global_position.y, climb_position.y + offset.y)
	var top := Vector3(on_ladder.x, landing.y, on_ladder.z)
	var off_ladder := Vector3(landing.x + offset.x, landing.y, landing.z + offset.y)

	var tween := create_tween()
	tween.tween_property(_origin, "global_position", on_ladder, _origin.global_position.distance_to(on_ladder) / step_speed)
	tween.tween_property(_origin, "global_position", top, on_ladder.distance_to(top) / climb_speed)
	tween.tween_property(_origin, "global_position", off_ladder, top.distance_to(off_ladder) / step_speed)
	tween.tween_callback(_finish_climb)


func _finish_climb() -> void:
	_set_floors_enabled(true)
	if _movement:
		_movement.set("enabled", true)
	_climbing = false


func _set_floors_enabled(on: bool) -> void:
	for body in get_tree().get_nodes_in_group(floor_group):
		for shape in body.find_children("*", "CollisionShape3D", true, false):
			shape.set_deferred("disabled", not on)


# The deck whose height is closest to the origin's
func _current_deck() -> int:
	var best := 0
	for i in landings.size():
		if absf(landings[i].y - _origin.global_position.y) < absf(landings[best].y - _origin.global_position.y):
			best = i
	return best

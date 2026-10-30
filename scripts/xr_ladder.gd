# Ladder climbing. Stand near the ladder and press A to climb up a deck, X to climb down.
# Moves the XROrigin3D to the ladder, up/down it, then off onto the landing.
# Floor collision is turned off while climbing so you pass through the decks.
#############################################

extends Node
class_name XRLadder


## Kill switch
@export var enabled := true

## Button action from the action map. A on the right controller, X on the left.
@export var button_action := "ax_button"

## Group holding the floor StaticBody3Ds to turn off while climbing
@export var floor_group := "habitat_floor"

@export_group("Nodes")
## Head
@export_node_path("XRCamera3D") var camera: NodePath
## Controller whose button climbs up
@export_node_path("XRController3D") var up_controller: NodePath
## Controller whose button climbs down
@export_node_path("XRController3D") var down_controller: NodePath
## Joystick locomotion, paused while climbing
@export_node_path("Node3D") var movement: NodePath

@export_group("Ladder")
## Ladder center on the floor plan (x, z), in world space
@export var ladder_position := Vector2(0.0, 0.46)
## Where your head goes while on the ladder (x, z). Inside the deck openings.
@export var climb_position := Vector2(0.0, 0.1)
## How close your head must be to the ladder to use it, in meters
@export var use_radius := 1.0
## Where you arrive on each deck, bottom to top. y is the deck height.
@export var landings: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.0, 2.6, 1.3),
	Vector3(-0.7, 5.2, 0.45),
]

@export_group("Parameters")
@export var climb_speed := 1.2 ## m/s, vertical
@export var step_speed := 1.0 ## m/s, getting on and off the ladder

var _origin: XROrigin3D = null
var _camera: XRCamera3D = null
var _movement: Node3D = null

var _climbing := false


func _ready() -> void:
	_origin = get_parent() as XROrigin3D
	if _origin == null:
		push_error("XRLadder|FATAL: this node must be a child of an XROrigin3D")
		return

	_camera = get_node_or_null(camera) as XRCamera3D
	_movement = get_node_or_null(movement) as Node3D

	var up := get_node_or_null(up_controller) as XRController3D
	var down := get_node_or_null(down_controller) as XRController3D
	if up:
		up.button_pressed.connect(_on_button_pressed.bind(1))
	if down:
		down.button_pressed.connect(_on_button_pressed.bind(-1))


func _on_button_pressed(action: StringName, step: int) -> void:
	if not enabled or _climbing or action != button_action or _camera == null:
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

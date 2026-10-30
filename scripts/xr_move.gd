## TEMPLATE FILE ############################
# Joystick locomotion. Left stick to move, right stick to rotate.
# Turning is smooth by default (push further = turn faster). Set turn_mode to Snap for 30° steps.
# Only the right stick's left/right is used here; its up/down is the wrist board scroll (XRNotePlacer).
#############################################

extends Node3D
class_name XRMovement


## Kill switch. Turn it off for cutscenes, menus, whatever
@export var enabled := true

## Stick action from the action map. "primary" is the thumbstick.
@export var stick_action := "primary"

@export_group("Nodes")
## Head
@export_node_path("XRCamera3D") var camera: NodePath
## Controller that moves you (left by convention)
@export_node_path("XRController3D") var move_controller: NodePath
## Controller that rotates you (right by convention)
@export_node_path("XRController3D") var turn_controller: NodePath

@export_group("Parameters")
@export var move_speed := 2.0 ## m/s
## Smooth: continuous rotation while the stick is held. Snap: snap_degrees per flick.
@export_enum("Smooth", "Snap") var turn_mode := 0
## Smooth turn: degrees per second at full stick deflection
@export var turn_speed_degrees := 90.0
@export var snap_degrees := 30.0
@export_range(0.0, 0.9) var deadzone := 0.2 ## for stick drift
## Right stick: ignore left/right below this so scrolling the board (up/down) does not turn you
@export_range(0.0, 0.9) var turn_deadzone := 0.3

var _origin: XROrigin3D = null
var _camera: XRCamera3D = null
var _move_controller: XRController3D = null
var _turn_controller: XRController3D = null

# Latch to stop multiple turns from one input
var _can_turn := true


func _ready() -> void:
	_origin = get_parent() as XROrigin3D
	if _origin == null:
		push_error("XRMovement|FATAL: this node must be a child of an XROrigin3D")
		set_process(false)
		return

	_camera = get_node_or_null(camera) as XRCamera3D
	_move_controller = get_node_or_null(move_controller) as XRController3D
	_turn_controller = get_node_or_null(turn_controller) as XRController3D

func _process(delta: float) -> void:
	if not enabled:
		return

	_slide(delta)
	if turn_mode == 0:
		_smooth_turn(delta)
	else:
		_snap_turn()


func _slide(delta: float) -> void:
	if _move_controller == null:
		return

	var stick := _move_controller.get_vector2(stick_action)
	if stick.length() < deadzone:
		return

	# Get head rotation and throw away the y component.
	var basis := _camera.global_transform.basis
	var forward := -basis.z
	var right := basis.x
	forward.y = 0.0
	right.y = 0.0

	# Keep the direction a unit vector as well. Otherwise diagonal movement is faster, a bug
	# youve probably seen in other games
	var direction := (right.normalized() * stick.x + forward.normalized() * stick.y).limit_length(1.0)
	_origin.global_position += direction * move_speed * delta


## Continuous rotation around the head. The further the stick is pushed, the faster the turn.
func _smooth_turn(delta: float) -> void:
	if _turn_controller == null or _camera == null:
		return
	var x := _turn_controller.get_vector2(stick_action).x
	if absf(x) < turn_deadzone:
		return
	var amount := (absf(x) - turn_deadzone) / (1.0 - turn_deadzone) * signf(x)
	_rotate_around_head(deg_to_rad(-turn_speed_degrees * amount * delta))


func _snap_turn() -> void:
	if _turn_controller == null:
		return

	var stick := _turn_controller.get_vector2(stick_action)

	# Allow a turn when the stick is in the deadzone.
	if absf(stick.x) < deadzone:
		_can_turn = true
		return

	if not _can_turn:
		return
	_can_turn = false # This is where a turn will happen. We flip this flag to stop another one

	# snap_degrees left or right
	_rotate_around_head(deg_to_rad(snap_degrees) * -signf(stick.x))


## Rotate the origin about the head's position so the body stays where it is.
func _rotate_around_head(angle: float) -> void:
	var pivot := _camera.global_position
	pivot.y = _origin.global_position.y
	var t := _origin.global_transform
	t = t.translated(-pivot)
	t = Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO) * t
	t = t.translated(pivot)
	_origin.global_transform = t

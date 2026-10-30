## Sticky notes for the VR rig.
##
## Put this node under the XROrigin3D. It builds everything the notes addon needs in VR:
##   - a wrist board on the left hand (WristBoard: identity, type chips, Note / List / Session)
##   - a pointer on the right hand (XRNotePlacer: trigger to place / open / record)
##   - the immersive clip theater (ClipTheater: fade, teleport, screen + sound)
## and listens for "Go there" / tour teleports from NoteManager.
##
## The template's controllers use the grip pose (for the controller models). The board and the
## pointer want the aim pose, so two extra XRController3D nodes are created here with the
## "default" pose (= aim in the OpenXR action map). Same trackers, same buttons, just a
## different pose.
##
## Right-hand buttons stay free for the template: A climbs the ladder, B toggles passthrough,
## grip grabs props. Only the trigger and the right stick's up / down (board scroll) are used here.
class_name XRNotes
extends Node

@export_group("Nodes")
## Head
@export_node_path("XRCamera3D") var camera: NodePath
## XRMovement, paused during clip playback
@export_node_path("Node3D") var movement: NodePath
## XRLadder, paused during clip playback
@export_node_path("Node") var ladder: NodePath

@export_group("Board")
## Board position / tilt relative to the left controller (aim pose). Adjust if it doesn't sit on the hand.
@export var board_offset := Vector3(0.0, 0.07, 0.10)
@export var board_tilt_degrees := Vector3(-55.0, 0.0, 0.0)
## Pose used for the board and the pointer. "default" = aim pose in the action map.
@export var controller_pose: StringName = &"default"

var origin: XROrigin3D
var left: XRController3D
var right: XRController3D
var board: WristBoard
var theater: ClipTheater
var placer: XRNotePlacer

var _camera: XRCamera3D
var _movement: Node3D
var _ladder: Node


func _ready() -> void:
	origin = get_parent() as XROrigin3D
	if origin == null:
		push_error("XRNotes|FATAL: this node must be a child of an XROrigin3D")
		return
	# The origin is still setting up its children during _ready(), and main.gd has not decided
	# VR / desktop yet. Build everything one frame later.
	_setup.call_deferred()


func _setup() -> void:
	if not get_viewport().use_xr:
		print("XRNotes|INFO: viewport is not in XR (desktop mode), sticky notes use the desktop player instead")
		return

	_camera = get_node_or_null(camera) as XRCamera3D
	if _camera == null:
		for c in origin.get_children():
			if c is XRCamera3D:
				_camera = c
				break
	if _camera == null:
		push_error("XRNotes|FATAL: no XRCamera3D found under the XROrigin3D")
		return
	_movement = get_node_or_null(movement) as Node3D
	_ladder = get_node_or_null(ladder)

	# ---- aim-pose controllers for the board and the pointer ----
	left = XRController3D.new()
	left.name = "NotesLeftAim"
	left.tracker = &"left_hand"
	left.pose = controller_pose
	origin.add_child(left)

	right = XRController3D.new()
	right.name = "NotesRightAim"
	right.tracker = &"right_hand"
	right.pose = controller_pose
	origin.add_child(right)

	# ---- wrist board on the left hand ----
	board = WristBoard.new()
	board.name = "WristBoard"
	board.position = board_offset
	board.rotation_degrees = board_tilt_degrees
	left.add_child(board)

	# ---- immersive clip playback ----
	theater = ClipTheater.new()
	theater.name = "ClipTheater"
	add_child(theater)
	theater.attach(_camera, origin)
	theater.started.connect(_set_locomotion.bind(false))
	theater.finished.connect(_set_locomotion.bind(true))

	# ---- right-hand pointer ----
	placer = XRNotePlacer.new()
	placer.name = "XRNotePlacer"
	placer.camera = _camera
	placer.left = left
	placer.right = right
	placer.board = board
	placer.theater = theater
	add_child(placer)

	NoteManager.teleport_requested.connect(_on_teleport)
	print("XRNotes|INFO: sticky notes ready (wrist board on left hand, trigger on right hand)")


## Joystick locomotion and the ladder are frozen while a clip plays back.
func _set_locomotion(on: bool) -> void:
	if _movement != null:
		_movement.set("enabled", on)
	if _ladder != null:
		_ladder.set("enabled", on)


## "Go there" / tour: move the head to where the author stood, looking the same way.
## The height is moved too so a note written on another deck takes you to that deck.
func _on_teleport(cam_pos: Vector3, cam_rot: Vector3) -> void:
	if theater != null and theater.active:
		return
	var current_yaw := _camera.global_transform.basis.get_euler().y
	_rotate_around_camera(cam_rot.y - current_yaw)
	origin.global_position += cam_pos - _camera.global_position


## Rotate the origin around the head (not around the play-space center) so the body stays put.
func _rotate_around_camera(angle: float) -> void:
	var pivot := _camera.global_position
	origin.global_rotate(Vector3.UP, angle)
	var shift := pivot - _camera.global_position
	shift.y = 0.0
	origin.global_position += shift

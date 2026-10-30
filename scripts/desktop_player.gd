## Desktop first-person player. Used when no headset is connected (see main.gd).
##
##   W A S D, mouse      move, look          Shift   run
##   Space / C           near the ladder: climb up / down one deck (same landings as XRLadder)
##   N (hold) / E / Tab  sticky notes (NotePlacer under the camera)
##   1 ~ 5, ] [, Esc     type filter, tour next / prev, close
##
## While a note panel is open the player stops; right-button drag looks around.
## The node origin is at the feet. The camera sits 1.6 m up.
class_name DesktopPlayer
extends CharacterBody3D

@export var speed := 3.0
@export var run_speed := 5.0
@export var mouse_sensitivity := 0.0025
@export var gravity := 9.8

@export_group("Ladder")
## Kill switch
@export var ladder_enabled := true
## Ladder center on the floor plan (x, z), world space. Keep in sync with XRLadder in main.tscn.
@export var ladder_position := Vector2(0.0, 0.46)
## Where your body goes while on the ladder (x, z). Inside the deck openings.
@export var climb_position := Vector2(0.0, 0.1)
## How close you must be to the ladder to use it, in metres
@export var use_radius := 1.2
## Where you arrive on each deck, bottom to top. y is the deck height.
@export var landings: Array[Vector3] = [
	Vector3(0.0, 0.0, 0.0),
	Vector3(0.0, 2.6, 1.3),
	Vector3(-0.7, 5.2, 0.45),
]
@export var climb_speed := 1.5 ## m/s, vertical
@export var step_speed := 1.5 ## m/s, getting on and off the ladder
## Collision groups switched off while climbing so you pass through the decks
@export var floor_groups: Array[String] = ["habitat_floor", "habitat_surface"]

@onready var camera: Camera3D = $Camera3D
@onready var placer: NotePlacer = $Camera3D/NotePlacer

var _climbing := false


func _ready() -> void:
	camera.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	NoteManager.teleport_requested.connect(_on_teleport)


func _unhandled_input(event: InputEvent) -> void:
	if placer.ui_open:
		# Panel open: look around only with the right mouse button held
		if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_look(event.relative)
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(event.relative)
	elif event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif ladder_enabled and not _climbing:
		if event.is_action_pressed("ladder_up"):
			_try_climb(1)
		elif event.is_action_pressed("ladder_down"):
			_try_climb(-1)


func _look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)
	camera.rotation.x = clampf(camera.rotation.x - relative.y * mouse_sensitivity, -1.45, 1.45)


func _physics_process(delta: float) -> void:
	if _climbing:
		return
	if placer.ui_open:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
		var s := run_speed if Input.is_action_pressed("move_run") else speed
		velocity.x = dir.x * s
		velocity.z = dir.z * s
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= gravity * delta
	move_and_slide()


# ---------------- ladder ----------------

func _try_climb(step: int) -> void:
	var here := Vector2(global_position.x, global_position.z)
	if here.distance_to(ladder_position) > use_radius:
		return
	var target := _current_deck() + step
	if target < 0 or target >= landings.size():
		return
	_climb(landings[target])


func _climb(landing: Vector3) -> void:
	_climbing = true
	velocity = Vector3.ZERO
	_set_floors_enabled(false)
	var on_ladder := Vector3(climb_position.x, global_position.y, climb_position.y)
	var top := Vector3(on_ladder.x, landing.y + 0.05, on_ladder.z)
	var off_ladder := landing + Vector3(0.0, 0.05, 0.0)
	var tween := create_tween()
	tween.tween_property(self, "global_position", on_ladder, global_position.distance_to(on_ladder) / step_speed)
	tween.tween_property(self, "global_position", top, on_ladder.distance_to(top) / climb_speed)
	tween.tween_property(self, "global_position", off_ladder, top.distance_to(off_ladder) / step_speed)
	tween.tween_callback(_finish_climb)


func _finish_climb() -> void:
	_set_floors_enabled(true)
	_climbing = false


func _set_floors_enabled(on: bool) -> void:
	for g in floor_groups:
		for body in get_tree().get_nodes_in_group(g):
			for shape in body.find_children("*", "CollisionShape3D", true, false):
				shape.set_deferred("disabled", not on)


## The deck whose height is closest to the feet
func _current_deck() -> int:
	var best := 0
	for i in landings.size():
		if absf(landings[i].y - global_position.y) < absf(landings[best].y - global_position.y):
			best = i
	return best


# ---------------- notes ----------------

## "Go there" / tour: stand where the author stood, look the same way.
func _on_teleport(cam_pos: Vector3, cam_rot: Vector3) -> void:
	if _climbing:
		return
	var feet := cam_pos - Vector3(0.0, camera.position.y, 0.0)
	# A note written in VR by a shorter person would put the feet under the deck. Snap to the deck.
	var deck := _nearest_landing_y(feet.y)
	if absf(deck - feet.y) < 0.8:
		feet.y = deck + 0.05
	global_position = feet
	rotation.y = cam_rot.y
	camera.rotation.x = cam_rot.x
	velocity = Vector3.ZERO


func _nearest_landing_y(y: float) -> float:
	var best := y
	var best_d := INF
	for l in landings:
		var d := absf(l.y - y)
		if d < best_d:
			best_d = d
			best = l.y
	return best

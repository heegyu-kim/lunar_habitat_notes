## Desktop player: fly mode passes through walls, walking mode lands on the ground; "Go outside" teleport.
##   Godot --headless --xr-mode off --path . res://tests/fly_smoke.tscn --quit-after 900
extends Node

var _fails := 0


func _check(cond: bool, what: String) -> void:
	print(("TEST|PASS  " if cond else "TEST|FAIL  ") + what)
	if not cond:
		_fails += 1


func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	for i in 10:
		await get_tree().physics_frame
	var player: CharacterBody3D = main.get_node_or_null("DesktopPlayer")
	_check(player != null, "desktop player present")
	if player == null:
		get_tree().quit(1)
		return
	# Walking into the tower wall must stop at it.
	player.global_position = Vector3(0.0, 0.05, 0.0)
	for i in 90:
		player.velocity = Vector3(0.0, 0.0, 4.0)   # push south towards the wall
		player.move_and_slide()
		await get_tree().physics_frame
	_check(player.global_position.z < 3.4, "walking stops at the wall (z=%.2f)" % player.global_position.z)
	# Fly mode ignores it.
	player.set_flying(true)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	for i in 60:
		player.global_position += Vector3(0.0, 0.0, 0.2)
		await get_tree().physics_frame
	_check(player.global_position.z > 11.0, "fly mode passes through the wall (z=%.2f)" % player.global_position.z)
	# Back to walking outside: gravity drops the player onto the ground collision.
	player.global_position = Vector3(0.0, 3.0, 14.0)
	player.set_flying(false)
	for i in 120:
		await get_tree().physics_frame
	_check(absf(player.global_position.y) < 0.3, "walking mode lands on the ground outside (y=%.2f)" % player.global_position.y)
	# Go outside / back inside teleports.
	NoteManager.teleport_requested.emit(Vector3(0.0, 1.65, 13.3), Vector3.ZERO)
	await get_tree().physics_frame
	_check(player.global_position.z > 12.0, "teleport outside (z=%.2f)" % player.global_position.z)
	var lands: Array[Vector3] = NoteManager.floor_landings()
	NoteManager.teleport_requested.emit(lands[0] + Vector3(0.0, 1.65, 0.0), Vector3.ZERO)
	await get_tree().physics_frame
	_check(player.global_position.distance_to(lands[0]) < 0.3, "teleport back to the ground-floor landing")
	print("TEST|DONE  failures=%d" % _fails)
	get_tree().quit(_fails)

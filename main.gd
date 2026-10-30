## Main scene root.
##
## With a headset:  starts OpenXR and runs the VR rig under XROrigin3D
##                  (ladder, grab, passthrough, hand tracking, sticky notes on the wrist board).
## Without one:     hides the VR rig and spawns the desktop first-person player
##                  (WASD + mouse, Space / C for the ladder, N / E / Tab for sticky notes).
##
## Godot propagates _ready() up through children, so everything under XROrigin3D is set up
## before this script runs.
extends Node3D

var xr_interface: OpenXRInterface

## Preferred refresh rate. Will fall back to what the headset reports.
@export var target_refresh_rate := 72.0

@export_group("Desktop fallback")
## Run the desktop player even when a headset is connected. Useful for typing note text at a desk.
@export var force_desktop := false
## Where the desktop player's feet start (world space). (0, 0, 0) is where the VR origin starts.
@export var desktop_start := Vector3(0.0, 0.05, 0.0)
@export var desktop_player_scene: PackedScene = preload("res://scenes/desktop_player.tscn")

## true once OpenXR is running. Scripts can check Main.is_vr via get_tree().current_scene.
var is_vr := false

@onready var xr_origin: XROrigin3D = $XROrigin3D


func _ready() -> void:
	xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface

	var xr_ok := false
	if force_desktop:
		print("Main|INFO: desktop mode forced")
	elif xr_interface == null:
		push_warning("Main|WARN: OpenXR interface not found (Project Settings -> XR). Running desktop.")
	elif xr_interface.is_initialized() or xr_interface.initialize():
		xr_ok = true
	else:
		print("Main|INFO: OpenXR failed to initialise (no headset connected?). Running desktop.")

	if not xr_ok:
		_start_desktop()
		return

	print("Main|INFO: OpenXR initialised successfully")

	# XR runtime frame pacing
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	get_viewport().use_xr = true
	is_vr = true

	xr_interface.session_begun.connect(_on_session_begun)


func _on_session_begun() -> void:
	var rates := xr_interface.get_available_display_refresh_rates()
	if target_refresh_rate in rates:
		xr_interface.display_refresh_rate = target_refresh_rate
	elif not rates.is_empty():
		print("Main|WARN: %s Hz unavailable, runtime offers %s" % [target_refresh_rate, rates])

	# Match physics to the actual rate.
	var actual: float = xr_interface.display_refresh_rate
	if actual > 0.0:
		Engine.physics_ticks_per_second = int(round(actual))
	print("Main|INFO: running at %s Hz" % Engine.physics_ticks_per_second)


## No headset: park the VR rig and bring in the desktop player.
func _start_desktop() -> void:
	xr_origin.visible = false
	xr_origin.process_mode = Node.PROCESS_MODE_DISABLED

	var player := desktop_player_scene.instantiate() as Node3D
	player.name = "DesktopPlayer"
	add_child(player)
	player.global_position = desktop_start
	print("Main|INFO: desktop player ready. WASD move, mouse look, Space / C ladder, N hold place note, E open, Tab list")

extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func tracker(hand: StringName) -> XRControllerTracker:
	var t := XRControllerTracker.new()
	t.name = hand
	t.type = XRServer.TRACKER_CONTROLLER
	t.set_pose(&"grip", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	t.set_input(&"primary_click", false)
	XRServer.add_tracker(t)
	return t


func click(hand: XRControllerTracker) -> void:
	hand.set_input(&"primary_click", true)
	hand.set_input(&"primary_click", false)


func _run() -> void:
	var l := tracker(&"left_hand")
	var r := tracker(&"right_hand")
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	scene.set_script(null) # No physical runtime; leave the real controller and minimap nodes in place.
	root.add_child(scene)
	var rig := scene.get_node("XROrigin3D") as XROrigin3D
	var map := rig.get_node("XRMinimap")
	if not is_instance_valid(map._device):
		push_error("Map did not initialize")
		quit(1)
		return
	await process_frame
	check(not map._device.visible, "Map starts closed")
	l.set_input(&"trigger", 0.9)
	r.set_input(&"trigger_click", true)
	map._process(0)
	check(not map._device.visible, "Triggers do not open the map")
	click(l)
	check(map._device.visible and map._device.get_parent() == map.left, "First click opens plan on left hand")
	check(map._decks[0].visible and not map._decks[1].visible, "Plan displays just the current deck")
	check(map._device.basis.y.is_equal_approx(Vector3.FORWARD), "Map lies flat and extends forward")
	for i in 3:
		check(map._zone_keys[i].get_child_count() == 5, "All five model landmarks are present on deck " + str(i + 1))
	r.set_input(&"trigger_click", false)
	l.set_input(&"trigger", 0.0)
	map._process(0)
	check(map._device.visible and "PLAN" in map._title.text, "Map stays open after releasing all buttons")
	click(r)
	check(map._device.get_parent() == map.left and "3D" in map._title.text and map._decks[2].visible, "Second click switches to 3D on the original hand")
	rig.position = Vector3(0.7, 5.2, -0.9)
	map._process(0)
	check("DECK  03" in map._title.text and map._fills[2].albedo_color == map.ACTIVE, "External locomotion changes the highlighted deck")
	check(is_equal_approx(map._marker.position.x, map.camera.global_position.x * map.MAP_SCALE), "Marker tracks live position")
	click(l)
	check(not map._device.visible, "Third click closes map")
	click(r)
	check(map._device.get_parent() == map.right and "PLAN" in map._title.text, "Right hand can reopen plan")
	XRServer.remove_tracker(r)
	map._process(0)
	check(not map._device.visible, "Tracking loss closes map")
	print("Minimap checks complete: %d failures" % failures)
	quit(1 if failures else 0)

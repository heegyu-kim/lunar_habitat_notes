## Screenshots the base from outside (and one from a window) so the lunar exterior can be checked.
##   Godot --xr-mode off --path . --resolution 1280x720 res://tests/exterior_shot.tscn --quit-after 900 -- out=<dir>
extends Node


func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	NoteManager.set_identity("Tester", 0)
	for n in get_tree().root.find_children("*", "", true, false):
		var sc: Variant = n.get_script()
		if sc != null and sc is Script and (sc as Script).get_global_name() == &"IdentityCard":
			n.visible = false
	for i in 15:
		await get_tree().process_frame
	var dir := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			dir = a.substr(4)
	var cam := Camera3D.new()
	cam.fov = 70
	cam.far = 6000.0
	main.add_child(cam)
	cam.make_current()
	var shots := {
		"ext_wide": [Vector3(-26.0, 9.0, 24.0), Vector3(-6.0, 1.5, -2.0)],
		"ext_low": [Vector3(14.0, 1.7, 12.0), Vector3(0.0, 2.0, 0.0)],
		"ext_horizon": [Vector3(4.0, 1.7, 6.0), Vector3(40.0, 4.0, -60.0)],
		"ext_earth": [Vector3(0.0, 1.7, 8.0), Vector3(0.0, 1.7, 8.0) + Vector3(0.35, 0.09, -0.93) * 50.0],
		"camp_wide": [Vector3(-30.0, 14.0, 26.0), Vector3(-8.0, 1.0, -4.0)],
		"camp_top": [Vector3(-8.0, 60.0, -5.0), Vector3(-8.0, 0.0, -5.5)],
		"camp_northside": [Vector3(-14.0, 2.0, -28.0), Vector3(-8.0, 1.5, -8.0)],
		"camp_north": [Vector3(-7.5, 6.0, 12.0), Vector3(-7.5, 1.0, -12.0)],
		"camp_b_inside": [Vector3(-3.0, 1.6, -12.0), Vector3(-12.0, 1.3, -12.3)],
		"camp_c_inside": [Vector3(-12.8, 1.6, 0.0), Vector3(-16.0, 1.2, 1.0)],
		"camp_c_deck2": [Vector3(-13.0, 4.2, 2.0), Vector3(-15.5, 3.4, -2.0)],
		"core_l3": [Vector3(1.8, 6.9, 1.8), Vector3(-1.0, 6.4, -1.0)],
		"camp_b_eclss": [Vector3(-4.5, 1.6, -10.6), Vector3(-9.0, 1.2, -13.4)],
	}
	for key in shots:
		cam.global_position = shots[key][0]
		cam.look_at(shots[key][1], Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(dir.path_join(key + ".png"))
		print("TEST|SHOT " + key)
	get_tree().quit()

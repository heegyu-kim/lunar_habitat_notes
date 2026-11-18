## Renders what the Quest will show (run with --rendering-method mobile), with and without the bake.
##   Godot --rendering-method mobile --xr-mode off --path . res://tests/quest_preview.tscn -- out=<dir> baked=1
extends Node

const VIEWS := [
	["hatch", Vector3(0.9, 1.6, 0.6), Vector3(-0.05, 2.4, 0.0)],
	["deck", Vector3(-0.6, 1.6, 0.9), Vector3(-0.25, -2.3, 0.0)],
	["upper", Vector3(0.6, 4.2, 0.9), Vector3(-0.1, 0.8, 0.0)],
]


func _ready() -> void:
	var out := "user://"
	var baked := true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		if a == "baked=0":
			baked = false
	var main: Node = load("res://main.tscn").instantiate()
	main.set("baked_lighting_on_desktop", baked)
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	for i in 30:
		await get_tree().process_frame
	if baked:
		main.call("_apply_vr_quality")
	for n in get_tree().root.find_children("*", "", true, false):
		if n is Control and n.get_script() != null and str(n.get_script().resource_path).ends_with("identity_card.gd"):
			n.visible = false
	var views := VIEWS.duplicate()
	var door := main.find_child("Hatch door H-1_001", true, false) as MeshInstance3D
	if door != null:
		var c: Vector3 = door.global_transform * door.get_aabb().get_center()
		var to_mid := Vector3(-c.x, 0.0, -c.z).normalized()
		var eye := Vector3(c.x, 1.6, c.z) + to_mid * 1.4
		var d := c - eye
		views.append(["door", eye, Vector3(atan2(d.y, Vector2(d.x, d.z).length()), atan2(-d.x, -d.z), 0.0)])
	for v in views:
		NoteManager.teleport_requested.emit(v[1], v[2])
		for i in 20:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path: String = out.path_join("%s_%s.png" % [v[0], "baked" if baked else "before"])
		get_viewport().get_texture().get_image().save_png(path)
		print("SHOT|", path)
	get_tree().quit()

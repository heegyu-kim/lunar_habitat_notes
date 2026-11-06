## Opens the desktop side panel on the Session tab and saves a screenshot, then quits.
##   Godot --xr-mode off --path . res://tests/ui_shot.tscn --quit-after 600 -- out=<png path>
extends Node


func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	for i in 20:
		await get_tree().process_frame
	var panel: Node = main.find_child("NotePanel", true, false)
	if panel == null:
		for n in get_tree().root.find_children("*", "NotePanel", true, false):
			panel = n
	if panel != null and panel.has_method("open_tab"):
		panel.open_tab(2)
	for i in 10:
		await get_tree().process_frame
	var out := "user://ui_session_tab.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("TEST|SHOT " + out + "  panel=" + str(panel != null))
	get_tree().quit()

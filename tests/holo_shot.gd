## Screenshots of holonote playback: a scripted holonote ghost in the habitat seen from the spot
## the VR theater puts you, and the wrist-board note view with the Play button. Not a test.
##   Godot --xr-mode off --path . res://tests/holo_shot.tscn -- out=<dir>
extends Node

const GHOST_HEAD := Vector3(0.0, 1.6, 0.6)


func _ready() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	for i in 30:
		await get_tree().process_frame
	NoteManager.clear_all()
	for n in get_tree().root.find_children("*", "", true, false):
		if n is Control and n.get_script() != null and str(n.get_script().resource_path).ends_with("identity_card.gd"):
			n.visible = false

	# A 3 s holonote: standing, looking ahead, right hand raised and pointing, left hand low.
	var m := HoloMotion.new()
	for f in 91:
		var k := f / 30.0
		var sway := sin(k * 2.0) * 0.03
		var head := Transform3D(Basis.from_euler(Vector3(-0.12, 0.25 + sway, 0.0)), GHOST_HEAD + Vector3(sway, 0, 0))
		var rb := Basis.from_euler(Vector3(0.25, 0.15 + sway, 0.0))
		var right := Transform3D(rb, GHOST_HEAD + Vector3(0.24, -0.22, -0.42))
		var left := Transform3D(Basis.from_euler(Vector3(-0.9, -0.2, 0.0)), GHOST_HEAD + Vector3(-0.22, -0.68, -0.12))
		m.add_frame({"head": head, "left": left, "right": right})
	var note := NoteData.make_new()
	note.author = "Guest"
	note.role = NoteData.Role.ARCHITECT
	note.type = NoteData.Type.PROPOSAL
	note.text = "Move this rack so the hatch path stays 0.8 m wide."
	note.anchor_name = "External hatch"
	note.position = GHOST_HEAD + Vector3(0, -0.3, -1.5)

	var p := NoteManager._ensure_holo_player()
	var spot := p.viewer_spot(m)
	NoteManager.teleport_requested.emit(spot[0], spot[1])
	for i in 5:
		await get_tree().physics_frame
	p.play(note, m)
	await get_tree().create_timer(1.0).timeout
	_save(get_viewport().get_texture().get_image(), out.path_join("holo_ghost.png"))
	p.stop()

	# Pose check in open ground: right arm points straight ahead (-Z), left hand low and forward.
	var g := Vector3(0.0, 1.62, -14.0)
	var m2 := HoloMotion.new()
	for f in 31:
		m2.add_frame({
			"head": Transform3D(Basis.IDENTITY, g),
			"right": Transform3D(Basis.IDENTITY, g + Vector3(0.22, -0.25, -0.5)),
			"left": Transform3D(Basis.from_euler(Vector3(-0.8, 0, 0)), g + Vector3(-0.25, -0.75, -0.2)),
		})
	for view in [["side", Vector3(2.4, 0.0, -0.2), PI * 0.5], ["front", Vector3(1.4, 0.0, -2.2), PI * 0.82]]:
		NoteManager.teleport_requested.emit(g + view[1], Vector3(0.0, view[2], 0.0))
		for i in 5:
			await get_tree().physics_frame
		var pl: Node3D = main.get_node_or_null("DesktopPlayer")
		if pl != null:
			pl.global_position = g + view[1] - Vector3(0, 1.6, 0)
			pl.rotation.y = view[2]
		p.play(note, m2)
		await get_tree().create_timer(0.6).timeout
		_save(get_viewport().get_texture().get_image(), out.path_join("holo_pose_%s.png" % view[0]))
		p.stop()

	# Wrist board: note view with the holonote player.
	note.holo_file = "holo_shot/holo.json"
	NoteManager._holo_cache[note.holo_file] = m
	NoteManager.add_note(note)
	var vp := SubViewport.new()
	vp.size = Vector2i(560, 760)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bg)
	var panel: Control = load("res://addons/sticky_notes/ui/vr_panel.gd").new()
	vp.add_child(panel)
	await get_tree().process_frame
	panel.show_note(note)
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save(vp.get_texture().get_image(), out.path_join("holo_board.png"))
	NoteManager.clear_all()
	get_tree().quit()


func _save(img: Image, path: String) -> void:
	print("SHOT|", path, " ", img.save_png(path) == OK)

## Notes still work after the pipeline changes: desktop placer puts a note on a wall, the
## sticky note instance appears, and the VR board panel builds all three tabs without errors.
##   Godot --headless --xr-mode off --path . res://tests/notes_smoke.tscn --quit-after 900
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
	NoteManager.clear_all()
	var player: CharacterBody3D = main.get_node_or_null("DesktopPlayer")
	var placer: Node = player.get_node("Camera3D/NotePlacer") if player != null else null
	_check(placer != null, "desktop NotePlacer present")
	# Look at the tower wall from the centre of L1 and place a note where the ray hits.
	player.global_position = Vector3(0.0, 0.05, 0.0)
	player.rotation.y = 0.0
	player.get_node("Camera3D").rotation.x = 0.0
	await get_tree().physics_frame
	var hit: Dictionary = placer._raycast()
	_check(not hit.is_empty(), "ray from the player hits habitat geometry (%s)" % str(hit.get("anchor", hit.get("collider", "?"))))
	var before := NoteManager.notes.size()
	if not hit.is_empty():
		await placer._place(hit)          # opens the editor with a screenshot
		await get_tree().process_frame
	_check(placer._panel.visible and placer._panel.note != null, "placer opened the editor for the new note")
	placer._panel._text.text = "smoke test note"
	placer._panel._on_save_note_pressed()
	await get_tree().process_frame
	_check(NoteManager.notes.size() == before + 1, "note saved from the editor (%d -> %d)" % [before, NoteManager.notes.size()])
	var root: Node = NoteManager._get_notes_root()
	_check(root != null and root.get_child_count() >= 1, "sticky note instance spawned in the scene")
	var n: NoteData = NoteManager.notes.values()[0] if not NoteManager.notes.is_empty() else null
	_check(n != null and n.anchor_name != "", "note has an anchor name (%s)" % (n.anchor_name if n else "-"))
	_check(n != null and n.zone_id != "", "note got a zone from the default session (%s)" % (n.zone_id if n else "-"))
	# VR board panel: build every tab.
	var VRPanelScript := load("res://addons/sticky_notes/ui/vr_panel.gd")
	var panel: Control = VRPanelScript.new()
	main.add_child(panel)
	await get_tree().process_frame
	var ok := true
	for t in 3:
		panel.open_tab(t)
		await get_tree().process_frame
		ok = ok and panel.visible
	_check(ok, "VR panel builds Note / List / Session tabs")
	# Desktop side panel too.
	placer._panel.open_tab(1)
	await get_tree().process_frame
	_check(placer._panel.visible, "desktop panel opens the List tab")
	NoteManager.clear_all()
	print("TEST|DONE  failures=%d" % _fails)
	get_tree().quit(_fails)

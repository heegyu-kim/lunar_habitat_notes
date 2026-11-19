## Bakes the habitat's lighting into lightmaps for the standalone Quest build.
##
## The Quest's Mobile renderer has no SDFGI / SSAO / SSIL, so the indirect light and the shadows of
## the interior lights are baked once on the PC (LunarHabitat/BakedLighting node of main.tscn, data in
## res://main.lmbake).
##
## In the editor:   Project > Tools > Bake habitat lightmaps (Quest)
##                  (the same as selecting the LightmapGI node and pressing "Bake Lightmaps")
## Unattended:      set QUEST_BAKE=1, then start  Godot --editor --path <project>
##                  The editor opens main.tscn, bakes, saves the scene and quits.
##
## Re-bake after the model or the lights change (tools/export_habitat_glb.py, InteriorLights).
@tool
extends EditorPlugin

const SCENE := "res://main.tscn"
const LIGHTMAP_NODE := "LunarHabitat/BakedLighting"
const DATA_PATH := "res://main.lmbake"
const MENU := "Bake habitat lightmaps (Quest)"


func _enter_tree() -> void:
	add_tool_menu_item(MENU, _bake.bind(false))
	if OS.get_environment("QUEST_BAKE") == "1":
		_bake.call_deferred(true)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU)


func _bake(unattended: bool) -> void:
	var ok := await _run(unattended)
	print("QUESTBAKE|%s" % ("DONE" if ok else "FAILED"))
	if unattended:
		EditorInterface.get_base_control().get_tree().quit(0 if ok else 1)


func _run(unattended: bool) -> bool:
	# The first start of a project imports its files; wait for that.
	var fs := EditorInterface.get_resource_filesystem()
	for i in 40:
		await get_tree().process_frame
	while fs.is_scanning():
		await get_tree().process_frame

	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != SCENE:
		EditorInterface.open_scene_from_path(SCENE)
		for i in 60:
			await get_tree().process_frame
		root = EditorInterface.get_edited_scene_root()
	if root == null:
		push_error("QUESTBAKE|could not open %s" % SCENE)
		return false
	var lm := root.get_node_or_null(LIGHTMAP_NODE) as LightmapGI
	if lm == null:
		push_error("QUESTBAKE|no %s node in %s" % [LIGHTMAP_NODE, SCENE])
		return false

	# With a saved LightmapGIData the editor bakes straight to that file, without a file dialog.
	if lm.light_data == null or not lm.light_data.resource_path.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DATA_PATH.get_base_dir()))
		var err := ResourceSaver.save(LightmapGIData.new(), DATA_PATH)
		if err != OK:
			push_error("QUESTBAKE|cannot create %s (%d)" % [DATA_PATH, err])
			return false
		lm.light_data = ResourceLoader.load(DATA_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)
	# The editor must know the folder before the bake writes its texture there, or the reimport fails.
	fs.scan()
	await get_tree().process_frame
	while fs.is_scanning():
		await get_tree().process_frame

	EditorInterface.set_main_screen_editor("3D")
	var sel := EditorInterface.get_selection()
	sel.clear()
	sel.add_node(lm)
	EditorInterface.edit_node(lm)
	for i in 20:
		await get_tree().process_frame

	var button := _find_bake_button(EditorInterface.get_base_control())
	if button == null:
		push_error("QUESTBAKE|the editor's Bake Lightmaps button was not found. Select the LightmapGI node and press it by hand.")
		return false
	print("QUESTBAKE|baking, this takes a few minutes...")
	var t0 := Time.get_ticks_msec()
	button.pressed.emit()          # blocks until the bake is finished
	for i in 10:
		await get_tree().process_frame
	var data := lm.light_data
	var users := data.get_user_count() if data != null else 0
	print("QUESTBAKE|bake took %.0f s, %d lightmapped meshes" % [(Time.get_ticks_msec() - t0) / 1000.0, users])
	if users == 0:
		push_error("QUESTBAKE|nothing was baked, see the editor's output")
		return false
	var err2 := EditorInterface.save_scene()
	if unattended:
		for i in 30:
			await get_tree().process_frame
	return err2 == OK


## The button belongs to the editor's own LightmapGI plugin; it has no script API, so it is found
## by what its "pressed" signal is connected to.
func _find_bake_button(node: Node) -> Button:
	if node is Button:
		for c in node.get_signal_connection_list("pressed"):
			var target: Object = (c["callable"] as Callable).get_object()
			if target != null and target.get_class() == "LightmapGIEditorPlugin":
				return node as Button
	for child in node.get_children():
		var found := _find_bake_button(child)
		if found != null:
			return found
	return null

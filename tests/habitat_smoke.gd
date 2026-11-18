## Checks the built-in habitat after a new export from Blender (tools/export_habitat_glb.py):
## every mesh has collision, the three decks are found, the ladder landings are free to stand on,
## the minimap landmarks still exist. Run headless:
##   Godot --headless --xr-mode off --path . res://tests/habitat_smoke.tscn --quit-after 900
## With a window and "-- out=<dir>" it also saves screenshots of every deck:
##   Godot --xr-mode off --path . --resolution 1280x720 res://tests/habitat_smoke.tscn --quit-after 2000 -- out=C:/tmp/shots
extends Node

var _fails := 0


func _check(cond: bool, what: String) -> void:
	if cond:
		print("TEST|PASS  " + what)
	else:
		_fails += 1
		print("TEST|FAIL  " + what)


func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	for i in 12:
		await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_run.call_deferred(main)


func _run(main: Node) -> void:
	var hab := main.get_node_or_null("LunarHabitat") as Node3D
	_check(hab != null and hab.visible, "LunarHabitat is in the scene and visible")
	if hab == null:
		get_tree().quit(1)
		return

	# 1. every mesh has a collision body
	var meshes := hab.find_children("*", "MeshInstance3D", true, false)
	var tris := 0
	var without: Array[String] = []
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var bb := mi.global_transform * mi.get_aabb()
		lo = lo.min(bb.position)
		hi = hi.max(bb.end)
		if mi.get_node_or_null(str(mi.name) + "_col") == null:
			without.append(str(mi.name))
	print("TEST|INFO  %d meshes, %d triangles, bounds %s .. %s" % [meshes.size(), tris, str(lo.snapped(Vector3.ONE * 0.01)), str(hi.snapped(Vector3.ONE * 0.01))])
	_check(meshes.size() > 100, "model has meshes (%d)" % meshes.size())
	_check(without.is_empty(), "every mesh has a collision body (%d without: %s)" % [without.size(), ", ".join(without.slice(0, 12))])
	_check(lo.y > -1.0, "nothing hangs below the ground (min y = %.2f)" % lo.y)

	# 2. floors
	var floors: Array = NoteManager.floors_sorted()
	print("TEST|INFO  floors: " + str(floors.map(func(f: Dictionary) -> String: return "%s %.2f" % [f["name"], float(f["y"])])))
	_check(floors.size() == 3, "three decks found (%d)" % floors.size())

	# 3. landings: a standing capsule there touches nothing but the floor
	var space := (main as Node3D).get_world_3d().direct_space_state
	var lands: Array[Vector3] = NoteManager.floor_landings()
	for l in lands:
		var down := PhysicsRayQueryParameters3D.create(l + Vector3(0, 1.0, 0), l + Vector3(0, -0.5, 0))
		var hit := space.intersect_ray(down)
		_check(not hit.is_empty() and absf((hit["position"] as Vector3).y - l.y) < 0.12, "landing %s stands on a floor" % str(l))
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.5
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis(), l + Vector3(0, 0.95, 0))
		var names: Array[String] = []
		for r in space.intersect_shape(q, 8):
			var body := r["collider"] as Node
			if body.is_in_group("habitat_surface"):      # furniture and walls; the player itself does not count
				names.append(str(body.name))
		_check(names.is_empty(), "landing %s is free to stand on %s" % [str(l), str(names)])

	# 4. minimap landmarks
	var by_name := {}
	for n in hab.find_children("*", "Node3D", true, false):
		by_name[str(n.name)] = n
	var mm := main.get_node_or_null("XROrigin3D/XRMinimap")
	if mm != null:
		var marks: Variant = mm.get_script().get_script_constant_map().get("LANDMARKS", [])
		for deck: Array in marks:
			for spec: Array in deck:
				var node := by_name.get(spec[0]) as Node3D
				var n_mesh := 0
				if node != null:
					n_mesh = node.find_children("*", "MeshInstance3D", true, false).size() + (1 if node is MeshInstance3D else 0)
				_check(n_mesh > 0, "minimap landmark '%s' has geometry (%d meshes)" % [spec[0], n_mesh])

	# 5. zones and noise of the default session
	print("TEST|INFO  zones=%d sources=%d warnings=%s" % [NoteManager.zones_sorted().size(), NoteManager.noise_sources_sorted().size(), str(NoteManager.noise_warnings())])
	for z in NoteManager.zones_sorted():
		var c: Vector3 = NoteManager.zone_center(z)
		_check(NoteManager.zone_id_at(c + Vector3(0, 1.0, 0)) == str(z["id"]), "zone '%s' found at its centre %s" % [z["name"], str(c.snapped(Vector3.ONE * 0.01))])

	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="):
			out = a.substr(4)
		elif a == "names":
			for n in hab.get_children():
				print("TEST|NODE  " + str(n.name) + "  " + n.get_class())
	if out != "" and DisplayServer.get_name() != "headless":
		await _shots(main, out)
	print("TEST|DONE fails=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _shots(main: Node, dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for n in get_tree().root.find_children("*", "", true, false):
		var sc: Variant = n.get_script()
		if sc != null and sc is Script and (sc as Script).get_global_name() == &"IdentityCard":
			n.visible = false
	var cam := Camera3D.new()
	cam.fov = 85
	cam.near = 0.03
	cam.far = 6000.0
	main.add_child(cam)
	cam.make_current()
	var shots := {
		"l1_from_ladder_north": [Vector3(0.0, 1.6, 1.6), Vector3(0.0, 1.2, -2.0)],
		"l1_airlock": [Vector3(0.0, 1.6, -1.2), Vector3(-1.2, 1.1, -1.6)],
		"l1_west": [Vector3(0.9, 1.6, 0.6), Vector3(-2.0, 1.0, 0.2)],
		"l1_southeast": [Vector3(-0.8, 1.6, 0.0), Vector3(1.5, 1.0, 1.6)],
		"l2_north": [Vector3(0.0, 4.2, 1.6), Vector3(0.0, 3.6, -2.0)],
		"l2_west_shower": [Vector3(0.0, 4.2, 1.5), Vector3(-1.6, 3.6, 0.3)],
		"l2_east_toilet": [Vector3(0.0, 4.2, 1.5), Vector3(1.6, 3.6, 0.3)],
		"l2_exercise": [Vector3(0.6, 4.2, -0.4), Vector3(-1.6, 3.4, -1.0)],
		"l3_north_beds": [Vector3(-0.6, 6.8, 1.4), Vector3(0.9, 6.0, -1.8)],
		"l3_medical": [Vector3(1.0, 6.8, 0.6), Vector3(-1.8, 6.1, -1.0)],
		"l3_wardroom": [Vector3(1.2, 6.8, -0.4), Vector3(-1.8, 6.0, 1.8)],
		"l3_labs": [Vector3(-1.2, 6.8, -0.2), Vector3(2.4, 6.2, 0.8)],
		"top_l1": [Vector3(0.0, 2.25, 0.0), Vector3(0.0, 0.0, -0.01)],
		"top_l2": [Vector3(0.0, 4.85, 0.0), Vector3(0.0, 2.6, -0.01)],
		"top_l3": [Vector3(0.0, 7.6, 0.0), Vector3(0.0, 5.2, -0.01)],
		"outside": [Vector3(9.0, 4.5, 9.0), Vector3(0.0, 3.5, 0.0)],
		"ext_ground_east": [Vector3(16.0, 1.6, 6.0), Vector3(0.0, 3.0, 0.0)],
		"ext_earth": [Vector3(10.0, 1.6, -2.0), Vector3(-141.7, 26.4, 30.0)],
		"ext_wide": [Vector3(45.0, 18.0, 40.0), Vector3(0.0, 3.0, 0.0)],
		"ext_look_east": [Vector3(0.0, 9.0, 0.0), Vector3(100.0, 0.0, 10.0)],
		"ext_look_south": [Vector3(0.0, 9.0, 0.0), Vector3(0.0, 0.0, 100.0)],
	}
	for key in shots:
		cam.global_position = shots[key][0]
		cam.look_at(shots[key][1], Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(dir.path_join(key + ".png"))
		print("TEST|SHOT " + key)

## Smoke test for the model import pipeline. Run headless:
##   Godot --headless --xr-mode off --path . res://tests/import_smoke.tscn --quit-after 600
## Builds a small two-storey box habitat as a .glb (Z-up, centimetres) with GLTFDocument,
## imports it through NoteManager, checks placement + collision + session v2 round trip.
extends Node

var _fails := 0
const SF := preload("res://addons/sticky_notes/space/space_floors.gd")


func _ready() -> void:
	# current_scene must be a direct child of the root, so the main scene goes next to this node.
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	await get_tree().process_frame
	await get_tree().process_frame
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		print("TEST|PASS  " + what)
	else:
		_fails += 1
		print("TEST|FAIL  " + what)


func _run() -> void:
	# 1. Build a test glb: two 6 x 4 m slabs 3 m apart, walls, authored in Z-up centimetres.
	var src := _build_test_glb()
	_check(src != "", "test glb written " + src)

	# 2. Import + load (Z-up, cm) and check placement.
	var file := NoteManager.import_model_file(src)
	_check(file == "zup_house.glb", "copied into models dir: " + file)
	var ok := NoteManager.load_model(file, {"unit": "cm", "up_axis": "Z"})
	_check(ok, "load_model ok: " + NoteManager.model_status)
	var b := NoteManager.model_bounds()
	_check(absf(b.position.y) < 0.01, "floor aligned to y=0 (min y = %.3f)" % b.position.y)
	_check(absf(b.size.y - 6.0) < 0.05, "height converted cm->m and Z-up->Y-up (%.2f m, expect 6)" % b.size.y)
	_check(absf(b.size.x - 6.0) < 0.05 and absf(b.size.z - 4.0) < 0.05, "footprint 6 x 4 m (%.2f x %.2f)" % [b.size.x, b.size.z])
	_check(absf(b.position.x + 3.0) < 0.05, "centred on origin (min x = %.2f)" % b.position.x)

	var hab := get_tree().current_scene.get_node_or_null("LunarHabitat")
	_check(hab != null and not hab.visible, "built-in habitat hidden")
	var layer_sum := 0
	for body in hab.find_children("*", "StaticBody3D", true, false):
		layer_sum += (body as StaticBody3D).collision_layer
	_check(layer_sum == 0, "built-in habitat collision disabled")

	# 3. Collision: a ray straight down from above the upper slab must hit the imported model.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var scene3d := get_tree().current_scene as Node3D
	var space: PhysicsDirectSpaceState3D = scene3d.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 10, 0), Vector3(0, -1, 0))
	var hit: Dictionary = space.intersect_ray(q)
	_check(not hit.is_empty(), "ray hits imported model")
	if not hit.is_empty():
		_check(absf(hit.position.y - 3.1) < 0.05, "upper slab top at y=3.1 (hit y=%.2f)" % hit.position.y)
		var col: Node = hit.collider
		_check(col.is_in_group("habitat_surface") or col.is_in_group("habitat_floor"), "hit body is a generated surface/floor body (%s)" % col.name)

	# 4. Session v2 round trip.
	var n := NoteData.make_new()
	n.text = "test note"
	n.position = Vector3(1, 3.1, 1)
	n.anchor_name = "slab"
	NoteManager.add_note(n)
	var path := NoteManager.save_session("import_smoke_test")
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	_check(int(parsed.get("version", 0)) == 2, "session version 2")
	_check(str(parsed.get("model", {}).get("file", "")) == "zup_house.glb", "session stores model file")
	_check(str(parsed.get("model", {}).get("unit", "")) == "cm" and str(parsed.get("model", {}).get("up_axis", "")) == "Z", "session stores unit + up axis")
	_check(parsed.has("floors") and parsed.has("zones") and parsed.has("noise_sources"), "session has floors/zones/noise_sources")

	NoteManager.unload_model()
	_check(hab.visible and not NoteManager.has_model(), "unload shows built-in habitat")
	var count := NoteManager.load_session(path, true)
	_check(count == 1, "session reloads 1 note")
	_check(NoteManager.has_model() and str(NoteManager.space["model"].get("file", "")) == "zup_house.glb", "session reload re-imports the model")
	_check(not hab.visible, "built-in hidden again after session load")

	# 4b. Floors on the imported box house: two slab tops at 0.1 and 3.1 m.
	var fs: Array = NoteManager.floors_sorted()
	_check(fs.size() == 2, "box house: 2 floors found (%d)" % fs.size())
	if fs.size() == 2:
		_check(absf(float(fs[0]["y"]) - 0.1) < 0.1 and absf(float(fs[1]["y"]) - 3.1) < 0.1, "box house floors at 0.1 / 3.1 m (%.2f / %.2f)" % [float(fs[0]["y"]), float(fs[1]["y"])])
		var mask: Dictionary = NoteManager.floor_masks[str(fs[1]["id"])]
		var filled: int = SF.mask_filled_count(mask)
		var expect := int(6.0 * 4.0 / (0.1 * 0.1))
		_check(absf(filled - expect) < expect * 0.1, "upper floor mask ~%d cells (%d)" % [expect, filled])
		var lands: Array[Vector3] = NoteManager.floor_landings()
		_check(SF.mask_contains(mask, lands[1].x, lands[1].z), "default landing lies on the floor mask")
		var bodies := get_tree().get_nodes_in_group("habitat_floor").filter(func(b: Node) -> bool: return b.name.begins_with("Floor_"))
		_check(bodies.size() == 2, "2 generated habitat_floor bodies (%d)" % bodies.size())
		# Rename + landing survive a session round trip.
		NoteManager.rename_floor(str(fs[1]["id"]), "Upper deck")
		NoteManager.set_floor_landing(str(fs[1]["id"]), Vector3(2.0, 3.1, 1.0))
		var p2 := NoteManager.save_session("import_smoke_floors")
		NoteManager.unload_model()
		NoteManager.load_session(p2, true)
		var fs2: Array = NoteManager.floors_sorted()
		_check(fs2.size() == 2 and str(fs2[1]["name"]) == "Upper deck", "floor name survives session reload")
		var l2: Array[Vector3] = NoteManager.floor_landings()
		_check(l2.size() == 2 and Vector2(l2[1].x, l2[1].z).distance_to(Vector2(2.0, 1.0)) < 0.01, "floor landing survives session reload")
		_check(NoteManager.floor_masks.has(str(fs2[1]["id"])), "masks regenerated on reload")
		DirAccess.remove_absolute(p2)

	# 4c. Zones on the box house (model is loaded again after the floors round trip).
	var zf: Array = NoteManager.floors_sorted()
	if zf.size() == 2:
		var upper := str(zf[1]["id"])
		var z: Dictionary = NoteManager.add_zone(upper, Rect2(0.0, 0.0, 3.0, 2.0), "crew_quarters")
		_check(int(z["noise_limit_db"]) == 35 and float(z["quiet"]) > 0.8, "zone takes preset defaults (%d dB)" % int(z["noise_limit_db"]))
		_check(str(z["name"]) == "Crew quarters 1", "zone auto-named (%s)" % str(z["name"]))
		var inside := NoteData.make_new()
		inside.text = "in zone"
		inside.position = Vector3(1.0, 3.2, 1.0)
		NoteManager.add_note(inside)
		var outside := NoteData.make_new()
		outside.text = "out of zone"
		outside.position = Vector3(-2.0, 3.2, -1.0)
		NoteManager.add_note(outside)
		var below := NoteData.make_new()
		below.text = "same x/z on the ground floor"
		below.position = Vector3(1.0, 0.3, 1.0)
		NoteManager.add_note(below)
		_check(inside.zone_id == str(z["id"]), "note inside the rect on that floor gets zone_id")
		_check(outside.zone_id == "", "note outside the rect has no zone")
		_check(below.zone_id == "", "note on another floor is not in the zone")
		_check(int(NoteManager.zone_note_counts().get(str(z["id"]), 0)) == 2, "zone note count = 2 (the step-4 note sits in the rect too)")
		NoteManager.update_zone(str(z["id"]), {"type": "eclss"})
		_check(int(NoteManager.zone_by_id(str(z["id"]))["noise_limit_db"]) == 80, "changing type re-applies preset (80 dB)")
		var vis := get_tree().current_scene.get_node_or_null("ZoneVisuals")
		_check(vis != null and vis.get_child_count() == 1, "zone outline drawn in the scene")
		var p3 := NoteManager.save_session("import_smoke_zones")
		NoteManager.clear_all()
		NoteManager.unload_model()
		NoteManager.load_session(p3, true)
		var zs: Array = NoteManager.zones_sorted()
		_check(zs.size() == 1 and str(zs[0]["type"]) == "eclss", "zone survives session reload")
		var n_in: NoteData = NoteManager.get_note(inside.id)
		_check(n_in != null and n_in.zone_id == str(zs[0]["id"]), "note zone_id restored on reload")
		# 4d. Noise: a fan inside the zone pushes it over 35 dB; moved to the floor below it does not.
		var zone0: Dictionary = zs[0]
		NoteManager.update_zone(str(zone0["id"]), {"type": "crew_quarters"})
		var fan: Dictionary = NoteManager.add_noise_source("fan", Vector3(1.0, 3.6, 1.0))
		_check(int(fan["db_at_1m"]) == 65 and str(fan["name"]) == "Fan 1", "noise source takes preset (%s %d dB)" % [str(fan["name"]), int(fan["db_at_1m"])])
		var zz: Dictionary = NoteManager.zone_by_id(str(zone0["id"]))
		_check(bool(zz.get("noise_over", false)) and int(zz.get("noise_db", 0)) >= 55, "zone over limit with a fan inside (%d dB)" % int(zz.get("noise_db", 0)))
		_check(NoteManager.noise_warnings().size() == 1, "one noise warning")
		NoteManager.update_noise_source(str(fan["id"]), {"position": Vector3(1.0, 0.6, 1.0)})
		zz = NoteManager.zone_by_id(str(zone0["id"]))
		_check(not bool(zz.get("noise_over", false)) and int(zz.get("noise_db", 0)) < 35, "fan on the floor below: zone under limit (%d dB)" % int(zz.get("noise_db", 0)))
		var p4 := NoteManager.save_session("import_smoke_noise")
		NoteManager.unload_model()
		NoteManager.load_session(p4, true)
		_check(NoteManager.noise_sources_sorted().size() == 1, "noise source survives session reload")
		var vis2 := get_tree().current_scene.get_node_or_null("ZoneVisuals")
		_check(vis2 != null and vis2.get_child_count() == 2, "zone + noise source drawn (%d)" % (vis2.get_child_count() if vis2 != null else -1))
		var html := NoteManager.export_report("import_smoke_report")
		var ht := FileAccess.get_file_as_string(html)
		_check(ht.find("<b>Zones</b>") >= 0, "report lists zones")
		DirAccess.remove_absolute(html)
		DirAccess.remove_absolute(p4)
		NoteManager.remove_noise_source(str(NoteManager.noise_sources_sorted()[0]["id"]))
		zs = NoteManager.zones_sorted()
		NoteManager.remove_zone(str(zs[0]["id"]))
		_check(NoteManager.get_note(inside.id).zone_id == "", "removing the zone clears zone_id")
		DirAccess.remove_absolute(p3)
		NoteManager.clear_all()

	# 5. Version 1 session (no model keys) falls back to the built-in habitat.
	var v1 := {"format": "sticky_notes", "version": 1, "notes": []}
	var p1 := NoteManager.SESSION_DIR + "import_smoke_v1.json"
	var f1 := FileAccess.open(p1, FileAccess.WRITE)
	f1.store_string(JSON.stringify(v1))
	f1.close()
	NoteManager.load_session(p1, true)
	_check(not NoteManager.has_model() and hab.visible, "v1 session shows built-in habitat")
	# Built-in habitat: three decks near 0 / 2.6 / 5.2 m, landings taken from the XR ladder.
	var bf: Array = NoteManager.floors_sorted()
	_check(bf.size() == 3, "built-in habitat: 3 floors (%d: %s)" % [bf.size(), str(bf.map(func(f: Dictionary) -> String: return "%.2f" % float(f["y"])))])
	if bf.size() == 3:
		_check(absf(float(bf[0]["y"])) < 0.2 and absf(float(bf[1]["y"]) - 2.6) < 0.2 and absf(float(bf[2]["y"]) - 5.2) < 0.2, "built-in floors at ~0 / 2.6 / 5.2 (%.2f / %.2f / %.2f)" % [float(bf[0]["y"]), float(bf[1]["y"]), float(bf[2]["y"])])
		var bl: Array[Vector3] = NoteManager.floor_landings()
		_check(bl[2].distance_to(Vector3(-0.7, float(bf[2]["y"]), 0.45)) < 0.05, "built-in landings come from XRLadder (%s)" % str(bl[2]))
		for fl in bf:
			var img: Image = SF.mask_to_image(NoteManager.floor_masks[str(fl["id"])])
			img.save_png("C:/Users/user/AppData/Local/Temp/claude/ec29f026d20d029c/5d53cc21-8bd9-4917-b371-2d2c1a0be905/scratchpad/mask_%s.png" % str(fl["name"]))

	# Clean up test artefacts (keep the user's own data).
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(p1)
	DirAccess.remove_absolute(NoteManager.MODELS_DIR + "zup_house.glb")
	DirAccess.remove_absolute(src)
	NoteManager.clear_all()
	NoteManager.unload_model()

	print("TEST|DONE  failures=%d" % _fails)
	get_tree().quit(_fails)


## Two slabs (z = 0 and z = 300 cm), four walls 600 cm tall, Z-up, centimetres.
func _build_test_glb() -> String:
	var root := Node3D.new()
	root.name = "zup_house"
	_box(root, "slab_ground", Vector3(600, 400, 10), Vector3(0, 0, 5))
	_box(root, "slab_upper", Vector3(600, 400, 10), Vector3(0, 0, 305))
	_box(root, "wall_n", Vector3(600, 10, 600), Vector3(0, 195, 300))
	_box(root, "wall_s", Vector3(600, 10, 600), Vector3(0, -195, 300))
	_box(root, "wall_e", Vector3(10, 400, 600), Vector3(295, 0, 300))
	_box(root, "wall_w", Vector3(10, 400, 600), Vector3(-295, 0, 300))
	add_child(root)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err != OK:
		return ""
	var out := ProjectSettings.globalize_path("user://zup_house.glb")
	err = doc.write_to_filesystem(state, out)
	root.queue_free()
	return out if err == OK else ""


func _box(parent: Node3D, name_: String, size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name_
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)

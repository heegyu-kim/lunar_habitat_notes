## Writes the default session for the built-in habitat (the NASA reference tower): its rooms as zones,
## its machinery as noise sources. The two berths on L3 stand next to the air-revitalisation racks, so
## the app opens with a noise warning to review. Edit ZONES / SOURCES when the model changes.
##   Godot --headless --xr-mode off --path . res://tools/build_default_session.tscn --quit-after 900
## Output: user://sticky_notes/sessions/default_base_camp.json, copied to res://assets/sessions/.
extends Node

const OUT := "res://assets/sessions/default_base_camp.json"

# Layout of the habitat exported from blender/Lunar_Surface_Habitat.blend (tools/export_habitat_glb.py).
# World axes: x east, z south (Blender Y = -z). Decks at y = 0 / 2.6 / 5.2.
# [name, floor y, type, x0, z0, x1, z1]
const ZONES := [
	# L1: airlock behind the partition (north), EVA preparation and workbench in front of it
	["EVA airlock & suit", 0.0, "airlock", -2.2, -2.3, 2.2, -0.25],
	["Workbench", 0.0, "workshop", -2.2, -0.25, -0.6, 2.2],
	["EVA station & stowage", 0.0, "logistics", 0.6, -0.25, 2.2, 2.2],
	# L2: exercise and biology either side of the air-revitalisation racks, hygiene booths south of them
	["Exercise", 2.6, "exercise", -2.4, -2.4, -0.6, -0.2],
	["Air revitalisation (L2)", 2.6, "eclss", -0.6, -2.4, 0.6, -0.3],
	["Biology lab", 2.6, "lab", 0.6, -2.4, 2.4, -0.2],
	["Shower", 2.6, "hygiene", -2.4, -0.2, -0.5, 1.4],
	["Toilet (UWMS)", 2.6, "uwms", 0.5, -0.2, 2.4, 1.4],
	# L3: two berths and the medical bay on the north side, right next to the upper air-revitalisation racks
	["Medical", 5.2, "medical", -3.1, -3.1, -0.6, -0.15],
	["Crew quarters 1", 5.2, "crew_quarters", -0.6, -3.1, 0.6, -1.1],
	["Crew quarters 2", 5.2, "crew_quarters", 0.6, -3.1, 3.1, -0.5],
	["Command station", 5.2, "lab", -3.1, -0.15, -0.55, 0.9],
	["Wardroom", 5.2, "galley", -3.1, 0.9, -0.6, 3.1],
	["Galley", 5.2, "galley", -0.6, 1.9, 1.2, 3.1],
	["Physics & human research", 5.2, "lab", 1.2, -0.5, 3.1, 3.1],
]

# [name, preset, x, y, z, db (0 = preset)]
const SOURCES := [
	# The air-revitalisation racks stand in one stack north of the ladder shaft, two per deck.
	["ARS rack fans (L2)", "fan", 0.0, 3.5, -0.75, 58],
	["ARS rack fans (L3)", "fan", 0.0, 6.1, -0.75, 58],
	["Exercise bike", "exercise", -1.5, 3.2, -0.9, 0],
]


func _ready() -> void:
	var main: Node = load("res://main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	get_tree().current_scene = main
	for i in 5:
		await get_tree().process_frame
	NoteManager.clear_all()
	NoteManager.unload_model()
	NoteManager.space["zones"] = []
	NoteManager.space["noise_sources"] = []
	# Detect the decks again from the model as it is now; landings come from the XRLadder node.
	NoteManager.space["floors"] = []
	NoteManager.rebuild_floors(false)
	var floors: Array = NoteManager.floors_sorted()
	print("BUILD| floors: " + str(floors.map(func(f: Dictionary) -> String: return "%s %.2f" % [f["name"], float(f["y"])])))
	for z in ZONES:
		var fid := _floor_id_at(float(z[1]))
		if fid == "":
			push_warning("no floor for zone %s at y=%.2f" % [z[0], float(z[1])])
			continue
		NoteManager.add_zone(fid, Rect2(Vector2(z[3], z[4]), Vector2(z[5] - z[3], z[6] - z[4])), str(z[2]), str(z[0]))
	for s in SOURCES:
		NoteManager.add_noise_source(str(s[1]), Vector3(s[2], s[3], s[4]), str(s[0]), float(s[5]))
	var warns: Array[String] = NoteManager.noise_warnings()
	print("BUILD| zones=%d sources=%d warnings=%s" % [NoteManager.zones_sorted().size(), NoteManager.noise_sources_sorted().size(), str(warns)])
	var path := NoteManager.save_session("default_base_camp")
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	var err := DirAccess.copy_absolute(path, OUT)
	print("BUILD|%s %s -> %s" % ["OK" if err == OK else "FAIL", path, OUT])
	get_tree().quit(0 if err == OK else 1)


func _floor_id_at(y: float) -> String:
	for fl in NoteManager.floors_sorted():
		if absf(float(fl["y"]) - y) < 0.4:
			return str(fl["id"])
	return ""

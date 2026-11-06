## Writes the default session for the built-in habitat (the NASA reference tower): its rooms as zones,
## its machinery as noise sources, and (on purpose) the two crew quarters next to the air-revitalisation
## fans, so the app opens with a noise warning to review. Edit ZONES / SOURCES when the model changes.
##   Godot --headless --xr-mode off --path . res://tools/build_default_session.tscn --quit-after 900
## Output: user://sticky_notes/sessions/default_base_camp.json, copied to res://assets/sessions/.
extends Node

const OUT := "res://assets/sessions/default_base_camp.json"

# [name, floor y, type, x0, z0, x1, z1]
const ZONES := [
	# NASA reference tower only (the base-camp blockout is a layout reference, not in the scene)
	["Suitport airlock (core)", 0.0, "airlock", -3.2, -3.2, 0.0, 3.2],
	["Workbench & geology (core)", 0.0, "workshop", 0.0, -3.2, 3.2, 3.2],
	["Hygiene & UWMS (core)", 2.6, "hygiene", -3.2, -3.2, 0.0, 0.0],
	["Exercise (core)", 2.6, "exercise", 0.0, -3.2, 3.2, 0.0],
	["Biology lab (core)", 2.6, "lab", 0.0, 0.0, 3.2, 3.2],
	["Water processing (core)", 2.6, "eclss", -3.2, 0.0, 0.0, 3.2],
	["Crew quarters core 1", 5.2, "crew_quarters", -3.2, -3.2, -0.3, -0.2],
	["Crew quarters core 2", 5.2, "crew_quarters", -3.2, 0.2, -0.3, 3.2],
	["Wardroom & galley (core)", 5.2, "galley", 0.3, -3.2, 3.2, 0.2],
	["Medical (core)", 5.2, "medical", 0.3, 0.2, 3.2, 3.2],
]

# [name, preset, x, y, z, db (0 = preset)]
const SOURCES := [
	# Three air-revitalisation pallets in the tower's core column, a wall away from the crew quarters.
	["ARS fan 1 (core)", "fan", 0.0, 5.6, 0.0, 58],
	["ARS fan 2 (core)", "fan", 0.2, 5.6, -0.25, 58],
	["ARS fan 3 (core)", "fan", -0.2, 5.6, 0.25, 58],
	["WPA pump 1 (core)", "pump", -1.2, 3.0, 1.2, 0],
	["WPA pump 2 (core)", "pump", -1.8, 3.0, 0.6, 0],
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

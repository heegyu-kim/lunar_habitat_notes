## Writes the default session for the built-in base camp: every zone type at least once, the
## noise sources of the machinery, and (on purpose) the NASA reference tower's two crew quarters
## next to the air-revitalisation fans, so the app opens with a noise warning to review.
##   Godot --headless --xr-mode off --path . res://tools/build_default_session.tscn --quit-after 900
## Output: user://sticky_notes/sessions/default_base_camp.json, copied to res://assets/sessions/.
extends Node

const OUT := "res://assets/sessions/default_base_camp.json"

# [name, floor y, type, x0, z0, x1, z1]
const ZONES := [
	# A core tower (NASA reference): L1 / L2 / L3
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
	# D hub and tunnels
	["Node hub", 0.0, "corridor", -9.5, -2.0, -5.5, 2.0],
	["Tunnel A-D", 0.0, "corridor", -5.5, -0.8, -3.3, 0.8],
	["Tunnel D-C", 0.0, "corridor", -11.3, -0.8, -9.5, 0.8],
	["Tunnel D-B", 0.0, "corridor", -8.3, -9.8, -6.7, -2.0],
	# B engineering
	["Dust vestibule & airlock", 0.0, "airlock", -1.7, -14.0, 0.5, -10.0],
	["Suit maintenance", 0.0, "workshop", -3.9, -14.0, -1.7, -10.0],
	["ECLSS bay", 0.0, "eclss", -10.5, -14.0, -3.9, -10.0],
	["Power & thermal", 0.0, "power", -12.3, -14.0, -10.5, -10.0],
	["Workshop", 0.0, "workshop", -14.1, -14.0, -12.3, -10.0],
	["Logistics", 0.0, "logistics", -15.5, -14.0, -14.1, -10.0],
	# C habitation deck 1
	["Crew quarters A", 0.0, "crew_quarters", -14.6, 0.4, -11.5, 3.5],
	["Crew quarters B", 0.0, "crew_quarters", -18.5, 0.4, -15.4, 3.5],
	["Crew quarters C", 0.0, "crew_quarters", -18.5, -3.5, -15.4, -0.4],
	["Crew quarters D", 0.0, "crew_quarters", -14.6, -3.5, -11.5, -0.4],
	["Storm shelter", 0.0, "shelter", -16.7, -1.7, -13.3, 1.7],
	["Hygiene A", 0.0, "hygiene", -12.6, -0.4, -11.4, 0.4],
	["Hygiene B", 0.0, "hygiene", -18.6, -0.4, -17.2, 0.4],
	["Stowage (C)", 0.0, "logistics", -15.4, 1.8, -14.6, 3.5],
	["Toilet (C)", 0.0, "uwms", -15.4, -3.5, -14.6, -1.8],
	# C habitation deck 2
	["Wardroom & galley", 2.6, "galley", -18.5, -3.6, -11.5, -0.5],
	["Medical", 2.6, "medical", -13.5, -0.5, -11.4, 1.5],
	["Exercise", 2.6, "exercise", -18.6, -0.5, -16.3, 1.6],
	["Greenhouse", 2.6, "greenhouse", -16.3, 1.6, -13.5, 3.6],
]

# [name, preset, x, y, z, db (0 = preset)]
const SOURCES := [
	# Three air-revitalisation pallets in the tower's core column, a wall away from the crew quarters.
	["ARS fan 1 (core)", "fan", 0.0, 5.6, 0.0, 58],
	["ARS fan 2 (core)", "fan", 0.2, 5.6, -0.25, 58],
	["ARS fan 3 (core)", "fan", -0.2, 5.6, 0.25, 58],
	["WPA pump 1 (core)", "pump", -1.2, 3.0, 1.2, 0],
	["WPA pump 2 (core)", "pump", -1.8, 3.0, 0.6, 0],
	["ECLSS fan 1", "fan", -4.5, 1.0, -13.4, 62],
	["ECLSS fan 2", "fan", -5.3, 1.0, -13.4, 62],
	["ECLSS pump 1", "pump", -6.1, 1.0, -13.4, 0],
	["ECLSS pump 2", "pump", -6.9, 1.0, -13.4, 0],
	["ECLSS fan 3", "fan", -7.7, 1.0, -13.4, 62],
	["ECLSS pump 3", "pump", -8.5, 1.0, -13.4, 0],
	["ECLSS fan 4", "fan", -9.3, 1.0, -13.4, 62],
	["Thermal pump", "pump", -11.4, 0.6, -11.8, 0],
	["Airlock compressor", "compressor", -0.6, 1.0, -13.5, 0],
	["Workshop tools", "tools", -13.2, 1.0, -13.3, 0],
	["Exercise device (C)", "exercise", -17.6, 3.3, 0.4, 0],
	["Wardroom conversation", "talk", -15.0, 3.5, -1.6, 0],
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

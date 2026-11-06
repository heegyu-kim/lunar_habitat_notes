## Generates the base-camp blockout (modules B, C, D, tunnels and exterior props) with CSG and
## writes it to assets/models/Base_Camp/base_camp.glb. Run headless:
##   Godot --headless --xr-mode off --path . res://tools/build_base_camp.tscn --quit-after 600
## Then let the editor import it (Godot --headless --xr-mode off --path . --import).
##
## Layout (metres, x east, z south, y up). Core tower A (the NASA reference glb) sits at the origin.
##   B engineering  horizontal cylinder 16 x 4.4 m, centre (-7.5, -12), floor y = 0
##   D hub          vertical cylinder r 2, centre (-7.5, 0)
##   C habitation   vertical cylinder r 3.75, two decks (0 / 2.6), centre (-15, 0), regolith berm
##   tunnels        A-D, D-C, D-B, rover port south of D
##   exterior       fission power 700 m north behind a berm + cable, solar towers, antenna, lander, LTV
## Everything the floor detector needs is real geometry: slabs at y = 0 and y = 2.6.
extends Node

const OUT := "res://assets/models/Base_Camp/base_camp.glb"
const OUT_EXT := "res://assets/models/Base_Camp/base_camp_exterior.glb"

var mats: Dictionary = {}
var root: Node3D          # whatever the helpers currently build into
var hab_root: Node3D      # modules: goes under LunarHabitat (floor detection, notes)
var ext_root: Node3D      # berm, power plant, lander...: goes at the scene root


func _ready() -> void:
	_make_materials()
	hab_root = Node3D.new()
	hab_root.name = "BaseCamp"
	add_child(hab_root)
	ext_root = Node3D.new()
	ext_root.name = "BaseCampExterior"
	add_child(ext_root)
	root = hab_root
	_build_hub()
	_build_tunnels()
	_build_engineering()
	_build_habitation()
	root = ext_root
	_build_berm()
	_build_exterior()
	# CSG meshes are computed on idle; give them two frames before export.
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_export()


func _export() -> void:
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	for pair in [[hab_root, OUT], [ext_root, OUT_EXT]]:
		var node: Node3D = pair[0]
		var path: String = pair[1]
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var err := doc.append_from_scene(node, state)
		if err != OK:
			push_error("BaseCamp: append_from_scene failed %d" % err)
			get_tree().quit(1)
			return
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
		if err != OK:
			push_error("BaseCamp: write failed %d" % err)
			get_tree().quit(1)
			return
		var size := FileAccess.get_file_as_bytes(path).size()
		print("BUILD|OK %s  %d KB  nodes=%d" % [path, size / 1024, node.get_child_count()])
	get_tree().quit(0)


# ---------------------------------------------------------------- materials

func _mat(name_: String, albedo: Color, rough: float = 0.6, metal: float = 0.0, alpha := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = name_
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mats[name_] = m
	return m


func _make_materials() -> void:
	_mat("hull", Color(0.72, 0.73, 0.76), 0.45, 0.55)
	_mat("inflatable", Color(0.86, 0.83, 0.76), 0.9, 0.0)
	_mat("interior", Color(0.90, 0.90, 0.88), 0.8, 0.0)
	_mat("floor", Color(0.38, 0.39, 0.42), 0.7, 0.2)
	_mat("deck_edge", Color(0.95, 0.75, 0.2), 0.6, 0.0)
	_mat("equipment", Color(0.30, 0.38, 0.58), 0.5, 0.3)
	_mat("equipment_dark", Color(0.42, 0.43, 0.46), 0.55, 0.4)
	_mat("bunk", Color(0.55, 0.45, 0.35), 0.8, 0.0)
	_mat("water", Color(0.35, 0.55, 0.75), 0.4, 0.1)
	_mat("glass", Color(0.65, 0.8, 0.95, 0.35), 0.1, 0.0, true)
	_mat("regolith", Color(0.30, 0.29, 0.28), 0.95, 0.0)
	_mat("solar", Color(0.10, 0.15, 0.35), 0.3, 0.4)
	_mat("accent", Color(0.9, 0.45, 0.15), 0.6, 0.0)
	_mat("plant", Color(0.35, 0.6, 0.25), 0.8, 0.0)


# ---------------------------------------------------------------- csg helpers

func _box(parent: Node, name_: String, size: Vector3, pos: Vector3, mat: String, op := CSGShape3D.OPERATION_UNION, rot_y := 0.0) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.name = name_
	b.size = size
	b.position = pos
	b.rotation.y = rot_y
	b.operation = op
	if mat != "":
		b.material = mats[mat]
	parent.add_child(b)
	return b


func _cyl(parent: Node, name_: String, radius: float, height: float, pos: Vector3, mat: String, axis := "y", op := CSGShape3D.OPERATION_UNION, sides := 48) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.name = name_
	c.radius = radius
	c.height = height
	c.sides = sides
	c.position = pos
	if axis == "x":
		c.rotation.z = PI / 2.0
	elif axis == "z":
		c.rotation.x = PI / 2.0
	c.operation = op
	if mat != "":
		c.material = mats[mat]
	parent.add_child(c)
	return c


func _combiner(name_: String, pos: Vector3 = Vector3.ZERO) -> CSGCombiner3D:
	var c := CSGCombiner3D.new()
	c.name = name_
	c.position = pos
	root.add_child(c)
	return c


## Hollow cylinder shell with optional openings (list of [size, local pos]).
func _shell_cyl(name_: String, pos: Vector3, radius: float, height: float, thickness: float, axis: String, mat: String, openings: Array = []) -> CSGCombiner3D:
	var c := _combiner(name_, pos)
	_cyl(c, "outer", radius, height, Vector3.ZERO, mat, axis)
	_cyl(c, "inner", radius - thickness, height + 0.2, Vector3.ZERO, mat, axis, CSGShape3D.OPERATION_SUBTRACTION)
	for i in openings.size():
		var o: Array = openings[i]
		_box(c, "opening_%d" % i, o[0], o[1], "", CSGShape3D.OPERATION_SUBTRACTION, o[2] if o.size() > 2 else 0.0)
	return c


func _hatch_frame(parent: Node, name_: String, pos: Vector3, rot_y: float = 0.0) -> void:
	# A rectangular frame 1.1 x 2.1 around a 0.9 x 1.9 opening, 0.12 deep.
	var f := CSGCombiner3D.new()
	f.name = name_
	f.position = pos
	f.rotation.y = rot_y
	parent.add_child(f)
	_box(f, "ring", Vector3(1.1, 2.1, 0.12), Vector3(0, 1.05, 0), "accent")
	_box(f, "hole", Vector3(0.9, 1.9, 0.3), Vector3(0, 1.0, 0), "", CSGShape3D.OPERATION_SUBTRACTION)


func _slab(parent: Node, name_: String, size: Vector2, pos: Vector3, mat := "floor") -> void:
	_box(parent, name_, Vector3(size.x, 0.1, size.y), pos + Vector3(0, -0.05, 0), mat)


# ---------------------------------------------------------------- D hub

const HUB := Vector3(-7.5, 0, 0)


func _build_hub() -> void:
	var openings := [
		[Vector3(0.9, 1.9, 1.0), Vector3(2.0, 1.0, 0.0)],     # east -> A
		[Vector3(0.9, 1.9, 1.0), Vector3(-2.0, 1.0, 0.0)],    # west -> C
		[Vector3(1.0, 1.9, 0.9), Vector3(0.0, 1.0, -2.0)],    # north -> B
		[Vector3(1.0, 1.9, 0.9), Vector3(0.0, 1.0, 2.0)],     # south -> rover port
	]
	var hub := _shell_cyl("D_Hub", HUB + Vector3(0, 1.4, 0), 2.0, 2.8, 0.15, "y", "hull", openings)
	_cyl(root, "D_Floor", 2.0, 0.1, HUB + Vector3(0, -0.05, 0), "floor")
	_cyl(root, "D_Ceiling", 2.0, 0.1, HUB + Vector3(0, 2.85, 0), "hull")
	# Emergency wall: extinguisher, masks, pressure panel.
	_box(root, "D_PressurePanel", Vector3(0.6, 0.4, 0.08), HUB + Vector3(1.2, 1.5, 1.3), "equipment", CSGShape3D.OPERATION_UNION, -PI / 4.0)
	_box(root, "D_Extinguisher", Vector3(0.18, 0.6, 0.18), HUB + Vector3(-1.3, 0.4, 1.2), "accent")
	_box(root, "D_MaskLocker", Vector3(0.5, 0.6, 0.25), HUB + Vector3(-1.2, 1.2, -1.2), "equipment_dark", CSGShape3D.OPERATION_UNION, PI / 4.0)
	# Rover docking port: short stub to the south with a hatch frame.
	var port := _combiner("D_RoverPort", HUB + Vector3(0, 1.1, 2.6))
	_box(port, "outer", Vector3(1.6, 2.2, 1.4), Vector3.ZERO, "hull")
	_box(port, "inner", Vector3(1.4, 2.0, 1.6), Vector3.ZERO, "", CSGShape3D.OPERATION_SUBTRACTION)
	_slab(root, "D_RoverPortFloor", Vector2(1.4, 1.4), HUB + Vector3(0, 0, 2.6))
	_hatch_frame(root, "D_Hatch_Rover", HUB + Vector3(0, 0, 3.25))


# ---------------------------------------------------------------- tunnels

func _tunnel(name_: String, from: Vector3, to: Vector3) -> void:
	var d := to - from
	var len := d.length()
	var mid := (from + to) * 0.5
	var rot := atan2(d.x, d.z)
	var c := _combiner(name_, mid + Vector3(0, 1.1, 0))
	c.rotation.y = rot
	_box(c, "outer", Vector3(1.6, 2.2, len), Vector3.ZERO, "hull")
	_box(c, "inner", Vector3(1.4, 2.0, len + 0.2), Vector3.ZERO, "", CSGShape3D.OPERATION_SUBTRACTION)
	# Floor slab inside, light strip on the ceiling.
	var f := _box(root, name_ + "_Floor", Vector3(1.4, 0.1, len), mid + Vector3(0, -0.05, 0), "floor")
	f.rotation.y = rot
	var l := _box(root, name_ + "_Light", Vector3(0.2, 0.03, len - 0.4), mid + Vector3(0, 2.0, 0), "interior")
	l.rotation.y = rot
	_hatch_frame(root, name_ + "_HatchA", from + d.normalized() * 0.1, rot)
	_hatch_frame(root, name_ + "_HatchB", to - d.normalized() * 0.1, rot)


func _build_tunnels() -> void:
	_tunnel("T_A_D", Vector3(-3.3, 0, 0), Vector3(-5.5, 0, 0))     # core tower -> hub
	_tunnel("T_D_C", Vector3(-9.5, 0, 0), Vector3(-11.3, 0, 0))    # hub -> habitation
	_tunnel("T_D_B", Vector3(-7.5, 0, -2.0), Vector3(-7.5, 0, -9.8))  # hub -> engineering


# ---------------------------------------------------------------- B engineering

const B_CENTER := Vector3(-7.5, 1.45, -12.0)
const B_LEN := 16.0
const B_R := 2.2
# Compartments east -> west: airlock, suit maintenance, ECLSS, power & thermal, workshop, logistics.
const B_SPLITS := [0.5, -1.7, -3.9, -10.5, -12.3, -14.1, -15.5]


func _build_engineering() -> void:
	var openings := [
		[Vector3(1.0, 1.9, 1.0), Vector3(0.0, -0.45, 2.2)],          # south wall at x = -7.5 -> tunnel from hub (local: centre is -7.5)
		[Vector3(1.0, 1.9, 1.2), Vector3(B_LEN / 2.0, -0.45, 0.0)],  # east end cap: EVA hatch
		[Vector3(1.2, 0.5, 1.0), Vector3(-5.5, 0.9, -2.2)],          # north wall: window in ECLSS bay
	]
	_shell_cyl("B_Engineering", B_CENTER, B_R, B_LEN, 0.15, "x", "hull", openings)
	_slab(root, "B_Floor", Vector2(B_LEN, 3.8), Vector3(B_CENTER.x, 0, B_CENTER.z))
	_box(root, "B_FloorEdgeN", Vector3(B_LEN, 0.12, 0.08), Vector3(B_CENTER.x, 0.06, B_CENTER.z - 1.9), "deck_edge")
	_box(root, "B_FloorEdgeS", Vector3(B_LEN, 0.12, 0.08), Vector3(B_CENTER.x, 0.06, B_CENTER.z + 1.9), "deck_edge")
	_box(root, "B_CableTray", Vector3(B_LEN - 0.4, 0.08, 0.3), Vector3(B_CENTER.x, 3.0, B_CENTER.z + 0.9), "equipment_dark")
	_box(root, "B_LightLine", Vector3(B_LEN - 0.4, 0.03, 0.2), Vector3(B_CENTER.x, 3.35, B_CENTER.z), "interior")
	# Partitions with a door opening; the ECLSS/power one is a full bulkhead with a hatch frame.
	for i in range(1, B_SPLITS.size() - 1):
		var x: float = B_SPLITS[i]
		var w := _combiner("B_Partition_%d" % i, Vector3(x, 1.2, B_CENTER.z))
		_box(w, "wall", Vector3(0.08, 2.4, 3.8), Vector3.ZERO, "interior")
		_box(w, "door", Vector3(0.3, 2.0, 0.9), Vector3(0, -0.2, 0.8), "", CSGShape3D.OPERATION_SUBTRACTION)
		if i == 3:
			_hatch_frame(root, "B_Hatch_Bulkhead", Vector3(x, 0, B_CENTER.z + 0.8), PI / 2.0)
	_hatch_frame(root, "B_Hatch_Tunnel", Vector3(-7.5, 0, B_CENTER.z + 2.2))
	_hatch_frame(root, "B_Hatch_EVA", Vector3(B_SPLITS[0] - 0.05, 0, B_CENTER.z), PI / 2.0)
	# B1 airlock / dust vestibule: suit stands, floor grille, air-shower nozzles.
	var b1 := (B_SPLITS[0] + B_SPLITS[1]) * 0.5
	for k in 4:
		_box(root, "B1_SuitStand_%d" % k, Vector3(0.45, 1.9, 0.35), Vector3(b1 - 0.6 + k * 0.4, 0.95, B_CENTER.z - 1.55), "equipment_dark")
	_box(root, "B1_FloorGrille", Vector3(2.0, 0.02, 3.4), Vector3(b1, 0.01, B_CENTER.z), "equipment_dark")
	_box(root, "B1_AirShower", Vector3(1.8, 0.12, 0.3), Vector3(b1, 2.9, B_CENTER.z + 1.2), "accent")
	# B2 suit maintenance: bench, parts shelf, charging rack.
	var b2 := (B_SPLITS[1] + B_SPLITS[2]) * 0.5
	_box(root, "B2_SuitBench", Vector3(1.8, 0.9, 0.7), Vector3(b2, 0.45, B_CENTER.z - 1.4), "equipment")
	_box(root, "B2_PartsShelf", Vector3(1.8, 1.6, 0.35), Vector3(b2, 1.6, B_CENTER.z - 1.6), "equipment_dark")
	_box(root, "B2_ChargeRack", Vector3(0.8, 1.8, 0.5), Vector3(b2 + 0.5, 0.9, B_CENTER.z + 1.5), "equipment")
	# B3 ECLSS bay: 8 Collins-style pallets standing in a row along the north wall, 1 m aisle in front.
	var x0: float = B_SPLITS[2] - 0.55
	for k in 8:
		var p := _box(root, "B3_Pallet_%02d" % (k + 1), Vector3(0.74, 1.83, 0.74), Vector3(x0 - k * 0.8, 0.915, B_CENTER.z - 1.45), "equipment")
		_box(root, "B3_Pallet_%02d_Panel" % (k + 1), Vector3(0.6, 1.5, 0.03), p.position + Vector3(0, 0.05, 0.38), "equipment_dark")
		_box(root, "B3_Pallet_%02d_Lamp" % (k + 1), Vector3(0.06, 0.06, 0.03), p.position + Vector3(0.25, 0.85, 0.39), "accent")
	_box(root, "B3_O2Tanks", Vector3(3.0, 0.9, 0.6), Vector3(B_SPLITS[2] - 3.3, 0.45, B_CENTER.z + 1.5), "equipment_dark")
	_box(root, "B3_Duct", Vector3(6.4, 0.35, 0.35), Vector3((B_SPLITS[2] + B_SPLITS[3]) * 0.5, 2.6, B_CENTER.z - 1.3), "equipment_dark")
	# B4 power & thermal: distribution cabinet, battery rack, pump package, status wall.
	var b4 := (B_SPLITS[3] + B_SPLITS[4]) * 0.5
	_box(root, "B4_PowerCabinet", Vector3(1.0, 2.0, 0.6), Vector3(b4, 1.0, B_CENTER.z - 1.45), "equipment")
	_box(root, "B4_BatteryRack", Vector3(1.4, 1.2, 0.6), Vector3(b4, 0.6, B_CENTER.z + 1.45), "equipment_dark")
	_box(root, "B4_PumpPackage", Vector3(0.6, 0.8, 0.8), Vector3(b4 + 0.5, 0.4, B_CENTER.z + 0.2), "equipment_dark")
	_box(root, "B4_StatusWall", Vector3(0.9, 0.5, 0.04), Vector3(b4, 1.9, B_CENTER.z + 1.72), "accent")
	# B5 workshop: bench, 3D printer, drawers.
	var b5 := (B_SPLITS[4] + B_SPLITS[5]) * 0.5
	_box(root, "B5_Workbench", Vector3(1.6, 0.9, 0.8), Vector3(b5, 0.45, B_CENTER.z - 1.3), "equipment_dark")
	_box(root, "B5_Printer", Vector3(0.7, 0.8, 0.7), Vector3(b5 - 0.3, 1.3, B_CENTER.z - 1.3), "equipment")
	_box(root, "B5_Drawers", Vector3(1.4, 1.0, 0.5), Vector3(b5, 0.5, B_CENTER.z + 1.5), "equipment_dark")
	# B6 logistics: CTB racks, two freezers.
	var b6 := (B_SPLITS[5] + B_SPLITS[6]) * 0.5
	_box(root, "B6_CTBRack", Vector3(1.0, 2.2, 0.7), Vector3(b6, 1.1, B_CENTER.z - 1.4), "equipment_dark")
	_box(root, "B6_Freezers", Vector3(1.0, 1.5, 0.7), Vector3(b6, 0.75, B_CENTER.z + 1.4), "equipment")
	# Roof: radiator panels and the cable entry.
	for k in 3:
		_box(root, "B_Radiator_%d" % k, Vector3(3.0, 1.6, 0.06), Vector3(B_CENTER.x - 4.0 + k * 4.0, B_R + 1.45 + 0.8, B_CENTER.z), "hull")
	_box(root, "B_CableEntry", Vector3(0.5, 0.6, 0.5), Vector3(b4, B_R + 1.45 + 0.3, B_CENTER.z - 0.8), "equipment_dark")


# ---------------------------------------------------------------- C habitation

const C_CENTER := Vector3(-15.0, 0, 0)
const C_R := 3.75
const C_H := 5.8
const C_DECK2 := 2.6


func _build_habitation() -> void:
	var openings := [
		[Vector3(1.0, 1.9, 0.9), Vector3(C_R, 1.0 - C_H / 2.0, 0.0)],               # east hatch -> hub tunnel
		[Vector3(0.9, 0.7, 1.0), Vector3(0.0, C_DECK2 + 1.4 - C_H / 2.0, -C_R)],   # north window (Earth)
		[Vector3(1.0, 0.7, 0.9), Vector3(-C_R, C_DECK2 + 1.4 - C_H / 2.0, 0.6)],   # west window
	]
	_shell_cyl("C_Habitation", C_CENTER + Vector3(0, C_H / 2.0, 0), C_R, C_H, 0.15, "y", "inflatable", openings)
	# Dome cap.
	var cap := CSGSphere3D.new()
	cap.name = "C_Dome"
	cap.radius = C_R
	cap.radial_segments = 48
	cap.rings = 24
	cap.scale = Vector3(1, 0.32, 1)
	cap.position = C_CENTER + Vector3(0, C_H, 0)
	cap.material = mats["inflatable"]
	root.add_child(cap)
	# Window glass.
	_box(root, "C_WindowGlass_N", Vector3(0.9, 0.7, 0.04), C_CENTER + Vector3(0, C_DECK2 + 1.4, -C_R + 0.08), "glass")
	_box(root, "C_WindowGlass_W", Vector3(0.04, 0.7, 0.9), C_CENTER + Vector3(-C_R + 0.08, C_DECK2 + 1.4, 0.6), "glass")
	_hatch_frame(root, "C_Hatch_East", C_CENTER + Vector3(C_R - 0.05, 0, 0), PI / 2.0)
	# Decks: ground slab, upper deck with a ladder opening, ladder.
	_cyl(root, "C_Floor1", C_R - 0.1, 0.1, C_CENTER + Vector3(0, -0.05, 0), "floor")
	var d2 := _combiner("C_Floor2", C_CENTER + Vector3(0, C_DECK2 - 0.05, 0))
	_cyl(d2, "deck", C_R - 0.15, 0.1, Vector3.ZERO, "floor")
	_box(d2, "ladder_hole", Vector3(1.2, 0.3, 1.0), Vector3(2.2, 0, 2.2), "", CSGShape3D.OPERATION_SUBTRACTION)
	_box(root, "C_Ladder", Vector3(0.08, C_DECK2 + 0.1, 0.5), C_CENTER + Vector3(2.85, C_DECK2 / 2.0, 2.2), "equipment_dark")
	for k in 6:
		_box(root, "C_LadderRung_%d" % k, Vector3(0.12, 0.03, 0.5), C_CENTER + Vector3(2.75, 0.35 + k * 0.4, 2.2), "deck_edge")
	# Deck 1: storm-shelter core (water tank wall ring with two gaps) + 8 radial partitions:
	# 4 crew quarters (50 deg) separated by 4 buffer compartments (hygiene, hygiene, UWMS, stowage).
	var shelter := _combiner("C_ShelterWall", C_CENTER + Vector3(0, 0.75, 0))
	_cyl(shelter, "ring_outer", 1.75, 1.5, Vector3.ZERO, "water")
	_cyl(shelter, "ring_inner", 1.45, 1.7, Vector3.ZERO, "", "y", CSGShape3D.OPERATION_SUBTRACTION)
	_box(shelter, "gap_e", Vector3(1.0, 1.7, 0.9), Vector3(1.6, 0, 0), "", CSGShape3D.OPERATION_SUBTRACTION)
	_box(shelter, "gap_w", Vector3(1.0, 1.7, 0.9), Vector3(-1.6, 0, 0), "", CSGShape3D.OPERATION_SUBTRACTION)
	_box(root, "C_ShelterSign", Vector3(0.8, 0.02, 0.4), C_CENTER + Vector3(0, 0.01, 0), "accent")
	var angles := [20.0, 70.0, 110.0, 160.0, 200.0, 250.0, 290.0, 340.0]
	for k in angles.size():
		var a: float = deg_to_rad(angles[k])
		var r_mid := (1.85 + C_R - 0.15) * 0.5
		var wall := _box(root, "C_Partition_%d" % k, Vector3(C_R - 0.15 - 1.85, 2.4, 0.06), C_CENTER + Vector3(cos(a) * r_mid, 1.2, sin(a) * r_mid), "interior")
		wall.rotation.y = -a
	# Crew quarters contents (bunk along the outer wall, desk, locker) at the centre angle of each 50-degree segment.
	var cq_angles := [45.0, 135.0, 225.0, 315.0]
	for k in cq_angles.size():
		var a: float = deg_to_rad(cq_angles[k])
		var out := C_CENTER + Vector3(cos(a) * 3.0, 0, sin(a) * 3.0)
		var bunk := _box(root, "C_CQ%d_Bunk" % (k + 1), Vector3(2.0, 0.5, 0.85), out + Vector3(0, 0.25, 0), "bunk")
		bunk.rotation.y = -a + PI / 2.0
		var desk := _box(root, "C_CQ%d_Desk" % (k + 1), Vector3(0.8, 0.75, 0.5), C_CENTER + Vector3(cos(a + 0.35) * 2.5, 0.375, sin(a + 0.35) * 2.5), "equipment_dark")
		desk.rotation.y = -a
		var locker := _box(root, "C_CQ%d_Locker" % (k + 1), Vector3(0.5, 1.8, 0.4), C_CENTER + Vector3(cos(a - 0.35) * 2.6, 0.9, sin(a - 0.35) * 2.6), "equipment")
		locker.rotation.y = -a
		var lamp := _box(root, "C_CQ%d_Lamp" % (k + 1), Vector3(0.3, 0.03, 0.3), out + Vector3(0, 2.35, 0), "interior")
		lamp.rotation.y = -a
	# Buffer compartments: hygiene x2, UWMS, stowage at 0, 90, 180, 270 degrees.
	var buf := ["Hygiene_A", "Stowage", "Hygiene_B", "UWMS"]
	for k in buf.size():
		var a: float = deg_to_rad(90.0 * k)
		var p := C_CENTER + Vector3(cos(a) * 2.75, 0, sin(a) * 2.75)
		var u := _box(root, "C_%s" % buf[k], Vector3(0.7, 1.0, 0.6), p + Vector3(0, 0.5, 0), "equipment_dark" if buf[k] == "Stowage" else "water")
		u.rotation.y = -a
	# Deck 2: wardroom + galley north (window), medical east, exercise west (window), greenhouse south.
	var y2 := C_DECK2
	_cyl(root, "C_WardroomTable", 0.7, 0.06, C_CENTER + Vector3(0, y2 + 0.75, -1.6), "interior")
	_cyl(root, "C_WardroomTableLeg", 0.08, 0.72, C_CENTER + Vector3(0, y2 + 0.36, -1.6), "equipment_dark")
	_box(root, "C_GalleyCounter", Vector3(2.2, 0.9, 0.6), C_CENTER + Vector3(1.4, y2 + 0.45, -2.9), "equipment", CSGShape3D.OPERATION_UNION, -0.5)
	_box(root, "C_Fridge", Vector3(0.6, 1.6, 0.6), C_CENTER + Vector3(2.6, y2 + 0.8, -2.0), "equipment_dark")
	_box(root, "C_MedicalBed", Vector3(0.8, 0.6, 2.0), C_CENTER + Vector3(2.8, y2 + 0.3, 0.3), "bunk")
	_box(root, "C_MedicalWall", Vector3(0.3, 1.4, 1.6), C_CENTER + Vector3(3.3, y2 + 1.3, 0.3), "equipment")
	_box(root, "C_ExerciseDevice", Vector3(0.7, 1.5, 1.4), C_CENTER + Vector3(-2.6, y2 + 0.75, 0.4), "equipment_dark")
	_box(root, "C_ExerciseBike", Vector3(0.5, 1.1, 1.2), C_CENTER + Vector3(-2.4, y2 + 0.55, -1.2), "equipment")
	for k in 2:
		_box(root, "C_GreenhouseRack_%d" % k, Vector3(1.6, 1.8, 0.5), C_CENTER + Vector3(-1.0 + k * 2.0, y2 + 0.9, 2.9), "equipment_dark")
		_box(root, "C_GreenhousePlants_%d" % k, Vector3(1.5, 0.3, 0.45), C_CENTER + Vector3(-1.0 + k * 2.0, y2 + 1.2, 2.9), "plant")
		_box(root, "C_GrowLight_%d" % k, Vector3(1.5, 0.03, 0.45), C_CENTER + Vector3(-1.0 + k * 2.0, y2 + 1.78, 2.9), "interior")
	_cyl(root, "C_Deck2Lamp", 0.5, 0.03, C_CENTER + Vector3(0, y2 + 2.9, 0), "interior")



## Regolith berm around C (exterior glb: it must not count as a floor).
func _build_berm() -> void:
	var berm := CSGTorus3D.new()
	berm.name = "C_Berm"
	berm.inner_radius = 4.2
	berm.outer_radius = 10.0
	berm.sides = 24
	berm.ring_sides = 12
	berm.position = C_CENTER + Vector3(0, 0.3, 0)
	berm.scale = Vector3(1, 1.15, 1)
	berm.material = mats["regolith"]
	root.add_child(berm)
	var cut := _box(root, "C_BermCut", Vector3(3.0, 8.0, 3.0), C_CENTER + Vector3(5.5, 0, 0), "", CSGShape3D.OPERATION_SUBTRACTION)
	cut.get_parent().remove_child(cut)
	berm.add_child(cut)   # keep the tunnel side open
	cut.position = Vector3(5.5, 0, 0)


# ---------------------------------------------------------------- exterior

func _build_exterior() -> void:
	# Fission surface power 700 m north, behind a regolith berm, cable back to B4.
	var fsp := Vector3(-7.5, 0, -700.0)
	_cyl(root, "E_FSP_Reactor", 1.2, 3.0, fsp + Vector3(0, 1.5, 0), "equipment_dark")
	for k in 4:
		var fin := _box(root, "E_FSP_Fin_%d" % k, Vector3(6.0, 2.4, 0.08), fsp + Vector3(0, 4.5, 0), "hull")
		fin.rotation.y = k * PI / 4.0
	_cyl(root, "E_FSP_Mast", 0.15, 2.4, fsp + Vector3(0, 3.6, 0), "hull")
	_box(root, "E_FSP_Berm", Vector3(16.0, 4.0, 3.0), fsp + Vector3(0, 1.5, 6.0), "regolith")
	_box(root, "E_FSP_Cable", Vector3(0.15, 0.25, 686.0), Vector3(-10.9, 0.15, -357.0 + 0.0), "equipment_dark")
	# Two vertical solar towers north of the base.
	for k in 2:
		var p := Vector3(-25.0 + k * 35.0, 0, -50.0)
		_cyl(root, "E_SolarMast_%d" % k, 0.3, 12.0, p + Vector3(0, 6.0, 0), "hull")
		_box(root, "E_SolarPanel_%d" % k, Vector3(6.0, 10.0, 0.12), p + Vector3(0, 11.0, 0), "solar")
		_box(root, "E_SolarBase_%d" % k, Vector3(3.0, 0.4, 3.0), p + Vector3(0, 0.2, 0), "equipment_dark")
	# Comms antenna east.
	_cyl(root, "E_AntennaMast", 0.12, 6.0, Vector3(12.0, 3.0, -20.0), "hull")
	var dish := _cyl(root, "E_AntennaDish", 1.3, 0.1, Vector3(12.0, 6.2, -20.0), "hull", "y", CSGShape3D.OPERATION_UNION, 32)
	dish.rotation.x = -0.9
	# Logistics lander 150 m east with an offloading crane.
	var lander := Vector3(150.0, 0, 10.0)
	_cyl(root, "E_Lander_Body", 2.5, 5.0, lander + Vector3(0, 4.5, 0), "hull")
	_cyl(root, "E_Lander_Deck", 3.5, 0.3, lander + Vector3(0, 2.0, 0), "equipment_dark")
	for k in 4:
		var a := k * PI / 2.0 + PI / 4.0
		var leg := _cyl(root, "E_Lander_Leg_%d" % k, 0.15, 3.0, lander + Vector3(cos(a) * 3.6, 1.2, sin(a) * 3.6), "hull")
		leg.rotation = Vector3(sin(a) * 0.45, 0, -cos(a) * 0.45)
		_cyl(root, "E_Lander_Pad_%d" % k, 0.6, 0.15, lander + Vector3(cos(a) * 4.3, 0.07, sin(a) * 4.3), "equipment_dark")
	_box(root, "E_Lander_Crane", Vector3(0.3, 0.3, 6.0), lander + Vector3(0, 7.5, 3.0), "accent")
	# Unpressurised rover (LTV) parked by the engineering airlock.
	var ltv := Vector3(5.0, 0, -12.0)
	_box(root, "E_LTV_Chassis", Vector3(3.2, 0.5, 2.0), ltv + Vector3(0, 0.75, 0), "equipment_dark")
	_box(root, "E_LTV_Seats", Vector3(1.2, 0.8, 1.4), ltv + Vector3(-0.6, 1.4, 0), "equipment")
	_box(root, "E_LTV_Cargo", Vector3(1.2, 0.6, 1.6), ltv + Vector3(1.0, 1.3, 0), "accent")
	for k in 4:
		var w := _cyl(root, "E_LTV_Wheel_%d" % k, 0.45, 0.3, ltv + Vector3(-1.1 + (k % 2) * 2.2, 0.45, -1.1 + (k / 2) * 2.2), "equipment_dark", "z", CSGShape3D.OPERATION_UNION, 20)
		w.name = "E_LTV_Wheel_%d" % k
	# Footpath grading between the modules (slightly darker regolith patches).
	_box(root, "E_Path_Airlock", Vector3(6.0, 0.02, 2.0), Vector3(3.0, 0.0, -12.0), "regolith")

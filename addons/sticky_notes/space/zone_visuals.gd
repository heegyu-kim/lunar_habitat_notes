## Draws every zone as a thin glowing outline on its floor plus a floating name, so people in VR
## can see where one zone ends and the next begins. Rebuilt by NoteManager whenever zones change.
extends Node3D

const EDGE := 0.04        # outline thickness, m
const LIFT := 0.02        # above the floor, m
const LABEL_HEIGHT := 0.35

const PresetsScript := preload("res://addons/sticky_notes/space/space_presets.gd")


func rebuild(zones: Array, manager: Node) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for z in zones:
		var fl: Dictionary = manager.floor_by_id(str(z["floor"]))
		if fl.is_empty():
			continue
		var y := float(fl["y"]) + LIFT
		var rect: Rect2 = manager.zone_rect(z)
		var color: Color = PresetsScript.zone_color(str(z["type"]))
		var warn := bool(z.get("noise_over", false))
		if warn:
			color = Color(1.0, 0.25, 0.2)
		var group := Node3D.new()
		group.name = "Zone_" + str(z["id"])
		add_child(group)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.5
		mat.render_priority = 5
		# Four edges.
		_edge(group, mat, Vector3(rect.position.x, y, rect.position.y), Vector3(rect.end.x, y, rect.position.y))
		_edge(group, mat, Vector3(rect.position.x, y, rect.end.y), Vector3(rect.end.x, y, rect.end.y))
		_edge(group, mat, Vector3(rect.position.x, y, rect.position.y), Vector3(rect.position.x, y, rect.end.y))
		_edge(group, mat, Vector3(rect.end.x, y, rect.position.y), Vector3(rect.end.x, y, rect.end.y))
		# Faint fill.
		var fill := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = rect.size
		fill.mesh = pm
		var fmat := StandardMaterial3D.new()
		fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fmat.albedo_color = Color(color.r, color.g, color.b, 0.10 if not warn else 0.22)
		fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		fmat.render_priority = 4
		fill.material_override = fmat
		fill.position = Vector3(rect.get_center().x, y - 0.005, rect.get_center().y)
		group.add_child(fill)
		# Name.
		var label := Label3D.new()
		label.text = str(z["name"]) + ("\n! noise %d > %d dB" % [int(z.get("noise_db", 0)), int(z["noise_limit_db"])] if warn else "")
		label.font_size = 48
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		label.modulate = color
		label.outline_modulate = Color(0, 0, 0, 0.8)
		label.outline_size = 8
		label.position = Vector3(rect.get_center().x, y + LABEL_HEIGHT, rect.get_center().y)
		group.add_child(label)
	# Noise sources: a small orange speaker ball with its level.
	for s in manager.noise_sources_sorted():
		var pos: Vector3 = manager.noise_source_position(s)
		var g := Node3D.new()
		g.name = "Noise_" + str(s["id"])
		add_child(g)
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.2
		ball.mesh = sm
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = Color(1.0, 0.55, 0.15)
		bm.emission_enabled = true
		bm.emission = Color(1.0, 0.55, 0.15)
		bm.render_priority = 6
		ball.material_override = bm
		ball.position = pos + Vector3(0.0, 0.1, 0.0)
		g.add_child(ball)
		var nl := Label3D.new()
		nl.text = "%s  %d dB" % [str(s["name"]), int(s["db_at_1m"])]
		nl.font_size = 40
		nl.pixel_size = 0.004
		nl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		nl.modulate = Color(1.0, 0.75, 0.4)
		nl.outline_modulate = Color(0, 0, 0, 0.8)
		nl.outline_size = 8
		nl.position = pos + Vector3(0.0, 0.35, 0.0)
		g.add_child(nl)


func _edge(parent: Node3D, mat: Material, a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	var d := b - a
	box.size = Vector3(maxf(absf(d.x), EDGE), 0.01, maxf(absf(d.z), EDGE))
	mi.mesh = box
	mi.material_override = mat
	mi.position = (a + b) * 0.5
	parent.add_child(mi)

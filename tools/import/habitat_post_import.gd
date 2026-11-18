@tool
extends EditorScenePostImport
## Post-import script for the habitat glb: turns inside-out meshes the right way round.
##
## About 80 meshes in the Blender export are inside out: both their triangle winding and their
## normals point into the solid (typical of a negative scale applied in Blender). They are drawn
## double-sided, so real-time lighting hides it, but the lightmap baker lights the inward side and
## those meshes bake black. This flips them back (winding and normals) after Godot has generated the
## lightmap UVs, so the UVs stay valid.
##
## Detection is exact for closed meshes: signed volume gives the winding's direction, and comparing
## vertex normals with the winding gives the normals' direction. Godot winds front faces clockwise, so
## a correct closed mesh has negative signed volume and normals against the (b-a)x(c-a) direction.
## Open or ambiguous meshes (thin plates, single faces) are left alone.

const MIN_REL_VOLUME := 0.05      # |volume| / AABB volume; below this the mesh is too open to judge
const MIN_NORMAL_AGREEMENT := 0.5


func _post_import(scene: Node) -> Object:
	var done := {}
	var flipped := 0
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh as ArrayMesh
		if m == null:
			continue
		if done.has(m):
			if done[m] != null:
				(mi as MeshInstance3D).mesh = done[m]
			continue
		if _is_inverted(m):
			var fixed := _flipped(m)
			done[m] = fixed
			(mi as MeshInstance3D).mesh = fixed
			flipped += 1
		else:
			done[m] = null
	# Hatch doors have 9 mm ribs and dozens of small parts. At the 5 cm lightmap texel the ribs bake
	# as dotted lines, and a finer texel blows the lightmap up (8x density = 4096x16384). Leave them
	# out of the bake: they are lit in real time by the interior lights and the reflection probes.
	var fine := 0
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if str(mi.name).begins_with("Hatch door"):
			(mi as MeshInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
			fine += 1
	print("habitat_post_import: flipped %d inside-out meshes, %d hatch doors lit in real time (not baked) in %s" % [flipped, fine, get_source_file()])
	return scene


static func _is_inverted(m: ArrayMesh) -> bool:
	var vol := 0.0
	var agree := 0.0
	var area := 0.0
	for s in m.get_surface_count():
		if m.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return false
		var arr := m.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if n.is_empty() or idx.is_empty():
			return false
		for t in range(0, idx.size(), 3):
			var a := v[idx[t]]
			var b := v[idx[t + 1]]
			var c := v[idx[t + 2]]
			var fn := (b - a).cross(c - a)
			vol += a.dot(b.cross(c)) / 6.0
			var ar := fn.length()
			if ar > 0.0:
				agree += (n[idx[t]] + n[idx[t + 1]] + n[idx[t + 2]]).normalized().dot(fn / ar) * ar
				area += ar
	var box := m.get_aabb().size
	var rel := absf(vol) / maxf(box.x * box.y * box.z, 1e-9)
	var a_n := agree / maxf(area, 1e-9)
	if rel < MIN_REL_VOLUME or absf(a_n) < MIN_NORMAL_AGREEMENT:
		return false
	return signf(vol) * signf(a_n) < 0.0


static func _flipped(m: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.resource_name = m.resource_name
	out.lightmap_size_hint = m.lightmap_size_hint
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var k := idx[t + 1]
			idx[t + 1] = idx[t + 2]
			idx[t + 2] = k
		arr[Mesh.ARRAY_INDEX] = idx
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in n.size():
			n[i] = -n[i]
		arr[Mesh.ARRAY_NORMAL] = n
		if arr[Mesh.ARRAY_TANGENT] is PackedFloat32Array:
			var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
			for i in range(3, tg.size(), 4):
				tg[i] = -tg[i]
			arr[Mesh.ARRAY_TANGENT] = tg
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, m.surface_get_material(s))
		out.surface_set_name(s, m.surface_get_name(s))
	return out

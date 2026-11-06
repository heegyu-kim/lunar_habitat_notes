## Floor (deck) detection from raw geometry, for the space-setup pipeline.
##
## Works on any model: it only looks at triangles, never at node names.
##   1. collect every upward-facing triangle under a root node (world space)
##   2. area-weighted histogram of their heights -> peaks are floors
##   3. per floor, rasterise the triangles near that height into a 0.1 m mask (the minimap base)
##   4. per floor, a ConcavePolygonShape3D of those triangles (the walkable "habitat_floor" body)
##
## Everything is static; NoteManager owns the results.
class_name SpaceFloors
extends RefCounted

const UP_NY := 0.8              # normal.y above this = faces up
const BIN := 0.1                # histogram bin, metres
const MIN_GAP := 2.0            # two floors are at least this far apart
const MIN_FRACTION := 0.02      # a floor holds at least this share of all upward area
const FLOOR_TOL := 0.15         # triangles within +-this of the floor height belong to it
const CELL := 0.1               # mask cell, metres
const MAX_CELLS := 4_000_000    # coarser cells for huge models


const HEADROOM_LO := 0.4        # a real floor has geometry (walls, ceiling) somewhere in [y+LO, y+HI]
const HEADROOM_HI := 2.8
const HEADROOM_FRACTION := 0.01 # ... holding at least this share of all face area; roofs and wall tops fail this


## Upward-facing triangles under `root`, world space.
## Returns {faces: PackedVector3Array (3 per tri), areas: PackedFloat32Array,
##          all_hist: Dictionary bin -> area of every triangle (any orientation), all_total: float}.
static func collect_up_faces(root: Node3D) -> Dictionary:
	var faces := PackedVector3Array()
	var areas := PackedFloat32Array()
	var all_hist: Dictionary = {}
	var all_total := 0.0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m == null or m.mesh == null or not m.is_visible_in_tree():
			continue
		var local := m.mesh.get_faces()
		var xf := m.global_transform
		var i := 0
		while i + 2 < local.size():
			var a := xf * local[i]
			var b := xf * local[i + 1]
			var c := xf * local[i + 2]
			i += 3
			# Godot front faces wind clockwise, so the outward normal is (c - a) x (b - a).
			var n := (c - a).cross(b - a)
			var len := n.length()
			if len < 1e-8:
				continue
			var tri_area := len * 0.5
			var k := int(floor((a.y + b.y + c.y) / 3.0 / BIN))
			all_hist[k] = all_hist.get(k, 0.0) + tri_area
			all_total += tri_area
			if n.y / len < UP_NY:
				continue
			faces.append(a)
			faces.append(b)
			faces.append(c)
			areas.append(tri_area)
	return {"faces": faces, "areas": areas, "all_hist": all_hist, "all_total": all_total}


## Area of every triangle whose centroid lies in [y0, y1).
static func _area_between(up: Dictionary, y0: float, y1: float) -> float:
	var hist: Dictionary = up.get("all_hist", {})
	var sum := 0.0
	for k in range(int(floor(y0 / BIN)), int(floor(y1 / BIN)) + 1):
		sum += hist.get(k, 0.0)
	return sum


## Floor heights (ascending) from the histogram of upward triangle centroids.
static func find_floor_heights(up: Dictionary) -> PackedFloat32Array:
	var faces: PackedVector3Array = up["faces"]
	var areas: PackedFloat32Array = up["areas"]
	var hist: Dictionary = {}       # bin index -> area
	var total := 0.0
	for t in areas.size():
		var y := (faces[t * 3].y + faces[t * 3 + 1].y + faces[t * 3 + 2].y) / 3.0
		var k := int(floor(y / BIN))
		hist[k] = hist.get(k, 0.0) + areas[t]
		total += areas[t]
	if total <= 0.0:
		return PackedFloat32Array()
	# Peaks: biggest bins first, skipping any bin within MIN_GAP of an accepted floor.
	var keys: Array = hist.keys()
	keys.sort_custom(func(a: int, b: int) -> bool: return hist[a] > hist[b])
	var accepted: Array[int] = []
	var all_total := float(up.get("all_total", 0.0))
	for k in keys:
		if hist[k] < total * MIN_FRACTION:
			break
		var ok := true
		for f in accepted:
			if absi(f - k) * BIN < MIN_GAP:
				ok = false
				break
		# Roofs and wall tops face up too, but nothing stands above them.
		var y: float = (int(k) + 0.5) * BIN
		if ok and all_total > 0.0 and _area_between(up, y + HEADROOM_LO, y + HEADROOM_HI) < all_total * HEADROOM_FRACTION:
			ok = false
		if ok:
			accepted.append(k)
	# Refine each peak: area-weighted mean over the bin and its neighbours.
	var out := PackedFloat32Array()
	for k in accepted:
		var sum := 0.0
		var w := 0.0
		for t in areas.size():
			var y := (faces[t * 3].y + faces[t * 3 + 1].y + faces[t * 3 + 2].y) / 3.0
			var kk := int(floor(y / BIN))
			if absi(kk - k) <= 1:
				sum += y * areas[t]
				w += areas[t]
		out.append(sum / w if w > 0.0 else (k + 0.5) * BIN)
	out.sort()
	return out


## XZ bounds of the upward faces near height y (all faces when y is NAN), padded.
static func bounds_xz(up: Dictionary, pad: float = 0.5, y: float = NAN) -> Rect2:
	var faces: PackedVector3Array = up["faces"]
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var t := 0
	while t + 2 < faces.size():
		if not is_nan(y):
			var cy := (faces[t].y + faces[t + 1].y + faces[t + 2].y) / 3.0
			if absf(cy - y) > FLOOR_TOL:
				t += 3
				continue
		for k in 3:
			var p := faces[t + k]
			mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.z))
			mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.z))
		t += 3
	if mn.x == INF:
		return Rect2()
	return Rect2(mn - Vector2.ONE * pad, mx - mn + Vector2.ONE * pad * 2.0)


## Occupancy mask of one floor: {origin: Vector2 (x, z of cell 0,0), cell: float, w: int, h: int, bits: PackedByteArray (0/255)}.
static func rasterize(up: Dictionary, y: float, area: Rect2, cell: float = CELL) -> Dictionary:
	var faces: PackedVector3Array = up["faces"]
	var w := int(ceil(area.size.x / cell))
	var h := int(ceil(area.size.y / cell))
	while w * h > MAX_CELLS:
		cell *= 2.0
		w = int(ceil(area.size.x / cell))
		h = int(ceil(area.size.y / cell))
	var bits := PackedByteArray()
	bits.resize(maxi(w * h, 1))
	bits.fill(0)
	var ox := area.position.x
	var oz := area.position.y
	var t := 0
	while t + 2 < faces.size():
		var a := faces[t]
		var b := faces[t + 1]
		var c := faces[t + 2]
		t += 3
		var cy := (a.y + b.y + c.y) / 3.0
		if absf(cy - y) > FLOOR_TOL:
			continue
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		var c2 := Vector2(c.x, c.z)
		var x0 := clampi(int(floor((minf(a2.x, minf(b2.x, c2.x)) - ox) / cell)), 0, w - 1)
		var x1 := clampi(int(floor((maxf(a2.x, maxf(b2.x, c2.x)) - ox) / cell)), 0, w - 1)
		var z0 := clampi(int(floor((minf(a2.y, minf(b2.y, c2.y)) - oz) / cell)), 0, h - 1)
		var z1 := clampi(int(floor((maxf(a2.y, maxf(b2.y, c2.y)) - oz) / cell)), 0, h - 1)
		for zi in range(z0, z1 + 1):
			for xi in range(x0, x1 + 1):
				var p := Vector2(ox + (xi + 0.5) * cell, oz + (zi + 0.5) * cell)
				if _in_tri(p, a2, b2, c2):
					bits[zi * w + xi] = 255
	_close(bits, w, h)
	return {"origin": Vector2(ox, oz), "cell": cell, "w": w, "h": h, "bits": bits}


static func _in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var d2 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d3 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	var neg := d1 < 0 or d2 < 0 or d3 < 0
	var pos := d1 > 0 or d2 > 0 or d3 > 0
	return not (neg and pos)


## Morphological closing (dilate then erode, 3x3) so hatches and seams do not cut the floor.
static func _close(bits: PackedByteArray, w: int, h: int) -> void:
	var tmp := bits.duplicate()
	for z in h:
		for x in w:
			if bits[z * w + x] == 0 and _any_neighbour(bits, w, h, x, z, 255):
				tmp[z * w + x] = 255
	for z in h:
		for x in w:
			if tmp[z * w + x] == 255 and _any_neighbour(tmp, w, h, x, z, 0):
				bits[z * w + x] = 0
			else:
				bits[z * w + x] = tmp[z * w + x]


static func _any_neighbour(bits: PackedByteArray, w: int, h: int, x: int, z: int, value: int) -> bool:
	for dz: int in [-1, 0, 1]:
		for dx: int in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var xx: int = x + dx
			var zz: int = z + dz
			if xx < 0 or zz < 0 or xx >= w or zz >= h:
				continue
			if bits[zz * w + xx] == value:
				return true
	return false


static func mask_to_image(mask: Dictionary) -> Image:
	var w: int = mask["w"]
	var h: int = mask["h"]
	return Image.create_from_data(w, h, false, Image.FORMAT_L8, mask["bits"])


static func mask_filled_count(mask: Dictionary) -> int:
	var n := 0
	for b in mask["bits"]:
		if b != 0:
			n += 1
	return n


## A filled cell nearest to the mask centroid, as a world point on the floor. Default landing.
static func mask_center(mask: Dictionary, y: float) -> Vector3:
	var w: int = mask["w"]
	var h: int = mask["h"]
	var bits: PackedByteArray = mask["bits"]
	var cell: float = mask["cell"]
	var origin: Vector2 = mask["origin"]
	var sx := 0.0
	var sz := 0.0
	var n := 0
	for z in h:
		for x in w:
			if bits[z * w + x] != 0:
				sx += x
				sz += z
				n += 1
	if n == 0:
		return Vector3(origin.x, y, origin.y)
	var cx := sx / n
	var cz := sz / n
	var best := Vector2(cx, cz)
	var best_d := INF
	for z in h:
		for x in w:
			if bits[z * w + x] != 0:
				var d := Vector2(x, z).distance_squared_to(Vector2(cx, cz))
				if d < best_d:
					best_d = d
					best = Vector2(x, z)
	return Vector3(origin.x + (best.x + 0.5) * cell, y, origin.y + (best.y + 0.5) * cell)


## Is world point (x, z) on a filled cell of the mask?
static func mask_contains(mask: Dictionary, x: float, z: float) -> bool:
	var origin: Vector2 = mask["origin"]
	var cell: float = mask["cell"]
	var xi := int(floor((x - origin.x) / cell))
	var zi := int(floor((z - origin.y) / cell))
	var w: int = mask["w"]
	var h: int = mask["h"]
	if xi < 0 or zi < 0 or xi >= w or zi >= h:
		return false
	return mask["bits"][zi * w + xi] != 0


## Collision shape made of the floor's own triangles (world space; put the body at the origin).
static func floor_shape(up: Dictionary, y: float) -> ConcavePolygonShape3D:
	var faces: PackedVector3Array = up["faces"]
	var tris := PackedVector3Array()
	var t := 0
	while t + 2 < faces.size():
		var cy := (faces[t].y + faces[t + 1].y + faces[t + 2].y) / 3.0
		if absf(cy - y) <= FLOOR_TOL:
			tris.append(faces[t])
			tris.append(faces[t + 1])
			tris.append(faces[t + 2])
		t += 3
	if tris.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(tris)
	shape.backface_collision = true
	return shape

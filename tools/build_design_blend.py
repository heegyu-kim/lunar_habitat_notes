# -*- coding: utf-8 -*-
"""Builds the dimension-exact reference model of modules B, C, D, tunnels and hatches in Blender.

Run from the project folder:
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b --python tools/build_design_blend.py
Output (git-ignored):  blender/base_camp_design_reference.blend  and  .glb
Geometry comes from tools/design/params.py, the same numbers as the drawings in docs/design/.

Blender frame: X east, Y north (= -z of the game), Z up (= y of the game). Tower A stands on the origin.
Hulls, floors, partitions and hatches are real solids; equipment is drawn as wire envelopes (bounding
boxes with the right size and position) to be replaced by detailed models.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "design"))
import params as P  # noqa: E402

OUT = os.path.join(ROOT, "blender")
os.makedirs(OUT, exist_ok=True)
SEG = 72

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"


# ------------------------------------------------------------------ basics
def coll(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


def mat(name, rgba, rough=0.6, metal=0.0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = rgba
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    if b:
        b.inputs["Base Color"].default_value = rgba
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        if rgba[3] < 1.0:
            b.inputs["Alpha"].default_value = rgba[3]
    return m


M = {
    "hull": mat("Hull aluminium", (0.72, 0.74, 0.78, 1), 0.45, 0.6),
    "infl": mat("Inflatable shell", (0.86, 0.82, 0.72, 1), 0.9),
    "floor": mat("Floor", (0.38, 0.39, 0.42, 1), 0.7),
    "part": mat("Partition", (0.88, 0.88, 0.86, 1), 0.8),
    "ring": mat("Port ring", (0.50, 0.53, 0.58, 1), 0.4, 0.7),
    "hatch": mat("Hatch", (0.88, 0.48, 0.13, 1), 0.5, 0.3),
    "tunnel": mat("Tunnel", (0.82, 0.84, 0.87, 1), 0.5, 0.4),
    "equip": mat("Equipment envelope", (0.45, 0.58, 0.82, 1), 0.6),
    "water": mat("Water", (0.35, 0.60, 0.85, 1), 0.3),
    "rego": mat("Regolith", (0.55, 0.52, 0.47, 1), 0.95),
    "glass": mat("Glass", (0.6, 0.85, 0.95, 0.4), 0.1),
    "ladder": mat("Ladder", (0.95, 0.80, 0.35, 1), 0.6),
    "ref": mat("Reference", (0.9, 0.9, 0.5, 1), 0.8),
}


def W(x, z, y=0.0):
    """Game world (x east, z south, y up) -> Blender vector."""
    return Vector((x, -z, y))


def new_obj(name, verts, faces, c, material=None, wire=False):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    bm = bmesh.new(); bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free(); me.update()
    ob = bpy.data.objects.new(name, me)
    c.objects.link(ob)
    if material:
        me.materials.append(material)
    if wire:
        ob.display_type = "WIRE"
    return ob


def boolean(ob, cutter, op="DIFFERENCE"):
    mod = ob.modifiers.new("b", "BOOLEAN")
    mod.operation = op; mod.object = cutter; mod.solver = "EXACT"
    dg = bpy.context.evaluated_depsgraph_get(); dg.update()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.clear()
    old = ob.data; mats = [m for m in old.materials]
    ob.data = me
    if not me.materials:
        for m in mats:
            me.materials.append(m)
    bpy.data.meshes.remove(old)


TMP = coll("_tmp cutters")


def drop(ob):
    bpy.data.objects.remove(ob, do_unlink=True)


def box(name, lo, hi, c, material=None, wire=False):
    x0, y0, z0 = lo; x1, y1, z1 = hi
    v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    f = [(0, 1, 2, 3), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return new_obj(name, v, f, c, material, wire)


def wbox(name, x0, x1, y0, y1, zs, zn, c, material=None, wire=False):
    """Box given in game-world terms: x range, y(up) range, z south / z north."""
    return box(name, (min(x0, x1), -zs, y0), (max(x0, x1), -zn, y1), c, material, wire)


def revolve_solid(name, profile, origin, c, material=None, axis="Z", seg=SEG):
    """Closed solid of revolution. profile = [(r, h), ...] from the axis (r=0) back to the axis."""
    def p3(r, h, a):
        if axis == "Z":
            return (origin.x + r * math.cos(a), origin.y + r * math.sin(a), origin.z + h)
        return (origin.x + r * math.cos(a), origin.y + h, origin.z + r * math.sin(a))
    verts = []; rings = []
    for r, h in profile:
        if r < 1e-7:
            rings.append([len(verts)]); verts.append(p3(0.0, h, 0.0))
        else:
            rings.append(list(range(len(verts), len(verts) + seg)))
            verts += [p3(r, h, 2 * math.pi * i / seg) for i in range(seg)]
    faces = []
    for a, b in zip(rings[:-1], rings[1:]):
        for i in range(seg):
            j = (i + 1) % seg
            if len(a) == 1 and len(b) == 1:
                continue
            if len(a) == 1:
                faces.append((a[0], b[i], b[j]))
            elif len(b) == 1:
                faces.append((a[i], a[j], b[0]))
            else:
                faces.append((a[i], a[j], b[j], b[i]))
    return new_obj(name, verts, faces, c, material)


def revolve_sector(name, poly, origin, az0, az1, c, material=None, seg=48):
    """Closed solid: polygon (r, h) swept about Z from azimuth az0 to az1 (degrees), with end caps."""
    n = len(poly); verts = []
    for i in range(seg + 1):
        a = math.radians(az0 + (az1 - az0) * i / seg)
        verts += [(origin.x + r * math.cos(a), origin.y + r * math.sin(a), origin.z + h) for r, h in poly]
    faces = []
    for i in range(seg):
        for k in range(n):
            k2 = (k + 1) % n
            faces.append((i * n + k, i * n + k2, (i + 1) * n + k2, (i + 1) * n + k))
    faces.append(tuple(range(n))); faces.append(tuple(seg * n + k for k in range(n)))
    return new_obj(name, verts, faces, c, material)


def tube(name, p0, p1, r_out, r_in, c, material=None, seg=SEG):
    """Horizontal tube (or solid cylinder when r_in = 0) from p0 to p1."""
    d = (p1 - p0).normalized()
    n1 = Vector((0, 0, 1)).cross(d).normalized(); n2 = Vector((0, 0, 1))
    def ring(p, r):
        return [tuple(p + n1 * (r * math.cos(2 * math.pi * i / seg)) + n2 * (r * math.sin(2 * math.pi * i / seg))) for i in range(seg)]
    verts = ring(p0, r_out) + ring(p1, r_out)
    faces = [(i, (i + 1) % seg, seg + (i + 1) % seg, seg + i) for i in range(seg)]
    if r_in > 1e-6:
        verts += ring(p0, r_in) + ring(p1, r_in)
        faces += [(2 * seg + i, 2 * seg + (i + 1) % seg, 3 * seg + (i + 1) % seg, 3 * seg + i) for i in range(seg)]
        faces += [(i, (i + 1) % seg, 2 * seg + (i + 1) % seg, 2 * seg + i) for i in range(seg)]
        faces += [(seg + i, seg + (i + 1) % seg, 3 * seg + (i + 1) % seg, 3 * seg + i) for i in range(seg)]
    else:
        faces += [tuple(range(seg)), tuple(range(seg, 2 * seg))]
    return new_obj(name, verts, faces, c, material)


def prism(name, pts, t0, t1, plane, c, material=None, origin=Vector((0, 0, 0))):
    """Extruded polygon. plane 'XY': pts (x, y), extruded z t0..t1. 'XZ': pts (x, z), extruded along y. 'YZ': pts (y, z), extruded along x."""
    def p3(a, b, t):
        if plane == "XY":
            return (origin.x + a, origin.y + b, origin.z + t)
        if plane == "XZ":
            return (origin.x + a, origin.y + t, origin.z + b)
        return (origin.x + t, origin.y + a, origin.z + b)
    n = len(pts)
    verts = [p3(a, b, t0) for a, b in pts] + [p3(a, b, t1) for a, b in pts]
    faces = [tuple(range(n)), tuple(range(n, 2 * n))] + [(i, (i + 1) % n, n + (i + 1) % n, n + i) for i in range(n)]
    return new_obj(name, verts, faces, c, material)


def rrect(w, h, r, n=8, cy=0.0):
    pts = []
    for cx_, cy_, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx_ + r * math.cos(a), cy + cy_ + r * math.sin(a)))
    return pts


def circle(r, n=SEG):
    return [(r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def polar_box(name, centre, az, r, tang, rad, z0, z1, c, material=None, wire=False):
    ob = box(name, (-rad / 2, -tang / 2, 0), (rad / 2, tang / 2, z1 - z0), c, material, wire)
    a = math.radians(az)
    ob.location = (centre.x + r * math.cos(a), centre.y + r * math.sin(a), z0)
    ob.rotation_euler = (0, 0, a)
    return ob


def arc_prism(name, centre, az0, az1, r0, r1, z0, z1, c, material=None, wire=False, n=24):
    pts = [(r1 * math.cos(math.radians(az0 + (az1 - az0) * i / n)), r1 * math.sin(math.radians(az0 + (az1 - az0) * i / n))) for i in range(n + 1)]
    pts += [(r0 * math.cos(math.radians(az1 - (az1 - az0) * i / n)), r0 * math.sin(math.radians(az1 - (az1 - az0) * i / n))) for i in range(n + 1)]
    ob = prism(name, pts, z0, z1, "XY", c, material, origin=centre)
    if wire:
        ob.display_type = "WIRE"
    return ob


def empty(name, loc, c, size=0.3, kind="PLAIN_AXES"):
    e = bpy.data.objects.new(name, None); e.empty_display_type = kind; e.empty_display_size = size; e.location = loc
    c.objects.link(e); return e


# ------------------------------------------------------------------ hatches (shared meshes, one assembly per port)
C_H = coll("Hatches H-01..H-12")
H = P.HATCH
_plate = prism("_hatch plate mesh", circle(P.RING["d_in"] / 2), -0.05, 0.0, "YZ", TMP, M["ring"])
_cut = prism("_cut", rrect(H["w"], H["h"], H["corner_r"]), -0.2, 0.2, "YZ", TMP)
boolean(_plate, _cut); drop(_cut)
_coam = prism("_hatch coaming mesh", rrect(H["coam_w"], H["coam_h"], 0.34), -0.05 - H["depth"], -0.05, "YZ", TMP, M["hatch"])
_cut = prism("_cut", rrect(H["w"], H["h"], H["corner_r"]), -0.5, 0.2, "YZ", TMP)
boolean(_coam, _cut); drop(_cut)
# Detailed door (tools/design/hatch_door.py): seal plane on the cabin face of the coaming, hinged, shown open.
import hatch_door  # noqa: E402
_door = hatch_door.build(TMP, os.path.join(OUT, "textures"), "Hatch door H-1 mesh", W=H["leaf_w"], H=H["leaf_h"], R=0.24)
_hinge = Vector(_door["hinge_local"])
DOOR_OPEN = Matrix.Translation((-0.05 - H["depth"], 0, 0)) @ Matrix.Translation(_hinge) @ Matrix.Rotation(math.radians(95), 4, "Z") @ Matrix.Translation(-_hinge)


def hatch(hid, desc, x, z, az, with_plate=True):
    root = empty(f"{hid} | {desc}", W(x, z, P.PORT_H), C_H, 0.4, "ARROWS")
    root.rotation_euler = (0, 0, math.radians(az))
    parts = [("coaming 1.30x1.80 (opening 1.02x1.52)", _coam), ("door 1.10x1.60 (open 95 deg, into the module)", _door)]
    if with_plate:
        parts.insert(0, ("plate d2.10", _plate))
    for nm, src in parts:
        ob = bpy.data.objects.new(f"{hid} | {nm}", src.data); C_H.objects.link(ob); ob.parent = root
        if src is _door:
            ob.matrix_local = DOOR_OPEN
    return root


for hid, desc, x, z, az, kind in P.ports():
    hatch(hid, desc, x, z, az, with_plate=(hid != "H-10"))


def ring_at(name, x, z, az, c):
    """Berthing ring whose OUTER face is at (x, z); it extends 0.25 back towards the module."""
    a = math.radians(az); n = Vector((math.cos(a), math.sin(a), 0))
    p1 = W(x, z, P.PORT_H); p0 = p1 - n * P.RING["length"]
    return tube(name, p0, p1, P.RING["d_out"] / 2, P.RING["d_in"] / 2, c, M["ring"])


# ------------------------------------------------------------------ A  (reference envelope only)
C_A = coll("A core tower (REFERENCE - append your own model)")
ob = revolve_solid("A | REFERENCE envelope metal d4.40 x 2.60", [(0, 0), (P.A["r_metal"], 0), (P.A["r_metal"], 2.6), (0, 2.6)], W(0, 0, 0), C_A, M["ref"]); ob.display_type = "WIRE"
ob = revolve_solid("A | REFERENCE envelope inflatable d6.50 x 5.20", [(0, 2.6), (P.A["r_infl"], 2.6), (P.A["r_infl"], 7.8), (0, 7.8)], W(0, 0, 0), C_A, M["ref"]); ob.display_type = "WIRE"
ring_at("A | new west port ring d2.40 (replaces the maintenance bench)", -P.A["r_metal"] - P.RING["length"], 0.0, 180.0, C_A)
empty("A | origin (tower centre, L1 floor)", W(0, 0, 0), C_A, 0.6)

# ------------------------------------------------------------------ D hub
C_D = coll("D hub")
dq = P.D; dc = W(dq["c"][0], dq["c"][1], 0)


def head_profile(r, y_lo, y_hi, head, n=16):
    pts = [(0.0, y_lo - head)]
    pts += [(r * math.sin(math.pi / 2 * i / n), y_lo - head * math.cos(math.pi / 2 * i / n)) for i in range(1, n + 1)]
    pts += [(r * math.cos(math.pi / 2 * i / n), y_hi + head * math.sin(math.pi / 2 * i / n)) for i in range(0, n)]
    pts += [(0.0, y_hi + head)]
    return pts


d_hull = revolve_solid("D | hull d4.40 (shell 0.10)", head_profile(dq["r_out"], -dq["floor_t"], dq["h_clear"] + dq["ceil_t"], dq["head"]), dc, C_D, M["hull"])
_in = revolve_solid("_in", head_profile(dq["r_in"], -dq["floor_t"], dq["h_clear"] + dq["ceil_t"], dq["head"] - 0.10), dc, TMP)
boolean(d_hull, _in); drop(_in)
for key, az in dq["ports"].items():
    a = math.radians(az); n = Vector((math.cos(a), math.sin(a), 0)); c0 = dc + Vector((0, 0, P.PORT_H))
    _cut = tube("_cut", c0 + n * 1.2, c0 + n * 2.6, P.RING["d_in"] / 2, 0.0, TMP); boolean(d_hull, _cut); drop(_cut)
    px, pz = P.pol(dq["c"], az, dq["r_out"] + P.RING["length"])
    ring_at(f"D | port ring {key}", px, pz, az, C_D)
revolve_solid("D | floor (top at 0.00)", [(0, -dq["floor_t"]), (dq["r_in"] - 0.005, -dq["floor_t"]), (dq["r_in"] - 0.005, 0), (0, 0)], dc, C_D, M["floor"])
revolve_solid("D | ceiling panel (underside 2.40)", [(0, dq["h_clear"]), (dq["r_in"] - 0.005, dq["h_clear"]), (dq["r_in"] - 0.005, dq["h_clear"] + dq["ceil_t"]), (0, dq["h_clear"] + dq["ceil_t"])], dc, C_D, M["part"])
C_DE = coll("D equipment (envelopes)")
for name, az, r, tang, rad, hgt, y0 in P.D_EQUIP:
    polar_box(f"D | {name}", dc, az, r, tang, rad, y0, y0 + hgt, C_DE, M["equip"], wire=True)
empty("D | centre", dc, C_D, 0.6)

# ------------------------------------------------------------------ tunnels
C_T = coll("T tunnels")
for name, x0, z0, x1, z1 in P.tunnels():
    p0 = W(x0, z0, P.PORT_H); p1 = W(x1, z1, P.PORT_H)
    tube(f"{name} | tunnel d2.30/2.10", p0, p1, P.TUNNEL["d_out"] / 2, P.TUNNEL["d_in"] / 2, C_T, M["tunnel"])
    fw = P.TUNNEL["floor_w"] / 2
    if abs(z1 - z0) < 1e-6:
        wbox(f"{name} | floor insert 1.08", min(x0, x1), max(x0, x1), -0.05, 0.0, z0 + fw, z0 - fw, C_T, M["floor"])
    else:
        wbox(f"{name} | floor insert 1.08", x0 - fw, x0 + fw, -0.05, 0.0, max(z0, z1), min(z0, z1), C_T, M["floor"])
sx, sz = dq["c"][0], dq["c"][1] + dq["r_out"] + P.RING["length"] + P.ROVER_STUB + P.RING["length"]
ring_at("T-DS | end ring (rover / logistics port)", sx, sz, 270.0, C_T)

# ------------------------------------------------------------------ B engineering
S = P.ST; bq = P.B
C_BU = coll("B-U utility segment"); C_BM = coll("B-M maintenance + EVA segment"); C_BE = coll("B equipment (envelopes)"); C_BX = coll("B external")
axis_o = Vector((bq["x"], 0.0, bq["axis_y"]))


def b_segment(name, c, z_c0, z_cy0, z_cy1, z_c1):
    y = [-z_c0, -z_cy0, -z_cy1, -z_c1]              # Blender Y (north) of: cone start, cyl start, cyl end, cone end
    ro, ri = bq["r_out"], bq["r_in"]; ko, ki = P.RING["d_out"] / 2, P.RING["d_in"] / 2
    hull = revolve_solid(f"{name} | hull d4.40 (shell 0.10)", [(0, y[0]), (ko, y[0]), (ro, y[1]), (ro, y[2]), (ko, y[3]), (0, y[3])], axis_o, c, M["hull"], axis="Y")
    _in = revolve_solid("_in", [(0, y[0] - 0.02), (ki, y[0] - 0.02), (ki, y[0]), (ri, y[1]), (ri, y[2]), (ki, y[3]), (ki, y[3] + 0.02), (0, y[3] + 0.02)], axis_o, TMP, axis="Y")
    boolean(hull, _in); drop(_in)
    fh = bq["floor_half"]; fr = P.TUNNEL["floor_w"] / 2
    prism(f"{name} | floor (top at 0.00, width 3.79)", [(-fr, y[0]), (-fh, y[1]), (-fh, y[2]), (-fr, y[3]), (fr, y[3]), (fh, y[2]), (fh, y[1]), (fr, y[0])], -0.06, 0.0, "XY", c, M["floor"], origin=Vector((bq["x"], 0, 0)))
    return hull


b_segment("B-U", C_BU, S["B-U cone S start"], S["B-U cyl S"], S["B-U cyl N"], S["B-U cone N end"])
b_segment("B-M", C_BM, S["B-M cone S start"], S["B-M cyl S"], S["B-M cyl N"], S["B-M cone N end"])
ring_at("B-U | south ring", bq["x"], S["B-U ring S face"], 270.0, C_BU)
ring_at("B-U | north ring", bq["x"], S["B-U ring N face"], 90.0, C_BU)
ring_at("B-M | south ring", bq["x"], S["B-U ring N face"], 270.0, C_BM)
ring_at("B-M | north ring (EV)", bq["x"], S["EV ring face"], 90.0, C_BM)


def b_section_pts(n=40):
    """Cross-section of the cabin above the floor: (x, z) points, x relative to the axis, z = height above floor."""
    ri = bq["r_in"] - 0.01; t0 = math.asin(bq["axis_y"] / bq["r_in"])
    pts = [(-bq["floor_half"] + 0.01, 0.0), (bq["floor_half"] - 0.01, 0.0)]
    for i in range(n + 1):
        a = -t0 + (math.pi + 2 * t0) * i / n
        pts.append((ri * math.cos(a), bq["axis_y"] + ri * math.sin(a)))
    return pts


for nm, zs, t, kind in P.B_PARTITIONS:
    c = C_BU if nm.startswith(("P1", "P2")) else C_BM
    ob = prism(f"B | {nm}", b_section_pts(), -zs, -zs + t, "XZ", c, M["part"] if kind == "door" else M["hull"], origin=Vector((bq["x"], 0, 0)))
    if kind == "door":
        _cut = box("_cut", (bq["x"] - P.B_DOOR["w"] / 2, -zs - 0.1, -0.01), (bq["x"] + P.B_DOOR["w"] / 2, -zs + t + 0.1, P.B_DOOR["h"]), TMP)
    else:
        _cut = prism("_cut", rrect(H["w"], H["h"], H["corner_r"]), -zs - 0.1, -zs + t + 0.1, "XZ", TMP, origin=Vector((bq["x"], 0, P.PORT_H)))
    boolean(ob, _cut); drop(_cut)
for name, room, x0, x1, y0, y1, zs, zn in P.b_equip_boxes():
    wbox(name + " (%.2fx%.2fx%.2f)" % (zs - zn, x1 - x0, y1 - y0), x0, x1, y0, y1, zs, zn, C_BE, M["equip"], wire=True)
for nm, x0, z0, x1, z1, y0, y1 in P.B_EXTERNAL:
    if "tank" in nm:
        tube(f"B ext | {nm}", W((x0 + x1) / 2, z0, (y0 + y1) / 2), W((x0 + x1) / 2, z1, (y0 + y1) / 2), 0.45, 0.0, C_BX, M["ring"], seg=32)
    else:
        wbox(f"B ext | {nm}", x0, x1, y0, y1, z0, z1, C_BX, M["tunnel"])
wbox("B ext | EVA porch 2.40x2.40 (grating at grade)", bq["x"] - P.PORCH["width"] / 2, bq["x"] + P.PORCH["width"] / 2, -0.08, 0.0, S["EV ring face"], S["EV ring face"] - P.PORCH["length"], C_BX, M["floor"])
for rid, nm, zt, zs, zn in P.B_ROOMS:
    empty(f"B-{rid} | room centre: {nm}", W(bq["x"], (zs + zn) / 2, 0), C_BU if rid.startswith("U") else C_BM, 0.3)

# ------------------------------------------------------------------ C habitation
C_C = coll("C habitation"); C_CE = coll("C equipment (envelopes)"); C_CX = coll("C external (berm)")
cq = P.C; cc = W(cq["c"][0], cq["c"][1], 0)


def c_profile(t, n=24):
    a = cq["r_in"] - cq["cap_r"]; b0 = -cq["bottom"]; b1 = cq["top"] - cq["wall_top"]
    pts = [(0.0, cq["bottom"] - t)]
    pts += [(cq["cap_r"] + (a + t) * math.sin(math.pi / 2 * i / n), -(b0 + t) * math.cos(math.pi / 2 * i / n)) for i in range(n + 1)]
    pts += [(cq["cap_r"] + (a + t) * math.cos(math.pi / 2 * i / n), cq["wall_top"] + (b1 + t) * math.sin(math.pi / 2 * i / n)) for i in range(n + 1)]
    pts += [(0.0, cq["top"] + t)]
    return pts


c_hull = revolve_solid("C | inflatable shell d7.50 (0.40 thick)", c_profile(cq["shell_t"]), cc, C_C, M["infl"])
_in = revolve_solid("_in", c_profile(0.0), cc, TMP); boolean(c_hull, _in); drop(_in)
c0 = cc + Vector((0, 0, P.PORT_H))
_cut = tube("_cut", c0 + Vector((2.6, 0, 0)), c0 + Vector((4.4, 0, 0)), P.RING["d_in"] / 2, 0.0, TMP); boolean(c_hull, _cut); drop(_cut)
for nm, az, w, y0, y1 in P.C_WINDOWS:
    a = math.radians(az)
    _cut = box("_cut", (cq["r_in"] - 0.3, -w / 2, y0), (cq["r_out"] + 0.3, w / 2, y1), TMP); _cut.rotation_euler = (0, 0, a); _cut.location = cc
    boolean(c_hull, _cut); drop(_cut)
    g = box(f"C | window glass {nm} 1.00x0.60", (cq["r_in"] + 0.15, -w / 2, y0), (cq["r_in"] + 0.20, w / 2, y1), C_C, M["glass"]); g.rotation_euler = (0, 0, a); g.location = cc
tube("C | rigid port frame liner (through the soft goods)", c0 + Vector((cq["r_in"] - 0.05, 0, 0)), c0 + Vector((cq["r_out"], 0, 0)), P.RING["d_in"] / 2 + 0.06, P.RING["d_in"] / 2, C_C, M["ring"])
ring_at("C | east port ring", cq["c"][0] + cq["r_out"] + P.RING["length"], 0.0, 0.0, C_C)
wbox("C | port throat floor 1.08", cq["c"][0] + cq["r_in"] - 0.05, cq["c"][0] + cq["r_out"] + P.RING["length"], -0.05, 0.0, P.TUNNEL["floor_w"] / 2, -P.TUNNEL["floor_w"] / 2, C_C, M["floor"])
revolve_solid("C | deck 1 floor (top at 0.00)", [(0, -0.08), (cq["r_in"] - 0.01, -0.08), (cq["r_in"] - 0.01, 0), (0, 0)], cc, C_C, M["floor"])
deck2 = revolve_solid("C | deck 2 floor cassette (2.40..2.60)", [(0, cq["deck2"] - cq["deck_t"]), (cq["r_in"] - 0.01, cq["deck2"] - cq["deck_t"]), (cq["r_in"] - 0.01, cq["deck2"]), (0, cq["deck2"])], cc, C_C, M["floor"])
lo = P.C_LADDER["opening"]
_cut = box("_cut", (cc.x + lo[0], cc.y - lo[3], 2.0), (cc.x + lo[2], cc.y - lo[1], 3.0), TMP); boolean(deck2, _cut); drop(_cut)
for az in P.C_POSTS_AZ:
    a = math.radians(az); p = cc + Vector((cq["lobby_r"] * math.cos(a), cq["lobby_r"] * math.sin(a), 0))
    revolve_solid(f"C | lobby post az{az:.0f}", [(0, 0), (0.05, 0), (0.05, cq["clear1"]), (0, cq["clear1"])], p, C_C, M["hull"], seg=12)
    rm = (cq["room_r0"] + cq["r_in"]) / 2
    polar_box(f"C | partition az{az:.0f} (0.08, acoustic)", cc, az, rm, cq["part_t"], cq["r_in"] - cq["room_r0"] - 0.02, 0.0, cq["clear1"], C_C, M["part"])
for nm, typ, a0, a1 in P.C_DECK1:
    if typ == "corridor":
        continue
    w = {"crew_quarters": P.C_DOORS["CQ"], "hygiene": P.C_DOORS["Hygiene"], "uwms": P.C_DOORS["UWMS"]}[typ]
    half = math.degrees(math.asin(w / 2 / cq["room_r0"])); am = (a0 + a1) / 2
    arc_prism(f"C | lobby wall {nm} a", cc, a0, am - half, cq["room_r0"] - 0.025, cq["room_r0"] + 0.025, 0.0, cq["clear1"], C_C, M["part"], n=8)
    arc_prism(f"C | lobby wall {nm} b", cc, am + half, a1, cq["room_r0"] - 0.025, cq["room_r0"] + 0.025, 0.0, cq["clear1"], C_C, M["part"], n=8)
    arc_prism(f"C | door header {nm} (door {w:.2f} x 1.95)", cc, am - half, am + half, cq["room_r0"] - 0.025, cq["room_r0"] + 0.025, 1.95, cq["clear1"], C_C, M["part"], n=4)
for name, deck, az, r, tang, rad, hgt, y0 in P.C_EQUIP:
    base = 0.0 if deck == 1 else cq["deck2"]
    if "table" in name:
        revolve_solid(f"C{deck} | {name}", [(0, base + hgt - 0.05), (tang / 2, base + hgt - 0.05), (tang / 2, base + hgt), (0, base + hgt)], cc + Vector((r * math.cos(math.radians(az)), r * math.sin(math.radians(az)), 0)), C_CE, M["equip"], seg=32).display_type = "WIRE"
    else:
        polar_box(f"C{deck} | {name}", cc, az, r, tang, rad, base + y0, base + y0 + hgt, C_CE, M["water"] if "canopy" in name else M["equip"], wire=True)
for name, deck, a0, a1, ra, rb, hgt, y0 in P.C_ARCS:
    base = 0.0 if deck == 1 else cq["deck2"]
    arc_prism(f"C{deck} | {name}", cc, a0, a1, ra, rb, base + y0, base + y0 + hgt, C_CE, M["equip"], wire=True)
L = P.C_LADDER
run = L["z_foot"] - L["z_top"]; length = math.hypot(run, cq["deck2"])
lad = box("C | ship ladder 70 deg, width 0.60", (-L["width"] / 2, -length / 2, -0.04), (L["width"] / 2, length / 2, 0.04), C_C, M["ladder"])
lad.location = cc + Vector((L["x"], -(L["z_foot"] + L["z_top"]) / 2, cq["deck2"] / 2)); lad.rotation_euler = (math.atan2(cq["deck2"], run), 0, 0)
empty("Landing | C deck 1", cc + Vector((L["landing1"][0], -L["landing1"][2], L["landing1"][1])), C_C, 0.25, "SPHERE")
empty("Landing | C deck 2", cc + Vector((L["landing2"][0], -L["landing2"][2], L["landing2"][1])), C_C, 0.25, "SPHERE")
empty("C | centre", cc, C_C, 0.6)
b = P.BERM
revolve_sector("C ext | regolith berm (crest 3.00, slope 1:1.5)", [(b["r0"], 0), (b["r_toe"], 0), (b["r_crest"], b["height"]), (b["r0"], b["height"])], cc, b["az0"], b["az1"], C_CX, M["rego"])

# ------------------------------------------------------------------ finish: remove helpers, self-check, save
for ob in list(TMP.objects):
    drop(ob)
bpy.data.collections.remove(TMP)


def bbox(name):
    ob = bpy.data.objects[name]
    pts = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    return [min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)]


bpy.context.view_layer.update()
checks = [
    ("D | hull d4.40 (shell 0.10)", "x", P.D["c"][0] - 2.2, P.D["c"][0] + 2.2), ("D | hull d4.40 (shell 0.10)", "z", P.D["y_bottom"], P.D["y_top"]),
    ("B-U | hull d4.40 (shell 0.10)", "y", -S["B-U cone S start"], -S["B-U cone N end"]), ("B-U | hull d4.40 (shell 0.10)", "z", bq["y_bottom"], bq["y_top"]),
    ("B-M | hull d4.40 (shell 0.10)", "y", -S["B-M cone S start"], -S["B-M cone N end"]),
    ("C | inflatable shell d7.50 (0.40 thick)", "x", cq["c"][0] - 3.75, cq["c"][0] + 3.75), ("C | inflatable shell d7.50 (0.40 thick)", "z", cq["y_bottom_out"], cq["y_top_out"]),
]
ok = True
for name, ax_, lo_, hi_ in checks:
    mn, mx = bbox(name); i = "xyz".index(ax_)
    good = abs(mn[i] - lo_) < 0.02 and abs(mx[i] - hi_) < 0.02
    ok = ok and good
    print("CHECK %s  %s %s: %.3f..%.3f (expect %.3f..%.3f)" % ("ok  " if good else "FAIL", name[:30], ax_, mn[i], mx[i], lo_, hi_))
n_mesh = sum(1 for o in bpy.data.objects if o.type == "MESH")
print("OBJECTS meshes=%d empties=%d  self-check=%s" % (n_mesh, sum(1 for o in bpy.data.objects if o.type == "EMPTY"), "PASS" if ok else "FAIL"))

blend = os.path.join(OUT, "base_camp_design_reference.blend")
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
print("WROTE", blend)
glb = os.path.join(OUT, "base_camp_design_reference.glb")
bpy.ops.export_scene.gltf(filepath=glb, export_format="GLB", export_yup=True, export_apply=True)
print("WROTE", glb)

# ------------------------------------------------------------------ preview renders (best effort)
try:
    prev = os.path.join(ROOT, "docs", "design")
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"; scene.display.shading.color_type = "MATERIAL"; scene.display.shading.show_cavity = True
    scene.render.resolution_x = 2000; scene.render.resolution_y = 1400; scene.render.film_transparent = False
    world = bpy.data.worlds.new("w"); scene.world = world; world.color = (1, 1, 1)
    cam_d = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("Preview camera", cam_d); scene.collection.objects.link(cam); scene.camera = cam
    for o in bpy.data.objects:
        if o.display_type == "WIRE" and o.type == "MESH":
            o.display_type = "SOLID"
    target = Vector((-8.5, 9.0, 1.0))

    def look(loc, tgt, ortho=None):
        cam.location = loc
        d = tgt - loc; cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
        if ortho:
            cam_d.type = "ORTHO"; cam_d.ortho_scale = ortho
        else:
            cam_d.type = "PERSP"; cam_d.lens = 35

    look(Vector((14.0, -22.0, 20.0)), target); scene.render.filepath = os.path.join(prev, "R-01_reference_model_exterior.png"); bpy.ops.render.render(write_still=True)
    # cutaway: hide shells, tunnels, ceilings and the berm, look straight down
    for o in bpy.data.objects:
        n = o.name
        if any(k in n for k in ("hull", "shell", "tunnel d", "ceiling", "berm", "REFERENCE", "deck 2", "Radiator", "liner", "door header")) or n.startswith("C2 |") or "window" in n:
            o.hide_render = True
    look(Vector((-8.5, 9.0, 60.0)), Vector((-8.5, 9.0, 0.0)), ortho=34.0); cam.rotation_euler = (0, 0, 0)
    scene.render.resolution_x = 2000; scene.render.resolution_y = 2000
    scene.render.filepath = os.path.join(prev, "R-02_reference_model_plan_cutaway.png"); bpy.ops.render.render(write_still=True)
    print("RENDERED previews")
except Exception as exc:  # preview only; the model is already saved
    print("PREVIEW skipped:", exc)

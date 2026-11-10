# -*- coding: utf-8 -*-
"""Procedural detailed hatch door (Blender module, used by tools/build_hatch_door.py and build_design_blend.py).

Design language follows the ISS CBM hatch: smooth pressure skin with a central viewport, crank handle,
kick latch and equalization valve on one face; radial ribs, central gear ring, spider plate and
push-rod latches inside a machined perimeter frame on the other.

Local frame of the returned object (door closed):
  x = 0 is the seal plane. +X points at the bulkhead / tunnel (smooth skin side, seals on the perimeter).
  -X is the cabin side (frame, ribs, latch mechanism), depth about 0.13 m with handles.
  Y = width, Z = height, origin at the centre of the door.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector


# ------------------------------------------------------------------ 2D helpers
def rr_pts(w, h, r, n=10):
    pts = []
    for cy, cz, a0 in ((w / 2 - r, h / 2 - r, 0), (-w / 2 + r, h / 2 - r, 90), (-w / 2 + r, -h / 2 + r, 180), (w / 2 - r, -h / 2 + r, 270)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cy + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def inside_rr(y, z, w, h, r):
    ay, az = abs(y), abs(z)
    if ay > w / 2 or az > h / 2:
        return False
    if ay <= w / 2 - r or az <= h / 2 - r:
        return True
    return (ay - (w / 2 - r)) ** 2 + (az - (h / 2 - r)) ** 2 <= r * r


def rr_ray(w, h, r, ang):
    """Distance from the centre to the rounded-rectangle boundary along direction ang (radians)."""
    lo, hi = 0.0, max(w, h)
    c, s = math.cos(ang), math.sin(ang)
    for _ in range(40):
        mid = (lo + hi) / 2
        if inside_rr(c * mid, s * mid, w, h, r):
            lo = mid
        else:
            hi = mid
    return lo


def circle_pts(r, n):
    return [(r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n)) for i in range(n)]


# ------------------------------------------------------------------ builder
class Builder:
    def __init__(self, collection, tex_dir, prefix="hatch"):
        self.coll = collection
        self.tex_dir = tex_dir
        self.parts = []
        self.xf = Matrix.Identity(4)
        self.prefix = prefix
        self.M = self._materials()

    # materials -----------------------------------------------------
    def _mat(self, name, rgb, rough, metal=0.0, alpha=1.0, image=None, coat=0.0):
        full = "Hatch " + name
        m = bpy.data.materials.get(full)
        if m:
            return m
        m = bpy.data.materials.new(full)
        m.use_nodes = True
        m.diffuse_color = (rgb[0], rgb[1], rgb[2], alpha)
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        if coat and "Coat Weight" in b.inputs:
            b.inputs["Coat Weight"].default_value = coat
        if alpha < 1.0:
            b.inputs["Alpha"].default_value = alpha
            try:
                m.surface_render_method = "BLENDED"
            except Exception:
                m.blend_method = "BLEND"
        if image:
            path = os.path.join(self.tex_dir, image)
            if os.path.isfile(path):
                img = bpy.data.images.load(path, check_existing=True)
                tex = m.node_tree.nodes.new("ShaderNodeTexImage"); tex.image = img
                m.node_tree.links.new(tex.outputs["Color"], b.inputs["Base Color"])
        return m

    def _materials(self):
        return {
            "white": self._mat("white paint", (0.86, 0.87, 0.85), 0.42, 0.0, coat=0.25),
            "alu": self._mat("machined aluminium", (0.78, 0.79, 0.80), 0.28, 1.0),
            "alu_dark": self._mat("anodised aluminium", (0.42, 0.44, 0.47), 0.4, 1.0),
            "steel": self._mat("steel", (0.62, 0.63, 0.65), 0.22, 1.0),
            "nickel": self._mat("pale linkage", (0.62, 0.66, 0.58), 0.38, 0.75),
            "rubber": self._mat("seal rubber", (0.03, 0.03, 0.035), 0.75),
            "black": self._mat("black knob", (0.05, 0.05, 0.055), 0.45),
            "tan": self._mat("handle tan", (0.78, 0.63, 0.36), 0.5, coat=0.2),
            "strap": self._mat("strap", (0.74, 0.74, 0.70), 0.85),
            "glass": self._mat("glass", (0.04, 0.07, 0.09), 0.06, 0.0, alpha=0.30),
            "red": self._mat("red", (0.75, 0.10, 0.08), 0.5),
            "p_open": self._mat("placard opening", (1, 1, 1), 0.6, image="hatch_placard_opening.png"),
            "p_close": self._mat("placard closing", (1, 1, 1), 0.6, image="hatch_placard_closing.png"),
            "p_warn": self._mat("label warning", (1, 1, 1), 0.6, image="hatch_label_warning.png"),
            "p_exit": self._mat("label exit", (1, 1, 1), 0.6, image="hatch_label_exit.png"),
            "p_ind": self._mat("label indicator", (1, 1, 1), 0.6, image="hatch_label_indicator.png"),
        }

    # part plumbing --------------------------------------------------
    def add(self, name, bm, mat, bevel=0.0, smooth=False, segments=2):
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.transform(self.xf)
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me); bm.free()
        ob = bpy.data.objects.new(self.prefix + " | " + name, me)
        self.coll.objects.link(ob)
        me.materials.append(self.M[mat] if isinstance(mat, str) else mat)
        ob["_smooth"] = bool(smooth)
        if bevel > 0:
            mod = ob.modifiers.new("bevel", "BEVEL")
            mod.width = bevel; mod.segments = segments; mod.limit_method = "ANGLE"; mod.angle_limit = math.radians(40)
        self.parts.append(ob)
        return ob

    def box(self, name, size, loc, mat, bevel=0.0015, rot=None):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        m = Matrix.Translation(Vector(loc)) @ (rot if rot is not None else Matrix.Identity(4)) @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
        bm.transform(m)
        return self.add(name, bm, mat, bevel)

    def cyl(self, name, r, depth, loc, mat, axis="X", seg=32, bevel=0.0, r2=None, smooth=True):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=depth)
        rot = {"X": Matrix.Rotation(math.pi / 2, 4, "Y"), "Y": Matrix.Rotation(-math.pi / 2, 4, "X"), "Z": Matrix.Identity(4)}[axis]
        bm.transform(Matrix.Translation(Vector(loc)) @ rot)
        return self.add(name, bm, mat, bevel, smooth=smooth)

    def cyl_between(self, name, p0, p1, r, mat, seg=16):
        p0, p1 = Vector(p0), Vector(p1)
        d = p1 - p0
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r, depth=d.length)
        q = Vector((0, 0, 1)).rotation_difference(d.normalized())
        bm.transform(Matrix.Translation((p0 + p1) / 2) @ q.to_matrix().to_4x4())
        return self.add(name, bm, mat, 0.0, smooth=True)

    def prism(self, name, loop, x0, x1, mat, hole=None, bevel=0.0, smooth=False, segments=2):
        """Loop(s) of (y, z) points extruded from x0 to x1. With `hole` (same point count) the result is a ring."""
        bm = bmesh.new()
        n = len(loop)
        o0 = [bm.verts.new((x0, y, z)) for y, z in loop]; o1 = [bm.verts.new((x1, y, z)) for y, z in loop]
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((o0[i], o0[j], o1[j], o1[i]))
        if hole is None:
            bm.faces.new(o0); bm.faces.new(o1)
        else:
            assert len(hole) == n
            i0 = [bm.verts.new((x0, y, z)) for y, z in hole]; i1 = [bm.verts.new((x1, y, z)) for y, z in hole]
            for i in range(n):
                j = (i + 1) % n
                bm.faces.new((i0[i], i0[j], i1[j], i1[i]))
                bm.faces.new((o0[i], o0[j], i0[j], i0[i]))
                bm.faces.new((o1[i], o1[j], i1[j], i1[i]))
        return self.add(name, bm, mat, bevel, smooth=smooth, segments=segments)

    def label(self, name, w, h, loc, mat, facing=1, roll=0.0):
        """Textured quad in the YZ plane, readable from +X (facing=1) or from -X (facing=-1)."""
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new("UVMap")
        hw, hh = w / 2, h / 2
        if facing > 0:
            co = [(0, -hw, -hh), (0, hw, -hh), (0, hw, hh), (0, -hw, hh)]
        else:
            co = [(0, hw, -hh), (0, -hw, -hh), (0, -hw, hh), (0, hw, hh)]
        vs = [bm.verts.new(c) for c in co]
        f = bm.faces.new(vs)
        for lp, t in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            lp[uv].uv = t
        bm.transform(Matrix.Translation(Vector(loc)) @ Matrix.Rotation(roll, 4, "X"))
        bm.transform(self.xf)
        me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
        ob = bpy.data.objects.new(self.prefix + " | " + name, me); self.coll.objects.link(ob)
        me.materials.append(self.M[mat]); ob["_smooth"] = False
        self.parts.append(ob)
        return ob

    def finish(self, name):
        """Apply modifiers, set shading, join everything into one object."""
        bpy.context.view_layer.update()
        dg = bpy.context.evaluated_depsgraph_get()
        for ob in self.parts:
            if ob.modifiers:
                me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
                old = ob.data; ob.modifiers.clear(); ob.data = me; bpy.data.meshes.remove(old)
            me = ob.data
            if ob.get("_smooth") or True:
                for p in me.polygons:
                    p.use_smooth = True
                try:
                    me.set_sharp_from_angle(angle=math.radians(38))
                except Exception:
                    pass
            if "_smooth" in ob:
                del ob["_smooth"]
        target = self.parts[0]
        with bpy.context.temp_override(active_object=target, selected_editable_objects=self.parts, selected_objects=self.parts, object=target):
            bpy.ops.object.join()
        target.name = name; target.data.name = name
        self.parts = [target]
        return target


# ------------------------------------------------------------------ the door
def build(collection, tex_dir, name="Hatch door H-1", W=1.10, H=1.60, R=0.24, side_latches=3, end_latches=2, prefix="hatch"):
    b = Builder(collection, tex_dir, prefix)
    FR = 0.070          # frame band width
    D = 0.090           # frame depth (cabin side)
    SK = 0.012          # skin thickness
    sy, sz = W / 1.10, H / 1.60       # placement scale relative to the H-1 layout
    s = min(W, H) / 1.10              # feature scale (hub, gear) follows the short side

    # --- pressure skin (smooth side) and seals
    b.prism("skin", rr_pts(W, H, R, 14), -SK, 0.0, "white", bevel=0.004, segments=3)
    for k, (inset, wd) in enumerate(((0.014, 0.010), (0.034, 0.008))):
        b.prism(f"seal {k+1}", rr_pts(W - 2 * inset, H - 2 * inset, R - inset, 14), 0.0, 0.004, "rubber",
                hole=rr_pts(W - 2 * (inset + wd), H - 2 * (inset + wd), R - inset - wd, 14), bevel=0.0015)
    b.prism("edge gasket", rr_pts(W + 0.006, H + 0.006, R + 0.003, 14), -0.010, -0.002, "rubber", hole=rr_pts(W - 0.004, H - 0.004, R - 0.002, 14))

    # --- machined perimeter frame with lightening pockets
    frame = b.prism("frame", rr_pts(W - 0.006, H - 0.006, R - 0.003, 14), -D, -SK, "alu", hole=rr_pts(W - 2 * FR, H - 2 * FR, R - FR, 14), bevel=0.003, segments=3)
    cut = bmesh.new()
    def pocket(cy, cz, ly, lz):
        m = Matrix.Translation((-(D + SK) / 2 - 0.004, cy, cz)) @ Matrix.Diagonal((D - SK - 0.034, ly, lz, 1.0))
        geo = bmesh.ops.create_cube(cut, size=1.0); bmesh.ops.transform(cut, matrix=m, verts=geo["verts"])
    ny = max(3, int(round((W - 2 * R) / 0.13))); nz = max(3, int(round((H - 2 * R) / 0.13)))
    for i in range(ny):
        y = -(W / 2 - R) + (W - 2 * R) * (i + 0.5) / ny
        for sgn in (-1, 1):
            pocket(y, sgn * (H / 2 - 0.003), (W - 2 * R) / ny - 0.035, 0.036)
    for i in range(nz):
        z = -(H / 2 - R) + (H - 2 * R) * (i + 0.5) / nz
        for sgn in (-1, 1):
            pocket(sgn * (W / 2 - 0.003), z, 0.036, (H - 2 * R) / nz - 0.035)
    cme = bpy.data.meshes.new("_cut"); cut.to_mesh(cme); cut.free()
    cob = bpy.data.objects.new("_cut", cme); collection.objects.link(cob)
    mod = frame.modifiers.new("pockets", "BOOLEAN"); mod.operation = "DIFFERENCE"; mod.object = cob; mod.solver = "EXACT"
    frame.modifiers.move(len(frame.modifiers) - 1, 0)
    # frame bolts and white inspection marks on the cabin face
    per = rr_pts(W - FR, H - FR, R - FR / 2, 6)
    step = max(1, len(per) // 34)
    for i in range(0, len(per), step):
        y, z = per[i]
        b.cyl("frame bolt", 0.0055, 0.004, (-D - 0.002, y, z), "steel", seg=10)

    # --- inner pan: hub plate and radial ribs
    hub_r = 0.175 * s
    iw, ih, ir = W - 2 * FR, H - 2 * FR, R - FR
    n_ribs = 32
    for i in range(n_ribs):
        a = 2 * math.pi * (i + 0.5) / n_ribs
        r1 = rr_ray(iw, ih, ir, a) - 0.004
        if r1 < hub_r + 0.05:
            continue
        c, sn = math.cos(a), math.sin(a)
        t = 0.0045
        h0, h1 = 0.040, 0.016
        bm = bmesh.new()
        def v(r, off, x):
            return bm.verts.new((x, c * r - sn * off, sn * r + c * off))
        a0, a1, a2, a3 = v(hub_r, -t, -SK), v(hub_r, t, -SK), v(r1, t, -SK), v(r1, -t, -SK)
        b0, b1, b2, b3 = v(hub_r, -t * 0.6, -SK - h0), v(hub_r, t * 0.6, -SK - h0), v(r1, t * 0.6, -SK - h1), v(r1, -t * 0.6, -SK - h1)
        for f in ((a0, a1, a2, a3), (b0, b1, b2, b3), (a0, a1, b1, b0), (a2, a3, b3, b2), (a1, a2, b2, b1), (a3, a0, b0, b3)):
            bm.faces.new(f)
        b.add("rib", bm, "white")
    b.prism("hub plate", circle_pts(hub_r + 0.01, 64), -SK - 0.046, -SK, "white", hole=circle_pts(0.100 * s, 64), bevel=0.003, smooth=True)
    # --- viewport
    win_r = 0.088 * s
    b.prism("window tube", circle_pts(win_r + 0.012, 64), -0.094, 0.004, "black", hole=circle_pts(win_r, 64), smooth=True)
    b.cyl("glass outer", win_r, 0.006, (0.010, 0, 0), "glass", seg=48)
    b.cyl("glass inner", win_r, 0.006, (-0.092, 0, 0), "glass", seg=48)
    b.prism("bezel outer", circle_pts(0.150 * s, 64), 0.0, 0.020, "alu", hole=circle_pts(win_r, 64), bevel=0.004, smooth=True, segments=3)
    b.prism("bezel outer lip", circle_pts(0.112 * s, 64), 0.018, 0.026, "alu_dark", hole=circle_pts(win_r - 0.004, 64), bevel=0.002, smooth=True)
    for k in range(4):
        a = math.radians(45 + 90 * k)
        b.cyl("bezel boss", 0.017 * s, 0.010, (0.024, 0.134 * s * math.cos(a), 0.134 * s * math.sin(a)), "alu", seg=20, bevel=0.002)
        b.cyl("bezel boss bolt", 0.008 * s, 0.006, (0.031, 0.134 * s * math.cos(a), 0.134 * s * math.sin(a)), "steel", seg=6, smooth=False)
    for k in range(12):
        a = math.radians(15 + 30 * k)
        b.cyl("bezel screw", 0.0045, 0.004, (0.021, 0.128 * s * math.cos(a), 0.128 * s * math.sin(a)), "steel", seg=8)
    b.label("indicator strip", 0.16 * s, 0.020 * s, (0.0265, 0.0, -0.100 * s), "p_ind", facing=1)
    # --- cabin side: gear ring, spider, inner bezel
    x_gear = -SK - 0.046
    teeth = 96
    gear = []
    for i in range(teeth):
        for f, rr in ((0.00, 0.196), (0.30, 0.206), (0.70, 0.206), (1.00, 0.196)):
            a = 2 * math.pi * (i + f * 0.55 + 0.2) / teeth
            gear.append((rr * s * math.cos(a), rr * s * math.sin(a)))
    b.prism("gear ring", gear, x_gear - 0.011, x_gear, "nickel", hole=circle_pts(0.166 * s, len(gear)), bevel=0.0008)
    x_sp = x_gear - 0.011
    b.prism("spider ring", circle_pts(0.158 * s, 64), x_sp - 0.008, x_sp, "nickel", hole=circle_pts(0.108 * s, 64), bevel=0.0015, smooth=True)
    b.prism("inner bezel", circle_pts(0.118 * s, 64), x_sp - 0.016, x_sp - 0.004, "white", hole=circle_pts(win_r, 64), bevel=0.003, smooth=True)
    for k in range(8):
        a = math.radians(22.5 + 45 * k)
        b.cyl("spider bolt", 0.006, 0.005, (x_sp - 0.010, 0.133 * s * math.cos(a), 0.133 * s * math.sin(a)), "steel", seg=8)
    # pinion + small reduction gear next to the ring (driven by the crank)
    crank_z = 0.0 if side_latches % 2 == 0 else -0.5 * (ih - 2 * ir - 0.10) / side_latches
    crank_z = max(crank_z, -0.20 * s)
    pin_y = -math.sqrt(max(1e-6, (0.264 * s) ** 2 - crank_z ** 2))
    pin = (x_gear - 0.006, pin_y, crank_z)
    b.cyl("pinion", 0.058 * s, 0.010, pin, "nickel", seg=28, bevel=0.001)
    b.cyl("pinion hub", 0.026 * s, 0.020, (pin[0] - 0.006, pin[1], pin[2]), "steel", seg=20, bevel=0.002)

    # --- latches around the perimeter, push rods from the spider
    spots = []
    for k in range(side_latches):
        z = (ih - 2 * ir - 0.10) * ((k + 0.5) / side_latches - 0.5) if side_latches > 1 else 0.0
        for sgn in (-1, 1):
            spots.append((sgn * iw / 2, z))
    for k in range(end_latches):
        y = (iw - 2 * ir + 0.02) * ((k + 0.5) / end_latches - 0.5) if end_latches > 1 else 0.0
        for sgn in (-1, 1):
            spots.append((y, sgn * ih / 2))
    x_link = x_sp - 0.004
    for (py, pz) in spots:
        dist = math.hypot(py, pz)
        u = Vector((0, -py / dist, -pz / dist))          # inward
        vv = Vector((0, -u.z, u.y))                       # tangent
        M = Matrix(((1, u.x, vv.x, 0), (0, u.y, vv.y, py), (0, u.z, vv.z, pz), (0, 0, 0, 1)))
        # the frame edge is not perpendicular to u everywhere: slide inward until clear of the frame
        b.xf = M
        b.box("latch base", (0.040, 0.085, 0.070), (-D + 0.026, 0.040, 0.0), "white", bevel=0.003)
        for sgn in (-1, 1):
            b.box("latch cheek", (0.052, 0.078, 0.006), (-D + 0.030, 0.030, sgn * 0.031), "white", bevel=0.0015)
        b.cyl("latch roller", 0.013, 0.050, (-D + 0.012, -0.004, 0.0), "steel", axis="Z", seg=20, bevel=0.0015)
        b.cyl("latch pivot", 0.006, 0.074, (-D + 0.040, 0.052, 0.0), "steel", axis="Z", seg=12)
        loop_o = [(0.060 + (p[0] + 0.065), p[1]) for p in rr_pts(0.130, 0.058, 0.014, 5)]
        loop_i = [(0.060 + (p[0] + 0.065), p[1]) for p in rr_pts(0.112, 0.040, 0.006, 5)]
        bm = bmesh.new()
        o0 = [bm.verts.new((x_link, a_, t_)) for a_, t_ in loop_o]; o1 = [bm.verts.new((x_link - 0.008, a_, t_)) for a_, t_ in loop_o]
        i0 = [bm.verts.new((x_link, a_, t_)) for a_, t_ in loop_i]; i1 = [bm.verts.new((x_link - 0.008, a_, t_)) for a_, t_ in loop_i]
        n = len(loop_o)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((o0[i], o0[j], o1[j], o1[i])); bm.faces.new((i0[i], i0[j], i1[j], i1[i]))
            bm.faces.new((o0[i], o0[j], i0[j], i0[i])); bm.faces.new((o1[i], o1[j], i1[j], i1[i]))
        b.add("latch link", bm, "nickel", bevel=0.001)
        b.box("link clevis", (0.012, 0.022, 0.020), (x_link - 0.004, 0.198, 0.0), "steel", bevel=0.002)
        r_arm = max(0.165 * s, min(0.275 * s, dist - 0.30))
        rod_end = dist - r_arm
        if rod_end > 0.215:
            b.cyl_between("push rod", (x_link - 0.004, 0.205, 0.0), (x_link - 0.004, rod_end, 0.0), 0.0048, "steel", seg=12)
            b.cyl("rod end", 0.009, 0.012, (x_link - 0.004, rod_end, 0.0), "steel", axis="X", seg=14, bevel=0.0015)
        b.xf = Matrix.Identity(4)
        # spider arm towards this latch
        ang = math.atan2(pz, py)
        Ma = Matrix.Rotation(ang, 4, "X")
        b.xf = Ma
        arm = [(0.150 * s, -0.024), (r_arm, -0.012), (r_arm + 0.012, 0.0), (r_arm, 0.012), (0.150 * s, 0.024)]
        b.prism("spider arm", arm, x_sp - 0.008, x_sp, "nickel", bevel=0.0015)
        b.xf = Matrix.Identity(4)

    # --- cabin side handles (tan), crank, valve plate, placards
    for sgn in (-1, 1):
        zc = sgn * (H / 2 - FR - 0.078)
        xb = -D - 0.040
        b.cyl("handle bar", 0.016, 0.21 * sy, (xb, 0, zc), "tan", axis="Y", seg=20, bevel=0.004)
        for e in (-1, 1):
            b.cyl("handle leg", 0.014, 0.058, (xb + 0.027, e * 0.088 * sy, zc), "tan", axis="X", seg=16, bevel=0.003)
            b.box("handle pad", (0.008, 0.060, 0.044), (xb + 0.060, e * 0.088 * sy, zc), "white", bevel=0.002)
            b.box("handle stand", (0.045, 0.022, 0.022), (-SK - 0.060, e * 0.088 * sy, zc), "white", bevel=0.002)
    ck = (-D + 0.004, pin_y, crank_z)
    b.cyl("crank hub", 0.040, 0.034, (ck[0] - 0.012, ck[1], ck[2]), "alu", seg=28, bevel=0.003)
    b.cyl("crank ratchet", 0.022, 0.016, (ck[0] - 0.036, ck[1], ck[2]), "alu_dark", seg=6, bevel=0.002, smooth=False)
    b.box("crank arm", (0.012, 0.022, 0.150), (ck[0] - 0.040, ck[1], ck[2] + 0.075), "white", bevel=0.003)
    b.cyl("crank grip", 0.014, 0.060, (ck[0] - 0.074, ck[1], ck[2] + 0.140), "white", axis="X", seg=18, bevel=0.004)
    b.box("label plate", (0.004, 0.120, 0.050), (ck[0] + 0.004, ck[1] - 0.005, ck[2] - 0.085), "white", bevel=0.001)
    b.label("warning cabin", 0.110, 0.044, (ck[0] + 0.0015, ck[1] - 0.005, ck[2] - 0.085), "p_warn", facing=-1)
    vl = (-SK - 0.030, -0.30 * sy, -0.57 * sz)
    b.box("valve stand", (0.036, 0.110, 0.110), (vl[0] + 0.006, vl[1], vl[2]), "white", bevel=0.003)
    b.box("valve plate", (0.006, 0.120, 0.120), (vl[0] - 0.014, vl[1], vl[2]), "alu", bevel=0.002)
    b.cyl("valve body", 0.036, 0.022, (vl[0] - 0.028, vl[1], vl[2]), "black", seg=24, bevel=0.003)
    b.box("valve tee", (0.010, 0.060, 0.012), (vl[0] - 0.044, vl[1], vl[2]), "steel", bevel=0.002)
    for (py, pz, wd, ht, mat) in ((-0.29 * sy, 0.56 * sz, 0.20, 0.17, "p_open"), (0.29 * sy, -0.56 * sz, 0.20, 0.15, "p_close")):
        b.box("placard plate cabin", (0.003, wd + 0.012, ht + 0.012), (-SK - 0.0415, py, pz), "white", bevel=0.001)
        b.box("placard stand cabin", (0.030, 0.020, 0.020), (-SK - 0.026, py, pz), "white", bevel=0.001)
        b.label("placard cabin", wd, ht, (-SK - 0.0435, py, pz), mat, facing=-1)

    # --- smooth side: strap, crank, kick latch, equalization valve, placards
    zt = 0.50 * sz
    b.box("strap", (0.004, 0.036, 0.230), (0.004, 0.0, zt), "strap", bevel=0.001)
    for e in (-1, 1):
        b.box("strap bracket", (0.012, 0.052, 0.022), (0.006, 0.0, zt + e * 0.118), "alu", bevel=0.002)
        b.cyl("strap pin", 0.004, 0.060, (0.014, 0.0, zt + e * 0.118), "steel", axis="Y", seg=10)
    cf = (0.0, 0.305 * sy, 0.015 * sz)
    b.cyl("crank base", 0.044, 0.010, (0.005, cf[1], cf[2]), "alu", seg=28, bevel=0.002)
    b.cyl("crank hub out", 0.030, 0.030, (0.024, cf[1], cf[2]), "alu", seg=24, bevel=0.003)
    b.cyl("crank ratchet out", 0.018, 0.014, (0.045, cf[1], cf[2]), "alu_dark", seg=6, bevel=0.002, smooth=False)
    b.box("ratchet selector", (0.008, 0.040, 0.012), (0.043, cf[1] - 0.030, cf[2] + 0.022), "black", bevel=0.002, rot=Matrix.Rotation(math.radians(35), 4, "X"))
    b.box("crank arm out", (0.012, 0.135, 0.022), (0.036, cf[1] + 0.068, cf[2] - 0.004), "alu", bevel=0.003)
    b.cyl("crank grip out", 0.013, 0.090, (0.036, cf[1] + 0.128, cf[2] - 0.052), "black", axis="Z", seg=18, bevel=0.004)
    b.label("warning out", 0.120, 0.048, (0.0008, cf[1] + 0.02, cf[2] - 0.075), "p_warn", facing=1)
    b.label("placard opening out", 0.20, 0.17, (0.0008, 0.30 * sy, 0.27 * sz), "p_open", facing=1)
    b.label("placard closing out", 0.20, 0.15, (0.0008, -0.30 * sy, -0.58 * sz), "p_close", facing=1)
    zk = -0.60 * sz
    b.box("kick plate", (0.006, 0.170, 0.110), (0.003, 0.0, zk), "white", bevel=0.002)
    for e in (-1, 1):
        b.box("kick post", (0.040, 0.014, 0.060), (0.024, e * 0.060, zk + 0.010), "alu", bevel=0.002)
    b.cyl("kick bar", 0.011, 0.150, (0.042, 0.0, zk + 0.034), "alu", axis="Y", seg=16, bevel=0.003)
    b.label("exit label", 0.150, 0.038, (0.0068, 0.0, zk - 0.030), "p_exit", facing=1)
    ve = (0.0, 0.26 * sy, -0.565 * sz)
    b.cyl("eq valve flange", 0.046, 0.008, (0.004, ve[1], ve[2]), "alu_dark", seg=28, bevel=0.002)
    b.cyl("eq valve body", 0.032, 0.030, (0.022, ve[1], ve[2]), "black", seg=24, bevel=0.003)
    b.cyl("eq valve stem", 0.010, 0.050, (0.030, ve[1] + 0.012, ve[2] - 0.045), "steel", axis="Z", seg=12, bevel=0.002)
    # cable from the crank to the valve, held by small clips
    path = [(0.006, cf[1] + 0.035, cf[2] - 0.105), (0.006, cf[1] + 0.060, cf[2] - 0.20), (0.006, cf[1] + 0.070, cf[2] - 0.34), (0.006, ve[1] + 0.060, ve[2] + 0.17), (0.006, ve[1] + 0.012, ve[2] + 0.046)]
    for p0, p1 in zip(path[:-1], path[1:]):
        b.cyl_between("cable", p0, p1, 0.0028, "steel", seg=8)
    for p in path[1:-1]:
        b.cyl("cable clip", 0.007, 0.006, (0.004, p[1], p[2]), "alu", seg=10)

    # --- hinges (-Y edge) and roller guides (+Y edge)
    hy = -W / 2 - 0.030
    for zf in (-0.30, 0.0, 0.30):
        zc = zf * H
        b.cyl("hinge knuckle", 0.017, 0.100, (-0.045, hy, zc), "alu", axis="Z", seg=20, bevel=0.002)
        b.box("hinge leaf", (0.040, 0.036, 0.090), (-0.045, hy + 0.024, zc), "alu", bevel=0.002)
        b.box("hinge strap", (0.008, 0.070, 0.060), (-D - 0.004, -W / 2 + 0.036, zc), "alu", bevel=0.002)
    b.cyl("hinge pin", 0.006, 0.60 * H + 0.14, (-0.045, hy, 0.0), "steel", axis="Z", seg=10)
    for zf in (-0.26, 0.26):
        zc = zf * H
        b.box("guide bracket", (0.050, 0.030, 0.070), (-0.045, W / 2 + 0.010, zc), "alu", bevel=0.003)
        b.cyl("guide pin", 0.007, 0.050, (-0.045, W / 2 + 0.045, zc), "steel", axis="Y", seg=12)
        b.cyl("guide roller", 0.013, 0.014, (-0.045, W / 2 + 0.066, zc), "steel", axis="Y", seg=16, bevel=0.002)

    door = b.finish(name)
    bpy.data.objects.remove(cob, do_unlink=True)
    door["width"] = W; door["height"] = H; door["hinge_local"] = (-0.045, hy, 0.0)
    return door

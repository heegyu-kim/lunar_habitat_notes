# -*- coding: utf-8 -*-
"""Builds the detailed hatch door asset and renders both faces.

  python -X utf8 tools/design/make_hatch_labels.py
  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b --python tools/build_hatch_door.py

Output: blender/hatch_door.blend (+ .glb) with two variants side by side:
  "Hatch door H-1"        1.10 x 1.60 m, fits the base-camp common hatch (clear opening 1.02 x 1.52)
  "Hatch door CBM square" 1.35 x 1.35 m, the proportions of the ISS hatch in the reference photos
Renders: docs/design/H-02_hatch_door_tunnel_side.png, H-03_hatch_door_cabin_side.png, H-04_hatch_door_cbm_square.png
"""
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "design"))
import hatch_door  # noqa: E402

OUT = os.path.join(ROOT, "blender")
TEX = os.path.join(OUT, "textures")
PREV = os.path.join(ROOT, "docs", "design")

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
c1 = bpy.data.collections.new("Hatch door H-1 (1.10 x 1.60)"); scene.collection.children.link(c1)
c2 = bpy.data.collections.new("Hatch door CBM square (1.35 x 1.35)"); scene.collection.children.link(c2)

d1 = hatch_door.build(c1, TEX, "Hatch door H-1", W=1.10, H=1.60, R=0.24, side_latches=3, end_latches=2, prefix="h1")
d2 = hatch_door.build(c2, TEX, "Hatch door CBM square", W=1.35, H=1.35, R=0.30, side_latches=2, end_latches=2, prefix="cbm")
d2.location = (0.0, 1.9, 0.0)
for d in (d1, d2):
    me = d.data
    print("DOOR %-24s verts=%d tris=%d  size=%.3f x %.3f x %.3f" % (d.name, len(me.vertices), sum(len(p.vertices) - 2 for p in me.polygons), d.dimensions.x, d.dimensions.y, d.dimensions.z))

bpy.ops.file.pack_all()
blend = os.path.join(OUT, "hatch_door.blend")
bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
print("WROTE", blend)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "hatch_door.glb"), export_format="GLB", export_yup=True, export_apply=True)
print("WROTE", os.path.join(OUT, "hatch_door.glb"))

# ------------------------------------------------------------------ renders
try:
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 96
    scene.cycles.use_denoising = True
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "OPTIX"; prefs.get_devices()
        for dev in prefs.devices:
            dev.use = True
        scene.cycles.device = "GPU"
    except Exception as exc:
        print("GPU not used:", exc)
    scene.render.resolution_x = 1920; scene.render.resolution_y = 1080
    world = bpy.data.worlds.new("w"); scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.045, 0.045, 0.045, 1); world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    scene.view_settings.view_transform = "Filmic" if "Filmic" in [v.name for v in bpy.types.ColorManagedViewSettings.bl_rna.properties["view_transform"].enum_items] else scene.view_settings.view_transform

    def light(name, loc, energy, size, target):
        ld = bpy.data.lights.new(name, "AREA"); ld.energy = energy; ld.size = size
        lo = bpy.data.objects.new(name, ld); scene.collection.objects.link(lo); lo.location = loc
        lo.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        return lo

    cam_d = bpy.data.cameras.new("cam"); cam_d.lens = 50
    cam = bpy.data.objects.new("cam", cam_d); scene.collection.objects.link(cam); scene.camera = cam

    def shot(path, loc, target, lights):
        los = [light("L%d" % i, *l, target) for i, l in enumerate(lights)]
        cam.location = loc
        cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        for lo in los:
            bpy.data.objects.remove(lo, do_unlink=True)
        print("RENDERED", path)

    # tunnel (smooth) side of H-1: camera on +X
    d2.hide_render = True
    shot(os.path.join(PREV, "H-02_hatch_door_tunnel_side.png"), (4.6, -2.6, 0.55), (0, 0, 0.0),
         [((3.0, -1.2, 3.2), 230, 2.5), ((3.5, 3.0, 0.5), 90, 3.0), ((1.0, 0.0, -2.5), 40, 2.0)])
    # cabin (mechanism) side of H-1: camera on -X
    shot(os.path.join(PREV, "H-03_hatch_door_cabin_side.png"), (-4.6, -2.6, 0.55), (0, 0, 0.0),
         [((-3.0, 2.5, 2.5), 230, 2.5), ((-3.5, -3.0, 0.5), 110, 3.0), ((-1.0, 0.0, -2.5), 40, 2.0)])
    # square variant, cabin side
    d2.hide_render = False; d1.hide_render = True
    shot(os.path.join(PREV, "H-04_hatch_door_cbm_square.png"), (-4.4, -0.4, 0.50), (0, 1.9, 0.0),
         [((-3.0, 4.4, 2.5), 230, 2.5), ((-3.5, -1.1, 0.5), 110, 3.0), ((-1.0, 1.9, -2.5), 40, 2.0)])
    shot(os.path.join(PREV, "H-05_hatch_door_cbm_square_tunnel_side.png"), (4.4, -0.4, 0.50), (0, 1.9, 0.0),
         [((3.0, 0.7, 3.2), 230, 2.5), ((3.5, 4.9, 0.5), 90, 3.0), ((1.0, 1.9, -2.5), 40, 2.0)])
except Exception as exc:
    import traceback
    traceback.print_exc()
    print("RENDER skipped:", exc)

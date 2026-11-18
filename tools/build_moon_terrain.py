# -*- coding: utf-8 -*-
"""Prepares the moon terrain for the game: puts the habitat site at the origin and levels a pad under it.

  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b --python tools/build_moon_terrain.py -- <source moon_terrain.glb>

Source: the 300 x 300 m terrain modelled for the rendering test (Documents/rendering-test/Assets/moon_terrain.glb).
Output: assets/environment/moon_terrain.glb, same mesh and UVs, with
  * the site (SITE_X, SITE_Z in the source mesh, Godot axes) moved to x = z = 0
  * the ground inside PAD_RADIUS levelled to GROUND_Y, blended back into the original relief by BLEND_RADIUS
The numbers printed at the end (EARTH ...) go into scripts/lunar_exterior.gd if the site changes.
"""
import math
import os
import sys

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "environment", "moon_terrain.glb")

# Valley floor 36 m from the viewpoint of the rendering test: the flattest ground near it, with the
# western plateau as a ridge line and Earth just above that ridge.
SITE_X = 41.0
SITE_Z = -23.0
PAD_RADIUS = 15.0      # level ground: the habitat (r 3.4 m) and the "Go outside" spot 13 m from it
BLEND_RADIUS = 34.0
GROUND_Y = -0.06       # the built-in habitat's foundation plate is at -0.07; imported models stand on y = 0

# Where things of the rendering-test scene were, in the source mesh's coordinates (Godot axes).
EARTH_SRC = (-100.66, 29.23, 7.0)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if not argv:
    raise SystemExit("usage: blender -b --python tools/build_moon_terrain.py -- <source moon_terrain.glb>")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(argv[0]))
obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
me = obj.data

# Blender (x, y, z) = Godot (x, -z, y)
sx, sy = SITE_X, -SITE_Z
near = [v.co.z for v in me.vertices if math.hypot(v.co.x - sx, v.co.y - sy) < PAD_RADIUS]
pad_h = sum(near) / len(near)
print("TERRAIN site (%.1f, %.1f): %d vertices on the pad, mean height %.2f, range %.2f" % (SITE_X, SITE_Z, len(near), pad_h, max(near) - min(near)))

for v in me.vertices:
    d = math.hypot(v.co.x - sx, v.co.y - sy)
    if d < BLEND_RADIUS:
        t = 0.0 if d <= PAD_RADIUS else (d - PAD_RADIUS) / (BLEND_RADIUS - PAD_RADIUS)
        t = t * t * (3.0 - 2.0 * t)
        v.co.z = pad_h + (v.co.z - pad_h) * t
    v.co.x -= sx
    v.co.y -= sy
    v.co.z += GROUND_Y - pad_h
me.update()
obj.name = "MoonTerrain"
me.name = "MoonTerrain"
for p in me.polygons:
    p.use_smooth = True

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True,
                          export_normals=True, export_texcoords=True, export_materials="NONE",
                          export_cameras=False, export_lights=False, export_animations=False)
zs = [v.co.z for v in me.vertices]
print("TERRAIN wrote %s (%.1f MB): %d vertices, height %.2f .. %.2f around the site" % (OUT, os.path.getsize(OUT) / 1e6, len(me.vertices), min(zs), max(zs)))
print("EARTH position in the game: Vector3(%.1f, %.1f, %.1f)" % (EARTH_SRC[0] - SITE_X, EARTH_SRC[1] - pad_h + GROUND_Y, EARTH_SRC[2] - SITE_Z))

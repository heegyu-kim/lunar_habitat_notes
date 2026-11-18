# -*- coding: utf-8 -*-
"""Exports the habitat working file to the glb the game loads.

Run again every time blender/Lunar_Surface_Habitat.blend is saved:

  "C:\\Program Files\\Blender Foundation\\Blender 4.5\\blender.exe" -b blender/Lunar_Surface_Habitat.blend --python tools/export_habitat_glb.py

  optional arguments after "--":  <output.glb>  (default: assets/models/Lunar Habitat/Lunar_Surface_Habitat.glb)

The .blend itself is never saved by this script. What gets exported:
  * only objects that are visible in the viewport (hide something in Blender to keep it out of the game)
  * modifiers applied; Subdivision Surface capped at MAX_SUBSURF so downloaded props do not explode
  * no lights, cameras or animations (the game lights the habitat itself)
  * textures embedded; anything larger than MAX_TEXTURE is scaled down in memory first
"""
import os
import sys

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "assets", "models", "Lunar Habitat", "Lunar_Surface_Habitat.glb")
MAX_SUBSURF = 0
MAX_TEXTURE = 2048

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = os.path.abspath(argv[0]) if argv else DEFAULT_OUT

scene = bpy.context.scene
view_layer = bpy.context.view_layer

# -- modifiers that multiply the triangle count
for o in scene.objects:
    for m in o.modifiers:
        if m.type == "SUBSURF" and m.levels > MAX_SUBSURF:
            print("EXPORT subsurf %s: viewport level %d -> %d" % (o.name, m.levels, MAX_SUBSURF))
            m.levels = MAX_SUBSURF
        elif m.type == "MULTIRES" and m.levels > MAX_SUBSURF:
            m.levels = MAX_SUBSURF

# -- oversized textures (in memory only)
for img in bpy.data.images:
    if img.type != "IMAGE" or img.size[0] == 0:
        continue
    w, h = img.size[0], img.size[1]
    big = max(w, h)
    if big > MAX_TEXTURE:
        f = MAX_TEXTURE / float(big)
        try:
            img.scale(max(1, int(round(w * f))), max(1, int(round(h * f))))
            print("EXPORT texture %s: %dx%d -> %dx%d" % (img.name, w, h, img.size[0], img.size[1]))
        except Exception as exc:  # an image that cannot be loaded is exported as it is
            print("EXPORT texture %s not scaled: %s" % (img.name, exc))

# -- what goes out
visible = [o for o in scene.objects if o.name in view_layer.objects and o.visible_get()]
hidden = [o for o in scene.objects if o.type == "MESH" and o not in visible]
meshes = [o for o in visible if o.type == "MESH"]
depsgraph = bpy.context.evaluated_depsgraph_get()
tris = 0
for o in meshes:
    ev = o.evaluated_get(depsgraph)
    me = ev.to_mesh()
    tris += sum(len(p.vertices) - 2 for p in me.polygons)
    ev.to_mesh_clear()
print("EXPORT %d mesh objects, %d triangles; %d hidden mesh objects left out: %s" % (
    len(meshes), tris, len(hidden), ", ".join(o.name for o in hidden)))

os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out,
    export_format="GLB",
    use_visible=True,
    use_active_scene=True,
    export_yup=True,
    export_apply=True,
    export_lights=False,
    export_cameras=False,
    export_animations=False,
    export_extras=False,
    export_image_format="AUTO",
    export_texcoords=True,
    export_normals=True,
    export_tangents=False,
    export_materials="EXPORT",
)
print("EXPORT wrote %s (%.1f MB)" % (out, os.path.getsize(out) / 1e6))

# Converts the project's glb models into .blend and .fbx files for Blender work.
# Run (Windows, from the project folder):
#   "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe" -b --python tools/glb_to_blend_fbx.py
# Output goes to blender/ next to the project (ignored by git: .blend/.fbx are large and derived).
import os
import sys
import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "blender")
os.makedirs(OUT, exist_ok=True)

# The NASA tower glb carries five empty extra scenes that Blender's importer rejects; tools/patch_glb_scenes
# (inline below) writes a copy with only the populated scene when BLENDER_GLB_SRC is set.
SRC_OVERRIDE = os.environ.get("BLENDER_GLB_SRC", "")
JOBS = [
    (SRC_OVERRIDE or "assets/models/Lunar Habitat/Lunar_Surface_Habitat.glb", "Lunar_Surface_Habitat"),
    ("assets/models/Base_Camp/base_camp.glb", "base_camp_blockout"),
    ("assets/models/Base_Camp/base_camp_exterior.glb", "base_camp_exterior_blockout"),
]

for rel, name in JOBS:
    src = rel if os.path.isabs(rel) else os.path.join(ROOT, rel)
    if not os.path.isfile(src):
        print("SKIP missing", src)
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    try:
        bpy.ops.import_scene.gltf(filepath=src)
    except Exception as exc:  # keep going with the other models
        print("FAILED import", src, exc)
        continue
    objs = [o for o in bpy.data.objects if o.type == "MESH"]
    # Scene units: metres, as the glb already is.
    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.scale_length = 1.0
    blend = os.path.join(OUT, name + ".blend")
    bpy.ops.file.pack_all()          # textures travel inside the .blend
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    fbx = os.path.join(OUT, name + ".fbx")
    bpy.ops.export_scene.fbx(
        filepath=fbx,
        use_selection=False,
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_ALL",
        axis_forward="-Z",
        axis_up="Y",
        object_types={"MESH", "EMPTY"},
        mesh_smooth_type="FACE",
        path_mode="COPY",
        embed_textures=True,
        bake_anim=False,
    )
    print("WROTE %s  (%d mesh objects)  %s  %s" % (name, len(objs), blend, fbx))

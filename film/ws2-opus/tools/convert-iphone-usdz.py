"""One-time loader conversion of Apple's iPhone 18 Pro USDZ to GLB.

Same rules as convert-air-usdz.py: the mesh, materials and UVs come from the
USDZ. No decimation, no remesh, no rebuild. Blender 4.5.14 LTS.

  /Volumes/Blender/Blender.app/Contents/MacOS/Blender --background --python \\
    tools/convert-iphone-usdz.py

Source: /tmp/usdz/iphone-18-pro-e-sim.usdz
  https://www.apple.com/105/media/us/iphone-18-pro/2026/591df885-5ee2-4173-86e6-401021249f7c/ar/iphone-18-pro-e-sim.usdz
Output: film/ws2-opus/public/mesh/iphone-18-pro.glb
"""
import os

import bpy

SRC = "/tmp/usdz/iphone-18-pro-e-sim.usdz"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "public", "mesh", "iphone-18-pro.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(
    filepath=SRC,
    import_meshes=True,
    import_materials=True,
    import_skeletons=True,
    import_blendshapes=True,
    import_subdiv=False,
    import_visible_only=True,
    read_mesh_uvs=True,
    read_mesh_colors=True,
    import_usd_preview=True,
    import_all_materials=True,
    import_textures_mode="IMPORT_PACK",
    validate_meshes=False,
    merge_parent_xform=False,
    apply_unit_conversion_scale=True,
    scale=1.0,
)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=OUT,
    export_format="GLB",
    use_selection=False,
    export_apply=False,
    export_skins=True,
    export_animations=False,
    export_texcoords=True,
    export_normals=True,
    export_materials="EXPORT",
    export_yup=True,
    export_image_format="AUTO",
    export_draco_mesh_compression_enable=False,
    export_cameras=False,
    export_lights=False,
)

for o in sorted([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: -len(o.data.vertices)):
    print("MESH", o.name, len(o.data.vertices), [round(v, 3) for v in o.dimensions])
print("WROTE", OUT, os.path.getsize(OUT))

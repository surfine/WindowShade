"""One-time loader conversion of Apple's 15-inch MacBook Air USDZ to GLB.

The mesh, materials, UVs and hinge come from the USDZ. This script does not
decimate, remesh, or rebuild the chassis. Blender's USD importer keeps the
authored vertices; the glTF exporter embeds those meshes and the packed
textures. import_subdiv stays off. Draco stays off.

Converter: Blender 4.5.14 LTS (macos-arm64)

Command (from anywhere):

  /Volumes/Blender/Blender.app/Contents/MacOS/Blender --background --python /private/tmp/ws2-g8-opus/film/ws2-opus/tools/convert-air-usdz.py

Source: /tmp/gg/usdz/macbook-air-15in-silver.usdz
  https://www.apple.com/105/media/us/macbook-air/2025/0833fe28-c438-4dc4-8edc-e39ef30df5f9/ar/macbook-air-15in-silver.usdz
Output: film/ws2-opus/public/mesh/macbook-air-15in-silver.glb
"""
import os

import bpy

SRC = "/tmp/gg/usdz/macbook-air-15in-silver.usdz"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "public", "mesh", "macbook-air-15in-silver.glb")

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
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
print("WROTE", OUT, os.path.getsize(OUT), "meshes", len(meshes), "verts", sum(len(o.data.vertices) for o in meshes))

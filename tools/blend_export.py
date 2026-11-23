"""Blender-Hilfe: exportiert die Mesh-Objekte einer .blend als scene.glb für Godot.

Aufruf:
  blender -b "pfad/auto.blend" --python tools/blend_export.py -- "pfad/scene.glb"

Nur Meshes werden exportiert (keine Kameras, Lichter, Hilfsobjekte), Modifier werden
angewendet. Godot lädt .glb direkt, .blend kann es nur mit installiertem Blender.
"""

import sys

import bpy


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args:
        raise SystemExit("usage: blender -b file.blend --python blend_export.py -- out.glb")
    out = args[-1]

    bpy.ops.object.select_all(action="DESELECT")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for obj in meshes:
        obj.select_set(True)
    if not meshes:
        raise SystemExit("no meshes in %s" % bpy.data.filepath)

    bpy.ops.export_scene.gltf(
        filepath=out,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print("EXPORTED %d meshes -> %s" % (len(meshes), out))


main()

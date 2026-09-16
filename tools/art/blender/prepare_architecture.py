"""Create editable Blender masters from authored geometry and preserve GLB materials."""
import bpy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
for name in ('cottage','seed_shop','barn','coop'):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'game/resources/models'/f'{name}.glb'))
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/3d/source'/f'{name}.blend'))
    print('BLENDER_MASTER',name)

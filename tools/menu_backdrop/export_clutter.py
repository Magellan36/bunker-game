## tools/menu_backdrop/export_clutter.py — exports main-menu clutter and ruin
## pieces as glTF (one folder per object: <name>.gltf + .bin + JPEG textures,
## so Godot references each texture once instead of extracting copies from a
## .glb): origin at ground contact bottom-centre, modifiers/transforms applied. Needs Blender 5.1+ (several Poly Haven files
## are saved in the 5.x format):
##   ~/blender-5.1.2-linux-x64/blender -b --factory-startup \
##       --python tools/menu_backdrop/export_clutter.py -- <unzipped clutter dir>
## Sources: "MAIN MENU CLUTTER" (Poly Haven, CC0; unzip each .blend.zip into
## <dir>/<name>/), and the "MAIN MENU BUILDINGS" packs for ruin pieces.
import bpy, os, sys, mathutils

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
CLUTTER = ARGS[0] if ARGS else ""
BUILD = "/mnt/storage/Bunker Game/models/NEW MODELS/MAIN MENU BUILDINGS"
MAJ = BUILD + "/LowPoly-Apocalyptic-Buildings-By-Majadroid/Apocalyptic Scene.blend"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../assets/models/menu_backdrop")

def ph(name, keep=None):
    return (os.path.join(CLUTTER, name, name + ".blend"), keep)

# out path (relative to OUT) -> (source file, object names to keep | None = all visible meshes)
JOBS = {
    "clutter/ammo_box": ph("ammo_box_1k"),
    "clutter/cardboard_box": ph("cardboard_box_01_1k"),
    "clutter/cash_register": ph("CashRegister_01_1k"),
    "clutter/cheese_box": ph("CheeseBox_01_1k"),
    "clutter/concrete_cat_statue": ph("concrete_cat_statue_1k"),
    "clutter/aircon_unit": ph("exterior_aircon_unit_1k", ["exterior_aircon_unit_rusted"]),
    "clutter/industrial_storage_cart": ph("industrial_storage_cart_1k"),
    "clutter/lantern": ph("Lantern_01_1k"),
    "clutter/boulder_03": ph("namaqualand_boulder_03_1k", ["namaqualand_boulder_03_LOD2"]),
    "clutter/boulder_05": ph("namaqualand_boulder_05_1k", ["namaqualand_boulder_05_LOD2"]),
    "clutter/military_compressor": ph("old_military_compressor_1k"),
    "clutter/military_crate": ph("old_military_crate_1k"),
    "clutter/tyre": ph("old_tyre_1k"),
    "clutter/jerrycan": ph("plastic_jerrycan_1k"),
    "clutter/monobloc_chair": ph("plastic_monobloc_chair_01_1k"),
    "clutter/signal_flashlight": ph("signal_flashlight_1k"),
    "clutter/fire_pit": ph("stone_fire_pit_1k"),
    "clutter/television": ph("Television_01_1k"),
    "clutter/utility_box_01": ph("utility_box_01_1k"),
    "clutter/utility_box_02": ph("utility_box_02_1k"),
    "clutter/vintage_flashlight": ph("vintage_flashlight_1k"),
    "clutter/spacecraft_instrument": ph("vintage_spacecraft_instrument_1k"),
    "clutter/wheelchair": ph("wheelchair_01_1k"),
    "clutter/wooden_crate": ph("wooden_military_crate_1k"),
}
for i in range(1, 7):
    JOBS["clutter/moss_rock_%02d" % i] = ph("rock_moss_set_01_1k", ["rock_moss_set_01_rock%02d" % i])
for n, keep in [("column_1", "Colonne_1"), ("column_2", "Colonne_2"), ("column_3", "Colonne_3"),
                ("debris", "Débris"), ("rocks", "Rocks"), ("road_slab", "Route")]:
    JOBS["destroyed/" + n] = (BUILD + "/Destroyed_City_Assets.fbx", [keep])
for n, keep in [("floor_slab", "Single Floor"), ("wreckage_1", "Wreckage 1"),
                ("wreckage_2", "Wreckage 2"), ("wreckage_3", "Wreckage 3"), ("fire_stairs", "FireStairs")]:
    JOBS["destroyed/" + n] = (MAJ, [keep])

def load(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=path)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.fbx(filepath=path)

ONLY = ARGS[1:]
for out, (path, keep) in JOBS.items():
    if ONLY and out not in ONLY:
        continue
    load(path)
    scene = bpy.context.scene
    if keep is None:
        targets = [o for o in scene.objects if o.type == 'MESH' and not o.hide_render and o.visible_get()]
    else:
        targets = []
        for k in keep:
            root = bpy.data.objects[k]
            targets += [o for o in [root] + list(root.children_recursive) if o.type == 'MESH']
    dg = bpy.context.evaluated_depsgraph_get()
    baked = []
    for o in targets:
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
        me.transform(o.matrix_world)
        nob = bpy.data.objects.new(os.path.basename(out), me)
        scene.collection.objects.link(nob)
        baked.append(nob)
    for o in list(scene.objects):
        if o not in baked:
            bpy.data.objects.remove(o, do_unlink=True)
    mn = mathutils.Vector((1e9,) * 3); mx = mathutils.Vector((-1e9,) * 3)
    for o in baked:
        for v in o.data.vertices:
            mn = mathutils.Vector(map(min, mn, v.co)); mx = mathutils.Vector(map(max, mx, v.co))
    shift = mathutils.Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
    for o in baked: o.data.transform(shift)
    bpy.ops.object.select_all(action='DESELECT')
    for o in baked: o.select_set(True)
    bpy.context.view_layer.objects.active = baked[0]
    if len(baked) > 1: bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    base = os.path.basename(out)
    dest = os.path.normpath(os.path.join(OUT, out, base + ".gltf"))
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=dest, export_format='GLTF_SEPARATE', use_selection=True,
        export_apply=True, export_yup=True, export_image_format='JPEG', export_jpeg_quality=88)
    d = mx - mn
    print("EXPORTED %-34s tris=%6d  W=%.2f H=%.2f D=%.2f" % (out, tris, d.x, d.z, d.y))

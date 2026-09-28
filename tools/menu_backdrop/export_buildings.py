## tools/menu_backdrop/export_buildings.py — exports the main-menu buildings,
## one .glb per model, origin at ground contact bottom-centre, transforms and
## modifiers applied, textures capped (2K hero / 1K others).
##   blender -b --factory-startup --python tools/menu_backdrop/export_buildings.py [-- name ...]
import bpy, sys, os, mathutils
SRC = "/mnt/storage/Bunker Game/models/NEW MODELS/MAIN MENU BUILDINGS"
OUT = "/mnt/storage/Default Project/bunker-game/assets/models/menu_backdrop"
MAJ = SRC + "/LowPoly-Apocalyptic-Buildings-By-Majadroid/Apocalyptic Scene.blend"
JOBS = [
    ("ruin_malik_facade", SRC + "/scene.gltf", None),
    ("shack_low", SRC + "/SurvivalWood/LowShack.fbx", "LowShack"),
] + [("tower_majadroid_%s" % n.split()[-1].lower() if n != "Building" else "tower_majadroid_base", MAJ, n)
     for n in ["Building", "Building 01", "Building 02", "Building 03", "Building 04",
               "Building 05", "Building 06", "Building 07"]]

def load(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=path)
    else:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        if ext == ".fbx": bpy.ops.import_scene.fbx(filepath=path)
        else: bpy.ops.import_scene.gltf(filepath=path)

def shack_material(obj, kind):
    tex = SRC + "/SurvivalWood/Textures/%sTextures/%s_" % (kind, kind)
    mat = bpy.data.materials.new(kind + "_Mat"); mat.use_nodes = True
    nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]
    alb = nt.nodes.new("ShaderNodeTexImage"); alb.image = bpy.data.images.load(tex + "Albedo.tga")
    nt.links.new(alb.outputs["Color"], bsdf.inputs["Base Color"])
    nrm = nt.nodes.new("ShaderNodeTexImage"); nrm.image = bpy.data.images.load(tex + "Normal.tga")
    nrm.image.colorspace_settings.name = "Non-Color"
    nmap = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(nrm.outputs["Color"], nmap.inputs["Color"]); nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    obj.data.materials.clear(); obj.data.materials.append(mat)

ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for name, path, keep in JOBS:
    if ONLY and name not in ONLY:
        continue
    load(path)
    if keep is None:
        targets = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    else:
        root = bpy.data.objects[keep]
        targets = [root] + [c for c in root.children_recursive if c.type == 'MESH']
    dg = bpy.context.evaluated_depsgraph_get()
    # Bake modifiers + world transform into standalone meshes.
    baked = []
    for o in targets:
        ev = o.evaluated_get(dg)
        me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
        me.transform(o.matrix_world)
        nob = bpy.data.objects.new(o.name + "_baked", me)
        bpy.context.scene.collection.objects.link(nob)
        baked.append(nob)
    for o in list(bpy.context.scene.objects):
        if o not in baked:
            bpy.data.objects.remove(o, do_unlink=True)
    if name.startswith("shack_"):
        for o in baked: shack_material(o, "LowShack")
    ## Texture budget (docs/systems/main-menu): hero 2K, small props 1K.
    cap = {"ruin_malik_facade": 2048, "shack_low": 1024}.get(name)
    if cap:
        for img in bpy.data.images:
            if img.size[0] > cap:
                img.scale(cap, cap)
    mn = mathutils.Vector((1e9,) * 3); mx = mathutils.Vector((-1e9,) * 3)
    for o in baked:
        for v in o.data.vertices:
            mn = mathutils.Vector(map(min, mn, v.co)); mx = mathutils.Vector(map(max, mx, v.co))
    shift = mathutils.Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
    for o in baked: o.data.transform(shift)
    # One object per asset keeps the Godot scene simple.
    bpy.ops.object.select_all(action='DESELECT')
    for o in baked: o.select_set(True)
    bpy.context.view_layer.objects.active = baked[0]
    if len(baked) > 1: bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active; obj.name = name
    d = mx - mn
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format='GLB',
        use_selection=True, export_apply=True, export_yup=True)
    print("EXPORTED %-24s tris=%6d  W=%.1f H=%.1f D=%.1f  mats=%s" % (name, tris, d.x, d.z, d.y,
        [m.name for m in obj.data.materials]))

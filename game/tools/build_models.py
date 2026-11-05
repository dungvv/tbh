# Build the game's 3D models from the downloaded CC0 packs (see art3d/README.md).
# Run: blender -b -P tools/build_models.py -- <src folder> <out folder: art3d>
# For each entry of tools/models3d.json: keep only the listed animations under short names
# (idle, run, attack, skill, hit, death, ...), attach weapons to bones, recolor if asked,
# then export a small .glb. Writes art3d/manifest.json with each model's standing height.
import bpy, json, os, sys
import numpy as np

args = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = args[0], args[1]
CFG = json.load(open(os.path.join(os.path.dirname(__file__), "models3d.json")))
os.makedirs(OUT, exist_ok=True)
TRIS = 1600  # skinned triangles per model after decimate(); an entry may set its own "tris"


def short(action_name: str) -> str:
    return action_name.split("|")[-1]


def recolor(lo: float, hi: float, hue: float, sat: float, val: float) -> None:
    """Recolor texture pixels whose hue is in [lo, hi] (e.g. the mage's purple robe); skin and trims stay."""
    for img in bpy.data.images:
        if img.size[0] == 0:
            continue
        px = np.empty(img.size[0] * img.size[1] * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        p = px.reshape(-1, 4)
        r, g, b = p[:, 0], p[:, 1], p[:, 2]
        mx, mn = p[:, :3].max(1), p[:, :3].min(1)
        d = mx - mn
        h = np.zeros_like(mx)
        m = d > 1e-6
        rc = np.where(m, (mx - r) / np.where(m, d, 1), 0)
        gc = np.where(m, (mx - g) / np.where(m, d, 1), 0)
        bc = np.where(m, (mx - b) / np.where(m, d, 1), 0)
        h = np.where(r == mx, bc - gc, np.where(g == mx, 2.0 + rc - bc, 4.0 + gc - rc))
        h = (h / 6.0) % 1.0
        s = np.where(mx > 1e-6, d / np.where(mx > 1e-6, mx, 1), 0)
        sel = (h >= lo) & (h <= hi) & (s > 0.15)
        h = np.where(sel, hue, h)
        s = np.where(sel, np.clip(s * sat, 0, 1), s)
        v = np.where(sel, np.clip(mx * val, 0, 1), mx)
        i = np.floor(h * 6).astype(int) % 6
        f = h * 6 - np.floor(h * 6)
        pp, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
        choices = [(v, t, pp), (q, v, pp), (pp, v, t), (pp, q, v), (t, pp, v), (v, pp, q)]
        for k, (cr, cg, cb) in enumerate(choices):
            sk = (i == k) & sel
            p[sk, 0], p[sk, 1], p[sk, 2] = cr[sk], cg[sk], cb[sk]
        img.pixels.foreach_set(p.ravel())
        img.pack()


def portrait(name: str, show: list, arm, z0: float, z1: float) -> None:
    """128 px picture of the hero in its idle pose for the UI, rendered then thrown away before export."""
    import math
    from mathutils import Vector
    hidden = []
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and o.parent_bone.startswith("handslot") and o.name not in show:
            o.hide_render = True
            hidden.append(o)
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = bpy.data.actions.get("idle")
    sc = bpy.context.scene
    sc.frame_set(1)
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 128
    sc.render.film_transparent = True
    cam = bpy.data.objects.new("pcam", bpy.data.cameras.new("pcam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = (z1 - z0) * 1.15
    ctr = Vector((0, 0, (z0 + z1) / 2))
    cam.location = ctr + Vector((math.sin(-0.45), -math.cos(-0.45), 0.25)) * 10
    cam.rotation_euler = (ctr - cam.location).to_track_quat("-Z", "Y").to_euler()
    sun = bpy.data.objects.new("psun", bpy.data.lights.new("psun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (0.8, 0.2, -0.6)
    sc.collection.objects.link(sun)
    w = bpy.data.worlds.new("pw")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.2
    os.makedirs(os.path.join(OUT, "portraits"), exist_ok=True)
    sc.render.filepath = os.path.join(OUT, "portraits", name + ".png")
    bpy.ops.render.render(write_still=True)
    for o in (cam, sun):
        bpy.data.objects.remove(o)
    bpy.data.worlds.remove(w)
    for o in hidden:
        o.hide_render = False
    arm.animation_data.action = None


def decimate(target: int) -> int:
    """Cut skinned meshes down to about `target` triangles in total. The game skins every vertex on each
    animation step and the actors are ~60 px tall, so dense meshes cost CPU for detail nobody sees."""
    skinned = [o for o in bpy.context.scene.objects
               if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)]
    tris = lambda: sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in skinned)
    total = tris()
    if total > target:
        for o in skinned:
            mod = o.modifiers.new("dec", "DECIMATE")
            mod.ratio = target / total
            mod.use_collapse_triangulate = True
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_move_to_index(modifier="dec", index=0)
            bpy.ops.object.modifier_apply(modifier="dec")
    return tris()


def join_skinned() -> None:
    """One skinned mesh per character: the renderer pays per skinned mesh on every frame, and KayKit splits
    each body into six. Weapons and hats are bone-attached rigid meshes and stay separate (they toggle)."""
    skinned = [o for o in bpy.context.scene.objects
               if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)]
    if len(skinned) < 2:
        return
    bpy.ops.object.select_all(action="DESELECT")
    for o in skinned:
        o.select_set(True)
    bpy.context.view_layer.objects.active = skinned[0]
    bpy.ops.object.join()
    skinned[0].name = "Body"


def build(name: str, e: dict) -> dict:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, e["src"]))
    arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
    for gl, bone in e.get("attach", []):
        before = set(bpy.context.scene.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, gl))
        for o in set(bpy.context.scene.objects) - before:
            if o.type == "MESH":
                o.parent = arm
                o.parent_type = "BONE"
                o.parent_bone = bone
                o.matrix_parent_inverse.identity()
                o.location = (0, -arm.data.bones[bone].length, 0)  # bone parenting sits at the tail; KayKit slots use the head
                o.rotation_euler = (0, 0, 0)
            else:
                bpy.data.objects.remove(o)
    for o in list(bpy.context.scene.objects):
        if o.name.startswith("Icosphere") or o.name in e.get("drop", []):
            bpy.data.objects.remove(o)
    # animations: keep one action per short name, renamed
    by_short = {short(a.name): a for a in bpy.data.actions}
    keep = {}
    for canon, cands in e["anims"].items():
        for c in cands:
            if c in by_short:
                keep[canon] = by_short[c]
                break
        else:
            print("WARN", name, "missing", canon, cands)
    for a in list(bpy.data.actions):
        if a not in keep.values():
            bpy.data.actions.remove(a)
    for canon, a in keep.items():
        if a.name != canon and list(keep.values()).count(a) > 1:
            a = a.copy()
        a.name = canon
        a.use_fake_user = True
    if "hue" in e:
        recolor(*e["hue"])
    tris = decimate(e.get("tris", TRIS))
    join_skinned()
    # standing height in rest pose, body only (weapons and slot meshes left out)
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    zs = []
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and not o.parent_bone.startswith("handslot"):
            ev = o.evaluated_get(bpy.context.evaluated_depsgraph_get())
            zs += [(o.matrix_world @ v.co).z for v in ev.to_mesh().vertices]
    arm.data.pose_position = "POSE"
    if "portrait" in e:
        portrait(name, e["portrait"], arm, min(zs), max(zs))
    out = os.path.join(OUT, name + ".glb")
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_animations=True,
                              export_animation_mode="ACTIONS", export_optimize_animation_size=True)
    return {"height": round(max(zs) - min(zs), 3), "anims": sorted(keep), "tris": tris}


manifest = {}
only = args[2:]  # optional: names to rebuild
for group in ("heroes", "monsters"):
    for name, e in CFG[group].items():
        if only and name not in only:
            continue
        manifest[name] = build(name, e)
        print("BUILT", name, manifest[name])
path = os.path.join(OUT, "manifest.json")
if only and os.path.exists(path):
    old = json.load(open(path))
    old.update(manifest)
    manifest = old
json.dump(manifest, open(path, "w"), indent=1, sort_keys=True)

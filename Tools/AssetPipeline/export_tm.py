# Экспорт .blend -> .tmdl (raw-deflate: 'TMDL', ver, jsonLen, json, pad4, blob)
import bpy, bmesh, sys, json, struct, zlib, os, math
import numpy as np
from mathutils import Matrix, Vector

cfg = json.load(open(sys.argv[-1]))
src = cfg["blend"]
if src.endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=src)
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if src.endswith(".fbx"): bpy.ops.import_scene.fbx(filepath=src)
    else: bpy.ops.wm.usd_import(filepath=src)
    bpy.context.view_layer.update()
AX = Matrix.Translation(Vector(cfg.get("shift", [0,0,0]))) @ Matrix(cfg["axis"]).to_4x4()   # blender -> game
scale = cfg.get("scale", 1.0)
outdir = cfg["outdir"]; os.makedirs(outdir, exist_ok=True)

# Предобработка: подразбиение/геоноды пониже, лишнее прочь.
for o in list(bpy.data.objects):
    if o.name in cfg.get("drop", []) or any(o.name.startswith(p) for p in cfg.get("dropPrefix", [])) or o.type not in ("MESH",):
        if o.type == "MESH": bpy.data.objects.remove(o, do_unlink=True)
        continue
    for m in o.modifiers:
        if m.type == "SUBSURF":
            m.levels = cfg.get("subsurf", 1)
# Раскраска по отдельным деталям (когда текстур нет): детали по убыванию размера -> материалы.
for oname, spec in cfg.get("colorParts", {}).items():
    o = bpy.data.objects[oname]
    me = o.data
    me.materials.clear()
    names = []
    for mname, props in spec["materials"].items():
        mm = bpy.data.materials.new(mname); mm.use_nodes = True
        b = mm.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = props["color"]
        b.inputs["Metallic"].default_value = props.get("metallic", 0)
        b.inputs["Roughness"].default_value = props.get("roughness", 0.5)
        me.materials.append(mm); names.append(mname)
    bm = bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
    seen = set(); comps = []
    for f in bm.faces:
        if f.index in seen: continue
        st = [f]; comp = []; seen.add(f.index)
        while st:
            x = st.pop(); comp.append(x)
            for e in x.edges:
                for g in e.link_faces:
                    if g.index not in seen: seen.add(g.index); st.append(g)
        comps.append(comp)
    comps.sort(key=lambda c: -len({v.index for f in c for v in f.verts}))
    order = spec["order"]
    for i, comp in enumerate(comps):
        mname = order[i] if i < len(order) else spec["default"]
        for f in comp: f.material_index = names.index(mname)
    bm.to_mesh(me); bm.free()
for name, off in cfg.get("offset", {}).items():
    o = bpy.data.objects.get(name)
    if o: o.matrix_world = Matrix.Translation(Vector(off)) @ o.matrix_world
for name, ratio in cfg.get("decimate", {}).items():
    for o in bpy.data.objects:
        if o.type == "MESH" and (o.name == name or (name.endswith("*") and o.name.startswith(name[:-1]))):
            d = o.modifiers.new("dec", "DECIMATE")
            if isinstance(ratio, dict):
                d.decimate_type = ratio.get("type", "COLLAPSE")
                if d.decimate_type == "UNSUBDIV": d.iterations = ratio.get("iterations", 1)
                else: d.ratio = ratio.get("ratio", 0.5)
            else:
                d.ratio = ratio

# Скелет: меши выгружаем в позе привязки, кости — мировыми матрицами в осях игры.
SKIN = cfg.get("skinned", False)
bones = []; boneIndex = {}; skeleton = []
if SKIN:
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    for o in bpy.data.objects:
        if o.type == "MESH":
            for m in o.modifiers:
                if m.type == "ARMATURE": m.show_viewport = False
            if o.data.shape_keys: o.shape_key_clear()
    def walk(b):
        bones.append(b)
        for c in b.children: walk(c)
    for b in arm.data.bones:
        if b.parent is None: walk(b)
    for i, b in enumerate(bones): boneIndex[b.name] = i
    for b in bones:
        Mb = AX @ Matrix.Scale(scale, 4) @ arm.matrix_world @ b.matrix_local
        loc, rot, _ = Mb.decompose()
        skeleton.append({"name": b.name, "parent": boneIndex[b.parent.name] if b.parent else -1,
                         "position": [loc.x, loc.y, loc.z], "rotation": [rot.x, rot.y, rot.z, rot.w]})
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()

materials = []; matIndex = {}
def mat_id(m):
    name = m.name if m else "default"
    if name in matIndex: return matIndex[name]
    rec = {"name": name, "color": [0.8,0.8,0.8,1], "metallic": 0.0, "roughness": 0.5,
           "emission": [0,0,0], "transmission": 0.0, "texture": None}
    rec["alphaCutout"] = False
    if m and m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                rec["color"] = list(n.inputs["Base Color"].default_value)
                rec["metallic"] = n.inputs["Metallic"].default_value
                rec["roughness"] = n.inputs["Roughness"].default_value
                e = n.inputs["Emission Color"].default_value; s = n.inputs["Emission Strength"].default_value
                rec["emission"] = [e[0]*s, e[1]*s, e[2]*s]
                rec["transmission"] = n.inputs["Transmission Weight"].default_value
        def save_img(img, role):
            fn = cfg["prefix"] + "_" + "".join(c if c.isalnum() else "_" for c in os.path.splitext(img.name)[0])
            cut = role == "base" and any(k in (m.name + img.name) for k in cfg.get("alphaCutout", []))
            im2 = img.copy(); w, h = im2.size
            lim = cfg.get("maxTexture", 1024)
            k = min(1.0, lim / max(w, h))
            if k < 1: im2.scale(max(1, int(w*k)), max(1, int(h*k)))
            if not cut:
                # Альфа не нужна: иначе SceneKit делает прозрачной всю поверхность.
                px = np.empty(im2.size[0] * im2.size[1] * 4, np.float32); im2.pixels.foreach_get(px)
                px[3::4] = 1.0; im2.pixels.foreach_set(px)
                fn += ".jpg"; im2.file_format = "JPEG"
            else:
                fn += ".png"; im2.file_format = "PNG"
            im2.filepath_raw = os.path.join(outdir, fn); im2.save()
            return fn, cut
        links = m.node_tree.links
        def image_into(node_type, socket):
            for l in links:
                if l.to_node.type == node_type and l.to_socket.name == socket and l.from_node.type == "TEX_IMAGE" \
                        and l.from_node.image and (l.from_node.image.packed_file or l.from_node.image.has_data):
                    return l.from_node.image
            return None
        base = image_into("BSDF_PRINCIPLED", "Base Color")
        if base is None:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image and n.image.packed_file and "ormal" not in n.image.name:
                    base = n.image; break
        if base is not None:
            rec["texture"], rec["alphaCutout"] = save_img(base, "base")
        nrm = image_into("NORMAL_MAP", "Color")
        if nrm is not None and cfg.get("normalMaps", False):
            rec["normalTexture"], _ = save_img(nrm, "normal")
    materials.append(rec); matIndex[name] = len(materials) - 1
    return matIndex[name]

def mesh_arrays(o, M):
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    me.calc_loop_triangles()
    nt = len(me.loop_triangles)
    if nt == 0: ev.to_mesh_clear(); return []
    tl = np.zeros(nt*3, np.int32); me.loop_triangles.foreach_get("loops", tl)
    tm = np.zeros(nt, np.int32); me.loop_triangles.foreach_get("material_index", tm)
    lv = np.zeros(len(me.loops), np.int32); me.loops.foreach_get("vertex_index", lv)
    co = np.zeros(len(me.vertices)*3, np.float32); me.vertices.foreach_get("co", co); co = co.reshape(-1,3)
    cn = np.zeros(len(me.loops)*3, np.float32); me.corner_normals.foreach_get("vector", cn); cn = cn.reshape(-1,3)
    uv = np.zeros((len(me.loops),2), np.float32)
    if me.uv_layers.active:
        a = np.zeros(len(me.loops)*2, np.float32); me.uv_layers.active.data.foreach_get("uv", a); uv = a.reshape(-1,2)
    mats = [s.material for s in o.material_slots] or [None]
    BI = BW = None
    if SKIN:
        names = [g.name for g in o.vertex_groups]
        nv = len(me.vertices)
        BI = np.zeros((nv, 4), np.uint16); BW = np.zeros((nv, 4), np.float32)
        fallback = boneIndex.get(o.parent_bone) if o.parent_bone else 0
        for v in me.vertices:
            ws = sorted(((g.weight, boneIndex[names[g.group]]) for g in v.groups
                         if g.group < len(names) and names[g.group] in boneIndex and g.weight > 0), reverse=True)[:4]
            tot = sum(w for w, _ in ws)
            if tot <= 0:
                BI[v.index, 0] = fallback or 0; BW[v.index, 0] = 1; continue
            for k, (w, bi) in enumerate(ws):
                BI[v.index, k] = bi; BW[v.index, k] = w / tot
    ev.to_mesh_clear()
    W = np.array(M, np.float32)
    R = W[:3,:3]; T = W[:3,3]
    N = np.linalg.inv(R).T
    p = co[lv[tl]] @ R.T + T
    n = cn[tl] @ N.T
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-8)
    u = uv[tl].copy(); u[:,1] = 1 - u[:,1]
    flip = np.linalg.det(R) < 0
    vidx = lv[tl]
    out = []
    for mi in np.unique(tm):
        sel = np.repeat(tm == mi, 3)
        P, Nn, U, VI = p[sel], n[sel], u[sel], vidx[sel]
        if flip:
            idx = np.arange(len(P)).reshape(-1,3)[:, ::-1].reshape(-1); P, Nn, U, VI = P[idx], Nn[idx], U[idx], VI[idx]
        sk = (BI[VI], BW[VI]) if SKIN else None
        out.append((mat_id(mats[min(mi, len(mats)-1)]), P, Nn, U, sk))
    return out

parts = []
blob = bytearray()
def add_part(name, objs, pivot_world=None):
    pivot = np.zeros(3, np.float32)
    groups = {}
    for o in objs:
        M = AX @ Matrix.Scale(scale, 4) @ o.matrix_world
        for mid, P, Nn, U, sk in mesh_arrays(o, M):
            groups.setdefault(mid, []).append((P, Nn, U, sk))
    if not groups: return
    if pivot_world is not None:
        pivot = np.array(pivot_world, np.float32)
    subs = []
    allv = []; alls = []
    base = 0
    idxs = []
    for mid, lst in groups.items():
        P = np.concatenate([a[0] for a in lst]) - pivot
        Nn = np.concatenate([a[1] for a in lst]); U = np.concatenate([a[2] for a in lst])
        key = np.concatenate([np.round(P*2000), np.round(Nn*200), np.round(U*4000)], axis=1).astype(np.int64)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        V = np.concatenate([P[first], Nn[first], U[first]], axis=1).astype(np.float32)
        allv.append(V)
        if SKIN:
            SI = np.concatenate([a[3][0] for a in lst])[first]; SW = np.concatenate([a[3][1] for a in lst])[first]
            rec = np.zeros(len(V), dtype=[("i", "<u2", 4), ("w", "<f4", 4)]); rec["i"] = SI; rec["w"] = SW
            alls.append(rec)
        idxs.append((mid, (inv.reshape(-1) + base).astype(np.uint32)))
        base += len(V)
    V = np.concatenate(allv)
    voff = len(blob); blob.extend(V.tobytes())
    soff = -1
    if SKIN:
        soff = len(blob); blob.extend(np.concatenate(alls).tobytes())
    for mid, I in idxs:
        ioff = len(blob); blob.extend(I.tobytes())
        subs.append({"material": int(mid), "indexOffset": ioff, "indexCount": int(len(I))})
    lo = V[:,:3].min(0); hi = V[:,:3].max(0)
    parts.append({"name": name, "pivot": [float(x) for x in pivot], "vertexOffset": voff, "vertexCount": int(len(V)),
                  "skinOffset": soff,
                  "submeshes": subs, "min": [float(x) for x in lo], "max": [float(x) for x in hi]})
    print(f"part {name}: verts={len(V)} tris={sum(s['indexCount'] for s in subs)//3}")

def world_center(objs):
    pts = []
    for o in objs:
        for c in o.bound_box:
            pts.append(AX @ Matrix.Scale(scale,4) @ o.matrix_world @ Vector(c))
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return [(lo[i]+hi[i])/2 for i in range(3)]

used = set()
for spec in cfg["parts"]:
    objs = [o for o in bpy.data.objects if o.type == "MESH" and o.name not in used and
            (o.name in spec.get("objects", []) or spec.get("rest"))]
    for o in objs: used.add(o.name)
    piv = world_center(objs) if spec.get("pivotCenter") else None
    add_part(spec["name"], objs, piv)

while len(blob) % 4: blob.append(0)
head = json.dumps({"parts": parts, "materials": materials, "skeleton": skeleton}).encode()
while len(head) % 4: head += b" "
raw = b"TMDL" + struct.pack("<II", 1, len(head)) + head + bytes(blob)
co = zlib.compressobj(9, zlib.DEFLATED, -15)
data = co.compress(raw) + co.flush()
open(os.path.join(outdir, cfg["prefix"] + ".tmdl"), "wb").write(data)
print("materials", len(materials), "raw", len(raw), "packed", len(data))

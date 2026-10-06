# Экспорт .blend -> .tmdl (raw-deflate: 'TMDL', ver, jsonLen, json, pad4, blob)
import bpy, bmesh, sys, json, struct, zlib, os, math
import numpy as np
from mathutils import Matrix, Vector

cfg = json.load(open(sys.argv[-1]))
bpy.ops.wm.open_mainfile(filepath=cfg["blend"])
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
        if o.name == name or (name.endswith("*") and o.name.startswith(name[:-1])):
            d = o.modifiers.new("dec", "DECIMATE"); d.ratio = ratio
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()

materials = []; matIndex = {}
def mat_id(m):
    name = m.name if m else "default"
    if name in matIndex: return matIndex[name]
    rec = {"name": name, "color": [0.8,0.8,0.8,1], "metallic": 0.0, "roughness": 0.5,
           "emission": [0,0,0], "transmission": 0.0, "texture": None}
    if m and m.node_tree:
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                rec["color"] = list(n.inputs["Base Color"].default_value)
                rec["metallic"] = n.inputs["Metallic"].default_value
                rec["roughness"] = n.inputs["Roughness"].default_value
                e = n.inputs["Emission Color"].default_value; s = n.inputs["Emission Strength"].default_value
                rec["emission"] = [e[0]*s, e[1]*s, e[2]*s]
                rec["transmission"] = n.inputs["Transmission Weight"].default_value
            if n.type == "TEX_IMAGE" and n.image and n.image.packed_file and rec["texture"] is None:
                img = n.image
                fn = cfg["prefix"] + "_" + "".join(c if c.isalnum() else "_" for c in os.path.splitext(img.name)[0]) + ".png"
                im2 = img.copy(); w, h = im2.size
                k = min(1.0, 1024 / max(w, h))
                if k < 1: im2.scale(max(1,int(w*k)), max(1,int(h*k)))
                im2.filepath_raw = os.path.join(outdir, fn); im2.file_format = "PNG"; im2.save()
                rec["texture"] = fn
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
    ev.to_mesh_clear()
    W = np.array(M, np.float32)
    R = W[:3,:3]; T = W[:3,3]
    N = np.linalg.inv(R).T
    p = co[lv[tl]] @ R.T + T
    n = cn[tl] @ N.T
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-8)
    u = uv[tl].copy(); u[:,1] = 1 - u[:,1]
    flip = np.linalg.det(R) < 0
    out = []
    for mi in np.unique(tm):
        sel = np.repeat(tm == mi, 3)
        P, Nn, U = p[sel], n[sel], u[sel]
        if flip:
            idx = np.arange(len(P)).reshape(-1,3)[:, ::-1].reshape(-1); P, Nn, U = P[idx], Nn[idx], U[idx]
        out.append((mat_id(mats[min(mi, len(mats)-1)]), P, Nn, U))
    return out

parts = []
blob = bytearray()
def add_part(name, objs, pivot_world=None):
    pivot = np.zeros(3, np.float32)
    groups = {}
    for o in objs:
        M = AX @ Matrix.Scale(scale, 4) @ o.matrix_world
        for mid, P, Nn, U in mesh_arrays(o, M):
            groups.setdefault(mid, []).append((P, Nn, U))
    if not groups: return
    if pivot_world is not None:
        pivot = np.array(pivot_world, np.float32)
    subs = []
    allv = []
    base = 0
    idxs = []
    for mid, lst in groups.items():
        P = np.concatenate([a[0] for a in lst]) - pivot
        Nn = np.concatenate([a[1] for a in lst]); U = np.concatenate([a[2] for a in lst])
        key = np.concatenate([np.round(P*2000), np.round(Nn*200), np.round(U*4000)], axis=1).astype(np.int64)
        _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
        V = np.concatenate([P[first], Nn[first], U[first]], axis=1).astype(np.float32)
        allv.append(V)
        idxs.append((mid, (inv.reshape(-1) + base).astype(np.uint32)))
        base += len(V)
    V = np.concatenate(allv)
    voff = len(blob); blob.extend(V.tobytes())
    for mid, I in idxs:
        ioff = len(blob); blob.extend(I.tobytes())
        subs.append({"material": int(mid), "indexOffset": ioff, "indexCount": int(len(I))})
    lo = V[:,:3].min(0); hi = V[:,:3].max(0)
    parts.append({"name": name, "pivot": [float(x) for x in pivot], "vertexOffset": voff, "vertexCount": int(len(V)),
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
head = json.dumps({"parts": parts, "materials": materials}).encode()
while len(head) % 4: head += b" "
raw = b"TMDL" + struct.pack("<II", 1, len(head)) + head + bytes(blob)
co = zlib.compressobj(9, zlib.DEFLATED, -15)
data = co.compress(raw) + co.flush()
open(os.path.join(outdir, cfg["prefix"] + ".tmdl"), "wb").write(data)
print("materials", len(materials), "raw", len(raw), "packed", len(data))

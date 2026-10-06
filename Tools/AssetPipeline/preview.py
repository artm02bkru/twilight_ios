# Читает .tmdl (как игра) и рендерит превью Cycles. args: file out.png cam(x,y,z game) target(x,y,z) [lens]
import bpy, sys, json, struct, zlib, math
import numpy as np
from mathutils import Vector
a = sys.argv[sys.argv.index("--")+1:]
path, out = a[0], a[1]
views = json.loads(a[2])
raw = zlib.decompress(open(path,"rb").read(), -15)
assert raw[:4] == b"TMDL"
ver, jl = struct.unpack("<II", raw[4:12]); head = json.loads(raw[12:12+jl]); blob = raw[12+jl:]
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
mats = []
for m in head["materials"]:
    mm = bpy.data.materials.new(m["name"]); mm.use_nodes = True
    b = mm.node_tree.nodes["Principled BSDF"]
    col = m["color"]
    if m["name"] == "Car Paint": col = [0.33, 0.06, 0.04, 1]
    b.inputs["Base Color"].default_value = col
    b.inputs["Metallic"].default_value = m["metallic"]; b.inputs["Roughness"].default_value = m["roughness"]
    b.inputs["Emission Color"].default_value = list(m["emission"]) + [1]; b.inputs["Emission Strength"].default_value = 1
    if m["transmission"] > 0.5 or "Glass" in m["name"]: b.inputs["Alpha"].default_value = 0.35
    mats.append(mm)
# game (x,y,z) y-up -> blender (x,-z,y)
def g2b(v): return (v[0], -v[2], v[1])
for p in head["parts"]:
    V = np.frombuffer(blob, np.float32, p["vertexCount"]*8, p["vertexOffset"]).reshape(-1,8)
    me = bpy.data.meshes.new(p["name"])
    piv = np.zeros(3) if len(head["parts"]) == 1 else np.array(p["pivot"])
    verts = [g2b(v[:3] + piv) for v in V]
    faces = []; fm = []
    for i, s in enumerate(p["submeshes"]):
        I = np.frombuffer(blob, np.uint32, s["indexCount"], s["indexOffset"]).reshape(-1,3)
        faces += I.tolist(); fm += [i]*len(I)
        me.materials.append(mats[s["material"]])
    me.from_pydata(verts, [], faces); me.polygons.foreach_set("material_index", fm)
    me.polygons.foreach_set("use_smooth", [True]*len(faces))
    o = bpy.data.objects.new(p["name"], me); sc.collection.objects.link(o)
w = bpy.data.worlds.new("w"); w.use_nodes = True; w.node_tree.nodes["Background"].inputs[0].default_value = (0.55,0.6,0.7,1); w.node_tree.nodes["Background"].inputs[1].default_value = 0.8
sc.world = w
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun","SUN")); sun.data.energy = 3; sun.rotation_euler = (0.7, 0.2, 0.8); sc.collection.objects.link(sun)
sc.render.engine = "CYCLES"; sc.cycles.samples = 12; sc.cycles.device = "CPU"
sc.render.resolution_x, sc.render.resolution_y = 640, 400
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
for i, (eye, tgt, lens) in enumerate(views):
    cam.location = g2b(eye); d = Vector(g2b(tgt)) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler(); cam.data.lens = lens
    sc.render.filepath = out.replace(".png", f"_{i}.png"); bpy.ops.render.render(write_still=True)

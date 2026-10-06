# Проверка ретаргетинга: процедурный скелет (как в Humanoid.swift) -> кости аватара -> LBS -> OBJ
import sys, json, struct, zlib, math, numpy as np
src, out = sys.argv[1], sys.argv[2]
raw = zlib.decompress(open(src,"rb").read(), -15)
jl = struct.unpack("<I", raw[8:12])[0]; head = json.loads(raw[12:12+jl]); blob = raw[12+jl:]
part = head["parts"][0]; nv = part["vertexCount"]
V = np.frombuffer(blob, np.float32, nv*8, part["vertexOffset"]).reshape(-1,8)
sk = np.frombuffer(blob, dtype=[("i","<u2",4),("w","<f4",4)], count=nv, offset=part["skinOffset"])
skel = head["skeleton"]
def quat2m(q):
    x,y,z,w = q
    return np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
def Rx(a): c,s=math.cos(a),math.sin(a); return np.array([[1,0,0],[0,c,-s],[0,s,c]])
def Ry(a): c,s=math.cos(a),math.sin(a); return np.array([[c,0,s],[0,1,0],[-s,0,c]])
def Rz(a): c,s=math.cos(a),math.sin(a); return np.array([[c,-s,0],[s,c,0],[0,0,1]])
def E(v): return Ry(v[1]) @ Rx(v[0]) @ Rz(v[2])
# --- процедурный скелет
def proc(p):
    J = {}
    def put(name, parent, off, rot):
        if parent is None: J[name] = (rot, np.array(off, float)); return
        pr, pp = J[parent]; J[name] = (pr @ rot, pp + pr @ np.array(off, float))
    put("body", None, (0,p.get("rootY",0),0), E((p.get("rootPitch",0),0,0)))
    put("hips","body",(0,0.98,0),E(p.get("hips",(0,0,0))))
    put("spine","hips",(0,0.10,0),E(p.get("spine",(0,0,0))))
    put("chest","spine",(0,0.16,0),E(p.get("chest",(0,0,0))))
    put("neck","chest",(0,0.25,-0.01),E(p.get("neck",(0,0,0))))
    put("head","neck",(0,0.075,0.005),E(p.get("head",(0,0,0))))
    for s,sx in (("L",0.158),("R",-0.158)):
        put("shoulder"+s,"chest",(sx,0.2,-0.01),E(p.get("shoulder"+s,(0,0,0.07 if s=="L" else -0.07))))
        put("elbow"+s,"shoulder"+s,(0,-0.29,0),E((p.get("elbow"+s,-0.12),0,0)))
        put("hand"+s,"elbow"+s,(0,-0.25,0),E(p.get("wrist"+s,(0,0,0))))
        put("hip"+s,"hips",(0.095 if s=="L" else -0.095,-0.07,0),E(p.get("hip"+s,(0,0,0))))
        put("knee"+s,"hip"+s,(0,-0.445,0),E((p.get("knee"+s,0),0,0)))
        put("ankle"+s,"knee"+s,(0,-0.415,0),np.eye(3))
    return J
MAP = {"Hips":"hips","Spine":"spine","Spine1":"chest","Neck":"neck","Head":"head",
       "LeftArm":"shoulderL","LeftForeArm":"elbowL","LeftHand":"handL","RightArm":"shoulderR","RightForeArm":"elbowR","RightHand":"handR",
       "LeftUpLeg":"hipL","LeftLeg":"kneeL","LeftFoot":"ankleL","RightUpLeg":"hipR","RightLeg":"kneeR","RightFoot":"ankleR"}
REF = {"shoulderL":(0,0,math.pi/2),"shoulderR":(0,0,-math.pi/2),"elbowL":0,"elbowR":0}
ref = proc(REF)
bindR = [quat2m(b["rotation"]) for b in skel]; bindP = [np.array(b["position"]) for b in skel]
par = [b["parent"] for b in skel]
bindLocalR = []; bindLocalP = []
for i in range(len(skel)):
    if par[i] < 0: bindLocalR.append(bindR[i]); bindLocalP.append(bindP[i])
    else:
        pr = bindR[par[i]]; bindLocalR.append(pr.T @ bindR[i]); bindLocalP.append(pr.T @ (bindP[i]-bindP[par[i]]))
fit = 1.79 / part["max"][1]
def pose_mesh(p):
    J = proc(p)
    WR = [None]*len(skel); WP = [None]*len(skel)
    for i,b in enumerate(skel):
        j = MAP.get(b["name"])
        if par[i] < 0:
            hp = bindP[i] + (J["hips"][1] - ref["hips"][1]) / fit
            WP[i] = hp
        else:
            WP[i] = WP[par[i]] + WR[par[i]] @ bindLocalP[i]
        if j:
            WR[i] = J[j][0] @ ref[j][0].T @ bindR[i]
        else:
            WR[i] = WR[par[i]] @ bindLocalR[i] if par[i] >= 0 else bindR[i]
    # LBS
    P = V[:,:3].astype(np.float64); out = np.zeros_like(P)
    for k in range(4):
        idx = sk["i"][:,k]; w = sk["w"][:,k][:,None]
        Ms = np.stack([WR[i] @ bindR[i].T for i in range(len(skel))]); Ts = np.stack([WP[i] - WR[i] @ bindR[i].T @ bindP[i] for i in range(len(skel))])
        out += w * (np.einsum("nij,nj->ni", Ms[idx], P) + Ts[idx])
    return out * fit
poses = json.loads(sys.argv[3])
faces = []
for s in part["submeshes"]:
    faces.append(np.frombuffer(blob, np.uint32, s["indexCount"], s["indexOffset"]).reshape(-1,3))
F = np.concatenate(faces)
for n,(name,p) in enumerate(poses.items()):
    P = pose_mesh(p) + np.array([n*1.2,0,0])
    with open(out+f"_{name}.obj","w") as f:
        f.write("".join(f"v {x:.4f} {y:.4f} {z:.4f}\n" for x,y,z in P))
        f.write("".join(f"f {a+1} {b+1} {c+1}\n" for a,b,c in F))
print("ok", len(F))

import sys, json, struct, zlib, numpy as np
raw = zlib.decompress(open(sys.argv[1],"rb").read(), -15)
jl = struct.unpack("<I", raw[8:12])[0]; head = json.loads(raw[12:12+jl]); blob = raw[12+jl:]
for p in head["parts"]:
    V = np.frombuffer(blob, np.float32, p["vertexCount"]*8, p["vertexOffset"]).reshape(-1,8)
    print("PART", p["name"], "pivot", [round(x,3) for x in p["pivot"]], "min", [round(x,2) for x in p["min"]], "max", [round(x,2) for x in p["max"]])
    for s in p["submeshes"]:
        I = np.frombuffer(blob, np.uint32, s["indexCount"], s["indexOffset"])
        W = V[I]; m = head["materials"][s["material"]]
        P = W[:,:3]; U = W[:,6:8]
        area = 0
        T = P.reshape(-1,3,3); area = 0.5*np.linalg.norm(np.cross(T[:,1]-T[:,0], T[:,2]-T[:,0]),axis=1).sum()
        TU = U.reshape(-1,3,2); d1=TU[:,1]-TU[:,0]; d2=TU[:,2]-TU[:,0]; uva = 0.5*np.abs(d1[:,0]*d2[:,1]-d1[:,1]*d2[:,0]).sum()
        print(f"  {m['name']:22s} tris={len(I)//3:6d} min={np.round(P.min(0),2)} max={np.round(P.max(0),2)} uv/m2={uva/max(area,1e-6):.3f} tex={m['texture']}")

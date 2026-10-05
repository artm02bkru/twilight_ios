import SceneKit
import simd

// MARK: - Примитивы поля расстояний

/// Примитив поля расстояний со «слотом» материала и костью скелета.
///
/// Тело, лицо, волосы и кузова машин описываются набором таких фигур,
/// которые плавно сливаются (smooth-min), а потом превращаются в гладкую сетку.
struct SDFPrim {
    enum Shape {
        /// Конус со скруглёнными концами: от a (радиус ra) до b (радиус rb).
        case capsule(V3, V3, Float, Float)
        /// Эллипсоид: центр, полуоси, поворот мир→локально.
        case ellipsoid(V3, V3, simd_float3x3)
        /// Скруглённый параллелепипед: центр, полуразмеры, скругление, поворот мир→локально.
        case box(V3, V3, Float, simd_float3x3)
    }

    var shape: Shape
    var slot: Int
    var bone: Int
    /// Мягкость слияния с остальным телом, метры.
    var blend: Float
    /// Вычесть фигуру (глазницы, вырезы, колёсные арки).
    var subtract: Bool
    private(set) var lo = V3.zero
    private(set) var hi = V3.zero

    init(_ shape: Shape, slot: Int, bone: Int = 0, blend: Float = 0.02, subtract: Bool = false) {
        self.shape = shape
        self.slot = slot
        self.bone = bone
        self.blend = blend
        self.subtract = subtract
        let pad = blend * 2 + 0.004
        switch shape {
        case let .capsule(a, b, ra, rb):
            let r = max(ra, rb) + pad
            lo = simd_min(a, b) - V3(repeating: r)
            hi = simd_max(a, b) + V3(repeating: r)
        case let .ellipsoid(c, r, _):
            let m = max(r.x, max(r.y, r.z)) + pad
            lo = c - V3(repeating: m)
            hi = c + V3(repeating: m)
        case let .box(c, h, round, _):
            let m = simd_length(h) + round + pad
            lo = c - V3(repeating: m)
            hi = c + V3(repeating: m)
        }
    }

    @inline(__always)
    func near(_ p: V3) -> Bool {
        p.x >= lo.x && p.y >= lo.y && p.z >= lo.z && p.x <= hi.x && p.y <= hi.y && p.z <= hi.z
    }

    @inline(__always)
    func distance(_ p: V3) -> Float {
        switch shape {
        case let .capsule(a, b, ra, rb):
            let pa = p - a, ba = b - a
            let t = clampf(simd_dot(pa, ba) / max(1e-6, simd_dot(ba, ba)), 0, 1)
            return simd_length(pa - ba * t) - lerpf(ra, rb, t)
        case let .ellipsoid(c, r, rot):
            let q = rot * (p - c)
            let k0 = simd_length(q / r)
            let k1 = simd_length(q / (r * r))
            return k1 > 1e-6 ? k0 * (k0 - 1) / k1 : -min(r.x, min(r.y, r.z))
        case let .box(c, h, round, rot):
            let q = simd_abs(rot * (p - c)) - h
            return simd_length(simd_max(q, V3.zero)) + min(max(q.x, max(q.y, q.z)), 0) - round
        }
    }
}

@inline(__always) func smin(_ a: Float, _ b: Float, _ k: Float) -> Float {
    guard k > 0 else { return min(a, b) }
    let h = max(k - abs(a - b), 0) / k
    return min(a, b) - h * h * k * 0.25
}

@inline(__always) func smax(_ a: Float, _ b: Float, _ k: Float) -> Float {
    -smin(-a, -b, k)
}

/// Поворот «мир → локально» из углов Эйлера (для эллипсоидов и коробок).
func rotationToLocal(_ euler: V3) -> simd_float3x3 {
    let q = simd_quatf(angle: euler.z, axis: V3(0, 0, 1))
        * simd_quatf(angle: euler.y, axis: V3(0, 1, 0))
        * simd_quatf(angle: euler.x, axis: V3(1, 0, 0))
    return simd_float3x3(q).transpose
}

// MARK: - Модель

/// Набор примитивов и построение из них гладкой сетки.
final class SDFModel {

    private(set) var prims: [SDFPrim] = []

    func add(_ prim: SDFPrim) { prims.append(prim) }

    func capsule(_ a: V3, _ b: V3, _ ra: Float, _ rb: Float, slot: Int, bone: Int = 0, blend: Float = 0.02) {
        prims.append(SDFPrim(.capsule(a, b, ra, rb), slot: slot, bone: bone, blend: blend))
    }

    func ellipsoid(_ c: V3, _ r: V3, rotation: V3 = .zero, slot: Int, bone: Int = 0,
                   blend: Float = 0.02, subtract: Bool = false) {
        prims.append(SDFPrim(.ellipsoid(c, r, rotationToLocal(rotation)), slot: slot, bone: bone,
                             blend: blend, subtract: subtract))
    }

    func box(_ c: V3, _ half: V3, round: Float, rotation: V3 = .zero, slot: Int, bone: Int = 0,
             blend: Float = 0.02, subtract: Bool = false) {
        prims.append(SDFPrim(.box(c, half, round, rotationToLocal(rotation)), slot: slot, bone: bone,
                             blend: blend, subtract: subtract))
    }

    @inline(__always)
    func field(_ p: V3) -> Float {
        var d: Float = 10
        for i in 0..<prims.count {
            let pr = prims[i]
            guard pr.near(p) else { continue }
            let di = pr.distance(p)
            d = pr.subtract ? smax(d, -di, pr.blend) : smin(d, di, pr.blend)
        }
        return d
    }

    /// Ближайший примитив: его слот материала и кость.
    private func owner(_ p: V3) -> (slot: Int, bone: Int) {
        var best: Float = .greatestFiniteMagnitude
        var result = (slot: 0, bone: 0)
        for pr in prims where !pr.subtract {
            let d = pr.distance(p)
            if d < best {
                best = d
                result = (pr.slot, pr.bone)
            }
        }
        return result
    }

    /// Веса костей для вершины: чем ближе фигуры кости, тем больше вес.
    private func boneWeights(_ p: V3, boneCount: Int) -> (SIMD4<UInt16>, SIMD4<Float>) {
        var dist = [Float](repeating: .greatestFiniteMagnitude, count: boneCount)
        for pr in prims where !pr.subtract {
            let d = pr.distance(p)
            if d < dist[pr.bone] { dist[pr.bone] = d }
        }
        let dmin = dist.min() ?? 0
        var ranked: [(Int, Float)] = []
        for (b, d) in dist.enumerated() where d < dmin + 0.08 {
            ranked.append((b, exp(-(d - dmin) / 0.014)))
        }
        ranked.sort { $0.1 > $1.1 }
        var idx = SIMD4<UInt16>(0, 0, 0, 0)
        var w = SIMD4<Float>(0, 0, 0, 0)
        var total: Float = 0
        for i in 0..<min(4, ranked.count) where ranked[i].1 > 0.02 {
            idx[i] = UInt16(ranked[i].0)
            w[i] = ranked[i].1
            total += ranked[i].1
        }
        if total > 0 { w /= total } else { w = SIMD4(1, 0, 0, 0) }
        return (idx, w)
    }

    // MARK: Сетка

    /// Строит гладкую сетку методом surface nets.
    /// cell — шаг сетки в метрах; boneCount > 0 — посчитать веса для скиннинга.
    func mesh(cell: Float, boneCount: Int = 0, uvScale: Float = 1) -> MeshData {
        var lo = V3(repeating: .greatestFiniteMagnitude)
        var hi = V3(repeating: -.greatestFiniteMagnitude)
        for pr in prims where !pr.subtract {
            lo = simd_min(lo, pr.lo)
            hi = simd_max(hi, pr.hi)
        }
        lo -= V3(repeating: cell * 2)
        hi += V3(repeating: cell * 2)
        let nx = Int(ceil((hi.x - lo.x) / cell)) + 1
        let ny = Int(ceil((hi.y - lo.y) / cell)) + 1
        let nz = Int(ceil((hi.z - lo.z) / cell)) + 1
        guard nx > 2, ny > 2, nz > 2 else { return MeshData() }

        @inline(__always) func index(_ x: Int, _ y: Int, _ z: Int) -> Int { x + nx * (y + ny * z) }
        @inline(__always) func point(_ x: Int, _ y: Int, _ z: Int) -> V3 {
            lo + V3(Float(x), Float(y), Float(z)) * cell
        }

        // 1. Значения поля. Блоки далеко от поверхности заполняем одним значением.
        var values = [Float](repeating: 1, count: nx * ny * nz)
        let block = 4
        let blockReach = cell * Float(block) * 0.9
        var bz = 0
        while bz < nz {
            var by = 0
            while by < ny {
                var bx = 0
                while bx < nx {
                    let ex = min(nx, bx + block), ey = min(ny, by + block), ez = min(nz, bz + block)
                    let center = point(bx, by, bz) + V3(Float(ex - bx - 1), Float(ey - by - 1), Float(ez - bz - 1)) * cell * 0.5
                    let dc = field(center)
                    if abs(dc) > blockReach {
                        for z in bz..<ez { for y in by..<ey { for x in bx..<ex { values[index(x, y, z)] = dc } } }
                    } else {
                        for z in bz..<ez { for y in by..<ey { for x in bx..<ex {
                            values[index(x, y, z)] = field(point(x, y, z))
                        } } }
                    }
                    bx += block
                }
                by += block
            }
            bz += block
        }

        // 2. Вершина в каждой ячейке, через которую проходит поверхность.
        let cx = nx - 1, cy = ny - 1, cz = nz - 1
        var cellVertex = [Int32](repeating: -1, count: cx * cy * cz)
        @inline(__always) func cellIndex(_ x: Int, _ y: Int, _ z: Int) -> Int { x + cx * (y + cy * z) }

        var positions: [V3] = []
        var corner = [Float](repeating: 0, count: 8)
        for z in 0..<cz {
            for y in 0..<cy {
                for x in 0..<cx {
                    var mask = 0
                    for c in 0..<8 {
                        let v = values[index(x + (c & 1), y + ((c >> 1) & 1), z + ((c >> 2) & 1))]
                        corner[c] = v
                        if v < 0 { mask |= 1 << c }
                    }
                    if mask == 0 || mask == 255 { continue }
                    var sum = V3.zero
                    var count: Float = 0
                    for c in 0..<8 {
                        for bit in [1, 2, 4] where c & bit == 0 {
                            let d = c | bit
                            let a = corner[c], b = corner[d]
                            if (a < 0) == (b < 0) { continue }
                            let t = a / (a - b)
                            let pa = V3(Float(c & 1), Float((c >> 1) & 1), Float((c >> 2) & 1))
                            let pb = V3(Float(d & 1), Float((d >> 1) & 1), Float((d >> 2) & 1))
                            sum += pa + (pb - pa) * t
                            count += 1
                        }
                    }
                    let local = sum / max(1, count)
                    cellVertex[cellIndex(x, y, z)] = Int32(positions.count)
                    positions.append(lo + (V3(Float(x), Float(y), Float(z)) + local) * cell)
                }
            }
        }

        // 3. Нормали по градиенту поля — отсюда гладкое освещение.
        let eps = cell * 0.5
        var normals: [V3] = positions.map { p in
            let g = V3(field(p + V3(eps, 0, 0)) - field(p - V3(eps, 0, 0)),
                       field(p + V3(0, eps, 0)) - field(p - V3(0, eps, 0)),
                       field(p + V3(0, 0, eps)) - field(p - V3(0, 0, eps)))
            let l = simd_length(g)
            return l > 1e-8 ? g / l : V3(0, 1, 0)
        }

        // 4. Четырёхугольник на каждое ребро сетки, пересекающее поверхность.
        var quads: [(Int32, Int32, Int32, Int32)] = []
        let dims = [nx, ny, nz]
        for z in 0..<nz {
            for y in 0..<ny {
                for x in 0..<nx {
                    let s = [x, y, z]
                    let v0 = values[index(x, y, z)]
                    for axis in 0..<3 {
                        var e = s
                        e[axis] += 1
                        if e[axis] >= dims[axis] || s[axis] > dims[axis] - 2 { continue }
                        let v1 = values[index(e[0], e[1], e[2])]
                        if (v0 < 0) == (v1 < 0) { continue }
                        let u = (axis + 1) % 3, w = (axis + 2) % 3
                        if s[u] < 1 || s[w] < 1 || s[u] > dims[u] - 2 || s[w] > dims[w] - 2 { continue }
                        func cellAt(_ du: Int, _ dw: Int) -> Int32 {
                            var c = s
                            c[u] -= du
                            c[w] -= dw
                            return cellVertex[cellIndex(c[0], c[1], c[2])]
                        }
                        let a = cellAt(1, 1), b = cellAt(0, 1), c = cellAt(0, 0), d = cellAt(1, 0)
                        if a < 0 || b < 0 || c < 0 || d < 0 { continue }
                        quads.append((a, b, c, d))
                    }
                }
            }
        }

        // 5. Слоты материалов, веса костей, UV.
        var vertexSlot = [Int](repeating: 0, count: positions.count)
        var boneIdx: [SIMD4<UInt16>] = []
        var boneW: [SIMD4<Float>] = []
        if boneCount > 0 {
            boneIdx.reserveCapacity(positions.count)
            boneW.reserveCapacity(positions.count)
        }
        var uvs: [SIMD2<Float>] = []
        uvs.reserveCapacity(positions.count)
        for (i, p) in positions.enumerated() {
            vertexSlot[i] = owner(p).slot
            if boneCount > 0 {
                let (bi, bw) = boneWeights(p, boneCount: boneCount)
                boneIdx.append(bi)
                boneW.append(bw)
            }
            // Кубическая проекция по главной оси нормали.
            let n = simd_abs(normals[i])
            let uv: SIMD2<Float>
            if n.x >= n.y && n.x >= n.z { uv = SIMD2(p.z, p.y) }
            else if n.y >= n.z { uv = SIMD2(p.x, p.z) }
            else { uv = SIMD2(p.x, p.y) }
            uvs.append(uv * uvScale)
        }

        // Лёгкое сглаживание — убирает «ступеньки» сетки, не трогая форму.
        var neighbors = [[Int32]](repeating: [], count: positions.count)
        for q in quads {
            let ring = [q.0, q.1, q.2, q.3]
            for k in 0..<4 {
                neighbors[Int(ring[k])].append(ring[(k + 1) % 4])
                neighbors[Int(ring[k])].append(ring[(k + 3) % 4])
            }
        }
        for _ in 0..<2 {
            var next = positions
            for i in 0..<positions.count where !neighbors[i].isEmpty {
                var avg = V3.zero
                for j in neighbors[i] { avg += positions[Int(j)] }
                avg /= Float(neighbors[i].count)
                next[i] = positions[i] + (avg - positions[i]) * 0.5
            }
            positions = next
        }

        var mesh = MeshData()
        let slotCount = (prims.map { $0.slot }.max() ?? 0) + 1
        mesh.triangles = [[UInt32]](repeating: [], count: slotCount)
        for q in quads {
            var (a, b, c, d) = (Int(q.0), Int(q.1), Int(q.2), Int(q.3))
            let tn = simd_cross(positions[b] - positions[a], positions[c] - positions[a])
            if simd_dot(tn, normals[a] + normals[b] + normals[c]) < 0 { swap(&b, &d) }
            for tri in [(a, b, c), (a, c, d)] {
                let s0 = vertexSlot[tri.0], s1 = vertexSlot[tri.1], s2 = vertexSlot[tri.2]
                let slot = (s1 == s2) ? s1 : s0
                mesh.triangles[slot].append(contentsOf: [UInt32(tri.0), UInt32(tri.1), UInt32(tri.2)])
            }
        }
        // Перепроверить нормали после сглаживания.
        for i in 0..<positions.count {
            let p = positions[i]
            let g = V3(field(p + V3(eps, 0, 0)) - field(p - V3(eps, 0, 0)),
                       field(p + V3(0, eps, 0)) - field(p - V3(0, eps, 0)),
                       field(p + V3(0, 0, eps)) - field(p - V3(0, 0, eps)))
            let l = simd_length(g)
            if l > 1e-8 { normals[i] = g / l }
        }
        mesh.positions = positions
        mesh.normals = normals
        mesh.uvs = uvs
        mesh.boneIndices = boneIdx
        mesh.boneWeights = boneW
        return mesh
    }
}

// MARK: - Готовая сетка

struct MeshData {
    var positions: [V3] = []
    var normals: [V3] = []
    var uvs: [SIMD2<Float>] = []
    /// Треугольники по слотам материалов.
    var triangles: [[UInt32]] = []
    var boneIndices: [SIMD4<UInt16>] = []
    var boneWeights: [SIMD4<Float>] = []

    var isEmpty: Bool { positions.isEmpty }

    /// SceneKit-геометрия: по элементу на каждый непустой слот.
    /// materials — по слоту; пустые слоты пропускаются.
    func geometry(materials: [SCNMaterial]) -> SCNGeometry {
        let verts = positions.map { SCNVector3($0.x, $0.y, $0.z) }
        let norms = normals.map { SCNVector3($0.x, $0.y, $0.z) }
        let uv = uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        var sources = [SCNGeometrySource(vertices: verts),
                       SCNGeometrySource(normals: norms)]
        if !uv.isEmpty { sources.append(SCNGeometrySource(textureCoordinates: uv)) }

        var elements: [SCNGeometryElement] = []
        var mats: [SCNMaterial] = []
        for (slot, tris) in triangles.enumerated() where !tris.isEmpty {
            elements.append(SCNGeometryElement(indices: tris, primitiveType: .triangles))
            mats.append(materials[min(slot, materials.count - 1)])
        }
        let g = SCNGeometry(sources: sources, elements: elements)
        g.materials = mats
        return g
    }

    func boneIndexSource() -> SCNGeometrySource {
        let data = boneIndices.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: .boneIndices, vectorCount: boneIndices.count,
                                 usesFloatComponents: false, componentsPerVector: 4,
                                 bytesPerComponent: MemoryLayout<UInt16>.size, dataOffset: 0,
                                 dataStride: MemoryLayout<SIMD4<UInt16>>.stride)
    }

    func boneWeightSource() -> SCNGeometrySource {
        let data = boneWeights.withUnsafeBufferPointer { Data(buffer: $0) }
        return SCNGeometrySource(data: data, semantic: .boneWeights, vectorCount: boneWeights.count,
                                 usesFloatComponents: true, componentsPerVector: 4,
                                 bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                 dataStride: MemoryLayout<SIMD4<Float>>.stride)
    }
}

/// Кеш сеток: Эдвард появляется на пяти площадках, строим его один раз.
enum MeshCache {
    private static var store: [String: MeshData] = [:]
    private static let lock = NSLock()

    static func mesh(_ key: String, build: () -> MeshData) -> MeshData {
        lock.lock()
        if let m = store[key] { lock.unlock(); return m }
        lock.unlock()
        let m = build()
        lock.lock()
        store[key] = m
        lock.unlock()
        return m
    }
}

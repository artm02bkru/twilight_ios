import Foundation
import SceneKit
import UIKit
import simd

/// Готовая модель из Blender (папка Models, файлы .tmdl).
/// Формат пишет конвертер Tools/AssetPipeline/export_tm.py: сжатый DEFLATE блок
/// «TMDL», версия, JSON-описание частей и материалов, затем вершины
/// (позиция, нормаль, UV — 8 float) и индексы треугольников (UInt32).
/// Оси уже игровые: Y вверх, перёд машины по +Z, метры.
final class ModelAsset {

    struct Material: Decodable {
        let name: String
        let color: [Float]
        let metallic: Float
        let roughness: Float
        let emission: [Float]
        let transmission: Float
        let texture: String?
        let normalTexture: String?
        /// Текстура с вырезами по альфе (листья, пряди волос).
        let alphaCutout: Bool?
    }

    /// Кость скелета в позе привязки (мировые координаты модели).
    struct BoneInfo: Decodable {
        let name: String
        let parent: Int
        let position: [Float]
        let rotation: [Float]   // x, y, z, w
        var bindPosition: V3 { V3(position[0], position[1], position[2]) }
        var bindRotation: simd_quatf { simd_quatf(ix: rotation[0], iy: rotation[1], iz: rotation[2], r: rotation[3]) }
    }

    struct Submesh: Decodable {
        let material: Int
        let indexOffset: Int
        let indexCount: Int
    }

    struct PartInfo: Decodable {
        let name: String
        let pivot: [Float]
        let vertexOffset: Int
        let vertexCount: Int
        /// Смещение весов скиннинга (4 × UInt16 индекса + 4 × Float веса на вершину), −1 — нет.
        let skinOffset: Int?
        let submeshes: [Submesh]
        let min: [Float]
        let max: [Float]
    }

    private struct Header: Decodable {
        let parts: [PartInfo]
        let materials: [Material]
        let skeleton: [BoneInfo]?
    }

    /// Часть модели: геометрия в локальных координатах вокруг pivot.
    struct Part {
        let info: PartInfo
        let geometry: SCNGeometry
        /// Источники индексов и весов костей (для персонажей со скелетом).
        let boneIndices: SCNGeometrySource?
        let boneWeights: SCNGeometrySource?
        var pivot: V3 { V3(info.pivot[0], info.pivot[1], info.pivot[2]) }
        var boundsMin: V3 { V3(info.min[0], info.min[1], info.min[2]) }
        var boundsMax: V3 { V3(info.max[0], info.max[1], info.max[2]) }
        /// Материал каждого элемента геометрии.
        var materialIndices: [Int] { info.submeshes.map(\.material) }
    }

    let name: String
    let materials: [Material]
    /// Скелет (родители раньше детей); пуст у статичных моделей.
    let skeleton: [BoneInfo]
    private(set) var parts: [String: Part] = [:]
    private(set) var partOrder: [String] = []

    // MARK: - Загрузка

    private static var cache: [String: ModelAsset] = [:]
    private static var images: [String: UIImage] = [:]
    private static let lock = NSLock()

    /// Модель из бандла; кешируется — повторные узлы делят буферы GPU.
    static func named(_ name: String) -> ModelAsset? {
        lock.lock()
        if let m = cache[name] { lock.unlock(); return m }
        lock.unlock()
        guard let url = Bundle.main.url(forResource: name, withExtension: "tmdl", subdirectory: "Models")
                ?? Bundle.main.url(forResource: name, withExtension: "tmdl"),
              let packed = try? Data(contentsOf: url),
              let model = ModelAsset(name: name, packed: packed) else {
            print("ModelAsset: не удалось загрузить \(name)")
            return nil
        }
        lock.lock()
        cache[name] = model
        lock.unlock()
        return model
    }

    /// Текстура из папки Models.
    static func image(_ file: String) -> UIImage? {
        lock.lock()
        if let i = images[file] { lock.unlock(); return i }
        lock.unlock()
        let base = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Models")
                ?? Bundle.main.url(forResource: base, withExtension: ext),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        lock.lock()
        images[file] = img
        lock.unlock()
        return img
    }

    private init?(name: String, packed: Data) {
        self.name = name
        guard let raw = try? (packed as NSData).decompressed(using: .zlib) as Data,
              raw.count > 12,
              raw.prefix(4) == Data("TMDL".utf8) else { return nil }
        func u32(_ at: Int) -> Int {
            raw.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: at, as: UInt32.self).littleEndian) }
        }
        let jsonLength = u32(8)
        let blobStart = 12 + jsonLength
        guard raw.count >= blobStart,
              let header = try? JSONDecoder().decode(Header.self, from: raw.subdata(in: 12..<blobStart)) else {
            return nil
        }
        materials = header.materials
        skeleton = header.skeleton ?? []
        let blob = raw.subdata(in: blobStart..<raw.count)
        let stride = 8 * MemoryLayout<Float>.size

        for info in header.parts {
            let vStart = info.vertexOffset, vEnd = vStart + info.vertexCount * stride
            guard vEnd <= blob.count else { return nil }
            let vertexData = blob.subdata(in: vStart..<vEnd)
            let count = info.vertexCount
            let skinned = (info.skinOffset ?? -1) >= 0
            let positions: SCNGeometrySource
            let normals: SCNGeometrySource
            let uvs: SCNGeometrySource
            if skinned {
                // Для скиннинга SceneKit нужны отдельные (не перемежённые) буферы — как у процедурных тел.
                var p = [SCNVector3](), n = [SCNVector3](), t = [CGPoint]()
                p.reserveCapacity(count); n.reserveCapacity(count); t.reserveCapacity(count)
                vertexData.withUnsafeBytes { raw in
                    let f = raw.bindMemory(to: Float.self)
                    for i in 0..<count {
                        let o = i * 8
                        p.append(SCNVector3(f[o], f[o + 1], f[o + 2]))
                        n.append(SCNVector3(f[o + 3], f[o + 4], f[o + 5]))
                        t.append(CGPoint(x: CGFloat(f[o + 6]), y: CGFloat(f[o + 7])))
                    }
                }
                positions = SCNGeometrySource(vertices: p)
                normals = SCNGeometrySource(normals: n)
                uvs = SCNGeometrySource(textureCoordinates: t)
            } else {
                positions = SCNGeometrySource(data: vertexData, semantic: .vertex, vectorCount: count,
                                              usesFloatComponents: true, componentsPerVector: 3,
                                              bytesPerComponent: 4, dataOffset: 0, dataStride: stride)
                normals = SCNGeometrySource(data: vertexData, semantic: .normal, vectorCount: count,
                                            usesFloatComponents: true, componentsPerVector: 3,
                                            bytesPerComponent: 4, dataOffset: 12, dataStride: stride)
                uvs = SCNGeometrySource(data: vertexData, semantic: .texcoord, vectorCount: count,
                                        usesFloatComponents: true, componentsPerVector: 2,
                                        bytesPerComponent: 4, dataOffset: 24, dataStride: stride)
            }
            var elements: [SCNGeometryElement] = []
            for sub in info.submeshes {
                let iEnd = sub.indexOffset + sub.indexCount * 4
                guard iEnd <= blob.count else { return nil }
                elements.append(SCNGeometryElement(data: blob.subdata(in: sub.indexOffset..<iEnd),
                                                   primitiveType: .triangles,
                                                   primitiveCount: sub.indexCount / 3,
                                                   bytesPerIndex: 4))
            }
            let geometry = SCNGeometry(sources: [positions, normals, uvs], elements: elements)
            var indices: SCNGeometrySource?
            var weights: SCNGeometrySource?
            if let so = info.skinOffset, so >= 0 {
                let skinStride = 4 * 2 + 4 * 4
                let sEnd = so + count * skinStride
                guard sEnd <= blob.count else { return nil }
                var bi = [SIMD4<UInt16>](), bw = [SIMD4<Float>]()
                bi.reserveCapacity(count); bw.reserveCapacity(count)
                blob.withUnsafeBytes { raw in
                    for i in 0..<count {
                        let o = so + i * skinStride
                        bi.append(SIMD4(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self),
                                        raw.loadUnaligned(fromByteOffset: o + 2, as: UInt16.self),
                                        raw.loadUnaligned(fromByteOffset: o + 4, as: UInt16.self),
                                        raw.loadUnaligned(fromByteOffset: o + 6, as: UInt16.self)))
                        bw.append(SIMD4(raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self),
                                        raw.loadUnaligned(fromByteOffset: o + 12, as: Float.self),
                                        raw.loadUnaligned(fromByteOffset: o + 16, as: Float.self),
                                        raw.loadUnaligned(fromByteOffset: o + 20, as: Float.self)))
                    }
                }
                indices = SCNGeometrySource(data: bi.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .boneIndices,
                                            vectorCount: count, usesFloatComponents: false, componentsPerVector: 4,
                                            bytesPerComponent: MemoryLayout<UInt16>.size, dataOffset: 0,
                                            dataStride: MemoryLayout<SIMD4<UInt16>>.stride)
                weights = SCNGeometrySource(data: bw.withUnsafeBufferPointer { Data(buffer: $0) }, semantic: .boneWeights,
                                            vectorCount: count, usesFloatComponents: true, componentsPerVector: 4,
                                            bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                            dataStride: MemoryLayout<SIMD4<Float>>.stride)
            }
            parts[info.name] = Part(info: info, geometry: geometry, boneIndices: indices, boneWeights: weights)
            partOrder.append(info.name)
        }
    }

    // MARK: - Узлы

    /// Узел части в точке pivot (колёса крутятся вокруг своей оси).
    /// Материалы подбирает замыкание по описанию из Blender;
    /// nil — материал по умолчанию (цвет, металл, шероховатость из файла).
    func node(_ partName: String, material: (Material) -> SCNMaterial? = { _ in nil }) -> SCNNode? {
        guard let part = parts[partName] else { return nil }
        let geometry = (part.geometry.copy() as? SCNGeometry) ?? part.geometry
        var built: [Int: SCNMaterial] = [:]
        geometry.materials = part.materialIndices.map { index in
            if let m = built[index] { return m }
            let desc = materials[index]
            let m = material(desc) ?? Self.defaultMaterial(desc)
            built[index] = m
            return m
        }
        let n = SCNNode(geometry: geometry)
        n.name = partName
        n.simdPosition = part.pivot
        return n
    }

    /// Часть, поставленная на землю: центр основания — в начале координат возвращённого узла.
    func grounded(_ partName: String, material: (Material) -> SCNMaterial? = { _ in nil }) -> SCNNode? {
        guard let part = parts[partName], let inner = node(partName, material: material) else { return nil }
        let lo = part.boundsMin, hi = part.boundsMax
        inner.simdPosition = V3(-(lo.x + hi.x) / 2, -lo.y, -(lo.z + hi.z) / 2)
        let n = SCNNode()
        n.name = partName
        n.addChildNode(inner)
        return n
    }

    /// Роща из частей-деревьев: копии со случайным поворотом и размером, склеенные в одну
    /// геометрию на материал (мало вызовов отрисовки).
    static func grove(parts: [(model: String, part: String)], spots: [V3], scale: ClosedRange<Float>,
                      seed: UInt64) -> SCNNode? {
        var rng = SeededRandom(seed: seed)
        let group = SCNNode()
        for (i, p) in spots.enumerated() {
            let pick = parts[i % max(1, parts.count)]
            guard let t = ModelAsset.named(pick.model)?.grounded(pick.part) else { continue }
            t.simdPosition = p
            t.simdEulerAngles.y = rng.range(0, 6.28)
            t.simdScale = V3(repeating: rng.range(scale.lowerBound, scale.upperBound))
            group.addChildNode(t)
        }
        guard !group.childNodes.isEmpty else { return nil }
        let flat = group.flattenedClone()
        flat.castsShadow = false
        return flat
    }

    /// Все части одним узлом (статичная модель).
    func wholeNode(material: (Material) -> SCNMaterial? = { _ in nil }) -> SCNNode {
        let root = SCNNode()
        root.name = name
        for p in partOrder {
            if let n = node(p, material: material) { root.addChildNode(n) }
        }
        return root
    }

    /// PBR-материал по параметрам из Blender (цвета там линейные — переводим в sRGB).
    static func defaultMaterial(_ d: Material) -> SCNMaterial {
        let color = srgb(d.color)
        var diffuse: Any = color
        if let file = d.texture, let img = image(file) { diffuse = img }
        let m = Materials.pbr(diffuse,
                              roughness: CGFloat(max(0.03, d.roughness)),
                              metalness: CGFloat(d.metallic))
        let e = d.emission
        if e.count >= 3, e.max() ?? 0 > 0.01 {
            m.emission.contents = srgb([min(1, e[0]), min(1, e[1]), min(1, e[2]), 1])
        }
        if let file = d.normalTexture, let img = image(file) {
            m.normal.contents = img
            m.normal.intensity = 0.8
        }
        if d.alphaCutout == true { makeCutout(m) }
        if d.transmission > 0.5 {
            m.transparency = 0.25
            m.transparencyMode = .dualLayer
            m.roughness.contents = 0.05
        }
        return m
    }

    /// Вырез по альфе текстуры: пиксели прозрачнее половины отбрасываются,
    /// остальное рисуется непрозрачным — без проблем сортировки у листвы и прядей волос.
    static func makeCutout(_ m: SCNMaterial) {
        m.isDoubleSided = true
        m.writesToDepthBuffer = true
        m.shaderModifiers = [.fragment: """
        if (_output.color.a < 0.5) { discard_fragment(); }
        _output.color.a = 1.0;
        """]
    }

    static func srgb(_ c: [Float]) -> UIColor {
        func g(_ v: Float) -> CGFloat {
            let x = max(0, min(1, v))
            return CGFloat(x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055)
        }
        return UIColor(red: g(c.count > 0 ? c[0] : 0.8), green: g(c.count > 1 ? c[1] : 0.8),
                       blue: g(c.count > 2 ? c[2] : 0.8), alpha: CGFloat(c.count > 3 ? c[3] : 1))
    }
}

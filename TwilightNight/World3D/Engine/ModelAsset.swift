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
        let submeshes: [Submesh]
        let min: [Float]
        let max: [Float]
    }

    private struct Header: Decodable {
        let parts: [PartInfo]
        let materials: [Material]
    }

    /// Часть модели: геометрия в локальных координатах вокруг pivot.
    struct Part {
        let info: PartInfo
        let geometry: SCNGeometry
        var pivot: V3 { V3(info.pivot[0], info.pivot[1], info.pivot[2]) }
        var boundsMin: V3 { V3(info.min[0], info.min[1], info.min[2]) }
        var boundsMax: V3 { V3(info.max[0], info.max[1], info.max[2]) }
        /// Материал каждого элемента геометрии.
        var materialIndices: [Int] { info.submeshes.map(\.material) }
    }

    let name: String
    let materials: [Material]
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
        let blob = raw.subdata(in: blobStart..<raw.count)
        let stride = 8 * MemoryLayout<Float>.size

        for info in header.parts {
            let vStart = info.vertexOffset, vEnd = vStart + info.vertexCount * stride
            guard vEnd <= blob.count else { return nil }
            let vertexData = blob.subdata(in: vStart..<vEnd)
            let count = info.vertexCount
            let positions = SCNGeometrySource(data: vertexData, semantic: .vertex, vectorCount: count,
                                              usesFloatComponents: true, componentsPerVector: 3,
                                              bytesPerComponent: 4, dataOffset: 0, dataStride: stride)
            let normals = SCNGeometrySource(data: vertexData, semantic: .normal, vectorCount: count,
                                            usesFloatComponents: true, componentsPerVector: 3,
                                            bytesPerComponent: 4, dataOffset: 12, dataStride: stride)
            let uvs = SCNGeometrySource(data: vertexData, semantic: .texcoord, vectorCount: count,
                                        usesFloatComponents: true, componentsPerVector: 2,
                                        bytesPerComponent: 4, dataOffset: 24, dataStride: stride)
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
            parts[info.name] = Part(info: info, geometry: geometry)
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
        if d.transmission > 0.5 {
            m.transparency = 0.25
            m.transparencyMode = .dualLayer
            m.roughness.contents = 0.05
        }
        return m
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

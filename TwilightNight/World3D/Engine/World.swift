import UIKit
import SceneKit
import simd

// MARK: - Детерминированный шум

/// Простой value-noise + fBm. Одинаковый для одного и того же seed,
/// поэтому мир каждый раз выглядит одинаково.
struct ValueNoise {
    let seed: Int

    init(seed: Int = 1337) { self.seed = seed }

    private func hash(_ xi: Int, _ yi: Int) -> Float {
        var h = UInt64(truncatingIfNeeded: xi) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(truncatingIfNeeded: yi) &* 0xBF58_476D_1CE4_E5B9
        h ^= UInt64(truncatingIfNeeded: seed) &* 0x94D0_49BB_1331_11EB
        h ^= h >> 29
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 32
        return Float(h & 0xFFFF_FF) / Float(0xFFFF_FF)
    }

    func value(_ x: Float, _ y: Float) -> Float {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - Float(xi), yf = y - Float(yi)
        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)
        let a = hash(xi, yi), b = hash(xi + 1, yi)
        let c = hash(xi, yi + 1), d = hash(xi + 1, yi + 1)
        return (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v
    }

    func fbm(_ x: Float, _ y: Float, octaves: Int = 4,
             lacunarity: Float = 2.0, gain: Float = 0.5) -> Float {
        var sum: Float = 0, amp: Float = 1, freq: Float = 1, norm: Float = 0
        for _ in 0..<octaves {
            sum += value(x * freq, y * freq) * amp
            norm += amp
            amp *= gain
            freq *= lacunarity
        }
        return sum / norm
    }
}

// MARK: - Мелкие удобства

extension UIColor {
    var rgba4: SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }

    func lightened(_ k: Float) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, r + CGFloat(k)), green: min(1, g + CGFloat(k)),
                       blue: min(1, b + CGFloat(k)), alpha: a)
    }

    func darkened(_ k: Float) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: max(0, r - CGFloat(k)), green: max(0, g - CGFloat(k)),
                       blue: max(0, b - CGFloat(k)), alpha: a)
    }

    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension SCNVector3 {
    static func - (a: SCNVector3, b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z)
    }

    static func + (a: SCNVector3, b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z)
    }

    static func * (a: SCNVector3, s: Float) -> SCNVector3 {
        SCNVector3(a.x * s, a.y * s, a.z * s)
    }

    var length: Float { (x * x + y * y + z * z).squareRoot() }

    var normalized: SCNVector3 {
        let l = length
        return l > 0.0001 ? SCNVector3(x / l, y / l, z / l) : SCNVector3(0, 1, 0)
    }

    static func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.y * b.z - a.z * b.y,
                   a.z * b.x - a.x * b.z,
                   a.x * b.y - a.y * b.x)
    }
}

// MARK: - Сборщик мешей

/// Копит треугольники с цветами вершин и отдаёт одну геометрию.
/// Один узел на сотни елей — так сцена остаётся быстрой.
final class MeshBuilder {

    private var positions: [SCNVector3] = []
    private var normals: [SCNVector3] = []
    private var colors: [SIMD4<Float>] = []
    private var indices: [Int32] = []

    var isEmpty: Bool { positions.isEmpty }
    var triangleCount: Int { indices.count / 3 }

    func addTriangle(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3, _ color: UIColor) {
        let n = SCNVector3.cross(b - a, c - a).normalized
        let base = Int32(positions.count)
        let cc = color.rgba4
        positions.append(contentsOf: [a, b, c])
        normals.append(contentsOf: [n, n, n])
        colors.append(contentsOf: [cc, cc, cc])
        indices.append(contentsOf: [base, base + 1, base + 2])
    }

    func addQuad(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3, _ d: SCNVector3,
                 _ color: UIColor) {
        addTriangle(a, b, c, color)
        addTriangle(a, c, d, color)
    }

    /// Треугольник с разными цветами вершин (градиент травинки от корня к кончику).
    func addColoredTriangle(_ a: SCNVector3, _ ca: SIMD4<Float>,
                            _ b: SCNVector3, _ cb: SIMD4<Float>,
                            _ c: SCNVector3, _ cc: SIMD4<Float>,
                            normal n: SCNVector3) {
        let base = Int32(positions.count)
        positions.append(contentsOf: [a, b, c])
        normals.append(contentsOf: [n, n, n])
        colors.append(contentsOf: [ca, cb, cc])
        indices.append(contentsOf: [base, base + 1, base + 2])
    }

    /// Треугольник с собственными нормалями — для рельефа, где нужна гладкость.
    func addSmoothTriangle(_ a: SCNVector3, _ na: SCNVector3,
                           _ b: SCNVector3, _ nb: SCNVector3,
                           _ c: SCNVector3, _ nc: SCNVector3,
                           _ color: UIColor) {
        let base = Int32(positions.count)
        let cc = color.rgba4
        positions.append(contentsOf: [a, b, c])
        normals.append(contentsOf: [na, nb, nc])
        colors.append(contentsOf: [cc, cc, cc])
        indices.append(contentsOf: [base, base + 1, base + 2])
    }

    func addBox(center: SCNVector3, size: SCNVector3, color: UIColor,
                rotationY: Float = 0) {
        let hx = size.x / 2, hy = size.y / 2, hz = size.z / 2
        let corners = [
            SCNVector3(-hx, -hy, -hz), SCNVector3(hx, -hy, -hz),
            SCNVector3(hx, hy, -hz), SCNVector3(-hx, hy, -hz),
            SCNVector3(-hx, -hy, hz), SCNVector3(hx, -hy, hz),
            SCNVector3(hx, hy, hz), SCNVector3(-hx, hy, hz)
        ]
        let c = cos(rotationY), s = sin(rotationY)
        let p = corners.map { v -> SCNVector3 in
            SCNVector3(center.x + v.x * c - v.z * s,
                       center.y + v.y,
                       center.z + v.x * s + v.z * c)
        }
        let top = color.lightened(0.05)
        let side = color
        let bottom = color.darkened(0.12)
        addQuad(p[4], p[5], p[6], p[7], top)        // верх
        addQuad(p[1], p[0], p[3], p[2], bottom)     // низ
        addQuad(p[5], p[1], p[2], p[6], side)       // +z
        addQuad(p[0], p[4], p[7], p[3], side)       // -z
        addQuad(p[4], p[0], p[1], p[5], side)       // -x
        addQuad(p[3], p[7], p[6], p[2], side)       // +x
    }

    func addCone(base: SCNVector3, radius: Float, height: Float,
                 sides: Int = 7, color: UIColor) {
        let apex = SCNVector3(base.x, base.y + height, base.z)
        for i in 0..<sides {
            let a0 = Float(i) / Float(sides) * 2 * Float.pi
            let a1 = Float(i + 1) / Float(sides) * 2 * Float.pi
            let p0 = SCNVector3(base.x + cos(a0) * radius, base.y, base.z + sin(a0) * radius)
            let p1 = SCNVector3(base.x + cos(a1) * radius, base.y, base.z + sin(a1) * radius)
            // лёгкая вариация оттенка по граням — читается объём
            let shade = color.darkened(Float(i % 2) * 0.045)
            addTriangle(p0, p1, apex, shade)
            addTriangle(p1, p0, base, color.darkened(0.16))
        }
    }

    func addCylinder(bottom: SCNVector3, radius: Float, height: Float,
                     sides: Int = 8, color: UIColor) {
        let top = SCNVector3(bottom.x, bottom.y + height, bottom.z)
        for i in 0..<sides {
            let a0 = Float(i) / Float(sides) * 2 * Float.pi
            let a1 = Float(i + 1) / Float(sides) * 2 * Float.pi
            let b0 = SCNVector3(bottom.x + cos(a0) * radius, bottom.y, bottom.z + sin(a0) * radius)
            let b1 = SCNVector3(bottom.x + cos(a1) * radius, bottom.y, bottom.z + sin(a1) * radius)
            let t0 = SCNVector3(b0.x, top.y, b0.z)
            let t1 = SCNVector3(b1.x, top.y, b1.z)
            let shade = color.darkened(Float(i % 2) * 0.05)
            addQuad(b0, b1, t1, t0, shade)
            addTriangle(t0, t1, top, color.lightened(0.08))
        }
    }

    func geometry(name: String? = nil) -> SCNGeometry {
        let vertexSource = SCNGeometrySource(vertices: positions)
        let normalSource = SCNGeometrySource(normals: normals)
        let colorSource = SCNGeometrySource(
            data: colors.withUnsafeBytes { Data($0) },
            semantic: .color,
            vectorCount: colors.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD4<Float>>.stride
        )
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource, normalSource, colorSource],
                                   elements: [element])
        geometry.name = name
        return geometry
    }
}

// MARK: - Материалы

enum Materials {

    static func matte(roughness: CGFloat = 0.85) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor.white
        m.roughness.contents = roughness
        m.metalness.contents = 0.0
        return m
    }

    static func wet(roughness: CGFloat = 0.22) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor.white
        m.roughness.contents = roughness
        m.metalness.contents = 0.25
        return m
    }

    static func glossy(roughness: CGFloat = 0.30, metalness: CGFloat = 0.6) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor.white
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        return m
    }

    static func emissive(_ color: UIColor, intensity: CGFloat = 1.6) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = color
        m.emission.intensity = intensity
        return m
    }

    static func glass() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(hex: 0x1A2530)
        m.roughness.contents = 0.08
        m.metalness.contents = 0.0
        m.transparency = 0.82
        return m
    }
}

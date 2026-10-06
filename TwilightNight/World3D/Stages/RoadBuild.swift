import UIKit
import SceneKit

// MARK: - Дорога

/// Извилистая дорога: положение центра и высота как функции пройденного пути.
struct RoadPath {
    var length: Float = 1500
    var winding: Float = 30
    var slope: Float = 14

    func center(_ z: Float) -> Float {
        sin(z * 0.0070) * winding
            + sin(z * 0.0183 + 1.3) * winding * 0.34
            + sin(z * 0.0410 + 2.1) * winding * 0.10
    }

    func height(_ z: Float) -> Float {
        sin(z * 0.0042 + 0.7) * slope
            + sin(z * 0.0110 + 2.4) * slope * 0.34
    }

    /// Касательная в точке — нужна для разметки и поворота кузова.
    func tangent(_ z: Float) -> SCNVector3 {
        let dz: Float = 0.5
        let dx = center(z + dz) - center(z - dz)
        let dy = height(z + dz) - height(z - dz)
        return SCNVector3(dx, dy, 2 * dz).normalized
    }

    func heading(_ z: Float) -> Float {
        let dz: Float = 0.5
        let dx = center(z + dz) - center(z - dz)
        return atan2(dx, 2 * dz)
    }
}

// MARK: - Мир

enum RoadBuild {

    static let roadHalfWidth: Float = 8.0
    static let roadShoulder: Float = 20.0

    // MARK: Рельеф

    /// Высота земли в точке. Вдоль дороги — корыто, чтобы полотно не проваливалось.
    static func groundHeight(_ x: Float, _ z: Float, path: RoadPath, noise: ValueNoise) -> Float {
        let base = path.height(z)
        let d = abs(x - path.center(z))

        // Холмы тем выше, чем дальше от дороги.
        let far = min(1, max(0, (d - roadHalfWidth) / 260))
        let hills = (noise.fbm(x * 0.0042, z * 0.0042, octaves: 4) - 0.5) * 62 * (0.25 + far * 1.5)
        let detail = (noise.fbm(x * 0.020, z * 0.020, octaves: 3) - 0.5) * 5.0 * (0.3 + far)

        if d < roadHalfWidth {
            return base - 0.55
        }
        let u = min(1, (d - roadHalfWidth) / roadShoulder)
        let blend = u * u * (3 - 2 * u)
        return (base - 0.55) + blend * (hills + detail + 0.55)
    }

    static func groundNormal(_ x: Float, _ z: Float, path: RoadPath, noise: ValueNoise) -> SCNVector3 {
        let e: Float = 1.5
        let hl = groundHeight(x - e, z, path: path, noise: noise)
        let hr = groundHeight(x + e, z, path: path, noise: noise)
        let hd = groundHeight(x, z - e, path: path, noise: noise)
        let hu = groundHeight(x, z + e, path: path, noise: noise)
        return SCNVector3(hl - hr, 2 * e, hd - hu).normalized
    }

    /// Полотно земли вокруг дороги.
    static func terrain(path: RoadPath, seed: Int) -> SCNGeometry {
        let noise = ValueNoise(seed: seed)
        let zStart: Float = -80
        let zEnd = path.length + 120
        let zStep: Float = 6
        let colStep: Float = 5.5
        let colHalf: Float = 230

        let rows = Int((zEnd - zStart) / zStep) + 1
        let cols = Int(colHalf * 2 / colStep) + 1

        let builder = MeshBuilder()

        var heights = [Float](repeating: 0, count: rows * cols)
        var xs = [Float](repeating: 0, count: rows * cols)
        var zs = [Float](repeating: 0, count: rows * cols)

        for r in 0..<rows {
            let z = zStart + Float(r) * zStep
            for c in 0..<cols {
                let x = -colHalf + Float(c) * colStep
                let i = r * cols + c
                xs[i] = x
                zs[i] = z
                heights[i] = groundHeight(x, z, path: path, noise: noise)
            }
        }

        func color(at i: Int) -> UIColor {
            let x = xs[i], z = zs[i], h = heights[i]
            let d = abs(x - path.center(z))
            let n = noise.fbm(x * 0.03, z * 0.03, octaves: 3)

            if d < roadHalfWidth + 2.5 {
                return UIColor(hex: 0x4A4640).darkened(Float(n) * 0.06)
            }
            // трава, местами бурая и каменистая; выше — холоднее
            let grass = UIColor(hex: 0x3C5730)
            let dry = UIColor(hex: 0x5A5A38)
            let rock = UIColor(hex: 0x5C5F5E)
            var col = grass.mixed(with: dry, amount: CGFloat(n) * 0.55)
            let altitude = min(1, max(0, (h - 22) / 40))
            col = col.mixed(with: rock, amount: CGFloat(altitude) * 0.7)
            let far = min(1, max(0, (d - 60) / 200))
            col = col.darkened(Float(far) * 0.12)
            return col
        }

        for r in 0..<(rows - 1) {
            for c in 0..<(cols - 1) {
                let i00 = r * cols + c
                let i10 = r * cols + c + 1
                let i01 = (r + 1) * cols + c
                let i11 = (r + 1) * cols + c + 1

                let p00 = SCNVector3(xs[i00], heights[i00], zs[i00])
                let p10 = SCNVector3(xs[i10], heights[i10], zs[i10])
                let p01 = SCNVector3(xs[i01], heights[i01], zs[i01])
                let p11 = SCNVector3(xs[i11], heights[i11], zs[i11])

                let n00 = groundNormal(xs[i00], zs[i00], path: path, noise: noise)
                let n10 = groundNormal(xs[i10], zs[i10], path: path, noise: noise)
                let n01 = groundNormal(xs[i01], zs[i01], path: path, noise: noise)
                let n11 = groundNormal(xs[i11], zs[i11], path: path, noise: noise)

                let cA = color(at: i00)
                let cB = color(at: i10)
                let cC = color(at: i11)
                let cD = color(at: i01)

                builder.addSmoothTriangle(p00, n00, p10, n10, p11, n11, cA)
                builder.addSmoothTriangle(p00, n00, p11, n11, p01, n01, cA)
                _ = (cB, cC, cD)
            }
        }

        let geometry = builder.geometry(name: "terrain")
        geometry.materials = [Materials.matte(roughness: 0.92)]
        return geometry
    }

    // MARK: Дорога

    static func road(path: RoadPath) -> SCNGeometry {
        let builder = MeshBuilder()
        let zStep: Float = 4
        let asphalt = UIColor(hex: 0x2A2C30)
        let asphaltLight = UIColor(hex: 0x35383D)

        let count = Int(path.length / zStep) + 1
        var left: [SCNVector3] = []
        var right: [SCNVector3] = []

        for i in 0..<count {
            let z = Float(i) * zStep
            let cx = path.center(z)
            let y = path.height(z)
            let t = path.tangent(z)
            let nx = -t.z, nz = t.x
            let nl = SCNVector3(nx, 0, nz).normalized
            left.append(SCNVector3(cx + nl.x * roadHalfWidth, y, z + nl.z * roadHalfWidth))
            right.append(SCNVector3(cx - nl.x * roadHalfWidth, y, z - nl.z * roadHalfWidth))
        }

        for i in 0..<(count - 1) {
            let shade = i % 2 == 0 ? asphalt : asphaltLight
            builder.addQuad(left[i], right[i], right[i + 1], left[i + 1], shade)
        }

        let geometry = builder.geometry(name: "road")
        geometry.materials = [Materials.wet(roughness: 0.18)]
        return geometry
    }

    /// Разметка: сплошные кромки и прерывистая осевая.
    static func roadMarkings(path: RoadPath) -> SCNGeometry {
        let builder = MeshBuilder()
        let white = UIColor(hex: 0xD8D8D0)
        let yellow = UIColor(hex: 0xC8A83C)

        func edgeLine(offset: Float, color: UIColor, dash: Bool, dashLength: Float, gap: Float) {
            var z: Float = 0
            while z < path.length {
                let segEnd = min(path.length, z + (dash ? dashLength : 8))
                if !dash || Int(z / (dashLength + gap)) % 2 == 0 {
                    let steps = max(1, Int((segEnd - z) / 4))
                    for s in 0..<steps {
                        let z0 = z + (segEnd - z) * Float(s) / Float(steps)
                        let z1 = z + (segEnd - z) * Float(s + 1) / Float(steps)
                        for (za, zb) in [(z0, z1)] {
                            let ca = path.center(za), cb = path.center(zb)
                            let ya = path.height(za) + 0.03, yb = path.height(zb) + 0.03
                            let ta = path.tangent(za), tb = path.tangent(zb)
                            let na = SCNVector3(-ta.z, 0, ta.x).normalized
                            let nb = SCNVector3(-tb.z, 0, tb.x).normalized
                            let w: Float = 0.30
                            let o = offset
                            builder.addQuad(
                                SCNVector3(ca + na.x * (o - w), ya, za + na.z * (o - w)),
                                SCNVector3(ca + na.x * (o + w), ya, za + na.z * (o + w)),
                                SCNVector3(cb + nb.x * (o + w), yb, zb + nb.z * (o + w)),
                                SCNVector3(cb + nb.x * (o - w), yb, zb + nb.z * (o - w)),
                                color)
                        }
                    }
                }
                z = segEnd + (dash ? gap : 0)
                if !dash { z = path.length }
            }
        }

        edgeLine(offset: 6.6, color: white, dash: false, dashLength: 0, gap: 0)
        edgeLine(offset: -6.6, color: white, dash: false, dashLength: 0, gap: 0)
        edgeLine(offset: 0, color: yellow, dash: true, dashLength: 5, gap: 7)

        let geometry = builder.geometry(name: "markings")
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor.white
        m.roughness.contents = 0.55
        m.metalness.contents = 0.0
        m.writesToDepthBuffer = true
        geometry.materials = [m]
        return geometry
    }

    /// Столбики вдоль обочины — дают ощущение скорости.
    static func roadsidePosts(path: RoadPath) -> SCNGeometry {
        let builder = MeshBuilder()
        let color = UIColor(hex: 0x8A8578)
        let dark = UIColor(hex: 0x3A3630)
        var z: Float = 10
        var flip = false
        while z < path.length {
            let side: Float = flip ? 1 : -1
            let cx = path.center(z)
            let y = path.height(z)
            let t = path.tangent(z)
            let n = SCNVector3(-t.z, 0, t.x).normalized
            let px = cx + n.x * side * (roadHalfWidth + 2.2)
            let pz = z + n.z * side * (roadHalfWidth + 2.2)
            builder.addBox(center: SCNVector3(px, y + 0.55, pz),
                           size: SCNVector3(0.22, 1.1, 0.22), color: color)
            builder.addBox(center: SCNVector3(px, y + 0.95, pz),
                           size: SCNVector3(0.24, 0.22, 0.24), color: dark)
            z += 26
            flip.toggle()
        }
        let geometry = builder.geometry(name: "posts")
        geometry.materials = [Materials.matte(roughness: 0.8)]
        return geometry
    }

    // MARK: Лес

    static func forest(path: RoadPath, seed: Int, count: Int, area: Float) -> SCNGeometry {
        // Шум для расстановки — свой, а высоту берём из того же шума, что и рельеф,
        // иначе деревья висят в воздухе или тонут в холме.
        let noise = ValueNoise(seed: seed &+ 77)
        let terrainNoise = ValueNoise(seed: seed)
        let builder = MeshBuilder()

        let needleBase = UIColor(hex: 0x1E3A22)

        var placed = 0
        var attempt = 0
        while placed < count && attempt < count * 6 {
            attempt += 1
            let z = noise.value(Float(attempt) * 0.37, 11.3) * (path.length + 160) - 80
            let x = (noise.value(Float(attempt) * 0.91, 5.7) - 0.5) * area * 2
            let d = abs(x - path.center(z))
            if d < roadHalfWidth + 4 { continue }
            // гуще у дороги, реже вдали — так честнее для глаза
            if d > 90 && noise.value(Float(attempt) * 0.13, 3.1) < 0.45 { continue }

            let y = groundHeight(x, z, path: path, noise: terrainNoise)
            let scale = 0.7 + noise.value(Float(attempt) * 0.53, 8.8) * 0.9
            let height = 13 * scale

            var treeRng = SeededRandom(seed: UInt64(attempt) &* 2654435761)
            Nature.addSpruce(to: builder, at: V3(x, y, z), height: height * 1.5, rng: &treeRng,
                             needle: needleBase.darkened(Float(noise.value(Float(attempt) * 0.7, 2.2)) * 0.10))
            placed += 1
        }

        let geometry = builder.geometry(name: "forest")
        let material = Materials.matte(roughness: 0.88)
        material.isDoubleSided = true
        geometry.materials = [material]
        return geometry
    }

    /// Кусты и камни у обочины.
    static func roadsideDetails(path: RoadPath, seed: Int, count: Int) -> SCNGeometry {
        let noise = ValueNoise(seed: seed &+ 303)
        let terrainNoise = ValueNoise(seed: seed)
        let builder = MeshBuilder()
        let bush = UIColor(hex: 0x27401F)
        let stone = UIColor(hex: 0x54585A)

        for i in 0..<count {
            let z = noise.value(Float(i) * 0.71, 1.9) * (path.length + 80) - 40
            let side: Float = noise.value(Float(i) * 0.31, 9.4) > 0.5 ? 1 : -1
            let offset = roadHalfWidth + 3 + noise.value(Float(i) * 0.47, 4.4) * 26
            let cx = path.center(z)
            let t = path.tangent(z)
            let n = SCNVector3(-t.z, 0, t.x).normalized
            let x = cx + n.x * side * offset
            let zz = z + n.z * side * offset
            let y = groundHeight(x, zz, path: path, noise: terrainNoise)

            if noise.value(Float(i) * 0.13, 6.6) > 0.45 {
                let s = 0.9 + noise.value(Float(i) * 0.23, 7.7) * 1.6
                builder.addBox(center: SCNVector3(x, y + s * 0.4, zz),
                               size: SCNVector3(s * 1.6, s * 0.9, s * 1.6),
                               color: stone.darkened(Float(noise.value(Float(i), 2.0)) * 0.1),
                               rotationY: noise.value(Float(i) * 0.9, 3.3) * 3.1)
            } else {
                let s = 0.9 + noise.value(Float(i) * 0.23, 7.7) * 1.3
                builder.addBox(center: SCNVector3(x, y + s * 0.35, zz),
                               size: SCNVector3(s * 1.8, s * 0.8, s * 1.8),
                               color: bush.darkened(Float(noise.value(Float(i), 5.0)) * 0.12),
                               rotationY: noise.value(Float(i) * 0.6, 1.1) * 3.1)
            }
        }

        let geometry = builder.geometry(name: "details")
        geometry.materials = [Materials.matte(roughness: 0.9)]
        return geometry
    }

    // MARK: Небо и погода

    static func skyGradient(top: UIColor, middle: UIColor, bottom: UIColor, size: CGSize)
        -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [top.cgColor, middle.cgColor, bottom.cgColor] as CFArray
            let locations: [CGFloat] = [0, 0.55, 1]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: locations) else { return }
            cg.drawLinearGradient(gradient,
                                  start: CGPoint(x: 0, y: 0),
                                  end: CGPoint(x: 0, y: size.height),
                                  options: [])
        }
    }

    static func skyDome(top: UIColor, middle: UIColor, bottom: UIColor) -> SCNNode {
        let sphere = SCNSphere(radius: 2600)
        sphere.segmentCount = 48
        let image = skyGradient(top: top, middle: middle, bottom: bottom,
                                size: CGSize(width: 8, height: 512))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.isDoubleSided = false
        m.cullMode = .front
        m.writesToDepthBuffer = false
        sphere.materials = [m]
        let node = SCNNode(geometry: sphere)
        node.name = "sky"
        node.renderingOrder = -100
        return node
    }

    /// Вертикальный штрих — из него собирается дождь.
    static func rainStreakImage() -> UIImage {
        let size = CGSize(width: 6, height: 44)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [UIColor.white.withAlphaComponent(0).cgColor,
                          UIColor.white.withAlphaComponent(0.85).cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 0.5, 1]) else { return }
            cg.drawLinearGradient(g, start: .zero,
                                  end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    static func rain(intensity: CGFloat = 900) -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.birthRate = intensity
        ps.particleLifeSpan = 1.2
        ps.particleLifeSpanVariation = 0.4
        ps.particleVelocity = 42
        ps.particleVelocityVariation = 14
        ps.emittingDirection = SCNVector3(0.10, -1, 0.04)
        ps.spreadingAngle = 4
        // Тонкие капли, растянутые по скорости в штрихи (картинка-штрих рисовалась квадратами).
        ps.particleSize = 0.022
        ps.particleSizeVariation = 0.008
        ps.stretchFactor = 0.035
        ps.particleImage = Textures.softDot
        ps.particleColor = UIColor(white: 0.88, alpha: 0.42)
        ps.particleColorVariation = SCNVector4(0, 0, 0, 0.22)
        ps.blendMode = .alpha
        ps.isAffectedByGravity = false
        ps.acceleration = SCNVector3(2, -34, 0)
        ps.emitterShape = SCNBox(width: 90, height: 2, length: 90, chamferRadius: 0)
        ps.birthLocation = .surface
        ps.birthDirection = .constant
        ps.loops = true
        ps.isLocal = false
        ps.speedFactor = 1.0
        return ps
    }

    /// Мокрая дымка у земли — низкие клочья тумана.
    static func mist() -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.birthRate = 22
        ps.particleLifeSpan = 9
        ps.particleLifeSpanVariation = 3
        ps.particleVelocity = 1.6
        ps.particleVelocityVariation = 0.8
        ps.emittingDirection = SCNVector3(1, 0.05, 0)
        ps.spreadingAngle = 0.6
        ps.particleSize = 26
        ps.particleSizeVariation = 12
        ps.particleColor = UIColor(white: 0.78, alpha: 0.045)
        ps.blendMode = .alpha
        ps.isAffectedByGravity = false
        ps.emitterShape = SCNBox(width: 240, height: 1, length: 200, chamferRadius: 0)
        ps.birthLocation = .volume
        ps.loops = true
        ps.isLocal = false
        return ps
    }
}

// MARK: - Смешивание цветов

extension UIColor {
    func mixed(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = min(1, max(0, amount))
        return UIColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }
}

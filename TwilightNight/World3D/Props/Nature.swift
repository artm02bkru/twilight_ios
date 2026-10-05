import SceneKit
import UIKit
import simd

// MARK: - Дополнения к сборщику мешей

extension MeshBuilder {

    /// Треугольник с разными цветами вершин и общей нормалью (трава, лепестки, хвоя).
    func addTriangle(_ a: V3, _ ca: UIColor, _ b: V3, _ cb: UIColor, _ c: V3, _ cc: UIColor, normal: V3) {
        addColoredTriangle(SCNVector3(a.x, a.y, a.z), ca.rgba4,
                           SCNVector3(b.x, b.y, b.z), cb.rgba4,
                           SCNVector3(c.x, c.y, c.z), cc.rgba4,
                           normal: SCNVector3(normal.x, normal.y, normal.z))
    }

    /// То же с готовыми цветами SIMD — без конвертаций UIColor в горячих циклах.
    func addTriangle(_ a: V3, _ ca: SIMD4<Float>, _ b: V3, _ cb: SIMD4<Float>, _ c: V3, _ cc: SIMD4<Float>,
                     normal: V3) {
        addColoredTriangle(SCNVector3(a.x, a.y, a.z), ca,
                           SCNVector3(b.x, b.y, b.z), cb,
                           SCNVector3(c.x, c.y, c.z), cc,
                           normal: SCNVector3(normal.x, normal.y, normal.z))
    }

    /// Низкополигональный шар (крона, куст, камень). squash — сплющить по вертикали.
    func addBlob(center: V3, radius: Float, color: UIColor, squash: Float = 1,
                 jitter: Float = 0.18, seed: UInt64 = 1, rings: Int = 5, segments: Int = 8) {
        var rng = SeededRandom(seed: seed)
        var grid: [[V3]] = []
        for r in 0...rings {
            let phi = Float(r) / Float(rings) * Float.pi
            var row: [V3] = []
            for s in 0..<segments {
                let theta = Float(s) / Float(segments) * 2 * Float.pi
                let k = 1 + (r == 0 || r == rings ? 0 : rng.range(-jitter, jitter))
                let p = V3(sin(phi) * cos(theta), cos(phi) * squash, sin(phi) * sin(theta)) * radius * k
                row.append(center + p)
            }
            grid.append(row)
        }
        for r in 0..<rings {
            for s in 0..<segments {
                let s1 = (s + 1) % segments
                let a = grid[r][s], b = grid[r][s1], c = grid[r + 1][s1], d = grid[r + 1][s]
                let shade = color.darkened(Float(r) / Float(rings) * 0.12)
                addQuad(SCNVector3(a.x, a.y, a.z), SCNVector3(b.x, b.y, b.z),
                        SCNVector3(c.x, c.y, c.z), SCNVector3(d.x, d.y, d.z), shade)
            }
        }
    }
}

// MARK: - Природа

enum Nature {

    // MARK: Ели

    /// Ель: ствол и ярусы поникших еловых лап. Каждая лапа — изогнутая полоса хвои,
    /// темнее у ствола и светлее на кончиках. Высота ~ height метров.
    static func addSpruce(to b: MeshBuilder, at p: V3, height: Float, rng: inout SeededRandom,
                          needle: UIColor = UIColor(hex: 0x1C3520), branchStart: Float = 0.1,
                          trunkRadius: Float? = nil) {
        b.addCylinder(bottom: SCNVector3(p.x, p.y - 0.3, p.z), radius: trunkRadius ?? height * 0.022,
                      height: height * 0.92, sides: trunkRadius == nil ? 6 : 12, color: UIColor(hex: 0x3A2A1E))
        let base = needle.rgba4
        let inner = base * SIMD4(0.45, 0.45, 0.45, 1)
        let tiers = 14
        for i in 0..<tiers {
            let t = Float(i) / Float(tiers)
            let y = p.y + height * (branchStart + t * (0.92 - branchStart))
            let length = height * 0.24 * (1 - t * 0.88) * rng.range(0.85, 1.12)
            let branches = 7 + Int(rng.unit() * 3)
            let spin = rng.range(0, 2 * Float.pi)
            let tipShade = 1.0 + rng.range(0.05, 0.25) + t * 0.15
            let tip = base * SIMD4(tipShade, tipShade * 1.05, tipShade, 1)
            for k in 0..<branches {
                let a = spin + Float(k) / Float(branches) * 2 * Float.pi + rng.range(-0.2, 0.2)
                let dir = V3(cos(a), 0, sin(a))
                let side = V3(-sin(a), 0, cos(a))
                let droop = length * rng.range(0.4, 0.65)
                let root = V3(p.x, y, p.z) + V3(0, length * 0.05, 0)
                let mid = root + dir * (length * 0.55) + V3(0, -droop * 0.25, 0)
                let end = root + dir * length + V3(0, -droop, 0)
                let w = length * 0.42
                let up = simd_normalize(dir * 0.35 + V3(0, 1, 0))
                // Две секции лапы: от ствола до середины и до кончика.
                b.addTriangle(root - side * (w * 0.25), inner, mid - side * w, base, mid + side * w, base, normal: up)
                b.addTriangle(root - side * (w * 0.25), inner, mid + side * w, base, root + side * (w * 0.25), inner, normal: up)
                b.addTriangle(mid - side * w, base, end, tip, mid + side * w, base, normal: up)
                // Нижний слой — объём лапы снизу, чуть темнее.
                let under = mid + V3(0, -length * 0.08, 0)
                b.addTriangle(root, inner, under - side * (w * 0.7), inner, end, base, normal: up)
                b.addTriangle(root, inner, end, base, under + side * (w * 0.7), inner, normal: up)
            }
        }
        // Верхушка.
        b.addCone(base: SCNVector3(p.x, p.y + height * 0.9, p.z), radius: height * 0.03,
                  height: height * 0.12, sides: 6, color: needle.lightened(0.04))
    }

    /// Лиственное дерево: ствол и несколько крон-шаров.
    static func addBroadleaf(to b: MeshBuilder, at p: V3, height: Float, rng: inout SeededRandom,
                             leaves: UIColor = UIColor(hex: 0x35522A)) {
        let trunk = UIColor(hex: 0x4A3628)
        b.addCylinder(bottom: SCNVector3(p.x, p.y - 0.3, p.z), radius: height * 0.035,
                      height: height * 0.55, sides: 7, color: trunk)
        for i in 0..<4 {
            let off = V3(rng.range(-1, 1), rng.range(-0.3, 0.4), rng.range(-1, 1)) * height * 0.15
            let c = p + V3(0, height * 0.68, 0) + off
            b.addBlob(center: c, radius: height * rng.range(0.18, 0.26),
                      color: leaves.darkened(rng.range(0, 0.08)).lightened(Float(i) * 0.015),
                      squash: 0.8, seed: rng.next())
        }
    }

    /// Кольцо леса вокруг площадки. corridor — свободный проход (угол в радианах и ширина).
    static func forestRing(center: V3 = .zero, inner: Float, outer: Float, count: Int,
                           seed: UInt64, heights: ClosedRange<Float> = 14...26,
                           broadleafShare: Float = 0.15,
                           corridor: (angle: Float, width: Float)? = nil,
                           clearing: ((V3) -> Bool)? = nil) -> SCNNode {
        let b = MeshBuilder()
        var rng = SeededRandom(seed: seed)
        var placed = 0, attempts = 0
        while placed < count && attempts < count * 8 {
            attempts += 1
            let a = rng.range(0, 2 * Float.pi)
            // Ближе к краю поляны деревья гуще.
            let r = inner + (outer - inner) * pow(rng.unit(), 1.6)
            let p = center + V3(sin(a) * r, 0, cos(a) * r)
            if let corridor {
                let along = V3(sin(corridor.angle), 0, cos(corridor.angle))
                let rel = p - center
                let side = abs(rel.x * along.z - rel.z * along.x)
                if simd_dot(rel, along) > 0 && side < corridor.width { continue }
            }
            if let clearing, clearing(p) { continue }
            let h = rng.range(heights.lowerBound, heights.upperBound)
            if rng.unit() < broadleafShare {
                addBroadleaf(to: b, at: p, height: h * 0.7, rng: &rng)
            } else {
                addSpruce(to: b, at: p, height: h, rng: &rng)
            }
            placed += 1
        }
        let node = SCNNode(geometry: b.geometry(name: "forest"))
        let m = Materials.matte(roughness: 0.9)
        m.isDoubleSided = true
        m.shaderModifiers = [.geometry: Materials.windModifier(strength: 0.006)]
        node.geometry?.materials = [m]
        node.castsShadow = true
        return node
    }

    // MARK: Трава и цветы

    /// Поле травинок. Каждая травинка — тонкий треугольник, всё одним мешем.
    static func grassField(radius: Float, count: Int, seed: UInt64,
                           height: ClosedRange<Float> = 0.25...0.6,
                           colors: [UIColor] = [UIColor(hex: 0x3E6A2A), UIColor(hex: 0x58803A), UIColor(hex: 0x6E8A3E)],
                           avoid: ((V3) -> Bool)? = nil,
                           rect: SIMD2<Float>? = nil) -> SCNNode {
        let b = MeshBuilder()
        var rng = SeededRandom(seed: seed)
        for _ in 0..<count {
            let p: V3
            if let rect {
                p = V3(rng.range(-rect.x, rect.x), 0, rng.range(-rect.y, rect.y))
            } else {
                let a = rng.range(0, 2 * Float.pi)
                let r = radius * sqrt(rng.unit())
                p = V3(sin(a) * r, 0, cos(a) * r)
            }
            if let avoid, avoid(p) { continue }
            let h = rng.range(height.lowerBound, height.upperBound)
            let w = rng.range(0.02, 0.045)
            let dir = rng.range(0, 2 * Float.pi)
            let side = V3(cos(dir), 0, sin(dir)) * w
            let lean = V3(sin(dir + 1.3), 0, cos(dir + 1.3)) * h * rng.range(0.1, 0.35)
            let color = colors[Int(rng.unit() * Float(colors.count)) % colors.count]
                .darkened(rng.range(0, 0.08)).rgba4
            // У корня травинка в тени соседей, кончик выгорел на свету.
            let root = color * SIMD4(0.4, 0.42, 0.4, 1)
            let tipColor = color * SIMD4(1.25, 1.22, 1.05, 1)
            let tip = p + V3(0, h, 0) + lean
            b.addTriangle(p - side, root, p + side, root, tip, tipColor, normal: V3(0, 1, 0))
        }
        let node = SCNNode(geometry: b.geometry(name: "grass"))
        let m = Materials.matte(roughness: 0.85)
        m.isDoubleSided = true
        m.shaderModifiers = [.geometry: Materials.windModifier(strength: 0.06)]
        node.geometry?.materials = [m]
        node.castsShadow = false
        return node
    }

    /// Полевые цветы: маленькие звёздочки лепестков на стебельках.
    static func flowers(radius: Float, count: Int, seed: UInt64,
                        palette: [UIColor] = [UIColor(hex: 0xE8E0F0), UIColor(hex: 0xF2D04A),
                                              UIColor(hex: 0x9A7AD8), UIColor(hex: 0xE88AA0)]) -> SCNNode {
        let b = MeshBuilder()
        var rng = SeededRandom(seed: seed)
        let stem = UIColor(hex: 0x3E6A2A)
        for _ in 0..<count {
            let a = rng.range(0, 2 * Float.pi)
            let r = radius * sqrt(rng.unit())
            let p = V3(sin(a) * r, 0, cos(a) * r)
            let h = rng.range(0.25, 0.55)
            let top = p + V3(0, h, 0)
            b.addTriangle(p + V3(-0.006, 0, 0), stem, p + V3(0.006, 0, 0), stem, top, stem, normal: V3(0, 1, 0))
            let color = palette[Int(rng.unit() * Float(palette.count)) % palette.count]
            let petals = 5
            let size = rng.range(0.03, 0.055)
            for i in 0..<petals {
                let t0 = Float(i) / Float(petals) * 2 * Float.pi
                let t1 = t0 + 0.9
                let p0 = top + V3(cos(t0), 0.15, sin(t0)) * size
                let p1 = top + V3(cos(t1), 0.15, sin(t1)) * size
                b.addTriangle(top, color, p0, color, p1, color, normal: V3(0, 1, 0))
            }
        }
        let node = SCNNode(geometry: b.geometry(name: "flowers"))
        let m = Materials.matte(roughness: 0.6)
        m.isDoubleSided = true
        m.shaderModifiers = [.geometry: Materials.windModifier(strength: 0.06)]
        node.geometry?.materials = [m]
        node.castsShadow = false
        return node
    }

    /// Камни и валуны.
    static func rocks(count: Int, seed: UInt64, area: (V3) -> V3?) -> SCNNode {
        let b = MeshBuilder()
        var rng = SeededRandom(seed: seed)
        let stone = UIColor(hex: 0x5E6062)
        for _ in 0..<count {
            guard let p = area(V3(rng.unit(), rng.unit(), rng.unit())) else { continue }
            let s = rng.range(0.3, 1.2)
            b.addBlob(center: p + V3(0, s * 0.2, 0), radius: s, color: stone.darkened(rng.range(0, 0.1)),
                      squash: rng.range(0.45, 0.75), jitter: 0.25, seed: rng.next(), rings: 4, segments: 7)
        }
        let node = SCNNode(geometry: b.geometry(name: "rocks"))
        node.geometry?.materials = [Materials.matte(roughness: 0.9)]
        return node
    }

    /// Земля: круглая или прямоугольная плоскость с материалом.
    static func ground(size: CGFloat, material: SCNMaterial) -> SCNNode {
        let plane = SCNPlane(width: size, height: size)
        plane.widthSegmentCount = 1
        plane.heightSegmentCount = 1
        let node = SCNNode(plane, material)
        node.eulerAngles.x = -Float.pi / 2
        node.castsShadow = false
        return node
    }

    // MARK: Частицы

    static func snow(area: Float = 40, rate: CGFloat = 260) -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.birthRate = rate
        ps.particleLifeSpan = 8
        ps.particleVelocity = 0.9
        ps.particleVelocityVariation = 0.4
        ps.emittingDirection = SCNVector3(0.15, -1, 0.05)
        ps.spreadingAngle = 25
        ps.particleSize = 0.035
        ps.particleSizeVariation = 0.02
        ps.particleImage = Textures.softDot
        ps.particleColor = UIColor(white: 1, alpha: 0.9)
        ps.blendMode = .alpha
        ps.isAffectedByGravity = false
        ps.acceleration = SCNVector3(0.2, -0.25, 0)
        ps.emitterShape = SCNBox(width: CGFloat(area), height: 1, length: CGFloat(area), chamferRadius: 0)
        ps.birthLocation = .volume
        ps.loops = true
        ps.isLocal = false
        ps.warmupDuration = 6
        return ps
    }

    /// Пылинки и пыльца в солнечных лучах.
    static func motes(area: Float, height: Float, rate: CGFloat = 40, color: UIColor) -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.birthRate = rate
        ps.particleLifeSpan = 6
        ps.particleLifeSpanVariation = 2
        ps.particleVelocity = 0.15
        ps.particleVelocityVariation = 0.1
        ps.spreadingAngle = 180
        ps.particleSize = 0.02
        ps.particleSizeVariation = 0.01
        ps.particleImage = Textures.softDot
        ps.particleColor = color
        ps.blendMode = .additive
        ps.isAffectedByGravity = false
        ps.emitterShape = SCNBox(width: CGFloat(area), height: CGFloat(height), length: CGFloat(area), chamferRadius: 0)
        ps.birthLocation = .volume
        ps.loops = true
        ps.isLocal = false
        ps.warmupDuration = 4
        return ps
    }

    /// Искры алмазной кожи — вылетают с поверхности тела.
    static func sparkles(shape: SCNGeometry) -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.birthRate = 0
        ps.particleLifeSpan = 0.22
        ps.particleLifeSpanVariation = 0.1
        ps.particleVelocity = 0.05
        ps.particleSize = 0.035
        ps.particleSizeVariation = 0.025
        ps.particleImage = Textures.star
        ps.particleColor = UIColor(red: 0.85, green: 0.93, blue: 1, alpha: 1)
        ps.particleIntensity = 3
        ps.blendMode = .additive
        ps.isAffectedByGravity = false
        ps.emitterShape = shape
        ps.birthLocation = .surface
        ps.loops = true
        ps.isLocal = false
        let fade = CAKeyframeAnimation()
        fade.values = [0.0, 1.0, 0.0]
        fade.keyTimes = [0, 0.3, 1]
        ps.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        return ps
    }

    /// Брызги снега или воды из-под колёс.
    static func spray(color: UIColor) -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.birthRate = 0
        ps.particleLifeSpan = 0.9
        ps.particleLifeSpanVariation = 0.3
        ps.particleVelocity = 2.2
        ps.particleVelocityVariation = 1.2
        ps.emittingDirection = SCNVector3(0, 0.6, 0)
        ps.spreadingAngle = 50
        ps.particleSize = 0.12
        ps.particleSizeVariation = 0.08
        ps.particleImage = Textures.smoke
        ps.particleColor = color
        ps.blendMode = .alpha
        ps.isAffectedByGravity = true
        ps.emitterShape = SCNBox(width: 0.5, height: 0.1, length: 2.6, chamferRadius: 0)
        ps.birthLocation = .volume
        ps.loops = true
        ps.isLocal = false
        let grow = CAKeyframeAnimation()
        grow.values = [0.6, 2.2]
        grow.keyTimes = [0, 1]
        let fade = CAKeyframeAnimation()
        fade.values = [0.7, 0.0]
        fade.keyTimes = [0, 1]
        ps.propertyControllers = [
            .size: SCNParticlePropertyController(animation: grow),
            .opacity: SCNParticlePropertyController(animation: fade)
        ]
        return ps
    }

    /// Низкий стелющийся туман.
    static func groundFog(area: Float, rate: CGFloat = 14, color: UIColor = UIColor(white: 0.8, alpha: 0.06)) -> SCNParticleSystem {
        let ps = SCNParticleSystem()
        ps.birthRate = rate
        ps.particleLifeSpan = 12
        ps.particleLifeSpanVariation = 3
        ps.particleVelocity = 0.4
        ps.particleVelocityVariation = 0.3
        ps.emittingDirection = SCNVector3(1, 0, 0.2)
        ps.spreadingAngle = 30
        ps.particleSize = 9
        ps.particleSizeVariation = 4
        ps.particleImage = Textures.smoke
        ps.particleColor = color
        ps.blendMode = .alpha
        ps.isAffectedByGravity = false
        ps.emitterShape = SCNBox(width: CGFloat(area), height: 0.6, length: CGFloat(area), chamferRadius: 0)
        ps.birthLocation = .volume
        ps.loops = true
        ps.isLocal = false
        ps.warmupDuration = 10
        let fade = CAKeyframeAnimation()
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0, 0.2, 0.8, 1]
        ps.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        return ps
    }

    // MARK: Молния

    /// Зигзаг молнии из тонких светящихся лент.
    static func lightningBolt(from top: V3, to bottom: V3, seed: UInt64) -> SCNGeometry {
        let b = MeshBuilder()
        var rng = SeededRandom(seed: seed)
        var points: [V3] = [top]
        let steps = 14
        for i in 1..<steps {
            let t = Float(i) / Float(steps)
            var p = mixv(top, bottom, t)
            p += V3(rng.range(-1, 1), 0, rng.range(-1, 1)) * 3.5
            points.append(p)
        }
        points.append(bottom)
        let white = UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1)
        func ribbon(_ a: V3, _ c: V3, width w: Float) {
            for side in [V3(w, 0, 0), V3(0, 0, w)] {
                b.addQuad(SCNVector3(a.x - side.x, a.y, a.z - side.z),
                          SCNVector3(a.x + side.x, a.y, a.z + side.z),
                          SCNVector3(c.x + side.x, c.y, c.z + side.z),
                          SCNVector3(c.x - side.x, c.y, c.z - side.z), white)
            }
        }
        for i in 0..<(points.count - 1) {
            ribbon(points[i], points[i + 1], width: 0.35)
            // Боковые отростки.
            if rng.unit() > 0.6 {
                let branchEnd = points[i] + V3(rng.range(-6, 6), -rng.range(4, 9), rng.range(-6, 6))
                ribbon(points[i], branchEnd, width: 0.15)
            }
        }
        let g = b.geometry(name: "bolt")
        let m = Materials.glow(white, intensity: 6)
        g.materials = [m]
        return g
    }
}

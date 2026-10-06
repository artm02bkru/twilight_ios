import SceneKit
import SwiftUI
import UIKit
import simd

/// Свадьба в саду у дома Калленов. Всё оформление переключается по выбору игрока
/// в реальном времени, а финальная кат-сцена показывает собранную свадьбу.
final class WeddingStage: Stage3D {

    private typealias Category = WeddingScene.Category

    private let bellaSlim = Humanoid(Cast.bellaBride)
    private let bellaPrincess = Humanoid(Cast.bellaPrincess)
    private let edward = Humanoid(Cast.edwardGroom)
    private let alice = Humanoid(Cast.alice)
    private let charlie = Humanoid(Cast.charlie)
    private var guests: [Humanoid] = []

    private var arches: [SCNNode] = []
    private var lights: [SCNNode] = []
    private var aisles: [SCNNode] = []
    private var ribbonMaterial = SCNMaterial()
    private var veils: [[SCNNode]] = [[], []]       // по варианту Беллы
    private var bouquetMaterials: [SCNMaterial] = []
    private var moonLight = SCNNode()
    private var key = SCNNode()

    /// Текущий выбор (индексы вариантов по категориям).
    private var picks: [Int] = Array(repeating: 0, count: Category.allCases.count)
    private var focus: Category = .dress

    private let altar = V3(0, 0, 0)
    private let aisleStart = V3(0, 0, 11)

    override init() {
        super.init()
        let root = scene.rootNode

        setSky(Textures.SkyStyle(
            zenith: SIMD3(0.16, 0.2, 0.4), horizon: SIMD3(0.95, 0.66, 0.5), ground: SIMD3(0.12, 0.14, 0.1),
            cloudCover: 0.35, cloudLight: SIMD3(1, 0.78, 0.65), cloudDark: SIMD3(0.4, 0.32, 0.4),
            sunAzimuth: -2.2, sunElevation: 0.08, sunColor: SIMD3(1, 0.7, 0.45), sunGlow: 1.0,
            sunDisc: true, stars: true, seed: 91), lighting: 0.9)
        setFog(color: UIColor(red: 0.4, green: 0.36, blue: 0.42, alpha: 1), start: 25, end: 160)
        key = addKeyLight(color: UIColor(red: 1, green: 0.72, blue: 0.5, alpha: 1), intensity: 420,
                          azimuth: -2.2, elevation: 0.25, shadowExtent: 26, softness: 10)
        addAmbient(color: UIColor(red: 0.42, green: 0.42, blue: 0.55, alpha: 1), intensity: 70)

        root.addChildNode(Nature.ground(size: 300, material: Materials.grass(tile: 60)))
        root.addChildNode(Nature.grassField(radius: 26, count: 30_000, seed: 41, height: 0.06...0.18,
                                            avoid: { p in abs(p.x) < 1.0 && p.z > -1 && p.z < 12 }))
        root.addChildNode(Nature.flowers(radius: 24, count: 700, seed: 42,
                                         palette: [UIColor(hex: 0xF5F2F8), UIColor(hex: 0xE9C8D8), UIColor(hex: 0xF2E3A8)]))
        // Поляна под дом Калленов за алтарём.
        func houseClearing(_ p: V3) -> Bool {
            let insideX: Bool = p.x > -30 && p.x < 36
            let insideZ: Bool = p.z > -62 && p.z < -16
            return insideX && insideZ
        }
        let clearing: ((V3) -> Bool)? = ModelAsset.named("cullen_house") == nil ? nil : houseClearing
        root.addChildNode(Nature.forestRing(center: V3(0, 0, -6), inner: 30, outer: 85, count: 520, seed: 43,
                                            heights: 18...32, broadleafShare: 0.25, clearing: clearing))
        buildHouse(root)
        buildChairs(root)
        buildArches(root)
        buildLights(root)
        buildAisles(root)

        for h in [bellaSlim, bellaPrincess, edward, alice, charlie] {
            root.addChildNode(h.node)
            h.node.setCastsShadow(true)
        }
        for look in [Cast.carlisle, Cast.esme, Cast.rosalie, Cast.emmett, Cast.jasper, Cast.mike, Cast.jessica, Cast.angela] {
            let g = Humanoid(look)
            root.addChildNode(g.node)
            g.node.setCastsShadow(true)
            guests.append(g)
        }
        dressBella(bellaSlim, index: 0)
        dressBella(bellaPrincess, index: 1)

        cameraSettings.bloomIntensity = 1.0
        cameraSettings.bloomThreshold = 0.65
        cameraSettings.exposureOffset = 0.35
        placeCamera(eye: V3(0, 1.8, 6), target: V3(0, 1.4, 0), fov: 46)
        applyPicks()
    }

    // MARK: - Сборка

    private func buildHouse(_ root: SCNNode) {
        if let model = ModelAsset.named("cullen_house") {
            // Модель дома Калленов: бетон, лиственница, стекло; в окнах — тёплый свет.
            let house = model.wholeNode { d in
                guard d.name.contains("Glass") else { return nil }
                let glass = Materials.pbr(UIColor(white: 0.06, alpha: 1), roughness: 0.04, metalness: 0.4)
                glass.emission.contents = UIColor(red: 1, green: 0.78, blue: 0.5, alpha: 1)
                glass.emission.intensity = 0.55
                glass.transparency = 0.85
                glass.transparencyMode = .dualLayer
                return glass
            }
            let base = V3(4, 0, -36)
            house.simdPosition = base
            house.childNodes.forEach { $0.castsShadow = true }
            root.addChildNode(house)
            addOmni(at: base + V3(0, 4, 14), color: UIColor(red: 1, green: 0.75, blue: 0.45, alpha: 1), intensity: 700, range: 22)
            buildGardenTrees(root)
            return
        }
        // Стеклянный дом Калленов среди деревьев, в окнах — тёплый свет.
        let wood = Materials.wood(tile: 1.5, roughness: 0.6)
        let glass = Materials.pbr(UIColor(white: 0.05, alpha: 1), roughness: 0.04, metalness: 0.4)
        glass.emission.contents = UIColor(red: 1, green: 0.78, blue: 0.5, alpha: 1)
        glass.emission.intensity = 0.55
        let white = Materials.pbr(UIColor(white: 0.9, alpha: 1), roughness: 0.6)
        let base = V3(4, 0, -26)
        for (i, size) in [V3(16, 4, 9), V3(12, 3.6, 8), V3(8, 3.2, 7)].enumerated() {
            let y = Float(i) * 3.8
            let slab = SCNNode(SCNBox(width: CGFloat(size.x), height: 0.3, length: CGFloat(size.z), chamferRadius: 0.02), white)
            slab.simdPosition = base + V3(Float(i) * -1.5, y + size.y + 0.15, 0)
            root.addChildNode(slab)
            let glassBox = SCNNode(SCNBox(width: CGFloat(size.x - 0.4), height: CGFloat(size.y), length: CGFloat(size.z - 0.4),
                                          chamferRadius: 0.01), glass)
            glassBox.simdPosition = base + V3(Float(i) * -1.5, y + size.y / 2, 0)
            root.addChildNode(glassBox)
            for dx in stride(from: -size.x / 2 + 0.6, through: size.x / 2 - 0.6, by: 2.4) {
                let mullion = SCNNode(SCNBox(width: 0.12, height: CGFloat(size.y), length: 0.12, chamferRadius: 0.01), wood)
                mullion.simdPosition = base + V3(Float(i) * -1.5 + dx, y + size.y / 2, size.z / 2 - 0.2)
                root.addChildNode(mullion)
            }
        }
        addOmni(at: base + V3(0, 2, 6), color: UIColor(red: 1, green: 0.75, blue: 0.45, alpha: 1), intensity: 600, range: 18)
    }

    /// Садовые деревья вдоль поляны: подстриженные кроны и лиственные деревья из моделей.
    private func buildGardenTrees(_ root: SCNNode) {
        var rng = SeededRandom(seed: 71)
        if let pack = ModelAsset.named("tree_pack") {
            // Фигурные кроны по сторонам прохода.
            let spots: [(V3, String)] = [(V3(-6.5, 0, 3), "t1"), (V3(6.5, 0, 3), "t2"), (V3(-7, 0, 9), "t5"),
                                         (V3(7, 0, 9), "t1"), (V3(-9, 0, -4), "t2"), (V3(9.5, 0, -4), "t5")]
            for (p, name) in spots {
                guard let t = pack.grounded(name) else { continue }
                t.simdPosition = p
                t.simdEulerAngles.y = rng.range(0, 6.28)
                t.simdScale = V3(repeating: rng.range(1.1, 1.4))
                t.setCastsShadow(true)
                root.addChildNode(t)
            }
        }
        if let trees = ModelAsset.named("tree_lowpoly") {
            for i in 0..<10 {
                let a: Float = Float(i) * 0.44 - 0.63
                let r: Float = rng.range(15, 21)
                guard let t = trees.grounded(i % 2 == 0 ? "a" : "b") else { continue }
                let x: Float = cos(a) * r
                let z: Float = sin(a) * r * 0.7 + 4
                t.simdPosition = V3(x, 0, z)
                t.simdEulerAngles.y = rng.range(0, 6.28)
                t.simdScale = V3(repeating: rng.range(1.6, 2.2))
                root.addChildNode(t)
            }
        }
    }

    private func chairNode() -> SCNNode {
        let n = SCNNode()
        let wood = Materials.pbr(UIColor(white: 0.93, alpha: 1), roughness: 0.45)
        let seat = SCNNode(SCNBox(width: 0.45, height: 0.05, length: 0.45, chamferRadius: 0.01), wood)
        seat.simdPosition = V3(0, 0.46, 0)
        n.addChildNode(seat)
        let back = SCNNode(SCNBox(width: 0.45, height: 0.48, length: 0.04, chamferRadius: 0.01), wood)
        back.simdPosition = V3(0, 0.72, 0.21)
        n.addChildNode(back)
        for x: Float in [-0.19, 0.19] {
            for z: Float in [-0.19, 0.19] {
                let leg = SCNNode(SCNCylinder(radius: 0.018, height: 0.46), wood)
                leg.simdPosition = V3(x, 0.23, z)
                n.addChildNode(leg)
            }
        }
        return n.flattenedClone()
    }

    private func buildChairs(_ root: SCNNode) {
        let chair = chairNode()
        ribbonMaterial = Materials.cloth(.white, roughness: 0.4, sheen: true)
        let ribbonGeo = SCNBox(width: 0.08, height: 0.5, length: 0.02, chamferRadius: 0.01)
        ribbonGeo.materials = [ribbonMaterial]
        for row in 0..<8 {
            for side: Float in [-1, 1] {
                for k in 0..<3 {
                    let c = chair.clone()
                    c.simdPosition = V3(side * (1.4 + Float(k) * 0.6), 0, 2.2 + Float(row) * 1.1)
                    root.addChildNode(c)
                    if k == 0 {
                        let bow = SCNNode(geometry: ribbonGeo)
                        bow.simdPosition = c.simdPosition + V3(-side * 0.24, 0.62, 0.22)
                        root.addChildNode(bow)
                    }
                }
            }
        }
    }

    /// Дуга арки как набор капсул.
    private func archFrame(radius: Float, material: SCNMaterial, thickness: CGFloat = 0.06) -> SCNNode {
        let n = SCNNode()
        let segments = 16
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * Float.pi
            let a1 = Float(i + 1) / Float(segments) * Float.pi
            let p0 = V3(cos(a0) * radius, 2.0 + sin(a0) * radius * 0.7, 0)
            let p1 = V3(cos(a1) * radius, 2.0 + sin(a1) * radius * 0.7, 0)
            let seg = SCNNode(SCNCapsule(capRadius: thickness, height: CGFloat(simd_length(p1 - p0)) + thickness * 2), material)
            seg.simdPosition = (p0 + p1) * 0.5
            seg.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: simd_normalize(p1 - p0))
            n.addChildNode(seg)
        }
        for x in [-radius, radius] {
            let post = SCNNode(SCNCapsule(capRadius: thickness, height: 2.1), material)
            post.simdPosition = V3(x, 1.0, 0)
            n.addChildNode(post)
        }
        return n
    }

    private func buildArches(_ root: SCNNode) {
        let r: Float = 1.5
        var rng = SeededRandom(seed: 5)
        let whiteWood = Materials.pbr(UIColor(white: 0.92, alpha: 1), roughness: 0.5)

        // 0: белые цветы и плющ.
        let a0 = archFrame(radius: r, material: whiteWood)
        let ivy = MeshBuilder()
        for i in 0..<160 {
            let a = Float(i) / 160 * Float.pi
            let p = V3(cos(a) * r, 2.0 + sin(a) * r * 0.7, 0) + V3(rng.range(-0.12, 0.12), rng.range(-0.12, 0.12), rng.range(-0.1, 0.1))
            let flower = rng.unit() > 0.45
            ivy.addBlob(center: p, radius: flower ? rng.range(0.06, 0.1) : rng.range(0.04, 0.07),
                        color: flower ? UIColor(white: 0.96, alpha: 1) : UIColor(hex: 0x2F5A2A),
                        squash: 0.8, seed: rng.next(), rings: 3, segments: 6)
        }
        for x in [-r, r] {
            for k in 0..<30 {
                let p = V3(x + rng.range(-0.1, 0.1), Float(k) / 30 * 2.0, rng.range(-0.1, 0.1))
                ivy.addBlob(center: p, radius: rng.range(0.04, 0.08), color: UIColor(hex: 0x2F5A2A).lightened(rng.range(0, 0.06)),
                            squash: 0.8, seed: rng.next(), rings: 3, segments: 6)
            }
        }
        let ivyNode = SCNNode(geometry: ivy.geometry(name: "ivy"))
        ivyNode.geometry?.materials = [Materials.matte(roughness: 0.6)]
        a0.addChildNode(ivyNode)

        // 1: ветви и свечи.
        let a1 = archFrame(radius: r, material: Materials.bark(), thickness: 0.05)
        let candleMat = Materials.pbr(UIColor(red: 0.96, green: 0.93, blue: 0.85, alpha: 1), roughness: 0.5)
        let flameMat = Materials.glow(UIColor(red: 1, green: 0.7, blue: 0.3, alpha: 1), intensity: 4, doubleSided: false)
        for i in 0..<9 {
            let x = -1.2 + Float(i) * 0.3
            let h = rng.range(0.25, 0.6)
            let candle = SCNNode(SCNCylinder(radius: 0.035, height: CGFloat(h)), candleMat)
            candle.simdPosition = V3(x, h / 2, rng.range(-0.5, -0.2))
            a1.addChildNode(candle)
            let flame = SCNNode(SCNSphere(radius: 0.02), flameMat)
            flame.simdScale = V3(1, 1.8, 1)
            flame.simdPosition = V3(x, h + 0.03, candle.simdPosition.z)
            a1.addChildNode(flame)
        }
        addOmni(at: V3(0, 0.6, -0.4), color: UIColor(red: 1, green: 0.7, blue: 0.35, alpha: 1), intensity: 380, range: 5, parent: a1)

        // 2: ткань и кристаллы.
        let a2 = archFrame(radius: r, material: Materials.chrome(), thickness: 0.035)
        let fabric = Materials.cloth(UIColor(white: 0.98, alpha: 1), roughness: 0.4, sheen: true)
        fabric.transparency = 0.75
        fabric.isDoubleSided = true
        for side: Float in [-1, 1] {
            let drape = SCNNode(SCNPlane(width: 0.9, height: 3.0), fabric)
            drape.simdPosition = V3(side * (r - 0.25), 1.6, 0.05)
            drape.eulerAngles = SCNVector3(0, side * 0.25, 0)
            a2.addChildNode(drape)
        }
        let crystal = Materials.pbr(UIColor(white: 1, alpha: 1), roughness: 0.02, metalness: 1)
        for i in 0..<40 {
            let a = Float(i) / 40 * Float.pi
            let p = V3(cos(a) * r, 2.0 + sin(a) * r * 0.7 - rng.range(0.05, 0.4), 0)
            let gem = SCNNode(SCNSphere(radius: CGFloat(rng.range(0.015, 0.03))), crystal)
            gem.simdPosition = p
            a2.addChildNode(gem)
        }

        // 3: еловые лапы.
        let a3 = archFrame(radius: r, material: Materials.bark(), thickness: 0.05)
        let boughs = MeshBuilder()
        for i in 0..<120 {
            let a = Float(i) / 120 * Float.pi
            let p = V3(cos(a) * r, 2.0 + sin(a) * r * 0.7, 0)
            let dir = simd_normalize(V3(rng.range(-1, 1), rng.range(-0.3, 1), rng.range(-1, 1)))
            let side = simd_normalize(simd_cross(dir, V3(0, 1, 0.01)))
            let len = rng.range(0.25, 0.45)
            let tip = p + dir * len
            let c = UIColor(hex: 0x1F4426).lightened(rng.range(0, 0.06))
            boughs.addTriangle(p - side * 0.06, c, p + side * 0.06, c, tip, c, normal: V3(0, 1, 0))
        }
        let boughNode = SCNNode(geometry: boughs.geometry(name: "boughs"))
        let boughMat = Materials.matte(roughness: 0.8)
        boughMat.isDoubleSided = true
        boughNode.geometry?.materials = [boughMat]
        a3.addChildNode(boughNode)

        // Вариант 0 — готовая арка из цветов и листьев, если модель есть.
        var first = a0
        if let model = ModelAsset.named("flower_arch") {
            first = model.wholeNode()
            first.setCastsShadow(true)
        }
        arches = [first, a1, a2, a3]
        for a in arches {
            a.simdPosition = altar + V3(0, 0, -0.6)
            root.addChildNode(a)
        }
    }

    private func buildLights(_ root: SCNNode) {
        // 0: тёплые гирлянды над проходом.
        let strings = SCNNode()
        let bulbMat = Materials.glow(UIColor(red: 1, green: 0.8, blue: 0.5, alpha: 1), intensity: 3.5, doubleSided: false)
        let bulb = SCNSphere(radius: 0.035)
        bulb.materials = [bulbMat]
        for row in 0..<6 {
            let z = Float(row) * 2.0
            for k in 0..<14 {
                let t = Float(k) / 13
                let p = V3(lerpf(-4.5, 4.5, t), 3.6 - sin(t * Float.pi) * 0.6, z)
                let b = SCNNode(geometry: bulb)
                b.simdPosition = p
                b.castsShadow = false
                strings.addChildNode(b)
            }
        }
        for z: Float in [1, 5, 9] {
            addOmni(at: V3(0, 3.0, z), color: UIColor(red: 1, green: 0.75, blue: 0.45, alpha: 1), intensity: 520, range: 7,
                    parent: strings)
        }

        // 1: фонари со свечами вдоль прохода.
        let lanterns = SCNNode()
        let frame = Materials.pbr(UIColor(white: 0.08, alpha: 1), roughness: 0.4, metalness: 0.8)
        let flame = Materials.glow(UIColor(red: 1, green: 0.65, blue: 0.3, alpha: 1), intensity: 4, doubleSided: false)
        for z in stride(from: Float(1.5), through: 10.5, by: 1.5) {
            for side: Float in [-0.85, 0.85] {
                let l = SCNNode()
                let cage = SCNNode(SCNBox(width: 0.2, height: 0.32, length: 0.2, chamferRadius: 0.01), frame)
                cage.geometry?.firstMaterial?.transparency = 0.4
                cage.simdPosition = V3(0, 0.16, 0)
                l.addChildNode(cage)
                let f = SCNNode(SCNSphere(radius: 0.03), flame)
                f.simdScale = V3(1, 1.7, 1)
                f.simdPosition = V3(0, 0.16, 0)
                l.addChildNode(f)
                l.simdPosition = V3(side, 0, z)
                lanterns.addChildNode(l)
            }
        }
        for z: Float in [2, 6, 10] {
            addOmni(at: V3(0, 0.6, z), color: UIColor(red: 1, green: 0.65, blue: 0.3, alpha: 1), intensity: 360, range: 5,
                    parent: lanterns)
        }

        // 2: холодный лунный свет.
        let moon = SCNNode()
        let ml = SCNLight()
        ml.type = .directional
        ml.color = UIColor(red: 0.6, green: 0.72, blue: 1, alpha: 1)
        ml.intensity = 500
        ml.castsShadow = true
        ml.shadowMode = .deferred
        ml.shadowSampleCount = 8
        ml.shadowRadius = 6
        moon.light = ml
        moon.simdPosition = V3(-30, 60, 20)
        moon.simdLook(at: .zero)
        let disc = SCNNode(SCNPlane(width: 14, height: 14),
                           Materials.glowImage(Textures.softDot, color: UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1), intensity: 2))
        disc.simdPosition = V3(-60, 70, -140)
        disc.constraints = [SCNBillboardConstraint()]
        moon.addChildNode(disc)
        moonLight = moon

        lights = [strings, lanterns, moon]
        for l in lights { root.addChildNode(l) }
    }

    private func buildAisles(_ root: SCNNode) {
        var rng = SeededRandom(seed: 9)
        // 0: лепестки.
        let petals = MeshBuilder()
        for _ in 0..<1400 {
            let p = V3(rng.range(-0.75, 0.75), 0.012, rng.range(0.2, 11.5))
            let a = rng.range(0, 2 * Float.pi)
            let d = V3(cos(a), 0, sin(a)) * 0.03
            let s = V3(-sin(a), 0, cos(a)) * 0.02
            let c = rng.unit() > 0.3 ? UIColor(white: 0.97, alpha: 1) : UIColor(red: 0.95, green: 0.78, blue: 0.84, alpha: 1)
            petals.addTriangle(p - d - s, c, p + d, c, p - d + s, c, normal: V3(0, 1, 0))
        }
        let petalNode = SCNNode(geometry: petals.geometry(name: "petals"))
        let pm = Materials.matte(roughness: 0.6)
        pm.isDoubleSided = true
        petalNode.geometry?.materials = [pm]

        // 1: мох и папоротник.
        let moss = SCNNode()
        let strip = SCNNode(SCNPlane(width: 1.5, height: 11.5), Materials.grass(tile: 3))
        strip.eulerAngles.x = -Float.pi / 2
        strip.simdPosition = V3(0, 0.01, 5.95)
        moss.addChildNode(strip)
        let ferns = Nature.grassField(radius: 0, count: 2500, seed: 12, height: 0.15...0.4,
                                      colors: [UIColor(hex: 0x2E5A26), UIColor(hex: 0x3E6E2E)], avoid: nil,
                                      rect: SIMD2(0.9, 5.8))
        ferns.simdPosition = V3(0, 0, 5.95)
        moss.addChildNode(ferns)

        // 2: ковровая дорожка.
        let carpet = SCNNode(SCNBox(width: 1.4, height: 0.02, length: 11.5, chamferRadius: 0.005),
                             Materials.cloth(UIColor(red: 0.55, green: 0.06, blue: 0.1, alpha: 1), roughness: 0.9))
        carpet.simdPosition = V3(0, 0.01, 5.95)

        aisles = [petalNode, moss, carpet]
        for a in aisles { root.addChildNode(a) }
    }

    /// Фата, венок и букет для одного из вариантов Беллы.
    private func dressBella(_ bride: Humanoid, index: Int) {
        let tulle = Materials.cloth(UIColor(white: 1, alpha: 1), roughness: 0.5, sheen: true)
        tulle.transparency = 0.55
        tulle.isDoubleSided = true
        tulle.transparencyMode = .dualLayer

        let longVeil = SCNNode(SCNPlane(width: 0.5, height: 1.6), tulle)
        longVeil.simdPosition = V3(0, -0.55, -0.13)
        longVeil.eulerAngles.x = 0.12
        let shortVeil = SCNNode(SCNPlane(width: 0.32, height: 0.3), tulle)
        shortVeil.simdPosition = V3(0, 0.12, 0.1)
        shortVeil.eulerAngles.x = -0.35
        let crown = SCNNode()
        var rng = SeededRandom(seed: UInt64(20 + index))
        for i in 0..<14 {
            let a = Float(i) / 14 * 2 * Float.pi
            let f = SCNNode(SCNSphere(radius: 0.018),
                            Materials.pbr(i % 3 == 0 ? UIColor(hex: 0xD8C8F0) : UIColor(white: 0.97, alpha: 1), roughness: 0.6))
            f.simdPosition = V3(cos(a) * 0.1, 0.19 + rng.range(-0.01, 0.01), sin(a) * 0.1 - 0.02)
            crown.addChildNode(f)
        }
        for n in [longVeil, shortVeil, crown] { bride.head.addChildNode(n) }
        veils[index] = [longVeil, shortVeil, crown]

        // Букет — в правой руке, у груди.
        let bouquet = SCNNode()
        let petals = Materials.pbr(UIColor.white, roughness: 0.55)
        bouquetMaterials.append(petals)
        let leaves = Materials.pbr(UIColor(hex: 0x2F5A2A), roughness: 0.6)
        for i in 0..<16 {
            let a = Float(i) * 2.4
            let r = Float(i) / 16 * 0.08
            let b = SCNNode(SCNSphere(radius: 0.032), i % 5 == 0 ? leaves : petals)
            b.simdPosition = V3(cos(a) * r, sin(a) * r, -0.02 - Float(i % 3) * 0.01)
            bouquet.addChildNode(b)
        }
        let stems = SCNNode(SCNCylinder(radius: 0.025, height: 0.18), leaves)
        stems.simdPosition = V3(0, 0.1, 0)
        bouquet.addChildNode(stems)
        bouquet.simdPosition = V3(0, -0.12, 0.04)
        bouquet.eulerAngles.x = Float.pi / 2
        bride.handR.addChildNode(bouquet)
    }

    // MARK: - Применение выбора

    private func color(_ category: Category, _ index: Int) -> UIColor {
        let options = WeddingScene.options[category] ?? []
        guard index >= 0, index < options.count else { return .white }
        return UIColor(options[index].color)
    }

    private var bride: Humanoid { picks[Category.dress.rawValue] == 2 ? bellaPrincess : bellaSlim }

    private func applyPicks() {
        let dress = picks[Category.dress.rawValue]
        bellaPrincess.isHidden = dress != 2
        bellaSlim.isHidden = dress == 2
        bride.setOutfit(top: color(.dress, dress))

        let veil = picks[Category.veil.rawValue]
        for set in veils {
            for (i, n) in set.enumerated() { n.isHidden = i != veil }
        }
        let bouquetColor = color(.bouquet, picks[Category.bouquet.rawValue])
        for m in bouquetMaterials { m.diffuse.contents = bouquetColor }

        let suit = color(.suit, picks[Category.suit.rawValue])
        edward.setOutfit(top: suit)

        for (i, a) in arches.enumerated() { a.isHidden = i != picks[Category.arch.rawValue] }
        let light = picks[Category.lights.rawValue]
        for (i, l) in lights.enumerated() { l.isHidden = i != light }
        // Луна — значит холодная ночь: гасим закатный свет.
        key.light?.intensity = light == 2 ? 120 : 420
        scene.fogColor = light == 2 ? UIColor(red: 0.18, green: 0.22, blue: 0.32, alpha: 1)
                                    : UIColor(red: 0.4, green: 0.36, blue: 0.42, alpha: 1)

        for (i, a) in aisles.enumerated() { a.isHidden = i != picks[Category.aisle.rawValue] }
        let ribbons = picks[Category.ribbons.rawValue]
        ribbonMaterial.diffuse.contents = color(.ribbons, ribbons)
        ribbonMaterial.transparency = ribbons == 2 ? 0 : 1
    }

    // MARK: - Расстановка

    private func layoutPreview() {
        for b in [bellaSlim, bellaPrincess] {
            b.place(altar + V3(-0.45, 0, 0.6), yaw: 0.25)
            b.snap(.holdBouquet)
        }
        edward.place(altar + V3(0.45, 0, 0.6), yaw: -0.25)
        edward.snap(.stand)
        alice.place(altar + V3(2.2, 0, 2.2), yaw: -0.9)
        alice.snap(.stand)
        charlie.isHidden = true
        for g in guests { g.isHidden = true }
    }

    private func seatGuests() {
        for (i, g) in guests.enumerated() {
            g.isHidden = false
            let side: Float = i % 2 == 0 ? -1 : 1
            let row = Float(i / 2)
            g.place(V3(side * 1.4, 0, 2.2 + row * 1.1), yaw: Float.pi)
            g.snap(.sitChair)
            g.target = .sitChair
        }
    }

    override var ambience: [SoundFX.Ambience: Float] { [.crickets: 0.35, .forest: 0.2, .wind: 0.1] }

    override func updateAmbient(dt: Float) {
        for h in [bellaSlim, bellaPrincess, edward, alice, charlie] + guests where !h.isHidden {
            h.update(dt: dt, time: time)
        }
    }

    // MARK: - Игра

    override func enterGameplay() {
        layoutPreview()
        applyPicks()
    }

    override func updateGameplay(_ engine: GameEngine, dt: Float) {
        let s = engine.wedding
        if s.picked != picks {
            picks = s.picked
            applyPicks()
        }
        focus = s.category
        alice.lookAt = bride.head.simdWorldPosition
        // Камера показывает то, что сейчас выбирают.
        let eye: V3, look: V3, fov: Float
        switch focus {
        case .dress, .veil, .bouquet:
            let h = bride.head.simdWorldPosition
            eye = h + V3(0.4, focus == .bouquet ? -0.35 : -0.2, 2.2)
            look = h + V3(0, focus == .dress ? -0.6 : (focus == .bouquet ? -0.45 : 0), 0)
            fov = focus == .dress ? 40 : 30
        case .suit:
            let h = edward.head.simdWorldPosition
            eye = h + V3(0.2, -0.3, 2.4)
            look = h + V3(0, -0.5, 0)
            fov = 38
        case .arch:
            eye = V3(0.5, 1.8, 6.5)
            look = V3(0, 1.9, -0.6)
            fov = 44
        case .lights:
            eye = V3(-5, 3.6, 14)
            look = V3(0, 1.4, 3)
            fov = 54
        case .aisle:
            eye = V3(0, 1.6, 13)
            look = V3(0, 0.3, 4)
            fov = 50
        case .ribbons:
            eye = V3(-3.2, 1.3, 9.5)
            look = V3(-1.4, 0.6, 6)
            fov = 46
        }
        followCamera(eye: eye, target: look, fov: fov, rate: 3, dt: max(dt, 0.016))
    }

    override func enterIdle() {
        layoutPreview()
        applyPicks()
    }

    override func updateIdle(dt: Float) {
        let a = time * 0.05
        placeCamera(eye: rotateY(V3(0, 2.2, 9), a) + V3(0, 0, 3), target: V3(0, 1.3, 2), fov: 52)
    }

    // MARK: - Кат-сцены

    override func beginShot(_ cue: Cue) {
        layoutPreview()
        applyPicks()
        switch cue {
        case .weddingAlice:
            alice.lookAt = nil
        case .weddingAisle:
            seatGuests()
            for g in guests { g.snap(.stand) }
            charlie.isHidden = false
            charlie.snap(.escort)
            edward.place(altar + V3(0.5, 0, 0.5), yaw: Float.pi)
            alice.place(V3(-2.6, 0, 1.2), yaw: Float.pi / 2)
        case .weddingVows, .weddingKiss, .weddingCrane:
            seatGuests()
            let b = bride
            b.place(altar + V3(-0.35, 0, 0.55), yaw: Float.pi / 2)
            edward.place(altar + V3(0.35, 0, 0.55), yaw: -Float.pi / 2)
            b.snap(.holdBouquet)
            edward.snap(.stand)
            b.lookAt = edward.head.simdWorldPosition
            edward.lookAt = b.head.simdWorldPosition
            alice.place(V3(-2.6, 0, 1.2), yaw: Float.pi / 2)
            if cue == .weddingKiss { SoundFX.shared.play(.chime, volume: 0.8) }
        default:
            break
        }
    }

    override func updateShot(_ cue: Cue, progress p: Float, dt: Float) {
        switch cue {
        case .weddingAlice:
            let h = alice.head.simdWorldPosition
            dolly(p, eye: (h + V3(-1.2, 0, 1.4), h + V3(-0.8, 0, 1.0)), look: (h, h), fov: (34, 30))
        case .weddingGarden:
            dolly(p, eye: (V3(-8, 7, 22), V3(-3, 2.6, 13)), look: (V3(0, 1, -2), V3(0, 1.4, 0)), fov: (58, 50))
        case .weddingReady:
            dolly(p, eye: (V3(0, 2.2, 15), V3(0, 1.7, 11)), look: (V3(0, 1.5, 0), V3(0, 1.6, 0)), fov: (50, 44))
        case .weddingAisle:
            // Чарли ведёт Беллу по проходу.
            let t = easeSoft(p)
            let z = lerpf(11, 1.6, t)
            let b = bride
            b.place(V3(0.28, 0, z), yaw: Float.pi)
            charlie.place(V3(-0.32, 0, z), yaw: Float.pi)
            b.target = Pose.walk(time * 3.2, stride: 0.45)
            var escortWalk = Pose.walk(time * 3.2 + 0.4, stride: 0.45)
            escortWalk.shoulderL = V3(-0.25, 0, 0.12)
            escortWalk.elbowL = -1.4
            charlie.target = escortWalk
            b.rate = 12
            charlie.rate = 12
            edward.lookAt = b.head.simdWorldPosition
            for g in guests { g.lookAt = b.head.simdWorldPosition }
            let c = V3(0, 1.45, z)
            placeCamera(eye: c + V3(0.15, 0.1, -3.4), target: c, fov: 42)
        case .weddingVows:
            let c = (bride.head.simdWorldPosition + edward.head.simdWorldPosition) * 0.5
            placeCamera(eye: c + rotateY(V3(0, 0.05, 1.8), -0.5 + p * 0.3), target: c, fov: 36)
        case .weddingKiss:
            bride.target = .dance
            edward.target = .dance
            let c = (bride.head.simdWorldPosition + edward.head.simdWorldPosition) * 0.5
            placeCamera(eye: c + rotateY(V3(0, 0.05, 1.1), p * 1.2), target: c, fov: 32)
        case .weddingCrane:
            dolly(p, eye: (V3(0, 2, 6), V3(0, 16, 22)), look: (V3(0, 1.5, 0), V3(0, 8, -40)), fov: (46, 60))
        default:
            break
        }
    }
}

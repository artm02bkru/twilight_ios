import SceneKit
import UIKit
import simd

/// Глава 3. Обледеневшая парковка школы Форкса: снег, мокрый асфальт, фургон Тайлера.
final class VanStage: Stage3D {

    private let bella = Humanoid(Cast.bella)
    private let edward = Humanoid(Cast.edward)
    private let van = Vehicle.van()
    private let truck = Vehicle.pickup()
    private let volvo = Vehicle.sedan(color: UIColor(hex: 0xB9BEC4), metallic: 0.85)

    private let zone = SCNNode()
    private let zoneEdges = SCNNode()
    private let streak = SCNNode()
    private let spray = Nature.spray(color: UIColor(white: 0.92, alpha: 0.8))
    private let snowNode = SCNNode()

    private var vanPos = V3(12, 0, 0)
    private var vanYaw: Float = 0
    private var lastVanX: Float = 12
    private var shotStart = V3.zero

    // Где кто стоит.
    private let bellaSpot = V3(-6.6, 0, 0.2)
    private let edwardHome = V3(4.2, 0, -6.4)
    private let tireSpot = V3(-6.95, 0, -1.45)

    /// Горизонталь игры (0...1, с запасом) → мировой X центра фургона.
    private func worldX(_ v: CGFloat) -> Float { -5 + (Float(v) + 0.25) * 10 }

    override init() {
        super.init()
        let root = scene.rootNode

        setSky(Textures.SkyStyle(
            zenith: SIMD3(0.42, 0.47, 0.55), horizon: SIMD3(0.66, 0.69, 0.73), ground: SIMD3(0.3, 0.31, 0.33),
            cloudCover: 0.95, cloudLight: SIMD3(0.74, 0.76, 0.8), cloudDark: SIMD3(0.44, 0.47, 0.53),
            sunAzimuth: 0.8, sunElevation: 0.22, sunColor: SIMD3(0.95, 0.92, 0.88), sunGlow: 0.3,
            sunDisc: false, seed: 9), lighting: 1.1)
        setFog(color: UIColor(red: 0.62, green: 0.65, blue: 0.7, alpha: 1), start: 18, end: 160, exponent: 1.2)

        addKeyLight(color: UIColor(red: 0.9, green: 0.93, blue: 1.0, alpha: 1), intensity: 700,
                    azimuth: 0.8, elevation: 0.75, shadowExtent: 34, softness: 14)

        // Мокрый, местами обледеневший асфальт с отражениями.
        let floor = SCNFloor()
        floor.reflectivity = 0.14
        floor.reflectionFalloffEnd = 8
        floor.reflectionResolutionScaleFactor = 0.5
        let asphalt = Materials.asphalt(tile: 0.22)
        floor.materials = [asphalt]
        root.addChildNode(SCNNode(geometry: floor))

        buildLot(root)
        buildSchool(root)

        let forest = Nature.forestRing(center: V3(0, 0, -20), inner: 48, outer: 110, count: 520, seed: 31,
                                       heights: 18...30, broadleafShare: 0.08)
        root.addChildNode(forest)

        // Машины.
        root.addChildNode(truck.node)
        truck.node.simdPosition = V3(-8.4, 0, 0.2)
        root.addChildNode(volvo.node)
        volvo.node.simdPosition = V3(5.8, 0, -7.6)
        volvo.node.simdEulerAngles.y = 0.05
        root.addChildNode(van.node)
        van.setHeadlights(0.7)
        let sprayNode = SCNNode()
        sprayNode.simdPosition = V3(-0.9, 0.1, 0)
        sprayNode.addParticleSystem(spray)
        van.node.addChildNode(sprayNode)

        for h in [bella, edward] {
            root.addChildNode(h.node)
            h.node.setCastsShadow(true)
        }

        // Светящаяся зона, где фургон нужно остановить.
        let plane = SCNPlane(width: 1, height: 5.5)
        zone.geometry = plane
        plane.materials = [Materials.glow(UIColor(red: 0.45, green: 0.75, blue: 1, alpha: 1), intensity: 0.5)]
        zone.eulerAngles.x = -Float.pi / 2
        zone.simdPosition = V3(2, 0.02, 0)
        zone.castsShadow = false
        root.addChildNode(zone)
        for side: Float in [-0.5, 0.5] {
            let curtain = SCNNode(SCNPlane(width: 5.5, height: 1.4),
                                  Materials.glowImage(Textures.softDot, color: UIColor(red: 0.5, green: 0.8, blue: 1, alpha: 1),
                                                      intensity: 0.8))
            curtain.simdPosition = V3(side, 0.7, 0)
            curtain.eulerAngles.y = Float.pi / 2
            curtain.name = side < 0 ? "lo" : "hi"
            zoneEdges.addChildNode(curtain)
        }
        root.addChildNode(zoneEdges)

        // След сверхскорости Эдварда.
        streak.geometry = SCNPlane(width: 1, height: 1.7)
        streak.geometry?.materials = [Materials.glowImage(Textures.smoke, color: UIColor(red: 0.8, green: 0.88, blue: 1, alpha: 1),
                                                          intensity: 1.2)]
        streak.opacity = 0
        root.addChildNode(streak)

        // Снег.
        snowNode.addParticleSystem(Nature.snow(area: 36, rate: 320))
        root.addChildNode(snowNode)

        cameraSettings.exposureOffset = -0.2
        cameraSettings.saturation = 0.85
        placeCamera(eye: V3(-3, 2.2, 16), target: V3(2.5, 1, 0), fov: 66)
    }

    // MARK: - Окружение

    private func buildLot(_ root: SCNNode) {
        // Разметка парковки.
        let paint = Materials.pbr(UIColor(white: 0.85, alpha: 1), roughness: 0.5)
        for row: Float in [-8, -15] {
            for i in -8...8 {
                let line = SCNNode(SCNPlane(width: 0.12, height: 4.8), paint)
                line.eulerAngles.x = -Float.pi / 2
                line.simdPosition = V3(Float(i) * 2.9 + 1.45, 0.004, row)
                line.castsShadow = false
                root.addChildNode(line)
            }
        }

        // Припаркованные машины.
        var rng = SeededRandom(seed: 5)
        let colors: [UIColor] = [UIColor(hex: 0x23272C), UIColor(hex: 0x6B1F22), UIColor(hex: 0xC8C4BA),
                                 UIColor(hex: 0x2F4636), UIColor(hex: 0x494F5A), UIColor(hex: 0x8E8A7E)]
        for (x, z) in [(-14.5, -8.0), (-11.6, -8.0), (-2.9, -8.0), (11.6, -8.0), (14.5, -8.0),
                       (-8.7, -15.0), (-2.9, -15.0), (2.9, -15.0), (8.7, -15.0), (17.4, -15.0)] {
            let car = Vehicle.sedan(color: colors[Int(rng.unit() * Float(colors.count)) % colors.count],
                                    metallic: CGFloat(rng.range(0.2, 0.7)))
            car.node.simdPosition = V3(Float(x), 0, Float(z))
            car.node.simdEulerAngles.y = rng.range(-0.04, 0.04) + (rng.unit() > 0.5 ? Float.pi : 0)
            root.addChildNode(car.node)
        }

        // Сугробы по краям и пятна снега на асфальте.
        let snow = Materials.snow(tile: 2)
        for (x, z, w, l) in [(-26.0, -2.0, 3.0, 30.0), (26.0, -2.0, 3.0, 30.0), (0.0, 13.0, 60.0, 2.5), (0.0, -20.5, 60.0, 2.0)] {
            let bank = SCNNode(SCNBox(width: CGFloat(w), height: 0.6, length: CGFloat(l), chamferRadius: 0.3), snow)
            bank.simdPosition = V3(Float(x), 0.05, Float(z))
            bank.simdScale = V3(1, 1, 1)
            root.addChildNode(bank)
        }
        for _ in 0..<26 {
            let patch = SCNNode(SCNSphere(radius: 1), snow)
            let p = V3(rng.range(-24, 24), 0, rng.range(-19, 12))
            if abs(p.z) < 3 && p.x > -9 && p.x < 13 { continue }
            patch.simdPosition = p
            patch.simdScale = V3(rng.range(0.6, 2.2), 0.03, rng.range(0.5, 1.6))
            patch.castsShadow = false
            root.addChildNode(patch)
        }

        // Фонари с натриевыми лампами.
        let pole = Materials.pbr(UIColor(white: 0.25, alpha: 1), roughness: 0.4, metalness: 0.8)
        let lampGlass = Materials.glow(UIColor(red: 1, green: 0.75, blue: 0.45, alpha: 1), intensity: 2.5, doubleSided: false)
        for (x, z) in [(-18.0, -4.0), (-1.0, -11.5), (16.0, -4.0), (8.0, 9.0)] {
            let base = V3(Float(x), 0, Float(z))
            let post = SCNNode(SCNCylinder(radius: 0.09, height: 7), pole)
            post.simdPosition = base + V3(0, 3.5, 0)
            root.addChildNode(post)
            let head = SCNNode(SCNBox(width: 0.5, height: 0.18, length: 0.9, chamferRadius: 0.06), pole)
            head.simdPosition = base + V3(0, 7.05, 0.3)
            root.addChildNode(head)
            let glass = SCNNode(SCNBox(width: 0.4, height: 0.04, length: 0.7, chamferRadius: 0.02), lampGlass)
            glass.simdPosition = base + V3(0, 6.95, 0.3)
            root.addChildNode(glass)
            addOmni(at: base + V3(0, 6.6, 0.3), color: UIColor(red: 1, green: 0.72, blue: 0.42, alpha: 1),
                    intensity: 900, range: 16)
        }
    }

    private func buildSchool(_ root: SCNNode) {
        let z: Float = -31
        let wall = SCNNode(SCNBox(width: 64, height: 7.5, length: 12, chamferRadius: 0.05), Materials.brick(tile: 10))
        wall.simdPosition = V3(0, 3.75, z)
        wall.geometry?.firstMaterial?.setTiling(10)
        root.addChildNode(wall)

        let roof = SCNNode(SCNBox(width: 65, height: 0.6, length: 13, chamferRadius: 0.1),
                           Materials.pbr(UIColor(hex: 0x2E3236), roughness: 0.7))
        roof.simdPosition = V3(0, 7.8, z)
        root.addChildNode(roof)
        let snowRoof = SCNNode(SCNBox(width: 64.6, height: 0.18, length: 12.6, chamferRadius: 0.09), Materials.snow(tile: 4))
        snowRoof.simdPosition = V3(0, 8.18, z)
        root.addChildNode(snowRoof)

        // Окна: тёмное стекло и тёплый свет классов.
        let windows = Materials.pbr(UIColor(white: 0.04, alpha: 1), roughness: 0.05, metalness: 0.3)
        windows.emission.contents = Textures.windowsLit
        windows.emission.intensity = 1.4
        windows.emission.contentsTransform = SCNMatrix4MakeScale(14, 1, 1)
        windows.emission.wrapS = .repeat
        windows.emission.wrapT = .repeat
        for y: Float in [2.0, 5.2] {
            let band = SCNNode(SCNPlane(width: 60, height: 2.0), windows)
            band.simdPosition = V3(0, y, z + 6.02)
            root.addChildNode(band)
        }

        // Козырёк входа и вывеска.
        let canopy = SCNNode(SCNBox(width: 8, height: 0.3, length: 3, chamferRadius: 0.08),
                             Materials.pbr(UIColor(hex: 0x3A3E44), roughness: 0.5))
        canopy.simdPosition = V3(0, 3.4, z + 7.3)
        root.addChildNode(canopy)
        let text = SCNText(string: "FORKS HIGH SCHOOL", extrusionDepth: 0.06)
        text.font = UIFont.systemFont(ofSize: 0.7, weight: .heavy)
        text.flatness = 0.005
        text.chamferRadius = 0.01
        text.materials = [Materials.pbr(UIColor(white: 0.92, alpha: 1), roughness: 0.4, metalness: 0.6)]
        let textNode = SCNNode(geometry: text)
        let (minB, maxB) = textNode.boundingBox
        textNode.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x) / 2 + minB.x, 0, 0)
        textNode.simdPosition = V3(0, 3.65, z + 8.0)
        root.addChildNode(textNode)

        // Флагшток.
        let pole = SCNNode(SCNCylinder(radius: 0.05, height: 10), Materials.chrome())
        pole.simdPosition = V3(-12, 5, z + 9)
        root.addChildNode(pole)
    }

    override var ambience: [SoundFX.Ambience: Float] { [.wind: 0.45] }

    private var lastStage: VanScene.Stage = .waiting

    // MARK: - Общее

    private func setVan(_ p: V3, yaw: Float, sliding: Bool) {
        let dx = p.x - lastVanX
        lastVanX = p.x
        vanPos = p
        vanYaw = yaw
        van.node.simdPosition = p
        van.node.simdEulerAngles = V3(0, yaw, sliding ? sin(time * 7) * 0.012 : 0)
        van.roll(distance: abs(dx) * 0.3)
        spray.birthRate = sliding ? 220 : 0
    }

    override func updateAmbient(dt: Float) {
        snowNode.simdPosition = camera.simdPosition + V3(0, 9, -6)
        for h in [bella, edward] { h.update(dt: dt, time: time) }
        streak.opacity = max(0, streak.opacity - CGFloat(dt) * 2.5)
    }

    private func dash(from a: V3, to b: V3) {
        let mid = (a + b) * 0.5 + V3(0, 1.0, 0)
        streak.simdPosition = mid
        streak.simdScale = V3(simd_length(b - a), 1, 1)
        streak.simdEulerAngles = V3(0, -atan2(b.z - a.z, b.x - a.x), 0)
        streak.opacity = 0.9
    }

    // MARK: - Игра

    override func enterGameplay() {
        bella.place(bellaSpot, yaw: Float.pi / 2)
        bella.snap(.stand)
        bella.lookAt = nil
        edward.place(edwardHome, yaw: -2.2)
        edward.snap(.handsInPockets)
        edward.opacity = 1
        setVan(V3(worldX(1.4), 0, 0), yaw: 0, sliding: false)
        zone.isHidden = false
        zoneEdges.isHidden = false
    }

    private var edwardAtVan = false

    override func updateGameplay(_ engine: GameEngine, dt: Float) {
        let s = engine.van
        if s.stage != lastStage {
            if s.stage == .sliding { SoundFX.shared.play(.skid, volume: 0.7) }
            if s.stage == .resolving {
                SoundFX.shared.play(.impact, volume: s.quality == .missed ? 1 : 0.85)
                if s.quality != .missed { SoundFX.shared.play(.whoosh, volume: 0.8) }
            }
            lastStage = s.stage
        }
        var x = worldX(s.vanX)
        // При промахе фургон упирается в пикап и Беллу.
        x = max(x, -5.0)
        let sliding = s.stage == .sliding || (s.stage == .resolving && s.quality == .missed && x > -5)
        let wobble: Float = sliding ? sin(time * 2.6) * 0.18 + 0.12 : 0.08 * Float(s.crumple)
        setVan(V3(x, 0, 0), yaw: wobble, sliding: sliding)
        van.setDent(Float(s.crumple))

        // Зона.
        let zx = worldX(s.zoneX) - 1.0
        let width = Float(s.zoneHalf) * 20
        zone.simdPosition = V3(zx, 0.02, 0)
        zone.simdScale = V3(width, 1, 1)
        let pulse = 0.55 + 0.45 * sin(time * 6)
        zone.opacity = s.stage == .sliding ? CGFloat(0.35 + 0.35 * pulse) : 0.15
        zoneEdges.simdPosition = V3(zx, 0, 0)
        zoneEdges.childNode(withName: "lo", recursively: false)?.simdPosition = V3(-width / 2, 0.7, 0)
        zoneEdges.childNode(withName: "hi", recursively: false)?.simdPosition = V3(width / 2, 0.7, 0)
        zoneEdges.opacity = zone.opacity

        // Эдвард: либо у своей машины, либо уже упирается ладонями в борт.
        let saved = s.stage == .resolving && s.quality != nil && s.quality != .missed
        if saved {
            let spot = V3(x - 1.45, 0, 0.1)
            if !edwardAtVan {
                dash(from: edward.position, to: spot)
                edwardAtVan = true
                shake = 1
            }
            edward.place(spot, yaw: Float.pi / 2)
            edward.target = .reachPush
            edward.rate = 30
        } else {
            if edwardAtVan {
                edwardAtVan = false
                edward.place(edwardHome, yaw: -2.2)
                edward.snap(.handsInPockets)
            }
            edward.lookAt = bella.head.simdWorldPosition
            edward.rate = 7
        }

        // Белла: вздрагивает, а при промахе падает.
        if s.stage == .resolving && s.quality == .missed && x < -3.5 {
            bella.target = .lieBack
            bella.rate = 10
        } else if s.bellaFlinch > 0.2 || (s.stage == .sliding && x < 3) {
            bella.target = .flinch
            bella.rate = 12
        } else {
            bella.target = .stand
            bella.rate = 5
        }
        bella.lookAt = van.node.simdPosition + V3(0, 1.2, 0)
        if s.impact > 0.9 { shake = max(shake, 0.8) }

        followCamera(eye: V3(-3 + (x - 4) * 0.08, 2.2, 16), target: V3(2.0 + (x - 4) * 0.12, 1, 0),
                     fov: 66, rate: 3, dt: max(dt, 0.016))
    }

    override func enterIdle() {
        enterGameplay()
        zone.isHidden = true
        zoneEdges.isHidden = true
    }

    override func updateIdle(dt: Float) {
        let a = sin(time * 0.1) * 0.35
        placeCamera(eye: V3(-4, 2.4, 15) + V3(a * 6, 0, 0), target: V3(0, 1.2, -2), fov: 62)
    }

    // MARK: - Кат-сцены

    override func beginShot(_ cue: Cue) {
        zone.isHidden = true
        zoneEdges.isHidden = true
        bella.lookAt = nil
        edward.lookAt = nil
        edward.opacity = 1
        switch cue {
        case .lotEstablish:
            bella.place(tireSpot, yaw: -Float.pi / 2)
            bella.snap(.crouchTire)
            edward.place(edwardHome, yaw: -2.2)
            edward.snap(.handsInPockets)
            setVan(V3(30, 0, 9), yaw: -Float.pi / 2, sliding: false)
        case .lotBella:
            bella.place(tireSpot, yaw: -Float.pi / 2)
            bella.snap(.crouchTire)
        case .lotEdward:
            edward.place(edwardHome, yaw: -2.2)
            edward.snap(.handsInPockets)
            edward.lookAt = bella.head.simdWorldPosition
        case .lotVanSkid:
            setVan(V3(30, 0, 6), yaw: -Float.pi / 2, sliding: true)
            shotStart = vanPos
            SoundFX.shared.play(.skid, volume: 0.9, delay: 0.8)
        case .lotVanClose:
            bella.place(bellaSpot, yaw: Float.pi / 2)
            bella.snap(.stand)
            bella.target = .flinch
            bella.rate = 3
            setVan(V3(13, 0, 0.5), yaw: 0.4, sliding: true)
        case .lotDent:
            SoundFX.shared.play(.impact)
            setVan(V3(-2.4, 0, 0), yaw: 0.06, sliding: false)
            van.setDent(1)
            edward.place(V3(-3.85, 0, 0.1), yaw: Float.pi / 2)
            edward.snap(.reachPush)
            bella.place(V3(-6.2, 0, 0.6), yaw: Float.pi / 2)
            bella.snap(.sitGround)
        case .lotFacesBella, .lotFacesEdward:
            setVan(V3(-2.4, 0, 0), yaw: 0.06, sliding: false)
            van.setDent(1)
            bella.place(V3(-6.2, 0, 0.6), yaw: Float.pi / 2)
            bella.snap(.sitGround)
            edward.place(V3(-5.25, 0, 1.0), yaw: -Float.pi / 2 - 0.35)
            edward.snap(.kneel)
            bella.lookAt = edward.head.simdWorldPosition
            edward.lookAt = bella.head.simdWorldPosition
        default:
            break
        }
    }

    override func updateShot(_ cue: Cue, progress p: Float, dt: Float) {
        switch cue {
        case .lotEstablish:
            dolly(p, eye: (V3(-22, 14, 32), V3(-9, 4.5, 18)), look: (V3(0, 2, -14), V3(-5, 1, -1)), fov: (60, 52))
        case .lotBella:
            let head = bella.head.simdWorldPosition
            dolly(p, eye: (V3(-4.6, 0.9, 0.2), V3(-5.2, 0.8, -0.3)), look: (head, head + V3(-0.4, -0.15, 0)), fov: (38, 30))
        case .lotEdward:
            let head = edward.head.simdWorldPosition
            dolly(p, eye: (V3(-6.0, 1.15, -0.6), V3(-4.0, 1.3, -2.2)), look: (head, head), fov: (32, 20))
        case .lotVanSkid:
            // Фургон заезжает и срывается в занос.
            let t = easeSoft(p)
            let pos = V3(lerpf(30, 13, t), 0, lerpf(6, 0.5, t))
            setVan(pos, yaw: -Float.pi / 2 + t * (Float.pi / 2 + 0.4), sliding: true)
            placeCamera(eye: V3(9, 1.0, 9) + V3(t * -2, 0, 0), target: vanPos + V3(0, 1, 0), fov: 48)
            if p > 0.4 { shake = max(shake, 0.25) }
        case .lotVanClose:
            // Замедленная съёмка: фургон надвигается на Беллу.
            let t = p
            setVan(V3(lerpf(13, 6.5, t), 0, lerpf(0.5, 0.2, t)), yaw: 0.4 - t * 0.25, sliding: true)
            bella.lookAt = vanPos + V3(0, 1.2, 0)
            dolly(p, eye: (V3(-7.6, 1.2, 1.6), V3(-7.3, 1.1, 1.2)),
                  look: (bella.head.simdWorldPosition, vanPos + V3(0, 1.3, 0)), fov: (44, 34))
            cameraSettings.motionBlurIntensity = 0.6
        case .lotDent:
            dolly(p, eye: (V3(-5.4, 1.3, 2.4), V3(-4.6, 1.15, 1.3)), look: (V3(-3.4, 1.1, 0), V3(-3.4, 1.15, 0)), fov: (40, 30))
        case .lotFacesBella:
            let target = bella.head.simdWorldPosition
            dolly(p, eye: (V3(-4.7, 1.0, 1.6), V3(-4.9, 0.95, 1.45)), look: (target, target), fov: (30, 26))
        case .lotFacesEdward:
            let target = edward.head.simdWorldPosition
            dolly(p, eye: (V3(-6.5, 0.85, 0.0), V3(-6.4, 0.85, 0.15)), look: (target, target), fov: (30, 25))
        default:
            break
        }
        if cue != .lotVanClose { cameraSettings.motionBlurIntensity = 0 }
    }
}

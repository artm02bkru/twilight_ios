import SceneKit
import UIKit
import simd

/// Глава 19. Балетная студия в Фениксе: паркет, разбитые зеркала, вечерний свет из окон.
final class StudioStage: Stage3D {

    private let bella = Humanoid(Cast.bella)
    private let edward = Humanoid(Cast.edward)
    private let carlisle = Humanoid(Cast.carlisle)
    private let alice = Humanoid(Cast.alice)

    private let venomLight = SCNNode()
    private let woundGlow = SCNNode()
    private let fluorescent = SCNNode()
    private var fluorescentMat = SCNMaterial()

    private let bellaFeet = V3(0.85, 0, 0)

    override init() {
        super.init()
        let root = scene.rootNode

        setSky(Textures.SkyStyle(
            zenith: SIMD3(0.12, 0.1, 0.18), horizon: SIMD3(0.75, 0.42, 0.28), ground: SIMD3(0.1, 0.08, 0.07),
            cloudCover: 0.2, sunAzimuth: 1.6, sunElevation: 0.05, sunColor: SIMD3(1, 0.55, 0.3),
            sunGlow: 1.0, sunDisc: true, seed: 23), lighting: 0.7)
        scene.background.contents = UIColor.black
        setFog(color: UIColor(red: 0.05, green: 0.04, blue: 0.05, alpha: 1), start: 6, end: 40, exponent: 1.5)

        buildRoom(root)

        for h in [bella, edward, carlisle, alice] {
            root.addChildNode(h.node)
            h.node.setCastsShadow(true)
        }

        // Яд: фиолетовое свечение раны и свет на коже.
        let glowMat = Materials.glowImage(Textures.softDot, color: UIColor(red: 0.6, green: 0.2, blue: 0.9, alpha: 1),
                                          intensity: 2)
        woundGlow.geometry = SCNPlane(width: 0.14, height: 0.14)
        woundGlow.geometry?.materials = [glowMat]
        woundGlow.constraints = [SCNBillboardConstraint()]
        root.addChildNode(woundGlow)
        let vl = SCNLight()
        vl.type = .omni
        vl.color = UIColor(red: 0.55, green: 0.2, blue: 0.95, alpha: 1)
        vl.intensity = 0
        vl.attenuationEndDistance = 1.4
        venomLight.light = vl
        root.addChildNode(venomLight)

        cameraSettings.exposureOffset = 0.3
        cameraSettings.bloomIntensity = 0.85
        cameraSettings.bloomThreshold = 0.8
        cameraSettings.saturation = 0.9
        cameraSettings.contrast = 0.18
        placeCamera(eye: V3(1.2, 1.4, 2.4), target: V3(-0.4, 0.2, 0.5), fov: 50)
    }

    private func buildRoom(_ root: SCNNode) {
        // Паркет с лаком — в нём отражаются окна и зеркала.
        let floor = SCNFloor()
        floor.reflectivity = 0.22
        floor.reflectionFalloffEnd = 3
        floor.reflectionResolutionScaleFactor = 0.6
        floor.materials = [Materials.wood(tile: 0.3, roughness: 0.25)]
        root.addChildNode(SCNNode(geometry: floor))

        let wallMat = Materials.pbr(UIColor(hex: 0xC9C2B8), roughness: 0.85, normal: Textures.groundNormal,
                                    normalIntensity: 0.15, tile: 3)
        let w: Float = 16, d: Float = 11, h: Float = 4.6
        func wall(_ width: Float, _ pos: V3, _ yaw: Float) {
            let n = SCNNode(SCNPlane(width: CGFloat(width), height: CGFloat(h)), wallMat)
            n.simdPosition = pos
            n.eulerAngles.y = yaw
            root.addChildNode(n)
        }
        wall(w, V3(0, h / 2, -d / 2), 0)
        wall(w, V3(0, h / 2, d / 2), Float.pi)
        wall(d, V3(w / 2, h / 2, 0), -Float.pi / 2)
        let ceiling = SCNNode(SCNPlane(width: CGFloat(w), height: CGFloat(d)),
                              Materials.pbr(UIColor(white: 0.5, alpha: 1), roughness: 0.9))
        ceiling.eulerAngles.x = Float.pi / 2
        ceiling.simdPosition = V3(0, h, 0)
        root.addChildNode(ceiling)

        // Стена окон (слева): закатное небо, переплёты.
        let windowWall = SCNNode(SCNPlane(width: CGFloat(d), height: CGFloat(h)),
                                 Materials.pbr(UIColor(white: 0.1, alpha: 1), roughness: 0.9))
        windowWall.simdPosition = V3(-w / 2, h / 2, 0)
        windowWall.eulerAngles.y = Float.pi / 2
        // Стена с окнами не должна перекрывать закатный свет снаружи.
        windowWall.castsShadow = false
        root.addChildNode(windowWall)
        let dusk = SCNMaterial()
        dusk.lightingModel = .constant
        dusk.diffuse.contents = Textures.sky(Textures.SkyStyle(
            zenith: SIMD3(0.12, 0.1, 0.2), horizon: SIMD3(1, 0.5, 0.25), ground: SIMD3(0.15, 0.1, 0.08),
            cloudCover: 0.35, cloudLight: SIMD3(1, 0.6, 0.4), cloudDark: SIMD3(0.3, 0.15, 0.2),
            sunAzimuth: 0, sunElevation: 0.04, sunColor: SIMD3(1, 0.6, 0.3), sunGlow: 1.2, seed: 31))
        dusk.emission.contents = dusk.diffuse.contents
        dusk.emission.intensity = 1.6
        let frame = Materials.pbr(UIColor(white: 0.12, alpha: 1), roughness: 0.4, metalness: 0.6)
        for i in 0..<4 {
            let z = -d / 2 + 1.5 + Float(i) * 2.7
            let pane = SCNNode(SCNPlane(width: 2.1, height: 2.6), dusk)
            pane.simdPosition = V3(-w / 2 + 0.02, 2.2, z)
            pane.eulerAngles.y = Float.pi / 2
            pane.castsShadow = false
            root.addChildNode(pane)
            for dz: Float in [-1.05, 0, 1.05] {
                let mullion = SCNNode(SCNBox(width: 0.06, height: 2.7, length: 0.06, chamferRadius: 0.01), frame)
                mullion.simdPosition = V3(-w / 2 + 0.05, 2.2, z + dz)
                root.addChildNode(mullion)
            }
        }
        // Закатный свет из окон — длинные тени по паркету.
        let sun = Stage3D.spotLight(color: UIColor(red: 1, green: 0.6, blue: 0.35, alpha: 1), intensity: 9000,
                                    angle: 60, range: 40, shadows: true)
        sun.simdPosition = V3(-w / 2 - 6, 3.4, 1)
        sun.simdLook(at: V3(1, 0, 0))
        root.addChildNode(sun)
        addAmbient(color: UIColor(red: 0.3, green: 0.3, blue: 0.4, alpha: 1), intensity: 35)

        // Зеркальная стена с балетным станком; часть зеркал разбита.
        let mirror = Materials.mirror()
        let cracked = Materials.pbr(UIColor(white: 0.6, alpha: 1), roughness: 0.25, metalness: 1,
                                    normal: Textures.asphaltNormal, normalIntensity: 2.5, tile: 2)
        for i in 0..<6 {
            let x = -w / 2 + 2 + Float(i) * 2.4
            let broken = i == 2 || i == 3
            let panel = SCNNode(SCNBox(width: 2.3, height: 2.6, length: 0.03, chamferRadius: 0.005),
                                broken ? cracked : mirror)
            panel.simdPosition = V3(x, 1.75, -d / 2 + 0.03)
            if broken { panel.eulerAngles.z = Float(i) * 0.01 - 0.025 }
            root.addChildNode(panel)
        }
        let barreMat = Materials.wood(tile: 1, roughness: 0.3)
        let barre = SCNNode(SCNCylinder(radius: 0.025, height: CGFloat(w - 1)), barreMat)
        barre.eulerAngles.z = Float.pi / 2
        barre.simdPosition = V3(0, 1.05, -d / 2 + 0.3)
        root.addChildNode(barre)
        for x: Float in [-6, -2, 2, 6] {
            let bracket = SCNNode(SCNCylinder(radius: 0.012, height: 0.28), Materials.chrome())
            bracket.eulerAngles.x = Float.pi / 2
            bracket.simdPosition = V3(x, 1.05, -d / 2 + 0.16)
            root.addChildNode(bracket)
        }

        // Осколки на полу.
        var rng = SeededRandom(seed: 19)
        let shardMat = Materials.mirror()
        for _ in 0..<70 {
            let shard = SCNNode(SCNPyramid(width: CGFloat(rng.range(0.03, 0.14)), height: 0.004,
                                           length: CGFloat(rng.range(0.03, 0.12))), shardMat)
            shard.simdPosition = V3(rng.range(-3.5, 2.5), 0.002, rng.range(-5.2, -1.5))
            shard.eulerAngles.y = rng.range(0, 6.28)
            shard.castsShadow = false
            root.addChildNode(shard)
        }

        // Мигающая лампа дневного света.
        fluorescentMat = Materials.glow(UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1), intensity: 2, doubleSided: false)
        fluorescent.geometry = SCNBox(width: 1.6, height: 0.05, length: 0.2, chamferRadius: 0.02)
        fluorescent.geometry?.materials = [fluorescentMat]
        fluorescent.simdPosition = V3(-0.5, h - 0.1, 0.5)
        let fl = SCNLight()
        fl.type = .omni
        fl.color = UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 1)
        fl.intensity = 500
        fl.attenuationEndDistance = 9
        fluorescent.light = fl
        root.addChildNode(fluorescent)
    }

    override func updateAmbient(dt: Float) {
        for h in [bella, edward, carlisle, alice] { h.update(dt: dt, time: time) }
        // Лампа то гаснет, то вспыхивает.
        let flick: Float = sin(time * 13) + sin(time * 31) > 1.4 ? 0.1 : 1
        fluorescent.light?.intensity = CGFloat(500 * flick)
        fluorescentMat.emission.intensity = CGFloat(2 * flick)

        let wrist = bella.handR.simdWorldPosition
        woundGlow.simdPosition = wrist + V3(0, 0.05, 0.02)
        venomLight.simdPosition = wrist + V3(0, 0.15, 0)
    }

    private func setVenom(_ v: Float, pulse: Float) {
        let beat = 0.75 + 0.25 * sin(pulse)
        venomLight.light?.intensity = CGFloat(v * 260 * beat)
        woundGlow.opacity = CGFloat(v * beat)
    }

    // MARK: - Расстановка

    private func layout() {
        bella.place(bellaFeet, yaw: Float.pi / 2)
        bella.snap(.lieArmOut)
        bella.breathing = 0.6
        let wrist = bella.handR.simdWorldPosition
        edward.place(V3(wrist.x - 0.05, 0, wrist.z + 0.62), yaw: Float.pi)
        edward.snap(.kneelBend)
        let head = bella.head.simdWorldPosition
        carlisle.place(V3(head.x - 0.6, 0, head.z + 0.15), yaw: Float.pi / 2)
        carlisle.snap(.kneel)
        carlisle.lookAt = head
        alice.place(V3(head.x - 0.4, 0, head.z - 0.8), yaw: 0.6)
        alice.snap(.kneel)
        alice.lookAt = head
    }

    // MARK: - Игра

    override func enterGameplay() {
        layout()
    }

    override func updateGameplay(_ engine: GameEngine, dt: Float) {
        let s = engine.studio

        // Удержание — склонился к ране; отпустил — выпрямился.
        let drinking = engine.phase == .playing && engine.isHolding
        edward.target = drinking ? .kneelBend : .kneelHold
        edward.rate = 5
        edward.lookAt = drinking ? bella.handR.simdWorldPosition : bella.head.simdWorldPosition

        // Жажда — алые глаза; потеря контроля — тряска.
        let thirst = Float(s.thirst)
        let eye = UIColor(red: CGFloat(0.78 + 0.2 * thirst), green: CGFloat(0.56 * (1 - thirst)),
                          blue: CGFloat(0.17 * (1 - thirst)), alpha: 1)
        edward.setEyes(eye, glow: CGFloat(0.3 + thirst * 2.5))
        if s.lostControl > 0.8 { shake = max(shake, 0.9) }
        setVenom(Float(s.venom), pulse: Float(s.pulse))

        // Камера наезжает, когда жажда растёт.
        let wrist = bella.handR.simdWorldPosition
        let push = thirst * 0.6
        followCamera(eye: wrist + V3(1.25 - push * 0.5, 1.1 - push * 0.4, 1.4 - push * 0.6),
                     target: wrist + V3(-0.2, 0.25, 0.25), fov: 50 - thirst * 10, rate: 2, dt: max(dt, 0.016))
    }

    override func enterIdle() {
        layout()
        setVenom(0.6, pulse: 0)
    }

    override func updateIdle(dt: Float) {
        let a = sin(time * 0.15) * 0.5
        let wrist = bella.handR.simdWorldPosition
        placeCamera(eye: wrist + rotateY(V3(1.6, 1.4, 1.8), a), target: wrist + V3(-0.4, 0.2, 0), fov: 50)
        setVenom(0.6, pulse: time * 3.4)
    }

    // MARK: - Кат-сцены

    override func beginShot(_ cue: Cue) {
        layout()
        edward.setEyes(Cast.topaz, glow: 0.3)
        switch cue {
        case .studioEstablish, .studioBite:
            edward.target = .kneelHold
            setVenom(1, pulse: 0)
        case .studioCarlisle, .studioEdward:
            edward.snap(.kneelHold)
            setVenom(1, pulse: 0)
        case .studioCalm:
            edward.snap(.kneelHold)
            setVenom(0, pulse: 0)
        case .studioEmbrace:
            edward.snap(.kneelHold)
            edward.place(edward.position + V3(-0.5, 0, -0.25), yaw: Float.pi + 0.6)
            setVenom(0, pulse: 0)
        default:
            break
        }
    }

    override func updateShot(_ cue: Cue, progress p: Float, dt: Float) {
        let wrist = bella.handR.simdWorldPosition
        let bellaHead = bella.head.simdWorldPosition
        switch cue {
        case .studioEstablish:
            setVenom(1, pulse: time * 3.4)
            dolly(p, eye: (V3(-6, 2.4, 3.8), V3(-2.4, 1.5, 2.8)), look: (V3(0, 0.6, -1), bellaHead), fov: (58, 46))
        case .studioBite:
            setVenom(1, pulse: time * 4.5)
            dolly(p, eye: (wrist + V3(0.42, 0.5, 0.5), wrist + V3(0.28, 0.32, 0.36)), look: (wrist, wrist), fov: (34, 26))
        case .studioCarlisle:
            setVenom(1, pulse: time * 3.4)
            let head = carlisle.head.simdWorldPosition
            dolly(p, eye: (head + V3(1.3, 0.1, 0.9), head + V3(1.1, 0.05, 0.7)), look: (head, head), fov: (32, 28))
        case .studioEdward:
            setVenom(1, pulse: time * 3.4)
            let head = edward.head.simdWorldPosition
            edward.lookAt = wrist
            edward.setEyes(UIColor(red: 0.85, green: 0.4, blue: 0.12, alpha: 1), glow: 0.6 + CGFloat(p))
            let front = V3(0.0, -0.05, -0.75)
            dolly(p, eye: (head + front + V3(0.2, 0, 0), head + front * 0.75), look: (head, head), fov: (30, 24))
        case .studioCalm:
            bella.lookAt = edward.head.simdWorldPosition
            dolly(p, eye: (bellaHead + V3(0.3, 0.55, 0.45), bellaHead + V3(0.2, 0.42, 0.32)),
                  look: (bellaHead, bellaHead), fov: (30, 24))
        case .studioEmbrace:
            edward.lookAt = bellaHead
            let c = (bellaHead + edward.head.simdWorldPosition) * 0.5
            placeCamera(eye: c + rotateY(V3(1.3, 0.5, 1.3), p * 0.6), target: c, fov: 38)
        default:
            break
        }
    }
}

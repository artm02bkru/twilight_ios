import SceneKit
import UIKit
import simd

/// Глава 17. Бейсбольное поле на лесной поляне в грозу: ливень, молнии, Каллены на позициях.
final class BaseballStage: Stage3D {

    private let edward = Humanoid(Cast.edward)
    private let alice = Humanoid(Cast.alice)
    private let emmett = Humanoid(Cast.emmett)
    private let rosalie = Humanoid(Cast.rosalie)
    private let jasper = Humanoid(Cast.jasper)
    private let carlisle = Humanoid(Cast.carlisle)
    private let esme = Humanoid(Cast.esme)
    private let bella = Humanoid(Cast.bella)
    private let james = Humanoid(Cast.james)
    private let laurent = Humanoid(Cast.laurent)
    private let victoria = Humanoid(Cast.victoria)
    private var everyone: [Humanoid] {
        [edward, alice, emmett, rosalie, jasper, carlisle, esme, bella, james, laurent, victoria]
    }
    private var nomads: [Humanoid] { [james, laurent, victoria] }

    private let ball = SCNNode()
    private let ballTrail = SCNNode()
    private let strikeZone = SCNNode()
    private let bolt = SCNNode()
    private let flashLight = SCNNode()
    private let rainNode = SCNNode()

    private var flash: Float = 0
    private var lastThunder: Double = 0
    private var strikeSeed: UInt64 = 1
    private var swingLatch = false

    private let mound = V3(0, 0.25, -18.4)
    private let batterSpot = V3(-0.85, 0, 0.15)

    override init() {
        super.init()
        let root = scene.rootNode

        setSky(Textures.SkyStyle(
            zenith: SIMD3(0.05, 0.06, 0.09), horizon: SIMD3(0.16, 0.18, 0.22), ground: SIMD3(0.03, 0.04, 0.04),
            cloudCover: 1.0, cloudLight: SIMD3(0.24, 0.26, 0.31), cloudDark: SIMD3(0.06, 0.07, 0.09),
            sunAzimuth: 1.2, sunElevation: 0.6, sunColor: SIMD3(0.5, 0.55, 0.7), sunGlow: 0.2,
            sunDisc: false, seed: 17), lighting: 0.55)
        setFog(color: UIColor(red: 0.1, green: 0.12, blue: 0.15, alpha: 1), start: 20, end: 170, exponent: 1.3)

        addKeyLight(color: UIColor(red: 0.6, green: 0.68, blue: 0.85, alpha: 1), intensity: 180,
                    azimuth: 1.2, elevation: 0.9, shadowExtent: 50, softness: 12)
        addAmbient(color: UIColor(red: 0.25, green: 0.3, blue: 0.4, alpha: 1), intensity: 60)

        // Вспышка молнии — направленный свет без теней.
        let fl = SCNLight()
        fl.type = .directional
        fl.color = UIColor(red: 0.75, green: 0.82, blue: 1, alpha: 1)
        fl.intensity = 0
        flashLight.light = fl
        flashLight.simdPosition = V3(-40, 80, -60)
        flashLight.simdLook(at: .zero)
        root.addChildNode(flashLight)

        buildField(root)
        root.addChildNode(Nature.forestRing(center: V3(0, 0, -30), inner: 88, outer: 170, count: 760, seed: 41,
                                            heights: 22...36, broadleafShare: 0.1))

        for h in everyone {
            root.addChildNode(h.node)
            h.node.setCastsShadow(true)
        }

        // Бита в правой руке Эдварда.
        let batNode = SCNNode()
        batNode.simdPosition = V3(0, -0.08, 0.38)
        if let model = ModelAsset.named("bat"), let mesh = model.node("bat", material: { d in
            let m = ModelAsset.defaultMaterial(d)
            m.roughness.contents = 0.35
            m.clearCoat.contents = 0.8
            return m
        }) {
            // Модель лежит наискосок: ось биты (ручка → бочка) разворачиваем вдоль кисти.
            mesh.simdPosition = V3(0.0002, 0.0293, -0.0463)
            batNode.simdOrientation = simd_quatf(from: simd_normalize(V3(0.0006, 0.4863, -0.8738)), to: V3(0, 0, 1))
            batNode.addChildNode(mesh)
        } else {
            let bat = SCNCone(topRadius: 0.032, bottomRadius: 0.017, height: 0.84)
            bat.radialSegmentCount = 20
            let cone = SCNNode(bat, Materials.pbr(UIColor(hex: 0xB88A55), roughness: 0.35))
            cone.geometry?.firstMaterial?.clearCoat.contents = 0.8
            cone.eulerAngles.x = Float.pi / 2
            batNode.addChildNode(cone)
        }
        edward.handR.addChildNode(batNode)
        // Перчатка-ловушка у Эммета.
        let mitt = SCNNode(SCNSphere(radius: 0.09), Materials.pbr(UIColor(hex: 0x5A3A22), roughness: 0.6))
        mitt.simdScale = V3(0.6, 1, 1)
        mitt.simdPosition = V3(0, -0.1, 0)
        emmett.handL.addChildNode(mitt)

        // Мяч и его след.
        let ballGeo = SCNSphere(radius: 0.037)
        ballGeo.segmentCount = 20
        ball.geometry = ballGeo
        ballGeo.materials = [Materials.pbr(UIColor(white: 0.95, alpha: 1), roughness: 0.55)]
        root.addChildNode(ball)
        let trail = SCNParticleSystem()
        trail.birthRate = 260
        trail.particleLifeSpan = 0.14
        trail.particleSize = 0.05
        trail.particleImage = Textures.softDot
        trail.particleColor = UIColor(red: 0.85, green: 0.92, blue: 1, alpha: 0.6)
        trail.blendMode = .additive
        trail.emitterShape = SCNSphere(radius: 0.02)
        trail.isLocal = false
        ballTrail.addParticleSystem(trail)
        ball.addChildNode(ballTrail)

        // Зона удара — светящийся отрезок траектории.
        let a = ballPath(BaseballScene.strikeLow), b = ballPath(BaseballScene.strikeHigh)
        let tube = SCNCylinder(radius: 0.13, height: CGFloat(simd_length(b - a)))
        tube.radialSegmentCount = 24
        strikeZone.geometry = tube
        tube.materials = [Materials.glowImage(Textures.smoke, color: UIColor(red: 0.5, green: 0.78, blue: 1, alpha: 1),
                                              intensity: 0.35)]
        strikeZone.simdPosition = (a + b) * 0.5
        let dir = simd_normalize(b - a)
        strikeZone.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: dir)
        strikeZone.castsShadow = false
        root.addChildNode(strikeZone)

        bolt.opacity = 0
        root.addChildNode(bolt)

        rainNode.addParticleSystem(RoadBuild.rain(intensity: 1700))
        root.addChildNode(rainNode)
        let fog = SCNNode()
        fog.addParticleSystem(Nature.groundFog(area: 160, rate: 18, color: UIColor(white: 0.7, alpha: 0.05)))
        fog.simdPosition = V3(0, 0.5, -60)
        root.addChildNode(fog)

        cameraSettings.exposureOffset = 0.5
        cameraSettings.bloomIntensity = 0.9
        cameraSettings.bloomThreshold = 0.75
        cameraSettings.saturation = 0.8
        placeCamera(eye: V3(0.7, 1.9, 4.6), target: V3(0, 1.2, -12), fov: 54)
    }

    private func buildField(_ root: SCNNode) {
        root.addChildNode(Nature.ground(size: 500, material: Materials.grass(tile: 80)))

        // Инфилд: земляной ромб, внутри трава.
        let infield = Nature.ground(size: 34, material: Materials.dirt(tile: 6))
        infield.simdPosition = V3(0, 0.01, -19.4)
        infield.eulerAngles.y = Float.pi / 4
        root.addChildNode(infield)
        let inner = Nature.ground(size: 24, material: Materials.grass(tile: 5))
        inner.simdPosition = V3(0, 0.02, -19.4)
        inner.eulerAngles.y = Float.pi / 4
        root.addChildNode(inner)
        root.addChildNode(Nature.grassField(radius: 60, count: 30_000, seed: 9, height: 0.08...0.2,
                                            avoid: { p in abs(p.x) + abs(p.z + 19.4) < 25 }))

        // Горка питчера.
        let moundNode = SCNNode(SCNSphere(radius: 1), Materials.dirt(tile: 2))
        moundNode.simdScale = V3(2.8, 0.25, 2.8)
        moundNode.simdPosition = V3(0, 0, -18.4)
        root.addChildNode(moundNode)

        // Базы и дом.
        let white = Materials.pbr(UIColor(white: 0.94, alpha: 1), roughness: 0.7)
        for p in [V3(19.4, 0.05, -19.4), V3(0, 0.05, -38.8), V3(-19.4, 0.05, -19.4)] {
            let base = SCNNode(SCNBox(width: 0.38, height: 0.08, length: 0.38, chamferRadius: 0.03), white)
            base.simdPosition = p
            base.eulerAngles.y = Float.pi / 4
            root.addChildNode(base)
        }
        let plate = SCNNode(SCNBox(width: 0.43, height: 0.03, length: 0.43, chamferRadius: 0.01), white)
        plate.simdPosition = V3(0, 0.03, 0)
        plate.eulerAngles.y = Float.pi / 4
        root.addChildNode(plate)
        let dirtCircle = SCNNode(SCNCylinder(radius: 3.2, height: 0.02), Materials.dirt(tile: 2))
        dirtCircle.simdPosition = V3(0, 0.012, 0)
        root.addChildNode(dirtCircle)

        // Скамейка у первой базы.
        let wood = Materials.wood(tile: 1, roughness: 0.7)
        let bench = SCNNode(SCNBox(width: 4, height: 0.08, length: 0.45, chamferRadius: 0.02), wood)
        bench.simdPosition = V3(-6, 0.45, 3.4)
        root.addChildNode(bench)
        for x: Float in [-7.7, -4.3] {
            let leg = SCNNode(SCNBox(width: 0.08, height: 0.45, length: 0.4, chamferRadius: 0.01), wood)
            leg.simdPosition = V3(x, 0.225, 3.4)
            root.addChildNode(leg)
        }
    }

    /// Точка траектории подачи (0 — рука Элис, 1 — у биты).
    private func ballPath(_ t: CGFloat) -> V3 {
        let k = Float(t)
        let start = V3(-0.25, 1.95, -17.7)
        let end = V3(-0.05, 0.95, 0.35)
        return mixv(start, end, k) + V3(0, sin(clampf(k, 0, 1) * Float.pi) * 0.35, 0)
    }

    // MARK: - Погода

    override var ambience: [SoundFX.Ambience: Float] { [.heavyRain: 1.0, .wind: 0.8] }

    private func strike() {
        // Гром догоняет вспышку с задержкой — молния далеко.
        SoundFX.shared.play(.thunder, volume: 1.0, delay: Double.random(in: 0.3...1.4))
        strikeSeed &+= 1
        var rng = SeededRandom(seed: strikeSeed)
        let base = V3(rng.range(-120, 120), 0, rng.range(-200, -110))
        bolt.geometry = Nature.lightningBolt(from: base + V3(rng.range(-20, 20), 140, 0), to: base, seed: strikeSeed)
        bolt.opacity = 1
        flash = 1
    }

    override func updateAmbient(dt: Float) {
        for h in everyone { h.update(dt: dt, time: time) }
        rainNode.simdPosition = camera.simdPosition + V3(0, 20, -10)

        flash = max(0, flash - dt * 3.5)
        // Мерцание: вспышка гаснет рывками.
        let flicker: Float = flash > 0.05 ? (sin(time * 70) > 0 ? 1 : 0.45) : 0
        flashLight.light?.intensity = CGFloat(flash * flicker * 2400)
        scene.background.intensity = CGFloat(1 + flash * flicker * 3)
        scene.lightingEnvironment.intensity = CGFloat(0.55 + flash * flicker * 2)
        bolt.opacity = CGFloat(flash > 0.3 ? flicker : 0)
        if flash > 0.6 { shake = max(shake, 0.15) }
    }

    // MARK: - Игра

    override func enterGameplay() {
        edward.place(batterSpot, yaw: Float.pi / 2)
        edward.snap(.batReady)
        alice.place(mound, yaw: 0)
        alice.snap(.pitchWindup)
        emmett.place(V3(0, 0, 1.15), yaw: Float.pi)
        emmett.snap(.catcher)
        rosalie.place(V3(17, 0, -21), yaw: -0.7)
        rosalie.snap(.fielder)
        jasper.place(V3(-16.5, 0, -22), yaw: 0.7)
        jasper.snap(.fielder)
        carlisle.place(V3(3, 0, -62), yaw: 0)
        carlisle.snap(.fielder)
        esme.place(V3(-3, 0, 2.6), yaw: 2.6)
        esme.snap(.stand)
        bella.place(V3(-4.2, 0, 3.0), yaw: 2.4)
        bella.snap(.handsInPockets)
        for (i, n) in nomads.enumerated() {
            n.place(V3(Float(i - 1) * 2.4, 0, -105), yaw: 0)
            n.snap(.stand)
            n.opacity = 0
        }
        strikeZone.isHidden = false
        ball.isHidden = false
    }

    override func updateGameplay(_ engine: GameEngine, dt: Float) {
        let s = engine.baseball

        // Гром из игры → молния на пике.
        if s.thunder > 0.86 && lastThunder <= 0.86 { strike() }
        lastThunder = s.thunder

        // Питчер: замах до броска, потом сопровождение.
        if s.stage == .flight && s.ballT >= 0 {
            alice.target = .pitchRelease
            alice.rate = 14
        } else {
            alice.target = .pitchWindup
            alice.rate = 4
        }

        // Мяч.
        if s.ballFlight > 0.01 && s.quality != .missed {
            let u = Float(1 - s.ballFlight)
            let contact = ballPath(1)
            let flight = V3(Float(s.ballFlightX) * 60 * u, sin(min(1, u * 1.2) * Float.pi) * 22, -85 * u)
            ball.simdPosition = contact + flight
        } else if s.stage == .flight || s.stage == .resolving {
            ball.simdPosition = s.ballT < 0
                ? alice.handR.simdWorldPosition
                : ballPath(s.ballT)
        } else {
            ball.simdPosition = alice.handR.simdWorldPosition
        }

        // Бэттер.
        let swinging = s.impact > 0.25 || (s.stage == .resolving && s.quality == .missed && s.ballT < BaseballScene.strikeHigh)
        if swinging && !swingLatch {
            shake = max(shake, 0.35)
            SoundFX.shared.play(s.quality == .missed ? .whiff : .batCrack, volume: s.quality == .noisy ? 1 : 0.6)
        }
        swingLatch = swinging
        edward.target = swinging ? .batFollow : .batReady
        edward.rate = swinging ? 24 : 5
        edward.lookAt = ball.simdPosition

        let inZone = s.ballT >= BaseballScene.strikeLow && s.ballT <= BaseballScene.strikeHigh && s.stage == .flight
        strikeZone.opacity = inZone ? 1 : 0.45

        // Кочевники подходят ближе с каждым громким ударом.
        let nomadZ = -105 + Float(s.noise) * 16
        for (i, n) in nomads.enumerated() {
            let target = V3(Float(i - 1) * 2.4, 0, nomadZ)
            n.position = dampv(n.position, target, 1.2, dt)
            n.opacity = damp(n.opacity, s.noise > 0 ? 1 : 0, 2, dt)
            n.lookAt = edward.head.simdWorldPosition
        }
        bella.lookAt = ball.simdPosition
        esme.lookAt = ball.simdPosition
        emmett.lookAt = ball.simdPosition

        followCamera(eye: V3(0.7, 1.9, 4.6), target: V3(0, 1.2, -12), fov: 54, rate: 2, dt: max(dt, 0.016))
    }

    override func enterIdle() {
        enterGameplay()
        strikeZone.isHidden = true
    }

    override func updateIdle(dt: Float) {
        if Int(time * 10) % 70 == 0 && flash < 0.05 { strike() }
        let a = time * 0.04
        placeCamera(eye: V3(0, 0, -16) + rotateY(V3(26, 11, 30), a), target: V3(0, 1, -16), fov: 56)
    }

    // MARK: - Кат-сцены

    override func beginShot(_ cue: Cue) {
        enterGameplay()
        strikeZone.isHidden = true
        ball.isHidden = true
        switch cue {
        case .stormSky:
            strike()
        case .alicePitch:
            alice.target = .pitchWindup
        case .nomadsTree:
            for (i, n) in nomads.enumerated() {
                n.place(V3(Float(i - 1) * 3, 0, -92), yaw: 0)
                n.opacity = 0.9
            }
        case .nomadsArrive, .jamesSniffs, .edwardShields:
            for h in [edward, alice, emmett, rosalie, jasper, carlisle, esme] {
                h.snap(.stand)
            }
            edward.place(V3(0.6, 0, -5.5), yaw: Float.pi)
            alice.place(V3(-1.6, 0, -6.2), yaw: Float.pi - 0.2)
            emmett.place(V3(2.4, 0, -6.4), yaw: Float.pi + 0.2)
            rosalie.place(V3(3.6, 0, -5.8), yaw: Float.pi + 0.3)
            jasper.place(V3(-2.8, 0, -6.0), yaw: Float.pi - 0.3)
            carlisle.place(V3(-0.6, 0, -7.0), yaw: Float.pi)
            esme.place(V3(-1.9, 0, -4.4), yaw: Float.pi)
            bella.place(V3(0.9, 0, -3.4), yaw: Float.pi)
            bella.snap(.stand)
            for (i, n) in nomads.enumerated() {
                n.place(V3(Float(i - 1) * 2.2, 0, cue == .nomadsArrive ? -38 : -16.5), yaw: 0)
                n.opacity = 1
                n.snap(.stand)
            }
            for h in [edward, alice, emmett, rosalie, jasper, carlisle, esme, bella] {
                h.lookAt = james.head.simdWorldPosition
            }
            if cue == .edwardShields {
                edward.place(V3(0.85, 0, -4.6), yaw: Float.pi)
                edward.target = .crouchDefend
                edward.rate = 9
            }
        default:
            break
        }
    }

    override func updateShot(_ cue: Cue, progress p: Float, dt: Float) {
        switch cue {
        case .stormSky:
            if p > 0.55 && p < 0.57 { strike() }
            dolly(p, eye: (V3(0, 1.5, 12), V3(0, 2.2, 10)), look: (V3(0, 40, -80), V3(0, 4, -30)), fov: (66, 58))
        case .cullensField:
            if p > 0.3 && p < 0.32 { strike() }
            dolly(p, eye: (V3(30, 20, 26), V3(15, 8, 16)), look: (V3(0, 0, -20), V3(0, 1, -14)), fov: (58, 52))
        case .alicePitch:
            let head = alice.head.simdWorldPosition
            alice.target = p < 0.7 ? .pitchWindup : .pitchRelease
            alice.rate = p < 0.7 ? 3 : 14
            dolly(p, eye: (V3(2.6, 1.7, -14.8), V3(1.6, 1.75, -15.6)), look: (head, head), fov: (34, 28))
        case .nomadsTree:
            for n in nomads { n.position.z += dt * 0.6 }
            dolly(p, eye: (V3(0.4, 1.7, -6), V3(0.4, 1.7, -16)), look: (V3(0, 1.6, -92), V3(0, 1.6, -92)), fov: (40, 22))
        case .nomadsArrive:
            walkTowards(p: p, dt: dt, from: -38, to: -18)
            dolly(p, eye: (V3(3.2, 1.4, -4), V3(2.6, 1.5, -5)), look: (V3(0, 1.6, -36), V3(0, 1.6, -18)), fov: (44, 40))
        case .jamesSniffs:
            let head = james.head.simdWorldPosition
            james.lookAt = bella.head.simdWorldPosition
            dolly(p, eye: (V3(-0.6, 1.75, -13.6), V3(-0.4, 1.75, -14.3)), look: (head, head), fov: (30, 24))
        case .edwardShields:
            james.lookAt = bella.head.simdWorldPosition
            let mid = edward.head.simdWorldPosition
            dolly(p, eye: (V3(1.6, 1.55, -1.2), V3(1.3, 1.3, -2.0)), look: (mid, mid + V3(0, 0.1, -3)), fov: (44, 36))
        default:
            break
        }
    }

    private func walkTowards(p: Float, dt: Float, from: Float, to: Float) {
        let z = lerpf(from, to, easeSoft(p))
        for (i, n) in nomads.enumerated() {
            n.position = V3(Float(i - 1) * 2.2, 0, z - Float(abs(i - 1)) * 0.6)
            n.target = Pose.walk(time * 5 + Float(i), stride: p < 0.95 ? 0.8 : 0)
            n.rate = 16
        }
    }
}

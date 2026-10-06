import SceneKit
import UIKit
import simd

/// Глава 8. Ночной Порт-Анджелес: мокрая улица, неон, фонари — Белла бежит от преследователей.
final class StreetStage: RunnerStageBase {

    private let bella = Humanoid(Cast.bella)
    private let edward = Humanoid(Cast.edward)
    private let volvo = Vehicle.sedan(color: UIColor(hex: 0xB9BEC4), metallic: 0.85)
    private var followers: [Humanoid] = []
    private var thugs: [ObjectIdentifier: Humanoid] = [:]
    private var key = SCNNode()
    private var runPhase: Float = 0

    init() {
        super.init(xScale: 3.3, segmentLength: 80)
        let root = scene.rootNode

        setSky(Textures.SkyStyle(
            zenith: SIMD3(0.01, 0.015, 0.035), horizon: SIMD3(0.07, 0.07, 0.11), ground: SIMD3(0.02, 0.02, 0.03),
            cloudCover: 0.6, cloudLight: SIMD3(0.12, 0.12, 0.16), cloudDark: SIMD3(0.03, 0.03, 0.05),
            sunAzimuth: 2.6, sunElevation: 0.6, sunColor: SIMD3(0.7, 0.75, 0.9), sunGlow: 0.3,
            sunDisc: true, stars: true, seed: 61), lighting: 0.5)
        setFog(color: UIColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 1), start: 15, end: 140, exponent: 1.3)
        key = addKeyLight(color: UIColor(red: 0.55, green: 0.62, blue: 0.85, alpha: 1), intensity: 90,
                          azimuth: 2.6, elevation: 0.9, shadowExtent: 30, softness: 8)
        addAmbient(color: UIColor(red: 0.18, green: 0.2, blue: 0.3, alpha: 1), intensity: 45)

        installSegments(count: 4)
        prewarm(variants: [0, 1, 2], count: 6)
        useRunnerQuality(key: key)

        root.addChildNode(bella.node)
        bella.node.setCastsShadow(true)
        root.addChildNode(edward.node)
        edward.node.setCastsShadow(true)
        edward.isHidden = true
        root.addChildNode(volvo.node)
        volvo.node.isHidden = true

        for look in [Cast.thugA, Cast.thugB, Cast.thugA, Cast.thugB] {
            let h = Humanoid(look)
            root.addChildNode(h.node)
            h.node.setCastsShadow(true)
            h.isHidden = true
            followers.append(h)
        }

        cameraSettings.bloomIntensity = 1.0
        cameraSettings.bloomThreshold = 0.65
        cameraSettings.exposureOffset = 0.8
        cameraSettings.saturation = 1.05
        placeCamera(eye: V3(0, 2, 4.6), target: V3(0, 1.2, -8), fov: 62)
    }

    // MARK: - Декорации

    override func makeSegment(_ index: Int) -> SCNNode {
        let seg = SCNNode()
        let L = segmentLength
        var rng = SeededRandom(seed: UInt64(1200 + index))

        // Мокрый асфальт и тротуары.
        let road = SCNNode(SCNPlane(width: 14, height: CGFloat(L)), Materials.asphalt(tile: 6))
        road.eulerAngles.x = -Float.pi / 2
        road.simdPosition = V3(0, 0, -L / 2)
        road.geometry?.firstMaterial?.roughness.contents = Textures.asphaltRoughness
        seg.addChildNode(road)
        let concrete = Materials.pbr(UIColor(white: 0.42, alpha: 1), roughness: 0.75, normal: Textures.asphaltNormal,
                                     normalIntensity: 0.4, tile: 4)
        for side: Float in [-1, 1] {
            let walk = SCNNode(SCNBox(width: 3.4, height: 0.16, length: CGFloat(L), chamferRadius: 0.02), concrete)
            walk.simdPosition = V3(side * 8.7, 0.08, -L / 2)
            seg.addChildNode(walk)
        }
        // Разметка.
        let paint = Materials.pbr(UIColor(white: 0.8, alpha: 1), roughness: 0.4)
        var z: Float = -2
        while z > -L {
            let dash = SCNNode(SCNPlane(width: 0.15, height: 3), paint)
            dash.eulerAngles.x = -Float.pi / 2
            dash.simdPosition = V3(0, 0.005, z)
            dash.castsShadow = false
            seg.addChildNode(dash)
            z -= 8
        }

        // Здания: кирпич и штукатурка, окна, вывески.
        let facades = [Materials.brick(tile: 6),
                       Materials.pbr(UIColor(hex: 0x6A6258), roughness: 0.85, normal: Textures.groundNormal,
                                     normalIntensity: 0.3, tile: 4),
                       Materials.pbr(UIColor(hex: 0x4A4E56), roughness: 0.8, normal: Textures.groundNormal,
                                     normalIntensity: 0.3, tile: 4)]
        let windows = Materials.pbr(UIColor(white: 0.03, alpha: 1), roughness: 0.05, metalness: 0.3)
        windows.emission.contents = Textures.windowsLit
        windows.emission.intensity = 1.3
        windows.emission.wrapS = .repeat
        windows.emission.wrapT = .repeat
        let signs = ["BOOKS", "DINER", "MOTEL", "OPEN 24", "BAR", "PAWN", "CINEMA", "LAUNDRY"]
        let neon: [UIColor] = [UIColor(red: 1, green: 0.25, blue: 0.4, alpha: 1), UIColor(red: 0.3, green: 0.8, blue: 1, alpha: 1),
                               UIColor(red: 1, green: 0.7, blue: 0.25, alpha: 1), UIColor(red: 0.6, green: 1, blue: 0.4, alpha: 1)]
        for side: Float in [-1, 1] {
            var zz: Float = 0
            while zz > -L {
                let depth = rng.range(13, 20)
                let height = rng.range(6, 17)
                let width: Float = 12
                let block = SCNNode(SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(depth - 0.4),
                                           chamferRadius: 0.05),
                                    facades[Int(rng.unit() * 3) % 3])
                block.simdPosition = V3(side * (10.4 + width / 2), height / 2, zz - depth / 2)
                seg.addChildNode(block)
                // Окна верхних этажей.
                if height > 7 {
                    let w = SCNNode(SCNPlane(width: CGFloat(depth - 2), height: CGFloat(height - 5)), windows)
                    w.simdPosition = V3(side * 10.38, 4 + (height - 5) / 2, zz - depth / 2)
                    w.eulerAngles.y = -side * Float.pi / 2
                    seg.addChildNode(w)
                }
                // Витрина первого этажа и неоновая вывеска.
                if rng.unit() > 0.35 {
                    let color = neon[Int(rng.unit() * Float(neon.count)) % neon.count]
                    let text = SCNText(string: signs[Int(rng.unit() * Float(signs.count)) % signs.count], extrusionDepth: 0.04)
                    text.font = UIFont.systemFont(ofSize: 0.9, weight: .bold)
                    text.flatness = 0.01
                    text.materials = [Materials.glow(color, intensity: 3.2, doubleSided: false)]
                    let t = SCNNode(geometry: text)
                    let (mn, mx) = t.boundingBox
                    t.pivot = SCNMatrix4MakeTranslation((mx.x - mn.x) / 2 + mn.x, 0, 0)
                    t.simdPosition = V3(side * 10.3, 3.2, zz - depth / 2)
                    t.eulerAngles.y = -side * Float.pi / 2
                    seg.addChildNode(t)
                    let shop = SCNNode(SCNPlane(width: CGFloat(depth - 3), height: 2.4),
                                       Materials.glow(color.withAlphaComponent(1), intensity: 0.25, doubleSided: false))
                    shop.simdPosition = V3(side * 10.37, 1.4, zz - depth / 2)
                    shop.eulerAngles.y = -side * Float.pi / 2
                    seg.addChildNode(shop)
                }
                zz -= depth
            }
        }

        // Фонари.
        let pole = Materials.pbr(UIColor(white: 0.2, alpha: 1), roughness: 0.4, metalness: 0.8)
        for (side, lz) in [(index % 2 == 0 ? Float(-1) : Float(1), Float(-40))] {
            let base = V3(side * 7.6, 0, lz)
            let post = SCNNode(SCNCylinder(radius: 0.08, height: 6), pole)
            post.simdPosition = base + V3(0, 3, 0)
            seg.addChildNode(post)
            let head = SCNNode(SCNSphere(radius: 0.22),
                               Materials.glow(UIColor(red: 1, green: 0.78, blue: 0.5, alpha: 1), intensity: 3, doubleSided: false))
            head.simdPosition = base + V3(-side * 0.4, 6, 0)
            seg.addChildNode(head)
            let lamp = Stage3D.spotLight(color: UIColor(red: 1, green: 0.75, blue: 0.45, alpha: 1), intensity: 5000,
                                         angle: 95, range: 20)
            lamp.simdPosition = base + V3(-side * 0.4, 5.9, 0)
            lamp.simdLook(at: base + V3(-side * 2.5, 0, 0))
            seg.addChildNode(lamp)
        }

        // Лужи — тёмные зеркальные пятна.
        let puddle = Materials.pbr(UIColor(white: 0.02, alpha: 1), roughness: 0.02, metalness: 0.6)
        for _ in 0..<5 {
            let p = SCNNode(SCNSphere(radius: 1), puddle)
            p.simdScale = V3(rng.range(0.8, 2.2), 0.01, rng.range(0.8, 2.6))
            p.simdPosition = V3(rng.range(-6, 6), 0.004, -rng.range(4, L - 4))
            p.castsShadow = false
            seg.addChildNode(p)
        }

        // Пар из люка.
        let steam = SCNParticleSystem()
        steam.birthRate = 6
        steam.particleLifeSpan = 4
        steam.particleVelocity = 0.6
        steam.emittingDirection = SCNVector3(0, 1, 0)
        steam.spreadingAngle = 15
        steam.particleSize = 1.2
        steam.particleSizeVariation = 0.5
        steam.particleImage = Textures.smoke
        steam.particleColor = UIColor(white: 0.8, alpha: 0.12)
        steam.isLocal = false
        let vent = SCNNode()
        vent.simdPosition = V3(rng.range(-4, 4), 0.1, -rng.range(10, L - 10))
        vent.addParticleSystem(steam)
        seg.addChildNode(vent)

        // Машины у обочины.
        for _ in 0..<2 {
            let car = Vehicle.sedan(color: [UIColor(hex: 0x3A2E2A), UIColor(hex: 0x24303A), UIColor(hex: 0x5A5A52)][Int(rng.unit() * 3) % 3],
                                    metallic: 0.4)
            car.node.simdPosition = V3((rng.unit() > 0.5 ? 1 : -1) * 5.6, 0, -rng.range(8, L - 8))
            seg.addChildNode(car.node)
        }
        return seg
    }

    private var thugToggle = false

    /// 0 — незнакомец (обойти), 1 — мусорный бак (перепрыгнуть), 2 — леса с вывеской (подкат).
    override func makeObstacle(_ variant: Int) -> SCNNode {
        switch variant {
        case 0:
            thugToggle.toggle()
            let h = Humanoid(thugToggle ? Cast.thugA : Cast.thugB)
            h.node.setCastsShadow(true)
            h.snap(.handsInPockets)
            thugs[ObjectIdentifier(h.node)] = h
            return h.node
        case 2:
            let n = SCNNode()
            let steel = Materials.pbr(UIColor(white: 0.35, alpha: 1), roughness: 0.4, metalness: 0.8)
            for x: Float in [-1.2, 1.2] {
                let post = SCNNode(SCNCylinder(radius: 0.05, height: 1.5), steel)
                post.simdPosition = V3(x, 0.75, 0)
                n.addChildNode(post)
            }
            let board = SCNNode(SCNBox(width: 2.6, height: 0.5, length: 0.08, chamferRadius: 0.02),
                                Materials.pbr(UIColor(red: 0.85, green: 0.6, blue: 0.1, alpha: 1), roughness: 0.5))
            board.simdPosition = V3(0, 1.45, 0)
            n.addChildNode(board)
            let text = SCNText(string: "ОСТОРОЖНО", extrusionDepth: 0.01)
            text.font = UIFont.systemFont(ofSize: 0.22, weight: .heavy)
            text.materials = [Materials.pbr(UIColor(white: 0.05, alpha: 1), roughness: 0.5)]
            let t = SCNNode(geometry: text)
            let (mn, mx) = t.boundingBox
            t.pivot = SCNMatrix4MakeTranslation((mx.x - mn.x) / 2 + mn.x, (mx.y - mn.y) / 2 + mn.y, 0)
            t.simdPosition = V3(0, 1.45, 0.05)
            n.addChildNode(t)
            return n
        default:
            let n = SCNNode()
            let bin = SCNNode(SCNCylinder(radius: 0.38, height: 0.9),
                              Materials.pbr(UIColor(hex: 0x2C3A2C), roughness: 0.5, metalness: 0.5))
            bin.simdPosition = V3(0, 0.45, 0)
            n.addChildNode(bin)
            let lid = SCNNode(SCNCylinder(radius: 0.42, height: 0.06),
                              Materials.pbr(UIColor(hex: 0x223022), roughness: 0.5, metalness: 0.5))
            lid.simdPosition = V3(0, 0.93, 0)
            n.addChildNode(lid)
            return n
        }
    }

    override func animateObstacle(_ node: SCNNode, variant: Int, relativeZ: Float) {
        guard let h = thugs[ObjectIdentifier(node)] else { return }
        h.yaw = 0
        h.lookAt = bella.head.simdWorldPosition
        // Преследователь делает шаг навстречу, когда Белла близко.
        h.target = relativeZ < 8 ? .flinch : .handsInPockets
        h.rate = 5
    }

    // MARK: - Общее

    override var ambience: [SoundFX.Ambience: Float] { [.rain: 0.25, .wind: 0.3, .hum: 0.06] }

    override func updateAmbient(dt: Float) {
        bella.update(dt: dt, time: time)
        edward.update(dt: dt, time: time)
        for h in followers where !h.isHidden { h.update(dt: dt, time: time) }
        for h in thugs.values where !h.node.isHidden { h.update(dt: dt, time: time) }
        updateTreadmill()
        key.simdPosition = V3(playerX, 0, playerZ) + simd_normalize(V3(0.5, 1.4, -0.8)) * 120
    }

    private func runBella(_ dt: Float, speed: Float) {
        runPhase += dt * min(14, 4 + speed * 0.9)
        bella.target = Pose.run(runPhase)
        bella.rate = 20
    }

    // MARK: - Игра

    override func enterGameplay() {
        playerZ = 0
        playerX = 0
        resetSegments()
        bella.place(.zero, yaw: Float.pi)
        bella.lookAt = nil
        edward.isHidden = true
        volvo.node.isHidden = true
        for h in followers { h.isHidden = true }
    }

    override func updateGameplay(_ engine: GameEngine, dt: Float) {
        let s = engine.portAngeles
        playerZ = -Float(s.distance)
        playerX = Float(s.playerX) * xScale
        bella.place(V3(playerX, Float(s.jumpHeight) * 1.3, playerZ), yaw: Float.pi)
        if dt > 0 { runBella(dt, speed: Float(s.speed)) }
        if s.isJumping {
            bella.target = .jump
            bella.rate = 18
        } else if s.isSliding {
            bella.target = .slide
            bella.rate = 18
        }
        if s.stumble > 0.9 { shake = 0.6 }
        layoutObstacles(s)
        runnerCamera(dt: dt, height: 3.2, back: 6.4)
    }

    override func enterIdle() {
        enterGameplay()
        hideObstacles()
    }

    override func updateIdle(dt: Float) {
        playerZ -= dt * 1.4
        bella.place(V3(0, 0, playerZ), yaw: Float.pi)
        bella.target = Pose.walk(time * 5)
        bella.rate = 16
        let p = V3(0, 0, playerZ)
        placeCamera(eye: p + V3(3, 1.6, -4), target: p + V3(0, 1.3, 0), fov: 48)
    }

    // MARK: - Кат-сцены

    override func beginShot(_ cue: Cue) {
        hideObstacles()
        playerX = 0
        switch cue {
        case .streetEstablish, .streetBellaLost:
            playerZ = 0
            resetSegments()
            for h in followers { h.isHidden = true }
            edward.isHidden = true
            volvo.node.isHidden = true
        case .streetFootsteps:
            for (i, h) in followers.enumerated() {
                h.isHidden = false
                h.place(V3(Float(i) * 1.1 - 1.6, 0, playerZ + 9 + Float(i % 2) * 1.5), yaw: Float.pi)
            }
        case .streetHeadlights:
            playerZ = -40
            for (i, h) in followers.enumerated() {
                h.isHidden = false
                h.place(V3(Float(i) * 1.1 - 1.6, 0, playerZ + 4 + Float(i % 2)), yaw: Float.pi)
                h.snap(.stand)
            }
            volvo.node.isHidden = false
            volvo.setHeadlights(1)
            SoundFX.shared.play(.skid, volume: 0.8, delay: 1.2)
            bella.place(V3(0, 0, playerZ), yaw: 0)
            bella.snap(.flinch)
        case .streetGetIn:
            volvo.node.isHidden = false
            volvo.node.simdPosition = V3(-1.5, 0, playerZ - 3)
            volvo.node.simdEulerAngles = V3(0, Float.pi / 2, 0)
            edward.isHidden = false
            edward.place(V3(-1.2, 0, playerZ - 1.6), yaw: 0.3)
            edward.snap(.stand)
            bella.place(V3(0.2, 0, playerZ), yaw: Float.pi - 0.4)
            bella.snap(.stand)
            edward.lookAt = bella.head.simdWorldPosition
            bella.lookAt = edward.head.simdWorldPosition
            for (i, h) in followers.enumerated() {
                h.place(V3(Float(i) * 1.3 - 2, 0, playerZ + 8), yaw: 0)
                h.snap(.flinch)
            }
        default:
            break
        }
    }

    override func updateShot(_ cue: Cue, progress p: Float, dt: Float) {
        switch cue {
        case .streetEstablish:
            playerZ -= dt * 1.3
            bella.place(V3(0, 0, playerZ), yaw: Float.pi)
            bella.target = Pose.walk(time * 5)
            bella.rate = 16
            dolly(p, eye: (V3(-4, 14, -60), V3(-3, 4, -14)), look: (V3(0, 2, 0), V3(0, 1.4, playerZ)), fov: (55, 48))
        case .streetBellaLost:
            bella.target = .handsInPockets
            bella.lookAt = bella.head.simdWorldPosition + V3(sin(time * 0.8) * 3, 0.3, -2)
            let c = bella.head.simdWorldPosition
            dolly(p, eye: (c + V3(1.3, -0.1, -1.6), c + V3(0.9, -0.05, -1.2)), look: (c, c), fov: (40, 32))
        case .streetFootsteps:
            for (i, h) in followers.enumerated() {
                h.position.z -= dt * 1.2
                h.target = Pose.walk(time * 4.6 + Float(i))
                h.rate = 14
                h.lookAt = bella.head.simdWorldPosition
            }
            bella.target = Pose.walk(time * 6)
            playerZ -= dt * 1.6
            bella.place(V3(0, 0, playerZ), yaw: Float.pi)
            let c = V3(0, 0.6, playerZ + 6)
            placeCamera(eye: c + V3(0.6, 0, -4), target: c + V3(0, 0.7, 4), fov: 50)
        case .streetHeadlights:
            let t = easeSoft(p)
            volvo.node.simdPosition = V3(lerpf(-26, -1.5, t), 0, playerZ - 3)
            volvo.node.simdEulerAngles = V3(0, Float.pi / 2 - (1 - t) * 0.5, 0)
            volvo.roll(distance: dt * 20 * (1 - t))
            if p > 0.7 { shake = max(shake, 0.2) }
            bella.lookAt = volvo.node.simdPosition + V3(0, 1, 0)
            dolly(p, eye: (V3(4, 1.5, playerZ + 3), V3(3, 1.4, playerZ + 2.5)),
                  look: (V3(-10, 1, playerZ - 3), V3(-1, 1.1, playerZ - 2)), fov: (55, 45))
        case .streetGetIn:
            let c = (edward.head.simdWorldPosition + bella.head.simdWorldPosition) * 0.5
            placeCamera(eye: c + rotateY(V3(1.6, 0.0, 1.8), p * 0.3), target: c, fov: 38)
        default:
            break
        }
    }
}

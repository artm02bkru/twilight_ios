import SceneKit
import UIKit
import simd

/// Глава 18. Ночное шоссе на юг: машина Элис уходит от фар Джеймса сквозь дождь.
final class ChaseStage: RunnerStageBase {

    private let car = Vehicle.sedan(color: UIColor(hex: 0x0C0D10), metallic: 0.7)
    private let hunter = Vehicle.sedan(color: UIColor(hex: 0x1A1612), metallic: 0.5)
    private var key = SCNNode()
    private let rainNode = SCNNode()
    private var hazards: [SCNMaterial] = []
    private var nightSky: UIImage
    private var dawnSky: UIImage
    private var hunterDistance: Float = 30

    init() {
        let night = Textures.SkyStyle(
            zenith: SIMD3(0.015, 0.02, 0.04), horizon: SIMD3(0.07, 0.08, 0.11), ground: SIMD3(0.02, 0.02, 0.03),
            cloudCover: 0.9, cloudLight: SIMD3(0.12, 0.13, 0.17), cloudDark: SIMD3(0.03, 0.03, 0.05),
            sunAzimuth: 2.0, sunElevation: 0.5, sunColor: SIMD3(0.6, 0.65, 0.85), sunGlow: 0.25,
            sunDisc: false, seed: 71)
        let dawn = Textures.SkyStyle(
            zenith: SIMD3(0.18, 0.24, 0.42), horizon: SIMD3(1.0, 0.62, 0.38), ground: SIMD3(0.18, 0.14, 0.12),
            cloudCover: 0.35, cloudLight: SIMD3(1, 0.7, 0.5), cloudDark: SIMD3(0.35, 0.25, 0.3),
            sunAzimuth: 3.1, sunElevation: 0.04, sunColor: SIMD3(1, 0.6, 0.3), sunGlow: 1.2,
            sunDisc: true, seed: 72)
        nightSky = Textures.sky(night)
        dawnSky = Textures.sky(dawn)
        super.init(xScale: 4.4, segmentLength: 150)
        let root = scene.rootNode

        scene.background.contents = nightSky
        scene.lightingEnvironment.contents = nightSky
        scene.lightingEnvironment.intensity = 0.55
        setFog(color: UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1), start: 20, end: 220, exponent: 1.3)
        key = addKeyLight(color: UIColor(red: 0.55, green: 0.62, blue: 0.85, alpha: 1), intensity: 110,
                          azimuth: 2.0, elevation: 0.8, shadowExtent: 40, softness: 8)
        addAmbient(color: UIColor(red: 0.2, green: 0.22, blue: 0.3, alpha: 1), intensity: 40)

        installSegments(count: 4)
        prewarm(variants: [0, 1, 2], count: 4)
        useRunnerQuality(key: key)

        root.addChildNode(car.node)
        car.setHeadlights(1)
        if let lamp = car.headlights.first?.light {
            lamp.castsShadow = true
            lamp.shadowMode = .deferred
            lamp.shadowSampleCount = 4
        }
        root.addChildNode(hunter.node)
        hunter.setHeadlights(1)

        rainNode.addParticleSystem(RoadBuild.rain(intensity: 1500))
        root.addChildNode(rainNode)

        cameraSettings.bloomIntensity = 1.0
        cameraSettings.bloomThreshold = 0.6
        cameraSettings.exposureOffset = 0.7
        placeCamera(eye: V3(0, 2.3, 6.8), target: V3(0, 0.8, -12), fov: 62)
    }

    // MARK: - Декорации

    override func makeSegment(_ index: Int) -> SCNNode {
        let seg = SCNNode()
        let L = segmentLength
        var rng = SeededRandom(seed: UInt64(1500 + index))

        let road = SCNNode(SCNPlane(width: 11, height: CGFloat(L)), Materials.asphalt(tile: 8))
        road.eulerAngles.x = -Float.pi / 2
        road.simdPosition = V3(0, 0.01, -L / 2)
        seg.addChildNode(road)
        let shoulder = SCNNode(SCNPlane(width: 120, height: CGFloat(L)), Materials.dirt(tile: 30))
        shoulder.eulerAngles.x = -Float.pi / 2
        shoulder.simdPosition = V3(0, 0, -L / 2)
        shoulder.castsShadow = false
        seg.addChildNode(shoulder)

        // Разметка: прерывистые между полосами, сплошные по краям.
        let white = Materials.pbr(UIColor(white: 0.85, alpha: 1), roughness: 0.45)
        for x: Float in [-1.2, 1.2] {
            var z: Float = -1
            while z > -L {
                let dash = SCNNode(SCNPlane(width: 0.14, height: 3), white)
                dash.eulerAngles.x = -Float.pi / 2
                dash.simdPosition = V3(x * 2, 0.015, z)
                dash.castsShadow = false
                seg.addChildNode(dash)
                z -= 9
            }
        }
        for x: Float in [-5.2, 5.2] {
            let edge = SCNNode(SCNPlane(width: 0.16, height: CGFloat(L)), white)
            edge.eulerAngles.x = -Float.pi / 2
            edge.simdPosition = V3(x, 0.015, -L / 2)
            edge.castsShadow = false
            seg.addChildNode(edge)
        }

        // Отбойники и столбики со светоотражателями.
        let steel = Materials.pbr(UIColor(white: 0.6, alpha: 1), roughness: 0.3, metalness: 0.9)
        let reflector = Materials.glow(UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1), intensity: 1.5, doubleSided: false)
        for side: Float in [-1, 1] {
            let rail = SCNNode(SCNBox(width: 0.08, height: 0.32, length: CGFloat(L), chamferRadius: 0.02), steel)
            rail.simdPosition = V3(side * 6.2, 0.62, -L / 2)
            seg.addChildNode(rail)
            var z: Float = -3
            while z > -L {
                let post = SCNNode(SCNBox(width: 0.1, height: 0.75, length: 0.1, chamferRadius: 0.01), steel)
                post.simdPosition = V3(side * 6.3, 0.37, z)
                seg.addChildNode(post)
                let r = SCNNode(SCNBox(width: 0.04, height: 0.08, length: 0.12, chamferRadius: 0.01), reflector)
                r.simdPosition = V3(side * 6.15, 0.66, z)
                seg.addChildNode(r)
                z -= 12
            }
        }

        // Лес вдоль шоссе.
        let b = MeshBuilder()
        for _ in 0..<80 {
            let side: Float = rng.unit() > 0.5 ? 1 : -1
            let x = side * rng.range(9, 60)
            Nature.addSpruce(to: b, at: V3(x, 0, -rng.range(0, L)),
                             height: rng.range(16, 32), rng: &rng, tiers: abs(x) < 20 ? 10 : 7)
        }
        let forest = SCNNode(geometry: b.geometry(name: "highway-forest"))
        let m = Materials.matte(roughness: 0.9)
        m.isDoubleSided = true
        forest.geometry?.materials = [m]
        forest.castsShadow = false
        seg.addChildNode(forest)

        // Дорожный знак.
        if index % 2 == 0 {
            let signPost = SCNNode(SCNCylinder(radius: 0.06, height: 3), steel)
            signPost.simdPosition = V3(7, 1.5, -L * 0.4)
            seg.addChildNode(signPost)
            let plate = SCNNode(SCNBox(width: 2.2, height: 1.2, length: 0.04, chamferRadius: 0.03),
                                Materials.pbr(UIColor(hex: 0x1E5E34), roughness: 0.4))
            plate.simdPosition = V3(7, 3.4, -L * 0.4)
            seg.addChildNode(plate)
            let text = SCNText(string: index == 0 ? "PHOENIX 1240" : "SOUTH  US-101", extrusionDepth: 0.01)
            text.font = UIFont.systemFont(ofSize: 0.28, weight: .bold)
            text.materials = [Materials.glow(UIColor(white: 0.95, alpha: 1), intensity: 0.8, doubleSided: false)]
            let t = SCNNode(geometry: text)
            let (mn, mx) = t.boundingBox
            t.pivot = SCNMatrix4MakeTranslation((mx.x - mn.x) / 2 + mn.x, (mx.y - mn.y) / 2 + mn.y, 0)
            t.simdPosition = V3(7, 3.4, -L * 0.4 + 0.03)
            seg.addChildNode(t)
        }
        return seg
    }

    override func makeObstacle(_ variant: Int) -> SCNNode {
        switch variant {
        case 0:
            // Заглохшая машина с аварийкой.
            let stalled = Vehicle.sedan(color: [UIColor(hex: 0x6A2A22), UIColor(hex: 0x8A8A80), UIColor(hex: 0x2A3A4A)].randomElement()!,
                                        metallic: 0.4)
            stalled.node.simdEulerAngles.y = Float.pi + Float.random(in: -0.15...0.15)
            let hazard = Materials.glow(UIColor(red: 1, green: 0.6, blue: 0.1, alpha: 1), intensity: 3, doubleSided: false)
            hazards.append(hazard)
            for x: Float in [-0.7, 0.7] {
                for z: Float in [-2.25, 2.25] {
                    let lamp = SCNNode(SCNSphere(radius: 0.07), hazard)
                    lamp.simdPosition = V3(x, 0.8, z)
                    stalled.node.addChildNode(lamp)
                }
            }
            return stalled.node
        case 1:
            // Поваленное дерево.
            let n = SCNNode()
            let log = SCNNode(SCNCylinder(radius: 0.38, height: 5.5), Materials.bark())
            log.eulerAngles.z = Float.pi / 2
            log.eulerAngles.y = 0.25
            log.simdPosition = V3(0, 0.38, 0)
            n.addChildNode(log)
            return n
        default:
            // Дорожный барьер с мигалкой.
            let n = SCNNode()
            let stripes = Materials.pbr(UIColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1), roughness: 0.4)
            let bar = SCNNode(SCNBox(width: 2.6, height: 0.35, length: 0.12, chamferRadius: 0.02), stripes)
            bar.simdPosition = V3(0, 0.9, 0)
            n.addChildNode(bar)
            for x: Float in [-1.1, 1.1] {
                let leg = SCNNode(SCNBox(width: 0.1, height: 1, length: 0.5, chamferRadius: 0.01),
                                  Materials.pbr(UIColor(white: 0.8, alpha: 1), roughness: 0.5))
                leg.simdPosition = V3(x, 0.5, 0)
                n.addChildNode(leg)
            }
            let hazard = Materials.glow(UIColor(red: 1, green: 0.55, blue: 0.1, alpha: 1), intensity: 3, doubleSided: false)
            hazards.append(hazard)
            let lamp = SCNNode(SCNSphere(radius: 0.1), hazard)
            lamp.simdPosition = V3(0, 1.2, 0)
            n.addChildNode(lamp)
            return n
        }
    }

    // MARK: - Общее

    override var ambience: [SoundFX.Ambience: Float] { [.heavyRain: 0.55, .engine: 0.5, .wind: 0.3] }

    override func updateAmbient(dt: Float) {
        updateTreadmill()
        rainNode.simdPosition = camera.simdPosition + V3(0, 18, -14)
        key.simdPosition = car.node.simdPosition + simd_normalize(V3(0.6, 1.3, -0.6)) * 120
        let blink: CGFloat = sin(time * 6) > 0 ? 3 : 0.1
        for h in hazards { h.emission.intensity = blink }
    }

    private func placeCar(x: Float, z: Float, steer: Float, speed: Float, dt: Float) {
        car.node.simdPosition = V3(x, 0, z)
        car.node.simdEulerAngles = V3(0, Float.pi - steer, -steer * 0.15)
        car.roll(distance: speed * dt)
        hunter.node.simdPosition = V3(x * 0.6, 0, z + hunterDistance)
        hunter.node.simdEulerAngles = V3(0, Float.pi, 0)
        hunter.roll(distance: speed * dt)
    }

    // MARK: - Игра

    override func enterGameplay() {
        playerZ = 0
        playerX = 0
        resetSegments()
        scene.background.contents = nightSky
        scene.lightingEnvironment.contents = nightSky
        hunterDistance = 30
        key.light?.color = UIColor(red: 0.55, green: 0.62, blue: 0.85, alpha: 1)
        key.light?.intensity = 110
    }

    override func updateGameplay(_ engine: GameEngine, dt: Float) {
        let s = engine.chase
        let newX = Float(s.playerX) * xScale
        let steer = dt > 0 ? clampf((newX - playerX) / max(dt, 0.001) * 0.06, -0.35, 0.35) : 0
        playerX = newX
        playerZ = -Float(s.distance)
        hunterDistance = damp(hunterDistance, lerpf(34, 4.5, Float(s.danger)), 2, max(dt, 0.001))
        placeCar(x: playerX, z: playerZ, steer: steer, speed: Float(s.speed), dt: dt)
        if s.stumble > 0.9 { shake = 1 }
        layoutObstacles(s)

        let p = V3(playerX, 0, playerZ)
        followCamera(eye: p + V3(-playerX * 0.3, 2.4, 7.2), target: p + V3(playerX * 0.15, 0.8, -12),
                     fov: 60 + Float(s.speed) * 0.12, rate: 5, dt: max(dt, 0.016))
        cameraSettings.motionBlurIntensity = 0
    }

    override func enterIdle() {
        enterGameplay()
        hideObstacles()
        cameraSettings.motionBlurIntensity = 0
    }

    override func updateIdle(dt: Float) {
        playerZ -= dt * 20
        placeCar(x: 0, z: playerZ, steer: 0, speed: 20, dt: dt)
        let p = V3(0, 0, playerZ)
        placeCamera(eye: p + V3(4.5, 1.4, -3), target: p + V3(0, 0.8, 1), fov: 50)
    }

    // MARK: - Кат-сцены

    override func beginShot(_ cue: Cue) {
        hideObstacles()
        cameraSettings.motionBlurIntensity = 0
        switch cue {
        case .chaseDepart:
            enterGameplay()
            hunterDistance = 60
        case .chaseMirror:
            hunterDistance = 26
        case .chaseLost:
            hunterDistance = 20
        case .chaseDawn:
            scene.background.contents = dawnSky
            scene.lightingEnvironment.contents = dawnSky
            key.light?.color = UIColor(red: 1, green: 0.62, blue: 0.4, alpha: 1)
            key.light?.intensity = 500
            hunterDistance = 400
        default:
            break
        }
    }

    override func updateShot(_ cue: Cue, progress p: Float, dt: Float) {
        let speed: Float = cue == .chaseDepart ? 8 + p * 20 : 28
        playerZ -= dt * speed
        if cue == .chaseLost { hunterDistance += dt * 25 }
        placeCar(x: 0, z: playerZ, steer: 0, speed: speed, dt: dt)
        let c = V3(0, 0, playerZ)
        switch cue {
        case .chaseDepart:
            dolly(p, eye: (c + V3(5, 1.0, -6), c + V3(3, 1.6, 6)), look: (c + V3(0, 0.8, 0), c + V3(0, 0.8, -8)), fov: (45, 55))
        case .chaseMirror:
            // Взгляд назад, поверх машины, на фары охотника.
            placeCamera(eye: c + V3(0.4, 1.7, -1.5), target: c + V3(0, 0.9, hunterDistance), fov: 40)
        case .chaseLost:
            placeCamera(eye: c + V3(0.3, 1.7, -1.4), target: c + V3(0, 0.9, 20), fov: 44)
        case .chaseDawn:
            dolly(p, eye: (c + V3(-4, 2, 4), c + V3(-10, 22, 30)), look: (c, c + V3(0, 6, -120)), fov: (55, 62))
        default:
            break
        }
    }
}

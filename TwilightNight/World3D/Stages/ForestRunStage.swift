import SceneKit
import UIKit
import simd

/// Глава 14. Эдвард бежит сквозь лес с Беллой на спине — стволы проносятся мимо.
final class ForestRunStage: RunnerStageBase {

    private let edward = Humanoid(Cast.edward)
    private let bella = Humanoid(Cast.bella)
    private var key = SCNNode()
    private let leaves = SCNNode()
    private var runPhase: Float = 0
    private var obstacleGeometry: [SCNGeometry] = []

    init() {
        super.init(xScale: 7, segmentLength: 120)
        let root = scene.rootNode

        setSky(Textures.SkyStyle(
            zenith: SIMD3(0.36, 0.44, 0.52), horizon: SIMD3(0.62, 0.68, 0.7), ground: SIMD3(0.12, 0.16, 0.12),
            cloudCover: 0.85, cloudLight: SIMD3(0.8, 0.82, 0.84), cloudDark: SIMD3(0.45, 0.5, 0.55),
            sunAzimuth: 0.4, sunElevation: 0.7, sunColor: SIMD3(1, 0.95, 0.85), sunGlow: 0.4,
            sunDisc: false, seed: 51), lighting: 1.0)
        setFog(color: UIColor(red: 0.42, green: 0.5, blue: 0.48, alpha: 1), start: 12, end: 110, exponent: 1.2)
        key = addKeyLight(color: UIColor(red: 1, green: 0.96, blue: 0.88, alpha: 1), intensity: 650,
                          azimuth: 0.4, elevation: 0.9, shadowExtent: 36, softness: 10)
        addAmbient(color: UIColor(red: 0.35, green: 0.42, blue: 0.38, alpha: 1), intensity: 80)

        // Три варианта деревьев-препятствий: толстый ствол, крона высоко.
        for (i, (h, r)) in [(Float(24), Float(0.5)), (Float(28), Float(0.65)), (Float(22), Float(0.8))].enumerated() {
            let b = MeshBuilder()
            var rng = SeededRandom(seed: UInt64(700 + i))
            Nature.addSpruce(to: b, at: .zero, height: h, rng: &rng, needle: UIColor(hex: 0x1E3A22),
                             branchStart: 0.3, trunkRadius: r, tiers: 10)
            let g = b.geometry(name: "obstacle-tree")
            let m = Materials.matte(roughness: 0.9)
            m.isDoubleSided = true
            m.shaderModifiers = [.geometry: Materials.windModifier(strength: 0.004)]
            g.materials = [m]
            obstacleGeometry.append(g)
        }

        installSegments(count: 4)
        prewarm(variants: [0, 1, 2], count: 7)
        useRunnerQuality(key: key)

        root.addChildNode(edward.node)
        edward.node.addChildNode(bella.node)
        edward.node.setCastsShadow(true)
        bella.node.setCastsShadow(true)

        // Листья и пыль, летящие навстречу.
        let ps = SCNParticleSystem()
        ps.birthRate = 140
        ps.particleLifeSpan = 1.2
        ps.particleVelocity = 24
        ps.particleVelocityVariation = 6
        ps.emittingDirection = SCNVector3(0, -0.05, 1)
        ps.spreadingAngle = 8
        ps.particleSize = 0.04
        ps.particleSizeVariation = 0.03
        ps.particleImage = Textures.softDot
        ps.particleColor = UIColor(red: 0.45, green: 0.55, blue: 0.3, alpha: 0.8)
        ps.particleColorVariation = SCNVector4(0.1, 0.2, 0.1, 0.2)
        ps.emitterShape = SCNBox(width: 14, height: 5, length: 1, chamferRadius: 0)
        ps.birthLocation = .volume
        ps.isLocal = false
        ps.loops = true
        leaves.addParticleSystem(ps)
        root.addChildNode(leaves)

        cameraSettings.motionBlurIntensity = 0.0
        cameraSettings.saturation = 0.9
        placeCamera(eye: V3(0, 2.8, 6.5), target: V3(0, 1.4, -10), fov: 66)
    }

    // MARK: - Декорации

    override func makeSegment(_ index: Int) -> SCNNode {
        let seg = SCNNode()
        let L = segmentLength
        let ground = SCNNode(SCNPlane(width: 120, height: CGFloat(L)), Materials.dirt(tile: 30))
        ground.eulerAngles.x = -Float.pi / 2
        ground.simdPosition = V3(0, 0, -L / 2)
        ground.castsShadow = false
        seg.addChildNode(ground)

        // Мох и трава по краям тропы.
        let moss = Nature.grassField(radius: 0, count: 3500, seed: UInt64(30 + index % 2), height: 0.08...0.3,
                                     colors: [UIColor(hex: 0x3C5A2A), UIColor(hex: 0x506A30), UIColor(hex: 0x6B6A3A)],
                                     avoid: nil, rect: SIMD2(28, L / 2))
        moss.simdPosition = V3(0, 0, -L / 2)
        seg.addChildNode(moss)

        // Лес по сторонам.
        let b = MeshBuilder()
        var rng = SeededRandom(seed: UInt64(900 + index % 2))
        for _ in 0..<70 {
            let side: Float = rng.unit() > 0.5 ? 1 : -1
            let x = side * rng.range(9.5, 55)
            let z = -rng.range(0, L)
            Nature.addSpruce(to: b, at: V3(x, 0, z), height: rng.range(16, 30), rng: &rng, tiers: abs(x) < 20 ? 11 : 7)
        }
        for _ in 0..<26 {
            let x = (rng.unit() > 0.5 ? 1 : -1) * rng.range(7, 30)
            b.addBlob(center: V3(x, 0.2, -rng.range(0, L)), radius: rng.range(0.4, 1.3),
                      color: UIColor(hex: 0x5A5E5C), squash: 0.55, seed: rng.next(), rings: 4, segments: 7)
        }
        let forest = SCNNode(geometry: b.geometry(name: "forest-strip"))
        let m = Materials.matte(roughness: 0.9)
        m.isDoubleSided = true
        m.shaderModifiers = [.geometry: Materials.windModifier(strength: 0.005)]
        forest.geometry?.materials = [m]
        forest.castsShadow = false
        seg.addChildNode(forest)
        return seg
    }

    override func makeObstacle(_ variant: Int) -> SCNNode {
        let g = obstacleGeometry[min(variant, obstacleGeometry.count - 1)]
        let n = SCNNode(geometry: g)
        n.castsShadow = true
        return n
    }

    // MARK: - Общее

    override var ambience: [SoundFX.Ambience: Float] { [.forest: 0.4, .wind: 0.75] }

    private func placeRunners(running: Bool, dt: Float, speed: Float) {
        edward.place(V3(playerX, 0, playerZ), yaw: Float.pi)
        if running {
            runPhase += dt * min(16, 6 + speed * 0.35)
            edward.target = Pose.carryRun(runPhase)
            edward.rate = 22
        }
        bella.place(V3(0, 0.56, -0.27), yaw: 0)
        bella.target = .piggyback
        bella.rate = 12
    }

    override func updateAmbient(dt: Float) {
        edward.update(dt: dt, time: time)
        bella.update(dt: dt, time: time)
        updateTreadmill()
        leaves.simdPosition = camera.simdPosition + V3(0, -0.5, -16)
        // Тени следуют за игроком.
        key.simdPosition = V3(playerX, 0, playerZ) + simd_normalize(V3(sin(0.4), 1.25, cos(0.4))) * 120
    }

    // MARK: - Игра

    /// Белла снова на спине у Эдварда (после сцены, где она сидела на земле).
    private func attachBella() {
        if bella.node.parent !== edward.node {
            bella.node.removeFromParentNode()
            edward.node.addChildNode(bella.node)
        }
        bella.lookAt = nil
        edward.lookAt = nil
    }

    override func enterGameplay() {
        attachBella()
        playerZ = 0
        playerX = 0
        resetSegments()
        bella.snap(.piggyback)
        edward.snap(Pose.carryRun(0))
        cameraSettings.motionBlurIntensity = 0
    }

    override func updateGameplay(_ engine: GameEngine, dt: Float) {
        let s = engine.forest
        playerZ = -Float(s.distance)
        let newX = Float(s.playerX) * xScale
        let lean = dt > 0 ? (newX - playerX) / max(dt, 0.001) : 0
        playerX = newX
        placeRunners(running: dt > 0, dt: dt, speed: Float(s.speed))
        edward.yaw = Float.pi - clampf(lean * 0.04, -0.5, 0.5)
        if s.stumble > 0.9 { shake = 1 }
        layoutObstacles(s)

        let p = V3(playerX, 0, playerZ)
        followCamera(eye: p + V3(-playerX * 0.25, 2.7, 6.2), target: p + V3(playerX * 0.1, 1.3, -12),
                     fov: 64 + Float(s.speed) * 0.25, rate: 6, dt: max(dt, 0.016))
    }

    override func enterIdle() {
        enterGameplay()
        hideObstacles()
        cameraSettings.motionBlurIntensity = 0
    }

    override func updateIdle(dt: Float) {
        // Неспешный бег на фоне карточки главы.
        playerZ -= dt * 6
        placeRunners(running: true, dt: dt, speed: 6)
        let p = V3(playerX, 0, playerZ)
        placeCamera(eye: p + V3(3.5, 1.8, 4.5), target: p + V3(0, 1.3, 0), fov: 50)
    }

    // MARK: - Кат-сцены

    override func beginShot(_ cue: Cue) {
        hideObstacles()
        cameraSettings.motionBlurIntensity = 0
        switch cue {
        case .forestOnBack, .forestLanding, .forestDizzy:
            playerZ = 0
            playerX = 0
            resetSegments()
            edward.place(V3(0, 0, 0), yaw: Float.pi)
            if cue == .forestDizzy {
                bella.node.removeFromParentNode()
                scene.rootNode.addChildNode(bella.node)
                bella.place(V3(1.0, 0, -0.8), yaw: -Float.pi / 2 + 0.4)
                bella.snap(.sitGround)
                edward.snap(.kneel)
                edward.place(V3(0.1, 0, -0.9), yaw: Float.pi / 2 + 0.3)
                bella.lookAt = edward.head.simdWorldPosition
                edward.lookAt = bella.head.simdWorldPosition
            } else {
                attachBella()
                bella.place(V3(0, 0.56, -0.27), yaw: 0)
                bella.snap(.piggyback)
                edward.snap(.stand)
            }
        case .forestTreetops:
            attachBella()
            playerZ = 0
            resetSegments()
        default:
            break
        }
    }

    override func updateShot(_ cue: Cue, progress p: Float, dt: Float) {
        switch cue {
        case .forestOnBack:
            edward.target = p < 0.5 ? .stand : Pose.carryRun(0)
            let c = V3(0, 1.3, 0)
            placeCamera(eye: c + rotateY(V3(2.6, 0.3, -2.6), p * 0.8), target: c, fov: 42)
        case .forestTreetops:
            playerZ -= dt * 24
            placeRunners(running: true, dt: dt, speed: 24)
            let pz = V3(0, 0, playerZ)
            dolly(p, eye: (pz + V3(-6, 1.2, -6), pz + V3(0, 14, 10)), look: (pz + V3(0, 1.4, 0), pz + V3(0, 0, -30)),
                  fov: (55, 70))
            cameraSettings.motionBlurIntensity = 0.5
        case .forestLanding:
            edward.target = .stand
            let c = edward.head.simdWorldPosition
            dolly(p, eye: (c + V3(1.6, 0, -2.2), c + V3(1.0, -0.1, -1.6)), look: (c, c), fov: (40, 34))
        case .forestDizzy:
            let c = bella.head.simdWorldPosition
            placeCamera(eye: c + rotateY(V3(1.4, 0.3, 0.8), p * 0.4), target: c, fov: 36)
        default:
            break
        }
    }
}

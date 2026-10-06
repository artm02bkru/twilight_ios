import SceneKit
import UIKit
import simd

/// Глава 13. Круглый луг в лесу: высокая трава под ветром, цветы, солнечные столбы сквозь облака.
final class MeadowStage: Stage3D {

    private let bella = Humanoid(Cast.bella)
    private let edward = Humanoid(Cast.edward)

    /// Пул световых столбов для лучей из игры.
    private var beams: [Beam] = []
    private let heroBeam: Beam
    private var key = SCNNode()
    private static let sunDir = simd_normalize(V3(-0.35, 1, 0.45))

    private var edwardX: Float = 0
    private var walkPhase: Float = 0

    /// Мировой X по горизонтали игры.
    private func worldX(_ v: CGFloat) -> Float { (Float(v) - 0.5) * 15 }

    /// Солнечный столб: светящийся объём, пятно на траве и прожектор.
    private final class Beam {
        let node = SCNNode()
        let shaft: SCNNode
        let pool: SCNNode
        let lamp: SCNNode

        init(sunDir: V3) {
            let cyl = SCNCylinder(radius: 1, height: 60)
            cyl.radialSegmentCount = 32
            let shaftMat = Materials.glowImage(Textures.smoke, color: UIColor(red: 1, green: 0.88, blue: 0.62, alpha: 1),
                                               intensity: 0.35)
            shaftMat.cullMode = .back
            shaft = SCNNode(cyl, shaftMat)
            // Наклонить ось столба к солнцу.
            let axis = simd_normalize(simd_cross(V3(0, 1, 0), sunDir))
            let angle = acos(simd_dot(V3(0, 1, 0), sunDir))
            shaft.simdOrientation = simd_quatf(angle: angle, axis: axis)
            shaft.simdPosition = sunDir * 30
            shaft.castsShadow = false
            node.addChildNode(shaft)

            pool = SCNNode(SCNPlane(width: 2, height: 2),
                           Materials.glowImage(Textures.softDot, color: UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 1),
                                               intensity: 0.6))
            pool.eulerAngles.x = -Float.pi / 2
            pool.simdPosition = V3(0, 0.05, 0)
            pool.castsShadow = false
            node.addChildNode(pool)

            lamp = Stage3D.spotLight(color: UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 1),
                                     intensity: 6000, angle: 12, range: 80)
            lamp.simdPosition = sunDir * 40
            lamp.simdLook(at: .zero)
            node.addChildNode(lamp)
        }

        func set(x: Float, radius: Float, strength: Float) {
            node.simdPosition = V3(x, 0, 0)
            shaft.simdScale = V3(radius, 1, radius)
            pool.simdScale = V3(radius * 1.3, radius * 1.3, 1)
            node.opacity = CGFloat(strength)
            lamp.light?.intensity = CGFloat(strength * 9000)
            lamp.light?.spotOuterAngle = CGFloat(atan(radius / 40) * 180 / Float.pi * 2.4)
            lamp.light?.spotInnerAngle = CGFloat(atan(radius / 40) * 180 / Float.pi * 1.6)
        }
    }

    override init() {
        heroBeam = Beam(sunDir: Self.sunDir)
        super.init()
        let root = scene.rootNode

        setSky(Textures.SkyStyle(
            zenith: SIMD3(0.22, 0.42, 0.72), horizon: SIMD3(0.72, 0.8, 0.88), ground: SIMD3(0.2, 0.24, 0.18),
            cloudCover: 0.62, cloudLight: SIMD3(0.95, 0.95, 0.96), cloudDark: SIMD3(0.48, 0.52, 0.6),
            sunAzimuth: -0.66, sunElevation: 0.9, sunColor: SIMD3(1, 0.93, 0.8), sunGlow: 0.9,
            sunDisc: true, seed: 13), lighting: 1.0)
        setFog(color: UIColor(red: 0.62, green: 0.7, blue: 0.72, alpha: 1), start: 30, end: 210, exponent: 1.1)

        // Рассеянный свет под облаками; прямое солнце — только в столбах.
        key = addKeyLight(color: UIColor(red: 0.82, green: 0.88, blue: 1.0, alpha: 1), intensity: 380,
                          azimuth: -0.66, elevation: 0.95, shadowExtent: 40, softness: 18)

        // Земля: трава на поляне, подстилка в лесу.
        let ground = Nature.ground(size: 400, material: Materials.grass(tile: 60))
        root.addChildNode(ground)
        let forestFloor = SCNNode(SCNTube(innerRadius: 22, outerRadius: 200, height: 0.02), Materials.dirt(tile: 50))
        forestFloor.simdPosition = V3(0, 0.005, 0)
        root.addChildNode(forestFloor)

        // Там, где Белла и Эдвард лежат в финале, трава примята — иначе высокая трава их скрывает.
        func flattened(_ p: V3) -> Bool { p.x * p.x * 0.18 + p.z * p.z < 2.2 }
        root.addChildNode(Nature.grassField(radius: 21, count: 52_000, seed: 3, height: 0.25...0.62,
                                            avoid: flattened))
        root.addChildNode(Nature.grassField(radius: 4.2, count: 2_400, seed: 13, height: 0.03...0.09,
                                            avoid: { p in !flattened(p) }))
        root.addChildNode(Nature.flowers(radius: 20, count: 2600, seed: 4))
        root.addChildNode(Nature.forestRing(inner: 23.5, outer: 80, count: 640, seed: 21, heights: 16...30,
                                            broadleafShare: 0.35, corridor: (angle: Float.pi, width: 2.6)))
        // Деревья из моделей по кромке луга.
        var edge: [V3] = []
        for k in 0..<16 {
            let a = Float(k) / 16 * 2 * Float.pi + 0.2
            let r: Float = 23.5 + Float(k % 3) * 1.6
            edge.append(V3(sin(a) * r, 0, cos(a) * r))
        }
        if let grove = ModelAsset.grove(parts: [("tree_lowpoly", "a"), ("tree_lowpoly", "b"), ("tree_pack", "t3")],
                                        spots: edge.filter { abs($0.x) > 3 || $0.z > 0 }, scale: 2.4...3.4, seed: 33) {
            root.addChildNode(grove)
        }
        // Кто-то следит из-за деревьев.
        if let wolf = ModelAsset.named("werewolf")?.grounded("wolf") {
            let spot = V3(18, 0, -16.5)
            wolf.simdPosition = spot
            wolf.simdEulerAngles.y = yawToward(from: spot, to: .zero)
            wolf.setCastsShadow(true)
            root.addChildNode(wolf)
        }
        root.addChildNode(Nature.rocks(count: 18, seed: 8) { r in
            let a = r.x * 2 * Float.pi, d = 19 + r.y * 6
            return V3(sin(a) * d, 0, cos(a) * d)
        })
        // Тропинка через лес.
        let trail = SCNNode(SCNPlane(width: 2.2, height: 60), Materials.dirt(tile: 8))
        trail.eulerAngles.x = -Float.pi / 2
        trail.simdPosition = V3(0, 0.012, -50)
        root.addChildNode(trail)

        let motes = SCNNode()
        motes.addParticleSystem(Nature.motes(area: 30, height: 6, rate: 70,
                                             color: UIColor(red: 1, green: 0.92, blue: 0.7, alpha: 0.7)))
        motes.simdPosition = V3(0, 3, 0)
        root.addChildNode(motes)

        for _ in 0..<6 {
            let b = Beam(sunDir: Self.sunDir)
            b.set(x: 0, radius: 1, strength: 0)
            root.addChildNode(b.node)
            beams.append(b)
        }
        heroBeam.set(x: 0, radius: 1.3, strength: 0)
        root.addChildNode(heroBeam.node)

        for h in [bella, edward] {
            root.addChildNode(h.node)
            h.node.setCastsShadow(true)
        }

        cameraSettings.bloomIntensity = 0.8
        cameraSettings.bloomThreshold = 0.8
        cameraSettings.saturation = 1.0
        placeCamera(eye: V3(0, 3.2, 11), target: V3(0, 1, 0), fov: 62)
    }

    override var ambience: [SoundFX.Ambience: Float] { [.forest: 0.6, .wind: 0.25] }

    private var wasInSun = false

    override func updateAmbient(dt: Float) {
        for h in [bella, edward] { h.update(dt: dt, time: time) }
    }

    /// Насколько точка под солнечным столбом.
    private func sunlight(at x: Float, engine: GameEngine) -> Float {
        var best: Float = 0
        for beam in engine.meadow.beams {
            let d = abs(worldX(beam.x) - x)
            let r = Float(beam.half) * 15
            best = max(best, 1 - smoothstepf(r * 0.8, r + 0.6, d))
        }
        return best
    }

    // MARK: - Игра

    override func enterGameplay() {
        bella.place(V3(0.6, 0, -4.2), yaw: 0.1)
        bella.snap(.sitGround)
        edward.place(V3(0, 0, 0), yaw: 0)
        edward.snap(.stand)
        edwardX = 0
        heroBeam.set(x: 0, radius: 1, strength: 0)
        setKey(color: UIColor(red: 0.82, green: 0.88, blue: 1.0, alpha: 1), intensity: 380)
    }

    override func updateGameplay(_ engine: GameEngine, dt: Float) {
        let s = engine.meadow
        let x = worldX(s.edwardX)
        let speed = dt > 0 ? (x - edwardX) / dt : 0
        edwardX = x
        edward.place(V3(x, 0, 0), yaw: clampf(speed * 0.08, -0.9, 0.9))
        if abs(speed) > 0.4 {
            walkPhase += dt * min(14, 4 + abs(speed) * 1.6)
            edward.target = Pose.walk(walkPhase, stride: min(1, abs(speed) / 4))
            edward.rate = 18
        } else {
            edward.target = .stand
            edward.rate = 6
        }
        edward.lookAt = camera.simdPosition

        // Лучи из игровой логики → световые столбы.
        let list = s.beams
        for (i, beam) in beams.enumerated() {
            if i < list.count {
                beam.set(x: worldX(list[i].x), radius: Float(list[i].half) * 15, strength: 1)
            } else {
                beam.set(x: 0, radius: 1, strength: 0)
            }
        }

        // Кожа на солнце горит алмазами; в тени — лишь редкие искры.
        let sun = sunlight(at: x, engine: engine)
        edward.setSparkle(max(sun, Float(s.glitter) * 0.12))
        if sun > 0.5 && !wasInSun { SoundFX.shared.play(.chime, volume: 0.6) }
        wasInSun = sun > 0.5
        bella.lookAt = edward.head.simdWorldPosition
        if s.hurtFlash > 0.9 { shake = 0.6 }

        followCamera(eye: V3(x * 0.25, 3.0, 11), target: V3(x * 0.4, 1.1, 0), fov: 62, rate: 3, dt: max(dt, 0.016))
    }

    override func enterIdle() {
        enterGameplay()
        heroBeam.set(x: 2.5, radius: 1.4, strength: 1)
    }

    override func updateIdle(dt: Float) {
        let a = time * 0.05
        placeCamera(eye: rotateY(V3(0, 2.6, 12), a), target: V3(0, 1, -1), fov: 58)
    }

    private func setKey(color: UIColor, intensity: CGFloat) {
        key.light?.color = color
        key.light?.intensity = intensity
    }

    // MARK: - Кат-сцены

    override func beginShot(_ cue: Cue) {
        for b in beams { b.set(x: 0, radius: 1, strength: 0) }
        bella.lookAt = nil
        edward.lookAt = nil
        edward.setSparkle(0)
        heroBeam.set(x: 0, radius: 1, strength: 0)
        setKey(color: UIColor(red: 0.82, green: 0.88, blue: 1.0, alpha: 1), intensity: 380)
        switch cue {
        case .edwardHesitates:
            heroBeam.set(x: 2.2, radius: 1.4, strength: 1)
            heroBeam.node.simdPosition = V3(2.2, 0, -17.2)
            edward.place(V3(3, 0, -21.2), yaw: Float.pi - 0.3)
            edward.snap(.stand)
            bella.place(V3(0.4, 0, -14.6), yaw: -Float.pi + 0.5)
            bella.snap(.stand)
            edward.lookAt = bella.head.simdWorldPosition
            bella.lookAt = edward.head.simdWorldPosition
        case .edwardSteps:
            SoundFX.shared.play(.chime, volume: 0.8, delay: 2.0)
            heroBeam.set(x: 2.2, radius: 1.4, strength: 1)
            heroBeam.node.simdPosition = V3(2.2, 0, -17.2)
            bella.place(V3(0.4, 0, -14.6), yaw: -Float.pi + 0.5)
            bella.snap(.stand)
        case .cloudsMove:
            beams[0].set(x: -6, radius: 1.3, strength: 1)
            beams[1].set(x: 4, radius: 1.0, strength: 1)
            bella.place(V3(0.6, 0, -4.2), yaw: 0.1)
            bella.snap(.sitGround)
            edward.place(V3(0, 0, 0), yaw: 0)
            edward.snap(.stand)
        case .meadowLying, .meadowLyingClose, .meadowSunset:
            bella.place(V3(-1.55, 0, 0.32), yaw: -Float.pi / 2)
            bella.snap(.lieBack)
            edward.place(V3(1.75, 0, -0.32), yaw: Float.pi / 2)
            edward.snap(.lieBack)
            if cue == .meadowSunset {
                setKey(color: UIColor(red: 1, green: 0.62, blue: 0.35, alpha: 1), intensity: 260)
            }
        default:
            break
        }
    }

    override func updateShot(_ cue: Cue, progress p: Float, dt: Float) {
        switch cue {
        case .forestHike:
            let z = lerpf(-62, -38, p)
            walkPhase += dt * 6.5
            edward.place(V3(0.45, 0, z + 1.6), yaw: 0)
            edward.target = Pose.walk(walkPhase + 1.2)
            edward.rate = 20
            bella.place(V3(-0.35, 0, z), yaw: 0)
            bella.target = Pose.walk(walkPhase)
            bella.rate = 20
            placeCamera(eye: V3(0.6, 1.65, z - 3.4), target: V3(0, 1.2, z + 6), fov: 56)
        case .meadowReveal:
            let z = lerpf(-23, -16.5, easeSoft(min(1, p * 1.3)))
            walkPhase += dt * 6.5 * (p < 0.75 ? 1 : 0)
            bella.place(V3(-0.35, 0, z), yaw: 0)
            bella.target = p < 0.75 ? Pose.walk(walkPhase) : .stand
            edward.place(V3(0.45, 0, z + 1.4 - p), yaw: 0.2)
            edward.target = p < 0.75 ? Pose.walk(walkPhase + 1.2) : .stand
            bella.rate = 16
            edward.rate = 16
            dolly(p, eye: (V3(0.3, 1.7, z - 4), V3(-3, 6.5, -32)), look: (V3(0, 1.2, z + 5), V3(0, 0.5, 2)), fov: (56, 64))
        case .edwardHesitates:
            let head = edward.head.simdWorldPosition
            dolly(p, eye: (V3(1.6, 1.6, -18.2), V3(2.0, 1.65, -18.8)), look: (head, head), fov: (34, 28))
        case .edwardSteps:
            let t = easeSoft(min(1, p * 1.5))
            let pos = mixv(V3(3, 0, -21.2), V3(2.2, 0, -17.4), t)
            walkPhase += dt * 4 * (t < 1 ? 1 : 0)
            edward.place(pos, yaw: Float.pi - 0.3 + t * 0.3)
            edward.target = t < 1 ? Pose.walk(walkPhase, stride: 0.6) : .stand
            edward.rate = 14
            edward.lookAt = bella.head.simdWorldPosition
            bella.lookAt = edward.head.simdWorldPosition
            edward.setSparkle(smoothstepf(0.35, 0.65, p))
            let head = edward.head.simdWorldPosition
            dolly(p, eye: (V3(4.6, 1.5, -14.5), V3(0.8, 1.7, -14.8)), look: (head, head), fov: (40, 30))
        case .cloudsMove:
            beams[0].set(x: lerpf(-6, -1, p), radius: 1.3, strength: 1)
            beams[1].set(x: lerpf(4, 7, p), radius: 1.0, strength: 1)
            dolly(p, eye: (V3(0, 1.4, 14), V3(0, 2.5, 13)), look: (V3(-3, 18, -30), V3(0, 1.4, 0)), fov: (64, 60))
        case .meadowLying:
            let a = p * 0.4
            placeCamera(eye: V3(0.1, 0, 0) + rotateY(V3(0, 3.6, 0.9), a), target: V3(0.1, 0.1, 0), fov: 48)
        case .meadowLyingClose:
            let a = 0.4 + p * 0.2
            bella.lookAt = edward.head.simdWorldPosition
            placeCamera(eye: V3(0.1, 0, 0) + rotateY(V3(0, 1.6, 0.5), a), target: V3(0.1, 0.12, 0), fov: 40)
        case .meadowSunset:
            setKey(color: UIColor(red: 1, green: lerpf(0.62, 0.45, p).cg, blue: 0.3, alpha: 1),
                   intensity: CGFloat(lerpf(260, 120, p)))
            dolly(p, eye: (V3(-6, 1.8, 9), V3(-12, 3.5, 16)), look: (V3(0, 0.5, 0), V3(0, 2, -6)), fov: (52, 60))
        default:
            break
        }
    }
}

private extension Float {
    var cg: CGFloat { CGFloat(self) }
}

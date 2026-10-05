import SceneKit
import UIKit
import simd

/// Главное меню: лунная поляна в тумане, Белла держит красное яблоко — как на обложке книги.
final class MenuStage: Stage3D {

    private let bella = Humanoid(Cast.bella)
    private let edward = Humanoid(Cast.edward)
    private let apple = SCNNode()
    private let moonBeam = SCNNode()

    override init() {
        super.init()
        let root = scene.rootNode

        setSky(Textures.SkyStyle(
            zenith: SIMD3(0.01, 0.015, 0.04), horizon: SIMD3(0.06, 0.08, 0.13), ground: SIMD3(0.01, 0.015, 0.02),
            cloudCover: 0.45, cloudLight: SIMD3(0.25, 0.28, 0.38), cloudDark: SIMD3(0.03, 0.04, 0.07),
            sunAzimuth: 2.6, sunElevation: 0.45, sunColor: SIMD3(0.8, 0.86, 1.0), sunGlow: 0.7,
            sunDisc: true, stars: true, seed: 101), lighting: 0.6)
        setFog(color: UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1), start: 8, end: 70, exponent: 1.2)

        // Лунный свет: холодный, с длинными тенями.
        addKeyLight(color: UIColor(red: 0.62, green: 0.72, blue: 1, alpha: 1), intensity: 260,
                    azimuth: 2.6, elevation: 0.55, shadowExtent: 16, softness: 8)
        addAmbient(color: UIColor(red: 0.12, green: 0.15, blue: 0.24, alpha: 1), intensity: 40)

        root.addChildNode(Nature.ground(size: 200, material: Materials.grass(tile: 40)))
        root.addChildNode(Nature.grassField(radius: 14, count: 24_000, seed: 77, height: 0.15...0.45,
                                            colors: [UIColor(hex: 0x2A4426), UIColor(hex: 0x37502C), UIColor(hex: 0x445A30)]))
        root.addChildNode(Nature.forestRing(inner: 9, outer: 55, count: 420, seed: 78, heights: 18...34,
                                            broadleafShare: 0.1))

        // Столб лунного света сквозь туман.
        let beam = SCNNode(SCNCylinder(radius: 1.8, height: 40),
                           Materials.glowImage(Textures.smoke, color: UIColor(red: 0.55, green: 0.65, blue: 0.95, alpha: 1),
                                               intensity: 0.18))
        let dir = simd_normalize(V3(sin(2.6), 1.3, cos(2.6)))
        beam.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: dir)
        beam.simdPosition = dir * 20
        beam.castsShadow = false
        moonBeam.addChildNode(beam)
        root.addChildNode(moonBeam)

        let fog = SCNNode()
        fog.addParticleSystem(Nature.groundFog(area: 40, rate: 16, color: UIColor(red: 0.7, green: 0.78, blue: 0.95, alpha: 0.05)))
        fog.simdPosition = V3(0, 0.3, 0)
        root.addChildNode(fog)
        let fireflies = SCNNode()
        fireflies.addParticleSystem(Nature.motes(area: 16, height: 3, rate: 14,
                                                 color: UIColor(red: 0.85, green: 0.95, blue: 1, alpha: 1)))
        fireflies.simdPosition = V3(0, 1.4, 0)
        root.addChildNode(fireflies)

        // Пара: Белла с яблоком, Эдвард за её плечом.
        root.addChildNode(bella.node)
        root.addChildNode(edward.node)
        bella.node.setCastsShadow(true)
        edward.node.setCastsShadow(true)
        bella.place(V3(0, 0, 0), yaw: 0.25)
        bella.snap(.holdApple)
        edward.place(V3(0.45, 0, -0.55), yaw: -0.2)
        edward.snap(.handsInPockets)

        // Яблоко: глянцевое, красное, с черенком и листом.
        let skin = Materials.pbr(UIColor(red: 0.62, green: 0.03, blue: 0.06, alpha: 1), roughness: 0.22)
        skin.clearCoat.contents = 1
        skin.clearCoatRoughness.contents = 0.1
        let body = SCNNode(SCNSphere(radius: 0.045), skin)
        body.simdScale = V3(1, 0.92, 1)
        apple.addChildNode(body)
        let stem = SCNNode(SCNCylinder(radius: 0.003, height: 0.025), Materials.bark())
        stem.simdPosition = V3(0.004, 0.048, 0)
        stem.eulerAngles.z = -0.3
        apple.addChildNode(stem)
        let leaf = SCNNode(SCNSphere(radius: 0.012), Materials.pbr(UIColor(hex: 0x2E5A26), roughness: 0.5))
        leaf.simdScale = V3(1.6, 0.25, 0.8)
        leaf.simdPosition = V3(0.018, 0.058, 0)
        apple.addChildNode(leaf)
        root.addChildNode(apple)

        cameraSettings.bloomIntensity = 1.1
        cameraSettings.bloomThreshold = 0.6
        cameraSettings.exposureOffset = 0.9
        cameraSettings.saturation = 0.9
        cameraSettings.vignettingIntensity = 0.9
        placeCamera(eye: V3(0.3, 1.5, 3.4), target: V3(0.1, 1.3, 0), fov: 44)
    }

    override var ambience: [SoundFX.Ambience: Float] { [.wind: 0.35, .crickets: 0.15] }

    override func updateAmbient(dt: Float) {
        bella.update(dt: dt, time: time)
        edward.update(dt: dt, time: time)
        // Яблоко лежит в ладонях Беллы.
        let hands = (bella.handL.simdWorldPosition + bella.handR.simdWorldPosition) * 0.5
        apple.simdPosition = hands + V3(0, 0.02, 0) + rotateY(V3(0, 0, 0.06), bella.yaw)
        apple.simdEulerAngles.y = time * 0.1
    }

    override func enterIdle() {
        bella.lookAt = nil
        edward.lookAt = bella.head.simdWorldPosition
    }

    override func updateIdle(dt: Float) {
        // Медленный облёт: то лицо Беллы, то яблоко, то оба героя.
        let t = time * 0.05
        let orbit = rotateY(V3(0.2, 0, 3.2), sin(t) * 0.45)
        let height = 1.35 + sin(t * 1.7) * 0.15
        let target = V3(0.12, 1.25 + sin(t * 0.8) * 0.1, 0)
        placeCamera(eye: target + orbit + V3(0, height - 1.25, 0), target: target, fov: 42 + sin(t * 0.6) * 4)
        bella.lookAt = camera.simdPosition
    }

    override func enterGameplay() { enterIdle() }
}

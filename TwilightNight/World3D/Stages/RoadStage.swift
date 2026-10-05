import SceneKit
import UIKit
import simd

/// Пролог и фон меню: ночная лесная дорога в Форкс, дождь, пикап Беллы с включёнными фарами.
final class RoadStage: Stage3D {

    private let path = RoadPath(length: 900, winding: 26, slope: 12)
    private let truck = Vehicle.pickup()
    private var truckZ: Float = 60
    private let speed: Float = 15
    private let rainNode = SCNNode()

    override init() {
        super.init()
        let root = scene.rootNode

        setSky(Textures.SkyStyle(
            zenith: SIMD3(0.02, 0.03, 0.06), horizon: SIMD3(0.09, 0.11, 0.15), ground: SIMD3(0.02, 0.02, 0.03),
            cloudCover: 0.85, cloudLight: SIMD3(0.16, 0.18, 0.23), cloudDark: SIMD3(0.04, 0.05, 0.07),
            sunAzimuth: 2.4, sunElevation: 0.5, sunColor: SIMD3(0.55, 0.62, 0.8), sunGlow: 0.25,
            sunDisc: false, stars: false, seed: 3), lighting: 0.6)
        setFog(color: UIColor(red: 0.07, green: 0.085, blue: 0.11, alpha: 1), start: 25, end: 320)

        let terrain = SCNNode(geometry: RoadBuild.terrain(path: path, seed: 7))
        terrain.castsShadow = false
        root.addChildNode(terrain)
        root.addChildNode(SCNNode(geometry: RoadBuild.road(path: path)))
        root.addChildNode(SCNNode(geometry: RoadBuild.roadMarkings(path: path)))
        root.addChildNode(SCNNode(geometry: RoadBuild.roadsidePosts(path: path)))
        let forest = SCNNode(geometry: RoadBuild.forest(path: path, seed: 7, count: 1300, area: 200))
        forest.geometry?.firstMaterial?.shaderModifiers = [.geometry: Materials.windModifier(strength: 0.005)]
        root.addChildNode(forest)
        root.addChildNode(SCNNode(geometry: RoadBuild.roadsideDetails(path: path, seed: 7, count: 420)))

        // Луна за облаками — холодный рассеянный свет.
        addKeyLight(color: UIColor(red: 0.55, green: 0.65, blue: 0.85, alpha: 1), intensity: 120,
                    azimuth: 2.4, elevation: 0.7, shadowExtent: 60, softness: 10)
        addAmbient(color: UIColor(red: 0.2, green: 0.25, blue: 0.35, alpha: 1), intensity: 40)

        root.addChildNode(truck.node)
        truck.setHeadlights(1)
        // Фары пикапа отбрасывают тени — дождь и ели видны в лучах.
        if let lamp = truck.headlights.first?.light {
            lamp.castsShadow = true
            lamp.shadowMode = .deferred
            lamp.shadowSampleCount = 4
        }

        // Дождь следует за камерой.
        rainNode.addParticleSystem(RoadBuild.rain(intensity: 1400))
        rainNode.simdPosition = V3(0, 22, 0)
        root.addChildNode(rainNode)
        let mist = SCNNode()
        mist.addParticleSystem(RoadBuild.mist())
        mist.simdPosition = V3(0, 1, 200)
        root.addChildNode(mist)

        cameraSettings.bloomIntensity = 0.9
        cameraSettings.bloomThreshold = 0.7
        cameraSettings.exposureOffset = 0.6
        placeCamera(eye: V3(10, 30, -20), target: V3(0, 0, 60), fov: 60)
    }

    // MARK: - Пикап едет сам по себе в любом режиме

    private var truckPos: V3 { V3(path.center(truckZ), path.height(truckZ), truckZ) }
    private var heading: Float { path.heading(truckZ) }
    private var forward: V3 { V3(sin(heading), 0, cos(heading)) }
    private var right: V3 { V3(-cos(heading), 0, sin(heading)) }

    override func updateAmbient(dt: Float) {
        truckZ += speed * dt
        if truckZ > path.length - 80 { truckZ = 60 }
        // Лёгкое покачивание на неровностях.
        let bob = sin(time * 9) * 0.015 + sin(time * 3.7) * 0.01
        truck.node.simdPosition = truckPos + V3(0, bob, 0)
        let slope = atan2(path.height(truckZ + 2) - path.height(truckZ - 2), 4)
        truck.node.simdEulerAngles = V3(-slope, heading, sin(time * 2.3) * 0.01)
        truck.roll(distance: speed * dt)
        rainNode.simdPosition = camera.simdPosition + V3(0, 18, 0) + forward * 10
    }

    // MARK: - Меню

    override func enterIdle() {}

    override func updateIdle(dt: Float) {
        // Медленный облёт пикапа сверху сбоку.
        let a = time * 0.06
        let offset = rotateY(V3(9, 4.5, -7), a)
        followCamera(eye: truckPos + offset, target: truckPos + forward * 6 + V3(0, 0.8, 0),
                     fov: 55, rate: 2, dt: dt)
    }

    // MARK: - Пролог

    override func updateShot(_ cue: Cue, progress p: Float, dt: Float) {
        let t = truckPos
        switch cue {
        case .roadAerial:
            dolly(p, eye: (t + V3(0, 55, -60), t + V3(-14, 22, -14)),
                  look: (t + forward * 40, t + forward * 8), fov: (50, 55))
        case .roadTruckFollow:
            dolly(p, eye: (t - forward * 9 + V3(0, 2.6, 0) + right * 1.5, t - forward * 6.5 + V3(0, 1.9, 0) + right * 0.8),
                  look: (t + forward * 12 + V3(0, 1, 0), t + forward * 10 + V3(0, 1.2, 0)), fov: (52, 48))
        case .roadTruckSide:
            dolly(p, eye: (t + right * 5.5 + forward * 3 + V3(0, 0.9, 0), t + right * 4.5 - forward * 2 + V3(0, 1.1, 0)),
                  look: (t + V3(0, 1.1, 0), t + V3(0, 1.2, 0) + forward), fov: (42, 38))
        case .roadTitle:
            dolly(p, eye: (t - forward * 10 + V3(0, 3, 0), t - forward * 30 + V3(0, 70, 0)),
                  look: (t + forward * 10, t + forward * 80 + V3(0, 10, 0)), fov: (55, 62))
        default:
            break
        }
    }
}

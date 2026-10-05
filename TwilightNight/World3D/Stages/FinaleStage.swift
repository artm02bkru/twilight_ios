import SceneKit
import UIKit
import simd

/// Эпилог: выпускной. Беседка в саду в сумерках, гирлянды огоньков, медленный танец.
final class FinaleStage: Stage3D {

    private let bella = Humanoid(Cast.bellaProm)
    private let edward = Humanoid(Cast.edwardProm)
    private var bulbs: [SCNNode] = []
    private let dancePivot = SCNNode()

    override init() {
        super.init()
        let root = scene.rootNode

        setSky(Textures.SkyStyle(
            zenith: SIMD3(0.08, 0.09, 0.22), horizon: SIMD3(0.85, 0.45, 0.35), ground: SIMD3(0.06, 0.06, 0.08),
            cloudCover: 0.4, cloudLight: SIMD3(0.95, 0.55, 0.45), cloudDark: SIMD3(0.25, 0.18, 0.3),
            sunAzimuth: -2.4, sunElevation: 0.02, sunColor: SIMD3(1, 0.5, 0.3), sunGlow: 1.1,
            sunDisc: false, stars: true, seed: 29), lighting: 0.7)
        setFog(color: UIColor(red: 0.22, green: 0.16, blue: 0.22, alpha: 1), start: 15, end: 120)

        addKeyLight(color: UIColor(red: 1, green: 0.55, blue: 0.4, alpha: 1), intensity: 220,
                    azimuth: -2.4, elevation: 0.12, shadowExtent: 20, softness: 8)
        addAmbient(color: UIColor(red: 0.3, green: 0.3, blue: 0.5, alpha: 1), intensity: 50)

        root.addChildNode(Nature.ground(size: 300, material: Materials.grass(tile: 50)))
        root.addChildNode(Nature.grassField(radius: 30, count: 26_000, seed: 15, height: 0.08...0.22,
                                            avoid: { p in simd_length(p) < 4.6 }))
        root.addChildNode(Nature.flowers(radius: 26, count: 900, seed: 16,
                                         palette: [UIColor(hex: 0xF2EEF5), UIColor(hex: 0xE8B4C8)]))
        root.addChildNode(Nature.forestRing(inner: 32, outer: 80, count: 380, seed: 61, heights: 14...26,
                                            broadleafShare: 0.5))

        buildGazebo(root)

        root.addChildNode(dancePivot)
        dancePivot.simdPosition = V3(0, 0.35, 0)
        for h in [bella, edward] {
            dancePivot.addChildNode(h.node)
            h.node.setCastsShadow(true)
        }

        let fireflies = SCNNode()
        fireflies.addParticleSystem(Nature.motes(area: 24, height: 3, rate: 18,
                                                 color: UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)))
        fireflies.simdPosition = V3(0, 1.2, 0)
        root.addChildNode(fireflies)

        cameraSettings.bloomIntensity = 1.1
        cameraSettings.bloomThreshold = 0.6
        cameraSettings.exposureOffset = 0.4
        placeCamera(eye: V3(0, 2, 7), target: V3(0, 1.3, 0), fov: 50)
    }

    private func buildGazebo(_ root: SCNNode) {
        let wood = Materials.wood(tile: 0.6, roughness: 0.35)
        let paint = Materials.pbr(UIColor(white: 0.92, alpha: 1), roughness: 0.5)

        let deck = SCNCylinder(radius: 4.2, height: 0.35)
        deck.radialSegmentCount = 8
        let deckNode = SCNNode(deck, wood)
        deckNode.simdPosition = V3(0, 0.175, 0)
        root.addChildNode(deckNode)

        let pillars = 8
        for i in 0..<pillars {
            let a = Float(i) / Float(pillars) * 2 * .pi + .pi / 8
            let p = V3(sin(a) * 3.9, 0, cos(a) * 3.9)
            let column = SCNCylinder(radius: 0.11, height: 3.0)
            column.radialSegmentCount = 16
            let c = SCNNode(column, paint)
            c.simdPosition = p + V3(0, 1.85, 0)
            root.addChildNode(c)
        }
        let ring = SCNTorus(ringRadius: 3.9, pipeRadius: 0.1)
        ring.ringSegmentCount = 48
        let ringNode = SCNNode(ring, paint)
        ringNode.simdPosition = V3(0, 3.35, 0)
        root.addChildNode(ringNode)
        let roof = SCNCone(topRadius: 0.1, bottomRadius: 4.6, height: 1.9)
        roof.radialSegmentCount = 8
        let roofNode = SCNNode(roof, Materials.pbr(UIColor(hex: 0x3D4650), roughness: 0.6, metalness: 0.4))
        roofNode.simdPosition = V3(0, 4.35, 0)
        root.addChildNode(roofNode)

        // Гирлянды: провисающие нити тёплых огоньков от вершины к колоннам.
        let bulbMat = Materials.glow(UIColor(red: 1, green: 0.78, blue: 0.45, alpha: 1), intensity: 3, doubleSided: false)
        let bulbGeo = SCNSphere(radius: 0.03)
        for i in 0..<pillars {
            let a = Float(i) / Float(pillars) * 2 * .pi + .pi / 8
            let end = V3(sin(a) * 3.9, 3.3, cos(a) * 3.9)
            let start = V3(0, 4.9, 0)
            for k in 1..<14 {
                let t = Float(k) / 14
                let p = mixv(start, end, t) - V3(0, sin(t * .pi) * 0.45, 0)
                let b = SCNNode(bulbGeo, bulbMat)
                b.simdPosition = p
                b.castsShadow = false
                root.addChildNode(b)
                bulbs.append(b)
            }
            // Нить между колоннами.
            let a2 = Float(i + 1) / Float(pillars) * 2 * .pi + .pi / 8
            let end2 = V3(sin(a2) * 3.9, 3.3, cos(a2) * 3.9)
            for k in 1..<8 {
                let t = Float(k) / 8
                let p = mixv(end, end2, t) - V3(0, sin(t * .pi) * 0.35, 0)
                let b = SCNNode(bulbGeo, bulbMat)
                b.simdPosition = p
                b.castsShadow = false
                root.addChildNode(b)
                bulbs.append(b)
            }
        }
        // Несколько настоящих источников света, чтобы гирлянды освещали героев.
        addOmni(at: V3(0, 3.9, 0), color: UIColor(red: 1, green: 0.75, blue: 0.45, alpha: 1), intensity: 900, range: 9)
        for a: Float in [0.4, 2.5, 4.6] {
            addOmni(at: V3(sin(a) * 3, 3.1, cos(a) * 3), color: UIColor(red: 1, green: 0.72, blue: 0.4, alpha: 1),
                    intensity: 350, range: 6)
        }
    }

    override func updateAmbient(dt: Float) {
        for h in [bella, edward] { h.update(dt: dt, time: time) }
        for (i, b) in bulbs.enumerated() {
            b.opacity = CGFloat(0.75 + 0.25 * sin(time * 2 + Float(i) * 1.7))
        }
        // Медленный танец: пара кружится и покачивается.
        dancePivot.simdEulerAngles.y = time * 0.25
        let sway = sin(time * 1.6) * 0.06
        bella.target.spine = V3(0, 0, sway)
        edward.target.spine = V3(0, 0, -sway)
    }

    private func layout() {
        // Белла стоит на ногах Эдварда — он ведёт.
        bella.place(V3(0, 0, 0.17), yaw: .pi)
        edward.place(V3(0, 0, -0.17), yaw: 0)
        bella.snap(.dance)
        edward.snap(.dance)
        bella.lookAt = nil
        edward.lookAt = nil
    }

    override func enterGameplay() { layout() }
    override func enterIdle() { layout() }

    override func updateIdle(dt: Float) {
        let a = time * 0.07
        placeCamera(eye: rotateY(V3(0, 2.1, 6.5), a), target: V3(0, 1.4, 0), fov: 48)
    }

    override func beginShot(_ cue: Cue) {
        layout()
    }

    override func updateShot(_ cue: Cue, progress p: Float, dt: Float) {
        switch cue {
        case .finaleDance:
            dolly(p, eye: (V3(-9, 2.6, 9), V3(-4, 2.0, 4.5)), look: (V3(0, 1.3, 0), V3(0, 1.45, 0)), fov: (50, 44))
        case .finaleClose:
            bella.lookAt = edward.head.simdWorldPosition
            edward.lookAt = bella.head.simdWorldPosition
            let c = (bella.head.simdWorldPosition + edward.head.simdWorldPosition) * 0.5
            placeCamera(eye: c + rotateY(V3(0.9, 0.05, 0.8), p * 0.5), target: c, fov: 34)
        case .finaleCrane:
            dolly(p, eye: (V3(0, 2.2, 5.5), V3(0, 14, 16)), look: (V3(0, 1.4, 0), V3(0, 6, -40)), fov: (46, 60))
        default:
            break
        }
    }
}

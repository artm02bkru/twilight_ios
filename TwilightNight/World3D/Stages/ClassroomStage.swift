import SceneKit
import UIKit
import simd

/// Глава 1. Кабинет биологии школы Форкса: лабораторные столы, микроскопы, дождь за окнами.
final class ClassroomStage: Stage3D {

    private let bella = Humanoid(Cast.bella)
    private let edward = Humanoid(Cast.edward)
    private let banner = Humanoid(Cast.banner)
    private let mike = Humanoid(Cast.mike)
    private let jessica = Humanoid(Cast.jessica)
    private let angela = Humanoid(Cast.angela)
    private var everyone: [Humanoid] { [bella, edward, banner, mike, jessica, angela] }

    private let bellaSeat = V3(-2.55, 0, -0.55)
    private let edwardSeat = V3(-1.45, 0, -0.55)
    private let microscopeSpot = V3(-2.15, 0.93, -1.15)
    private let doorSpot = V3(4.6, 0, 4.2)
    private var flicker = SCNNode()

    override init() {
        super.init()
        let root = scene.rootNode

        setSky(Textures.SkyStyle(
            zenith: SIMD3(0.5, 0.54, 0.58), horizon: SIMD3(0.66, 0.68, 0.7), ground: SIMD3(0.3, 0.3, 0.3),
            cloudCover: 1, cloudLight: SIMD3(0.75, 0.77, 0.8), cloudDark: SIMD3(0.5, 0.52, 0.56),
            sunAzimuth: 1, sunElevation: 0.5, sunColor: SIMD3(0.9, 0.92, 0.95), sunGlow: 0.2,
            sunDisc: false, seed: 81), lighting: 0.7)
        scene.background.contents = UIColor(white: 0.1, alpha: 1)

        buildRoom(root)

        for h in everyone {
            root.addChildNode(h.node)
            h.node.setCastsShadow(true)
        }

        cameraSettings.exposureOffset = 0.2
        cameraSettings.saturation = 0.88
        cameraSettings.contrast = 0.14
        placeCamera(eye: V3(-2, 1.6, 2.4), target: microscopeSpot, fov: 52)
    }

    private func buildRoom(_ root: SCNNode) {
        let w: Float = 12, d: Float = 11, h: Float = 3.4
        let floor = SCNFloor()
        floor.reflectivity = 0.08
        floor.reflectionResolutionScaleFactor = 0.5
        floor.materials = [Materials.pbr(UIColor(hex: 0x9A9488), roughness: 0.35, normal: Textures.asphaltNormal,
                                         normalIntensity: 0.15, tile: 0.5)]
        root.addChildNode(SCNNode(geometry: floor))

        let wall = Materials.pbr(UIColor(hex: 0xD8D2C2), roughness: 0.9, normal: Textures.groundNormal,
                                 normalIntensity: 0.1, tile: 3)
        func panel(_ width: Float, _ pos: V3, _ yaw: Float, _ m: SCNMaterial) {
            let n = SCNNode(SCNPlane(width: CGFloat(width), height: CGFloat(h)), m)
            n.simdPosition = pos
            n.eulerAngles.y = yaw
            root.addChildNode(n)
        }
        panel(w, V3(0, h / 2, -d / 2), 0, wall)
        panel(w, V3(0, h / 2, d / 2), Float.pi, wall)
        panel(d, V3(w / 2, h / 2, 0), -Float.pi / 2, wall)
        let ceiling = SCNNode(SCNPlane(width: CGFloat(w), height: CGFloat(d)),
                              Materials.pbr(UIColor(white: 0.85, alpha: 1), roughness: 0.95))
        ceiling.eulerAngles.x = Float.pi / 2
        ceiling.simdPosition = V3(0, h, 0)
        root.addChildNode(ceiling)

        // Стена с окнами: серое дождливое небо и капли.
        let windowWall = SCNNode(SCNPlane(width: CGFloat(d), height: CGFloat(h)), wall)
        windowWall.simdPosition = V3(-w / 2, h / 2, 0)
        windowWall.eulerAngles.y = Float.pi / 2
        windowWall.castsShadow = false
        root.addChildNode(windowWall)
        let outside = SCNMaterial()
        outside.lightingModel = .constant
        outside.diffuse.contents = Textures.sky(Textures.SkyStyle(
            zenith: SIMD3(0.6, 0.64, 0.68), horizon: SIMD3(0.75, 0.77, 0.78), ground: SIMD3(0.25, 0.3, 0.25),
            cloudCover: 1, cloudLight: SIMD3(0.85, 0.86, 0.88), cloudDark: SIMD3(0.6, 0.62, 0.66),
            sunAzimuth: 0, sunElevation: 0.3, sunColor: SIMD3(1, 1, 1), sunGlow: 0.1, sunDisc: false, seed: 82))
        outside.emission.contents = outside.diffuse.contents
        outside.emission.intensity = 1.2
        let frame = Materials.pbr(UIColor(white: 0.85, alpha: 1), roughness: 0.4, metalness: 0.3)
        for i in 0..<3 {
            let z = -3.4 + Float(i) * 3.4
            let pane = SCNNode(SCNPlane(width: 2.6, height: 1.7), outside)
            pane.simdPosition = V3(-w / 2 + 0.02, 1.9, z)
            pane.eulerAngles.y = Float.pi / 2
            pane.castsShadow = false
            root.addChildNode(pane)
            for dz: Float in [-1.3, 0, 1.3] {
                let m = SCNNode(SCNBox(width: 0.05, height: 1.75, length: 0.05, chamferRadius: 0.005), frame)
                m.simdPosition = V3(-w / 2 + 0.04, 1.9, z + dz)
                root.addChildNode(m)
            }
            let sill = SCNNode(SCNBox(width: 0.25, height: 0.05, length: 2.8, chamferRadius: 0.01), frame)
            sill.simdPosition = V3(-w / 2 + 0.12, 1.03, z)
            root.addChildNode(sill)
        }
        // Холодный дневной свет из окон.
        let daylight = Stage3D.spotLight(color: UIColor(red: 0.82, green: 0.88, blue: 1, alpha: 1), intensity: 7000,
                                         angle: 80, range: 30, shadows: true)
        daylight.simdPosition = V3(-w / 2 - 5, 3.2, 0)
        daylight.simdLook(at: V3(0, 0.5, 0))
        root.addChildNode(daylight)

        // Лампы дневного света.
        let tube = Materials.glow(UIColor(red: 0.92, green: 0.96, blue: 1, alpha: 1), intensity: 2.4, doubleSided: false)
        for (i, z) in [Float(-2.5), 1.5].enumerated() {
            for x: Float in [-2.5, 2.5] {
                let fixture = SCNNode(SCNBox(width: 1.4, height: 0.06, length: 0.3, chamferRadius: 0.02), tube)
                fixture.simdPosition = V3(x, h - 0.05, z)
                root.addChildNode(fixture)
            }
            let l = addOmni(at: V3(0, h - 0.4, z), color: UIColor(red: 0.92, green: 0.95, blue: 1, alpha: 1),
                            intensity: 650, range: 10)
            if i == 1 { flicker = l }
        }
        addAmbient(color: UIColor(red: 0.6, green: 0.62, blue: 0.68, alpha: 1), intensity: 120)

        // Доска.
        let board = SCNNode(SCNBox(width: 5, height: 1.4, length: 0.05, chamferRadius: 0.01),
                            Materials.pbr(UIColor(hex: 0x1F3328), roughness: 0.85))
        board.simdPosition = V3(0, 1.75, -d / 2 + 0.05)
        root.addChildNode(board)
        let chalk = Materials.pbr(UIColor(white: 0.92, alpha: 1), roughness: 0.9)
        chalk.emission.contents = UIColor(white: 0.25, alpha: 1)
        for (row, line) in ["МИТОЗ", "профаза → метафаза → анафаза → телофаза"].enumerated() {
            let text = SCNText(string: line, extrusionDepth: 0.002)
            text.font = UIFont.systemFont(ofSize: row == 0 ? 0.32 : 0.14, weight: row == 0 ? .bold : .regular)
            text.flatness = 0.005
            text.materials = [chalk]
            let t = SCNNode(geometry: text)
            let (mn, mx) = t.boundingBox
            t.pivot = SCNMatrix4MakeTranslation((mx.x - mn.x) / 2 + mn.x, 0, 0)
            t.simdPosition = V3(0, row == 0 ? 2.0 : 1.55, -d / 2 + 0.085)
            root.addChildNode(t)
        }
        // Стол учителя.
        let woodDesk = Materials.wood(tile: 0.6, roughness: 0.45)
        let desk = SCNNode(SCNBox(width: 1.8, height: 0.78, length: 0.8, chamferRadius: 0.02), woodDesk)
        desk.simdPosition = V3(1.6, 0.39, -3.8)
        root.addChildNode(desk)

        // Лабораторные столы: чёрная столешница, деревянные тумбы, табуреты, микроскопы.
        let top = Materials.pbr(UIColor(white: 0.05, alpha: 1), roughness: 0.18)
        top.clearCoat.contents = 1
        let cabinet = Materials.wood(tile: 0.5, roughness: 0.5)
        let metal = Materials.pbr(UIColor(white: 0.25, alpha: 1), roughness: 0.35, metalness: 0.9)
        for row in 0..<3 {
            for col in 0..<2 {
                let center = V3(col == 0 ? -2 : 2, 0, -1.15 + Float(row) * 2.3)
                let slab = SCNNode(SCNBox(width: 2.4, height: 0.05, length: 0.8, chamferRadius: 0.01), top)
                slab.simdPosition = center + V3(0, 0.93, 0)
                root.addChildNode(slab)
                let body = SCNNode(SCNBox(width: 2.3, height: 0.88, length: 0.7, chamferRadius: 0.01), cabinet)
                body.simdPosition = center + V3(0, 0.45, -0.03)
                root.addChildNode(body)
                for dx: Float in [-0.55, 0.55] {
                    let stool = SCNNode()
                    let seat = SCNNode(SCNCylinder(radius: 0.19, height: 0.05),
                                       Materials.pbr(UIColor(hex: 0x3A2A22), roughness: 0.6))
                    seat.simdPosition = V3(0, 0.62, 0)
                    stool.addChildNode(seat)
                    let leg = SCNNode(SCNCylinder(radius: 0.025, height: 0.6), metal)
                    leg.simdPosition = V3(0, 0.3, 0)
                    stool.addChildNode(leg)
                    let ring = SCNNode(SCNTorus(ringRadius: 0.16, pipeRadius: 0.012), metal)
                    ring.simdPosition = V3(0, 0.25, 0)
                    stool.addChildNode(ring)
                    stool.simdPosition = center + V3(dx, 0, 0.6)
                    root.addChildNode(stool)
                }
                root.addChildNode(microscope(at: center + V3(-0.15, 0.955, 0)))
            }
        }

        // Плакаты.
        for (i, color) in [UIColor(hex: 0x3E6A8A), UIColor(hex: 0x8A3E4A), UIColor(hex: 0x4A7A3E)].enumerated() {
            let poster = SCNNode(SCNPlane(width: 0.9, height: 1.2), Materials.pbr(color, roughness: 0.7))
            poster.simdPosition = V3(w / 2 - 0.02, 1.8, -3 + Float(i) * 2.2)
            poster.eulerAngles.y = -Float.pi / 2
            root.addChildNode(poster)
        }
        // Дверь.
        let door = SCNNode(SCNBox(width: 1.0, height: 2.15, length: 0.06, chamferRadius: 0.01),
                           Materials.wood(tile: 0.4, roughness: 0.5))
        door.simdPosition = V3(4.6, 1.075, d / 2 - 0.03)
        root.addChildNode(door)
    }

    private func microscope(at p: V3) -> SCNNode {
        let n = SCNNode()
        let body = Materials.pbr(UIColor(white: 0.92, alpha: 1), roughness: 0.3)
        let black = Materials.pbr(UIColor(white: 0.05, alpha: 1), roughness: 0.25, metalness: 0.4)
        let base = SCNNode(SCNBox(width: 0.16, height: 0.03, length: 0.22, chamferRadius: 0.012), body)
        base.simdPosition = V3(0, 0.015, 0)
        n.addChildNode(base)
        let arm = SCNNode(SCNBox(width: 0.04, height: 0.24, length: 0.05, chamferRadius: 0.012), body)
        arm.simdPosition = V3(0, 0.14, 0.07)
        arm.eulerAngles.x = -0.2
        n.addChildNode(arm)
        let stageNode = SCNNode(SCNBox(width: 0.12, height: 0.012, length: 0.12, chamferRadius: 0.003), black)
        stageNode.simdPosition = V3(0, 0.1, -0.01)
        n.addChildNode(stageNode)
        let tube = SCNNode(SCNCylinder(radius: 0.02, height: 0.16), black)
        tube.simdPosition = V3(0, 0.22, 0.0)
        tube.eulerAngles.x = 0.35
        n.addChildNode(tube)
        let eyepiece = SCNNode(SCNCylinder(radius: 0.014, height: 0.06), black)
        eyepiece.simdPosition = V3(0, 0.31, 0.035)
        eyepiece.eulerAngles.x = 0.35
        n.addChildNode(eyepiece)
        let lamp = SCNNode(SCNSphere(radius: 0.012), Materials.glow(UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1),
                                                                     intensity: 2, doubleSided: false))
        lamp.simdPosition = V3(0, 0.05, -0.01)
        n.addChildNode(lamp)
        n.simdPosition = p
        n.eulerAngles.y = Float.pi
        return n
    }

    // MARK: - Общее

    override var ambience: [SoundFX.Ambience: Float] { [.rain: 0.35, .hum: 0.12] }

    override func updateAmbient(dt: Float) {
        for h in everyone { h.update(dt: dt, time: time) }
        let f: CGFloat = sin(time * 17) + sin(time * 23) > 1.7 ? 120 : 650
        flicker.light?.intensity = f
    }

    private func seatEveryone() {
        bella.place(bellaSeat, yaw: Float.pi)
        bella.snap(.sitChair)
        edward.place(edwardSeat, yaw: Float.pi)
        edward.snap(.sitAloof)
        edward.setEyes(UIColor(white: 0.04, alpha: 1), glow: 0.1)
        mike.place(V3(1.45, 0, 1.75), yaw: Float.pi)
        mike.snap(.sitChair)
        jessica.place(V3(2.55, 0, 1.75), yaw: Float.pi)
        jessica.snap(.sitChair)
        angela.place(V3(-2.55, 0, 4.05), yaw: Float.pi)
        angela.snap(.sitChair)
        banner.place(V3(0.4, 0, -4.2), yaw: 0.15)
        banner.snap(.stand)
        for h in everyone { h.lookAt = nil }
        mike.lookAt = bella.head.simdWorldPosition
        jessica.lookAt = bella.head.simdWorldPosition
    }

    // MARK: - Игра

    override func enterGameplay() {
        seatEveryone()
        edward.setEyes(Cast.topaz, glow: 0.3)
    }

    override func updateGameplay(_ engine: GameEngine, dt: Float) {
        let s = engine.biology
        bella.target = s.stage == .showing ? .sitMicroscope : .sitChair
        bella.rate = 5
        if s.stage == .feedback {
            edward.target = .sitChair
            edward.lookAt = bella.head.simdWorldPosition
            bella.lookAt = s.lastCorrect == true ? edward.head.simdWorldPosition : nil
        } else {
            edward.target = .sitAloof
            edward.lookAt = microscopeSpot
            bella.lookAt = nil
        }
        edward.rate = 4
        banner.lookAt = bella.head.simdWorldPosition
        let c = microscopeSpot + V3(0, 0.2, 0)
        followCamera(eye: c + V3(0.9, 0.55, 1.6), target: c, fov: 46, rate: 2, dt: max(dt, 0.016))
    }

    override func enterIdle() {
        seatEveryone()
        edward.setEyes(Cast.topaz, glow: 0.3)
    }

    override func updateIdle(dt: Float) {
        let a = sin(time * 0.12) * 0.4
        placeCamera(eye: V3(3.5, 2.1, 4.2) + V3(a, 0, 0), target: V3(-1.6, 1.0, -0.8), fov: 54)
    }

    // MARK: - Кат-сцены

    override func beginShot(_ cue: Cue) {
        seatEveryone()
        switch cue {
        case .classBellaEnters:
            bella.place(doorSpot, yaw: Float.pi)
            bella.snap(.stand)
        case .classEdwardStare:
            edward.lookAt = bella.head.simdWorldPosition
        case .classBell, .classEdwardSmile:
            edward.setEyes(Cast.topaz, glow: 0.3)
            if cue == .classBell {
                SoundFX.shared.play(.chime, volume: 0.9)
                edward.snap(.stand)
            } else {
                edward.isHidden = true
            }
        default:
            break
        }
    }

    override func updateShot(_ cue: Cue, progress p: Float, dt: Float) {
        switch cue {
        case .classEstablish:
            dolly(p, eye: (V3(4.5, 2.6, 4.6), V3(2.5, 1.9, 3.2)), look: (V3(-2, 1.4, -2), V3(-1.8, 1.1, -0.8)), fov: (60, 52))
        case .classBellaEnters:
            // Белла идёт от двери к своему месту.
            let t = easeSoft(min(1, p * 1.15))
            let path = mixv(doorSpot, bellaSeat + V3(0, 0, 0.9), t)
            bella.place(path, yaw: yawToward(from: doorSpot, to: bellaSeat) )
            bella.target = t < 1 ? Pose.walk(time * 5) : .stand
            bella.rate = 14
            edward.lookAt = bella.head.simdWorldPosition
            placeCamera(eye: V3(-3.6, 1.5, -0.9), target: bella.head.simdWorldPosition, fov: 40)
        case .classEdwardStare:
            let head = edward.head.simdWorldPosition
            dolly(p, eye: (head + V3(0.4, 0.0, -1.1), head + V3(0.3, -0.02, -0.75)), look: (head, head), fov: (30, 24))
        case .classMicroscope:
            banner.lookAt = V3(-1, 1.2, 0)
            let c = microscopeSpot + V3(0, 0.2, 0)
            dolly(p, eye: (V3(0.4, 1.9, -3.4), c + V3(0.5, 0.35, 0.7)), look: (banner.head.simdWorldPosition, c), fov: (40, 36))
        case .classBell:
            let t = easeSoft(p)
            let from = edwardSeat + V3(0, 0, 0.9)
            let to = doorSpot
            edward.place(mixv(from, to, t), yaw: yawToward(from: from, to: to))
            edward.target = Pose.walk(time * 7)
            edward.rate = 16
            bella.lookAt = edward.head.simdWorldPosition
            placeCamera(eye: V3(-3.4, 1.4, -1.6), target: edward.head.simdWorldPosition, fov: 46)
        case .classEdwardSmile:
            let head = bella.head.simdWorldPosition
            dolly(p, eye: (head + V3(-0.9, 0.05, -1.0), head + V3(-0.7, 0.02, -0.8)), look: (head, head), fov: (32, 26))
        default:
            break
        }
        if cue != .classEdwardSmile { edward.isHidden = false }
    }
}

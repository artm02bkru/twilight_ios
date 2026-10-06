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

    private let bellaSeat = V3(-2.42, 0, 0.48)
    private let edwardSeat = V3(-3.45, 0, 0.48)
    private let microscopeSpot = V3(-2.62, 0.69, 0.0)
    private let doorSpot = V3(3.55, 0, -3.4)
    /// Проход Беллы от двери к месту: вдоль доски, затем по проходу у окон.
    /// Проход Беллы: от двери по свободной полосе перед первой партой (за спиной учителя не проходит),
    /// затем по проходу у окон к своему месту.
    private var bellaPath: [V3] { [doorSpot, V3(1.6, 0, -2.45), V3(-1.46, 0, -2.45), V3(-1.46, 0, 0.66), V3(-1.95, 0, 0.66)] }
    /// Эдвард уходит: за стульями к проходу и к двери.
    private var edwardPath: [V3] { [edwardSeat + V3(0, 0, 0.42), V3(-1.46, 0, 0.88), V3(-1.46, 0, -2.45), V3(1.6, 0, -2.45), doorSpot] }
    private var flicker = SCNNode()

    override init() {
        super.init()
        let root = scene.rootNode

        setSky(Textures.SkyStyle(
            zenith: SIMD3(0.5, 0.54, 0.58), horizon: SIMD3(0.66, 0.68, 0.7), ground: SIMD3(0.3, 0.3, 0.3),
            cloudCover: 1, cloudLight: SIMD3(0.75, 0.77, 0.8), cloudDark: SIMD3(0.5, 0.52, 0.56),
            sunAzimuth: 1, sunElevation: 0.5, sunColor: SIMD3(0.9, 0.92, 0.95), sunGlow: 0.2,
            sunDisc: false, seed: 81), lighting: 0.35)
        scene.background.contents = UIColor(white: 0.1, alpha: 1)

        buildRoom(root)

        for h in everyone {
            root.addChildNode(h.node)
            h.node.setCastsShadow(true)
        }

        cameraSettings.exposureOffset = -0.45
        cameraSettings.bloomIntensity = 0.25
        cameraSettings.bloomThreshold = 1.2
        cameraSettings.saturation = 0.88
        cameraSettings.contrast = 0.14
        placeCamera(eye: V3(-1.7, 1.5, 2.4), target: microscopeSpot, fov: 52)
    }

    /// Кабинет из модели classroom.tmdl: доска впереди (−Z), окна слева (−X), дверь у доски справа.
    /// Пол на y = 0, столы 0.69 м, сиденья стульев 0.42 м.
    private func buildRoom(_ root: SCNNode) {
        if let model = ModelAsset.named("classroom") {
            let room = model.wholeNode { d in Self.roomMaterial(d) }
            room.childNodes.forEach { $0.castsShadow = $0.name != "windows" }
            root.addChildNode(room)
        }

        // За окнами — серое дождливое небо Форкса.
        let outside = SCNMaterial()
        outside.lightingModel = .constant
        outside.diffuse.contents = Textures.sky(Textures.SkyStyle(
            zenith: SIMD3(0.6, 0.64, 0.68), horizon: SIMD3(0.75, 0.77, 0.78), ground: SIMD3(0.22, 0.28, 0.22),
            cloudCover: 1, cloudLight: SIMD3(0.85, 0.86, 0.88), cloudDark: SIMD3(0.6, 0.62, 0.66),
            sunAzimuth: 0, sunElevation: 0.3, sunColor: SIMD3(1, 1, 1), sunGlow: 0.1, sunDisc: false, seed: 82))
        outside.emission.contents = outside.diffuse.contents
        outside.emission.intensity = 0.55
        let view = SCNNode(SCNPlane(width: 14, height: 4.5), outside)
        view.simdPosition = V3(-4.9, 1.6, 0.9)
        view.eulerAngles.y = Float.pi / 2
        view.castsShadow = false
        root.addChildNode(view)

        // Холодный дневной свет сквозь окна.
        let daylight = Stage3D.spotLight(color: UIColor(red: 0.82, green: 0.88, blue: 1, alpha: 1), intensity: 1200,
                                         angle: 80, range: 30, shadows: true)
        daylight.light?.shadowColor = UIColor(white: 0, alpha: 0.35)
        daylight.simdPosition = V3(-10, 3.4, 1.0)
        daylight.simdLook(at: V3(0, 0.3, 1.0))
        root.addChildNode(daylight)

        // Лампы дневного света под потолком.
        for (i, z) in [Float(-1.6), 2.6].enumerated() {
            let l = addOmni(at: V3(0, 2.4, z), color: UIColor(red: 0.92, green: 0.95, blue: 1, alpha: 1),
                            intensity: 380, range: 12)
            if i == 1 { flicker = l }
        }
        addAmbient(color: UIColor(red: 0.6, green: 0.62, blue: 0.68, alpha: 1), intensity: 90)

        // На доске — тема урока, синим маркером.
        let marker = Materials.pbr(UIColor(hex: 0x1B2A6B), roughness: 0.5)
        for (row, line) in ["МИТОЗ", "профаза → метафаза → анафаза → телофаза"].enumerated() {
            let text = SCNText(string: line, extrusionDepth: 0.001)
            text.font = UIFont.systemFont(ofSize: row == 0 ? 0.26 : 0.12, weight: row == 0 ? .bold : .regular)
            text.flatness = 0.005
            text.materials = [marker]
            let t = SCNNode(geometry: text)
            let (mn, mx) = t.boundingBox
            t.pivot = SCNMatrix4MakeTranslation((mx.x - mn.x) / 2 + mn.x, 0, 0)
            t.simdPosition = V3(0, row == 0 ? 1.6 : 1.3, -4.08)
            root.addChildNode(t)
        }

        // Микроскопы на передних партах; у Беллы и Эдварда — свой.
        root.addChildNode(microscope(at: microscopeSpot, yaw: 0.1))
        for gz: Float in [-1.36, 0.0] {
            for gx: Float in [2.95, 0.05, -3.25] where !(gz == 0 && gx < 0) {
                root.addChildNode(microscope(at: V3(gx, 0.69, gz), yaw: gx * 0.13))
            }
        }
    }

    /// Материалы класса: текстуры автора в файл не вошли — даём свои.
    private static func roomMaterial(_ d: ModelAsset.Material) -> SCNMaterial? {
        switch d.name {
        case "Ground":
            let m = Materials.pbr(UIColor(hex: 0x8E8A80), roughness: 0.32, normal: Textures.groundNormal,
                                  normalIntensity: 0.12, tile: 20)
            m.clearCoat.contents = 0.3
            return m
        case "roof.001":
            return Materials.pbr(UIColor(white: 0.86, alpha: 1), roughness: 0.92, normal: Textures.groundNormal,
                                 normalIntensity: 0.2, tile: 14)
        case "wall":
            return Materials.pbr(UIColor(hex: 0xB9B3A2), roughness: 0.88, normal: Textures.groundNormal,
                                 normalIntensity: 0.1, tile: 5)
        case "Wood", "Wood.001":
            return Materials.wood(tile: 1.5, roughness: 0.42)
        case "wood":
            return Materials.wood(tile: 2, roughness: 0.5)
        case "Glass.002":
            let m = Materials.pbr(UIColor(white: 1, alpha: 1), roughness: 0.02)
            m.transparency = 0.12
            m.transparencyMode = .dualLayer
            m.isDoubleSided = true
            return m
        case "EMMISION":
            let m = Materials.pbr(UIColor(white: 1, alpha: 1), roughness: 0.3)
            m.emission.contents = UIColor(red: 0.92, green: 0.96, blue: 1, alpha: 1)
            m.emission.intensity = 0.9
            return m
        case "WHITE.001":
            let m = Materials.pbr(UIColor(white: 0.95, alpha: 1), roughness: 0.12)
            m.clearCoat.contents = 0.6
            return m
        case "Material":
            // Табличка «Выход».
            let m = Materials.pbr(UIColor(hex: 0x1E8A3A), roughness: 0.4)
            m.emission.contents = UIColor(hex: 0x2EC25A)
            m.emission.intensity = 0.8
            return m
        case "toetsenbord":
            return Materials.pbr(UIColor(white: 0.12, alpha: 1), roughness: 0.6)
        default:
            return nil
        }
    }

    /// Школьный микроскоп (модель microscope.tmdl), основание — в точке p.
    private func microscope(at p: V3, yaw: Float) -> SCNNode {
        let n = SCNNode()
        if let model = ModelAsset.named("microscope"), let part = model.parts["microscope"],
           let body = model.node("microscope", material: { d in
               switch d.name {
               case "chrome": return Materials.chrome()
               case "mirror": return Materials.mirror()
               default: return nil
               }
           }) {
            // Ставим на стол низом основания.
            body.simdPosition = V3(0, -part.boundsMin.y, 0)
            body.castsShadow = true
            n.addChildNode(body)
        }
        n.simdPosition = p
        n.eulerAngles.y = yaw
        return n
    }

    // MARK: - Общее

    override var ambience: [SoundFX.Ambience: Float] { [.rain: 0.35, .hum: 0.12] }

    override func updateAmbient(dt: Float) {
        for h in everyone { h.update(dt: dt, time: time) }
        let f: CGFloat = sin(time * 17) + sin(time * 23) > 1.7 ? 110 : 380
        flicker.light?.intensity = f
    }

    private func seatEveryone() {
        bella.place(bellaSeat, yaw: Float.pi)
        bella.snap(.sitDesk)
        edward.place(edwardSeat, yaw: Float.pi)
        edward.snap(.sitDeskAloof)
        edward.setEyes(UIColor(white: 0.04, alpha: 1), glow: 0.1)
        mike.place(V3(0.53, 0, 1.8), yaw: Float.pi)
        mike.snap(.sitDesk)
        jessica.place(V3(-0.5, 0, 1.8), yaw: Float.pi)
        jessica.snap(.sitDesk)
        angela.place(V3(-3.45, 0, 3.34), yaw: Float.pi)
        angela.snap(.sitDesk)
        banner.place(V3(0.3, 0, -3.2), yaw: 0.15)
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
        bella.target = s.stage == .showing ? .sitDeskMicroscope : .sitDesk
        bella.rate = 5
        if s.stage == .feedback {
            edward.target = .sitDesk
            edward.lookAt = bella.head.simdWorldPosition
            bella.lookAt = s.lastCorrect == true ? edward.head.simdWorldPosition : nil
        } else {
            edward.target = .sitDeskAloof
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
        // Ровный кадр через класс на парту Беллы и Эдварда, без наклона.
        placeCamera(eye: V3(-2.6 + a * 0.3, 1.6, 2.25), target: V3(-2.9 + a * 0.3, 0.95, 0.25), fov: 50)
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
            dolly(p, eye: (V3(3.3, 2.3, 5.4), V3(2.2, 1.8, 3.8)), look: (V3(-2.6, 1.0, -1.0), V3(-2.6, 0.9, 0.2)), fov: (60, 52))
        case .classBellaEnters:
            // Белла идёт от двери к своему месту.
            let t = easeSoft(min(1, p * 1.15))
            let (pos, dir) = along(bellaPath, t)
            bella.place(pos, yaw: atan2(dir.x, dir.z))
            bella.target = t < 1 ? Pose.walk(time * 5) : .stand
            bella.rate = 14
            edward.lookAt = bella.head.simdWorldPosition
            placeCamera(eye: V3(-3.5, 1.5, -0.68), target: bella.head.simdWorldPosition, fov: 40)
        case .classEdwardStare:
            let head = edward.head.simdWorldPosition
            dolly(p, eye: (head + V3(0.4, 0.0, -1.1), head + V3(0.3, -0.02, -0.75)), look: (head, head), fov: (30, 24))
        case .classMicroscope:
            banner.lookAt = V3(-1, 1.2, 0)
            let c = microscopeSpot + V3(0, 0.2, 0)
            dolly(p, eye: (V3(0.4, 1.9, -3.4), c + V3(0.5, 0.35, 0.7)), look: (banner.head.simdWorldPosition, c), fov: (40, 36))
        case .classBell:
            let t = easeSoft(p)
            let (pos, dir) = along(edwardPath, t)
            edward.place(pos, yaw: atan2(dir.x, dir.z))
            edward.target = Pose.walk(time * 7)
            edward.rate = 16
            bella.lookAt = edward.head.simdWorldPosition
            placeCamera(eye: V3(-3.6, 1.55, -0.65), target: edward.head.simdWorldPosition, fov: 46)
        case .classEdwardSmile:
            let head = bella.head.simdWorldPosition
            dolly(p, eye: (head + V3(-0.9, 0.05, -1.0), head + V3(-0.7, 0.02, -0.8)), look: (head, head), fov: (32, 26))
        default:
            break
        }
        if cue != .classEdwardSmile { edward.isHidden = false }
    }

    /// Точка на ломаной при доле пути t (0...1) и направление движения.
    private func along(_ pts: [V3], _ t: Float) -> (V3, V3) {
        var lengths: [Float] = []
        for i in 1..<pts.count { lengths.append(simd_length(pts[i] - pts[i - 1])) }
        var d = clampf(t, 0, 1) * lengths.reduce(0, +)
        for i in 0..<lengths.count {
            if d <= lengths[i] || i == lengths.count - 1 {
                let k = lengths[i] > 0 ? min(1, d / lengths[i]) : 1
                let dir = simd_normalize(pts[i + 1] - pts[i] + V3(0, 0, 1e-5))
                return (mixv(pts[i], pts[i + 1], k), dir)
            }
            d -= lengths[i]
        }
        return (pts.last ?? .zero, V3(0, 0, -1))
    }
}

/// Позы за обычной партой: стул ниже лабораторного табурета (сиденье 0.42 м).
private extension Pose {
    static let sitDesk: Pose = { var p = Pose.sitChair; p.rootY = -0.38; return p }()
    static let sitDeskMicroscope: Pose = { var p = Pose.sitMicroscope; p.rootY = -0.38; return p }()
    static let sitDeskAloof: Pose = { var p = Pose.sitAloof; p.rootY = -0.38; return p }()
}

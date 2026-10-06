import SceneKit
import UIKit
import simd

/// Машина: обтекаемый кузов (гладкая сетка из поля расстояний), колёса, фары.
/// Перёд — по +Z, ширина — по X, низ колёс — y = 0.
final class Vehicle {

    enum Slot: Int { case paint = 0, glass, chrome, trim, headlight, taillight, interior }

    let node = SCNNode()
    let bodyNode: SCNNode
    private(set) var wheels: [SCNNode] = []
    private(set) var headlights: [SCNNode] = []
    let paint: SCNMaterial
    /// Материалы, которые светятся сильнее при включённых фарах.
    private var lampMaterials: [SCNMaterial] = []
    private let wheelRadius: Float

    init(mesh: MeshData, paintColor: UIColor, wheelSpots: [V3], wheelRadius: Float,
         headlightSpots: [V3], metallic: CGFloat = 0.45) {
        paint = Materials.carPaint(paintColor, metallic: metallic)
        let headlightMaterial = Materials.pbr(UIColor(white: 1, alpha: 1), roughness: 0.05)
        lampMaterials = [headlightMaterial]
        headlightMaterial.emission.contents = UIColor(red: 1, green: 0.93, blue: 0.8, alpha: 1)
        headlightMaterial.emission.intensity = 0.2
        let tail = Materials.pbr(UIColor(red: 0.5, green: 0.02, blue: 0.02, alpha: 1), roughness: 0.1)
        tail.emission.contents = UIColor(red: 1, green: 0.05, blue: 0.04, alpha: 1)
        tail.emission.intensity = 0.4
        let trim = Materials.pbr(UIColor(white: 0.05, alpha: 1), roughness: 0.55)
        let interior = Materials.pbr(UIColor(white: 0.04, alpha: 1), roughness: 0.9)
        let glass = Materials.tintedGlass()

        bodyNode = SCNNode(geometry: mesh.geometry(materials: [
            paint, glass, Materials.chrome(), trim, headlightMaterial, tail, interior
        ]))
        bodyNode.castsShadow = true
        node.addChildNode(bodyNode)
        self.wheelRadius = wheelRadius

        // Колёса: покрышка-тор, диск, колпак.
        for spot in wheelSpots {
            let wheel = SCNNode()
            wheel.simdPosition = spot
            let tire = SCNTorus(ringRadius: CGFloat(wheelRadius * 0.68), pipeRadius: CGFloat(wheelRadius * 0.32))
            tire.ringSegmentCount = 36
            tire.pipeSegmentCount = 16
            let rubber = Materials.rubber()
            rubber.normal.contents = Textures.tireTread
            rubber.normal.intensity = 0.9
            rubber.normal.contentsTransform = SCNMatrix4MakeScale(1, 6, 1)
            rubber.normal.wrapS = .repeat
            rubber.normal.wrapT = .repeat
            let tireNode = SCNNode(tire, rubber)
            tireNode.eulerAngles.z = Float.pi / 2
            wheel.addChildNode(tireNode)
            let rim = SCNCylinder(radius: CGFloat(wheelRadius * 0.55), height: CGFloat(wheelRadius * 0.5))
            rim.radialSegmentCount = 28
            let rimNode = SCNNode(rim, Materials.pbr(UIColor(white: 0.55, alpha: 1), roughness: 0.3, metalness: 0.9))
            rimNode.eulerAngles.z = Float.pi / 2
            wheel.addChildNode(rimNode)
            // Спицы диска и болты.
            let outward: Float = spot.x > 0 ? 1 : -1
            let spokeMat = Materials.pbr(UIColor(white: 0.7, alpha: 1), roughness: 0.25, metalness: 0.95)
            for k in 0..<6 {
                let a = Float(k) / 6 * 2 * Float.pi
                let spoke = SCNNode(SCNBox(width: 0.02, height: CGFloat(wheelRadius * 0.95), length: 0.05, chamferRadius: 0.008),
                                    spokeMat)
                spoke.simdPosition = V3(outward * wheelRadius * 0.26, 0, 0)
                spoke.simdEulerAngles = V3(a, 0, 0)
                wheel.addChildNode(spoke)
                let nut = SCNNode(SCNCylinder(radius: 0.011, height: 0.02), Materials.chrome())
                nut.simdPosition = V3(outward * wheelRadius * 0.28, sin(a) * wheelRadius * 0.12, cos(a) * wheelRadius * 0.12)
                nut.eulerAngles.z = Float.pi / 2
                wheel.addChildNode(nut)
            }
            let cap = SCNSphere(radius: CGFloat(wheelRadius * 0.22))
            let capNode = SCNNode(cap, Materials.chrome())
            capNode.simdScale = V3(0.5, 1, 1)
            capNode.simdPosition = V3((spot.x > 0 ? 1 : -1) * wheelRadius * 0.26, 0, 0)
            wheel.addChildNode(capNode)
            node.addChildNode(wheel)
            wheels.append(wheel)
        }

        addDetails(length: wheelSpots.map { abs($0.z) }.max() ?? 1.5)

        for spot in headlightSpots {
            let lamp = Stage3D.spotLight(color: UIColor(red: 1, green: 0.92, blue: 0.78, alpha: 1),
                                         intensity: 0, angle: 55, range: 45)
            lamp.simdPosition = spot
            lamp.simdLook(at: spot + V3(0, -0.6, 10))
            node.addChildNode(lamp)
            headlights.append(lamp)
        }
    }

    /// Машина из готовой модели: кузов — часть «body», колёса — отдельные части с осью в центре.
    init(model: ModelAsset, paintColor: UIColor, metallic: CGFloat, wheelParts: [String],
         headlightSpots: [V3], materials: @escaping (ModelAsset.Material) -> SCNMaterial?) {
        let paint = Materials.carPaint(paintColor, metallic: metallic)
        self.paint = paint
        let lamp = Materials.pbr(UIColor(white: 0.95, alpha: 1), roughness: 0.1)
        lamp.emission.contents = UIColor(red: 1, green: 0.93, blue: 0.8, alpha: 1)
        lamp.emission.intensity = 0.2
        var lamps = [lamp]
        let pick: (ModelAsset.Material) -> SCNMaterial? = { d in
            switch d.name {
            case "Car Paint": return paint
            case "Light": return lamp
            case "Lights":
                // Атлас фар и фонарей: светится сам по себе.
                let m = ModelAsset.defaultMaterial(d)
                m.emission.contents = m.diffuse.contents
                m.emission.intensity = 0.2
                lamps.append(m)
                return m
            default: return materials(d)
            }
        }
        bodyNode = model.node("body", material: pick) ?? SCNNode()
        bodyNode.castsShadow = true
        node.addChildNode(bodyNode)
        var radius: Float = 0.38
        var wheelNodes: [SCNNode] = []
        for name in wheelParts {
            guard let wheel = model.node(name, material: pick), let part = model.parts[name] else { continue }
            radius = (part.boundsMax.y - part.boundsMin.y) / 2
            wheel.castsShadow = true
            wheelNodes.append(wheel)
        }
        wheelRadius = radius
        wheels = wheelNodes
        for w in wheelNodes { node.addChildNode(w) }
        lampMaterials = lamps

        for spot in headlightSpots {
            let light = Stage3D.spotLight(color: UIColor(red: 1, green: 0.92, blue: 0.78, alpha: 1),
                                          intensity: 0, angle: 55, range: 45)
            light.simdPosition = spot
            light.simdLook(at: spot + V3(0, -0.6, 10))
            node.addChildNode(light)
            headlights.append(light)
        }
    }

    /// Мелочи, без которых машина выглядит игрушкой: ручки, зеркала, номера, дворники, антенна, выхлоп.
    private func addDetails(length: Float) {
        let chrome = Materials.chrome()
        let black = Materials.pbr(UIColor(white: 0.04, alpha: 1), roughness: 0.4)
        let (bmin, bmax) = bodyNode.boundingBox
        let halfW = max(abs(bmin.x), abs(bmax.x))
        let front = bmax.z, back = bmin.z, roof = bmax.y

        // Дверные ручки.
        for side: Float in [-1, 1] {
            for z: Float in [0.25, -0.75] where z < front - 0.8 {
                let handle = SCNNode(SCNBox(width: 0.03, height: 0.03, length: 0.16, chamferRadius: 0.012), chrome)
                handle.simdPosition = V3(side * (halfW - 0.005), roof * 0.66, z)
                bodyNode.addChildNode(handle)
            }
            // Зеркало заднего вида.
            let arm = SCNNode(SCNBox(width: 0.12, height: 0.03, length: 0.04, chamferRadius: 0.01), black)
            arm.simdPosition = V3(side * (halfW + 0.04), roof * 0.78, front * 0.38)
            bodyNode.addChildNode(arm)
            let mirror = SCNNode(SCNBox(width: 0.06, height: 0.12, length: 0.18, chamferRadius: 0.025), paint)
            mirror.simdPosition = V3(side * (halfW + 0.11), roof * 0.79, front * 0.38)
            bodyNode.addChildNode(mirror)
            let glass = SCNNode(SCNPlane(width: 0.14, height: 0.09), Materials.mirror())
            glass.simdPosition = V3(side * (halfW + 0.11), roof * 0.79, front * 0.38 - 0.092)
            glass.eulerAngles.y = Float.pi
            bodyNode.addChildNode(glass)
        }
        // Номера спереди и сзади.
        let plateMat = Materials.pbr(Textures.plate(["FRK 053", "TYL 921", "CLN 001", "WA 4417"].randomElement() ?? "FRK 053"),
                                     roughness: 0.35, metalness: 0.3)
        for (z, yaw) in [(front + 0.012, Float(0)), (back - 0.012, Float.pi)] {
            let plate = SCNNode(SCNPlane(width: 0.32, height: 0.16), plateMat)
            plate.simdPosition = V3(0, 0.45, z)
            plate.eulerAngles.y = yaw
            bodyNode.addChildNode(plate)
        }
        // Дворники на лобовом стекле.
        for x: Float in [-0.25, 0.3] {
            let wiper = SCNNode(SCNBox(width: 0.55, height: 0.012, length: 0.02, chamferRadius: 0.004), black)
            wiper.simdPosition = V3(x, roof * 0.7, front * 0.42)
            wiper.eulerAngles = SCNVector3(-0.5, 0, 0.25)
            bodyNode.addChildNode(wiper)
        }
        // Антенна и выхлопная труба.
        let antenna = SCNNode(SCNCylinder(radius: 0.004, height: 0.55), black)
        antenna.simdPosition = V3(halfW * 0.6, roof + 0.2, back * 0.6)
        bodyNode.addChildNode(antenna)
        let exhaust = SCNNode(SCNCylinder(radius: 0.035, height: 0.25), chrome)
        exhaust.simdPosition = V3(-halfW * 0.55, 0.28, back - 0.02)
        exhaust.eulerAngles.x = Float.pi / 2
        bodyNode.addChildNode(exhaust)
        _ = length
    }

    /// Включить фары (0...1).
    func setHeadlights(_ value: Float) {
        for m in lampMaterials { m.emission.intensity = CGFloat(0.2 + value * 4) }
        for lamp in headlights { lamp.light?.intensity = CGFloat(value * 2200) }
    }

    /// Провернуть колёса на пройденное расстояние.
    func roll(distance: Float) {
        for wheel in wheels {
            wheel.simdEulerAngles.x += distance / wheelRadius
        }
    }

    // MARK: - Модели

    /// Пикап Беллы — старый «Шевроле» 50-х: круглые крылья, хром, ржаво-красный.
    static func pickup() -> Vehicle {
        if let model = ModelAsset.named("bella_truck") { return importedPickup(model) }
        let mesh = MeshCache.mesh("veh-pickup") {
            let m = SDFModel()
            let paint = Slot.paint.rawValue, glass = Slot.glass.rawValue
            let chrome = Slot.chrome.rawValue, trim = Slot.trim.rawValue
            m.box(V3(0, 0.8, -0.1), V3(0.86, 0.26, 2.35), round: 0.12, slot: paint, blend: 0.06)
            m.box(V3(0, 1.02, 1.45), V3(0.72, 0.15, 0.8), round: 0.15, slot: paint, blend: 0.14)
            for s: Float in [1, -1] {
                m.ellipsoid(V3(s * 0.78, 0.86, 1.5), V3(0.26, 0.34, 0.66), slot: paint, blend: 0.14)
                m.ellipsoid(V3(s * 0.84, 0.82, -1.5), V3(0.2, 0.3, 0.56), slot: paint, blend: 0.1)
            }
            m.box(V3(0, 1.42, 0.3), V3(0.76, 0.36, 0.6), round: 0.22, slot: paint, blend: 0.12)
            // Кузов-платформа: вырез сверху.
            m.box(V3(0, 1.08, -1.35), V3(0.78, 0.3, 1.0), round: 0.03, slot: paint, blend: 0.03, subtract: true)
            // Колёсные арки.
            for s: Float in [1, -1] {
                for z: Float in [1.5, -1.5] {
                    m.ellipsoid(V3(s * 0.9, 0.42, z), V3(0.32, 0.46, 0.5), slot: paint, blend: 0.03, subtract: true)
                }
            }
            // Окна: углубление и стекло.
            m.box(V3(0, 1.58, 0.9), V3(0.64, 0.17, 0.1), round: 0.05, rotation: V3(-0.3, 0, 0),
                  slot: paint, blend: 0.02, subtract: true)
            m.box(V3(0, 1.58, 0.86), V3(0.64, 0.17, 0.03), round: 0.012, rotation: V3(-0.3, 0, 0),
                  slot: glass, blend: 0.002)
            for s: Float in [1, -1] {
                m.box(V3(s * 0.8, 1.58, 0.3), V3(0.1, 0.17, 0.42), round: 0.05, slot: paint, blend: 0.02, subtract: true)
                m.box(V3(s * 0.74, 1.58, 0.3), V3(0.03, 0.17, 0.42), round: 0.012, slot: glass, blend: 0.002)
            }
            m.box(V3(0, 1.6, -0.3), V3(0.55, 0.14, 0.08), round: 0.04, slot: paint, blend: 0.02, subtract: true)
            m.box(V3(0, 1.6, -0.26), V3(0.55, 0.14, 0.03), round: 0.012, slot: glass, blend: 0.002)
            // Решётка, бамперы, подножки.
            m.box(V3(0, 0.88, 2.28), V3(0.55, 0.16, 0.05), round: 0.03, slot: chrome, blend: 0.012)
            for i in 0..<3 {
                m.box(V3(0, 0.78 + Float(i) * 0.1, 2.33), V3(0.5, 0.022, 0.03), round: 0.01, slot: chrome, blend: 0.004)
            }
            m.capsule(V3(-0.92, 0.55, 2.38), V3(0.92, 0.55, 2.38), 0.07, 0.07, slot: chrome, blend: 0.01)
            m.capsule(V3(-0.92, 0.55, -2.48), V3(0.92, 0.55, -2.48), 0.07, 0.07, slot: chrome, blend: 0.01)
            for s: Float in [1, -1] {
                m.box(V3(s * 0.92, 0.5, 0.0), V3(0.1, 0.025, 0.85), round: 0.02, slot: trim, blend: 0.02)
                m.ellipsoid(V3(s * 0.78, 1.1, 2.08), V3(0.12, 0.12, 0.08), slot: Slot.headlight.rawValue, blend: 0.02)
                m.ellipsoid(V3(s * 0.84, 0.98, -2.42), V3(0.05, 0.08, 0.03), slot: Slot.taillight.rawValue, blend: 0.01)
            }
            // Тёмный салон за стёклами.
            m.box(V3(0, 1.35, 0.3), V3(0.66, 0.25, 0.48), round: 0.05, slot: Slot.interior.rawValue, blend: 0.0)
            return m.mesh(cell: 0.017, uvScale: 1)
        }
        let v = Vehicle(mesh: mesh, paintColor: UIColor(hex: 0x7A1E16),
                        wheelSpots: [V3(0.8, 0.4, 1.5), V3(-0.8, 0.4, 1.5), V3(0.84, 0.4, -1.5), V3(-0.84, 0.4, -1.5)],
                        wheelRadius: 0.4,
                        headlightSpots: [V3(0.78, 1.1, 2.15), V3(-0.78, 1.1, 2.15)],
                        metallic: 0.2)
        // Выцветшая краска: шероховатее, чем у новых машин.
        v.paint.roughness.contents = 0.45
        v.paint.clearCoatRoughness.contents = 0.25
        return v
    }

    /// Пикап Беллы из модели «1959 Chevrolet Apache» (автор ojosamson527, CGTrader):
    /// выцветший красный, хром, фары-атлас, надписи на шинах.
    private static func importedPickup(_ model: ModelAsset) -> Vehicle {
        let v = Vehicle(model: model, paintColor: UIColor(hex: 0x7A1E16), metallic: 0.2,
                        wheelParts: ["wheelFL", "wheelFR", "wheelRL", "wheelRR"],
                        headlightSpots: [V3(0.72, 0.97, 2.0), V3(-0.72, 0.97, 2.0)]) { d in
            switch d.name {
            case "Chrome": return Materials.chrome()
            case "Chrome frosted": return Materials.pbr(UIColor(white: 0.62, alpha: 1), roughness: 0.32, metalness: 1)
            case "Black rubber": return Materials.rubber()
            case "Tire":
                // Боковина с надписями: белые буквы приглушаем до серой резины.
                let m = Materials.rubber()
                if let file = d.texture, let img = ModelAsset.image(file) {
                    m.diffuse.contents = img
                    m.multiply.contents = UIColor(white: 0.32, alpha: 1)
                }
                return m
            case "Glass": return Materials.tintedGlass()
            case "Headlight Glass":
                let m = Materials.pbr(UIColor(white: 1, alpha: 1), roughness: 0.02)
                m.transparency = 0.18
                m.transparencyMode = .dualLayer
                return m
            case "Mirror": return Materials.mirror()
            case "Black metal": return Materials.pbr(UIColor(white: 0.05, alpha: 1), roughness: 0.45, metalness: 0.8)
            case "WoodP": return Materials.pbr(UIColor(hex: 0x5A3E28), roughness: 0.7)
            default: return nil
            }
        }
        // Выцветшая краска: шероховатее, чем у новых машин.
        v.paint.roughness.contents = 0.45
        v.paint.clearCoatRoughness.contents = 0.25
        return v
    }

    /// Синий пикап из модели «Vehicle SUV» (одна сетка с текстурным атласом) — для парковок и трассы.
    /// tint затемняет или осветляет атлас, чтобы машины не были одинаковыми.
    static func suv(tint: UIColor? = nil, headlights: Bool = false) -> Vehicle? {
        guard let model = ModelAsset.named("suv") else { return nil }
        let spots: [V3] = headlights ? [V3(0.62, 0.78, 2.0), V3(-0.62, 0.78, 2.0)] : []
        let v = Vehicle(model: model, paintColor: .white, metallic: 0, wheelParts: [], headlightSpots: spots) { d in
            let m = ModelAsset.defaultMaterial(d)
            m.roughness.contents = 0.42
            m.clearCoat.contents = 0.4
            if let tint { m.multiply.contents = tint }
            return m
        }
        if headlights {
            // Видимые фары: светящиеся диски на передке.
            let glass = Materials.glow(UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1), intensity: 2.5, doubleSided: false)
            for x: Float in [0.62, -0.62] {
                let lamp = SCNNode(SCNPlane(width: 0.26, height: 0.14), glass)
                lamp.simdPosition = V3(x, 0.8, 1.975)
                v.node.addChildNode(lamp)
            }
        }
        return v
    }

    /// Машина Эдварда — синий пикап; если модели нет, серебристый седан.
    static func edwardsCar() -> Vehicle {
        suv(headlights: true) ?? sedan(color: UIColor(hex: 0xB9BEC4), metallic: 0.85)
    }

    /// Фургон Тайлера — высокий, с длинной полосой окон.
    static func van() -> Vehicle {
        let mesh = MeshCache.mesh("veh-van") {
            let m = SDFModel()
            let paint = Slot.paint.rawValue, glass = Slot.glass.rawValue, trim = Slot.trim.rawValue
            m.box(V3(0, 1.22, -0.1), V3(0.96, 0.72, 2.3), round: 0.3, slot: paint, blend: 0.05)
            m.box(V3(0, 0.9, 2.05), V3(0.93, 0.42, 0.42), round: 0.3, slot: paint, blend: 0.25)
            for s: Float in [1, -1] {
                for z: Float in [1.6, -1.55] {
                    m.ellipsoid(V3(s * 0.98, 0.42, z), V3(0.3, 0.46, 0.5), slot: paint, blend: 0.03, subtract: true)
                }
            }
            // Лобовое стекло.
            m.box(V3(0, 1.58, 2.0), V3(0.84, 0.3, 0.1), round: 0.06, rotation: V3(-0.55, 0, 0),
                  slot: paint, blend: 0.02, subtract: true)
            m.box(V3(0, 1.58, 1.96), V3(0.84, 0.3, 0.03), round: 0.012, rotation: V3(-0.55, 0, 0),
                  slot: glass, blend: 0.002)
            // Боковая полоса окон.
            for s: Float in [1, -1] {
                m.box(V3(s * 0.98, 1.58, 0.15), V3(0.08, 0.22, 1.75), round: 0.08, slot: paint, blend: 0.02, subtract: true)
                m.box(V3(s * 0.92, 1.58, 0.15), V3(0.03, 0.22, 1.75), round: 0.012, slot: glass, blend: 0.002)
                // Молдинг вдоль борта.
                m.box(V3(s * 0.97, 0.95, -0.05), V3(0.02, 0.03, 2.1), round: 0.01, slot: trim, blend: 0.004)
                m.ellipsoid(V3(s * 0.62, 0.98, 2.43), V3(0.14, 0.09, 0.05), slot: Slot.headlight.rawValue, blend: 0.02)
                m.ellipsoid(V3(s * 0.85, 1.0, -2.4), V3(0.07, 0.14, 0.03), slot: Slot.taillight.rawValue, blend: 0.01)
            }
            m.box(V3(0, 1.4, -2.38), V3(0.7, 0.25, 0.04), round: 0.04, slot: glass, blend: 0.004)
            m.box(V3(0, 0.55, 2.48), V3(0.95, 0.1, 0.07), round: 0.05, slot: trim, blend: 0.02)
            m.box(V3(0, 0.55, -2.42), V3(0.95, 0.1, 0.07), round: 0.05, slot: trim, blend: 0.02)
            m.box(V3(0, 0.82, 2.46), V3(0.5, 0.1, 0.03), round: 0.02, slot: trim, blend: 0.006)
            m.box(V3(0, 1.4, 0.1), V3(0.84, 0.3, 2.0), round: 0.05, slot: Slot.interior.rawValue, blend: 0)
            return m.mesh(cell: 0.017, uvScale: 1)
        }
        let v = Vehicle(mesh: mesh, paintColor: UIColor(hex: 0x2C4A5E),
                        wheelSpots: [V3(0.88, 0.4, 1.6), V3(-0.88, 0.4, 1.6), V3(0.88, 0.4, -1.55), V3(-0.88, 0.4, -1.55)],
                        wheelRadius: 0.4,
                        headlightSpots: [V3(0.62, 0.98, 2.5), V3(-0.62, 0.98, 2.5)])
        // Вмятина от ладони — смещение вершин в шейдере, сила задаётся из игры.
        v.paint.shaderModifiers = [.geometry: """
        #pragma arguments
        float dentAmount;
        #pragma body
        float3 dp = _geometry.position.xyz - float3(-0.98, 1.15, 0.0);
        float3 sp = dp * float3(0.6, 1.0, 0.8);
        float dd = dot(sp, sp);
        // Глубокая вмятина от ладони и мелкая рябь смятого металла вокруг.
        float h = dentAmount * (0.3 * exp(-dd / 0.16) + 0.025 * sin(sqrt(dd) * 40.0) * exp(-dd / 0.3));
        _geometry.position.x += h;
        // Нормаль наклоняем по склону вмятины — тогда она читается светом и тенью.
        float slope = -2.0 / 0.16 * dentAmount * 0.3 * exp(-dd / 0.16);
        _geometry.normal.y += slope * dp.y;
        _geometry.normal.z += slope * dp.z * 0.64;
        _geometry.normal = normalize(_geometry.normal);
        """]
        v.paint.setValue(NSNumber(value: 0), forKey: "dentAmount")
        return v
    }

    /// Вдавить борт фургона (0...1).
    func setDent(_ value: Float) {
        paint.setValue(NSNumber(value: value), forKey: "dentAmount")
    }

    /// Седан — «Вольво» Эдварда и машины на парковке.
    static func sedan(color: UIColor, metallic: CGFloat = 0.6) -> Vehicle {
        let mesh = MeshCache.mesh("veh-sedan") {
            let m = SDFModel()
            let paint = Slot.paint.rawValue, glass = Slot.glass.rawValue, trim = Slot.trim.rawValue
            m.box(V3(0, 0.68, 0), V3(0.88, 0.26, 2.3), round: 0.2, slot: paint, blend: 0.05)
            m.box(V3(0, 1.12, -0.15), V3(0.78, 0.22, 1.15), round: 0.24, slot: paint, blend: 0.28)
            for s: Float in [1, -1] {
                for z: Float in [1.42, -1.42] {
                    m.ellipsoid(V3(s * 0.9, 0.36, z), V3(0.3, 0.42, 0.46), slot: paint, blend: 0.03, subtract: true)
                }
                m.box(V3(s * 0.82, 1.15, -0.15), V3(0.08, 0.15, 0.95), round: 0.06, slot: paint, blend: 0.02, subtract: true)
                m.box(V3(s * 0.76, 1.15, -0.15), V3(0.03, 0.15, 0.95), round: 0.012, slot: glass, blend: 0.002)
                m.ellipsoid(V3(s * 0.62, 0.78, 2.25), V3(0.2, 0.06, 0.06), slot: Slot.headlight.rawValue, blend: 0.02)
                m.box(V3(s * 0.62, 0.82, -2.28), V3(0.18, 0.06, 0.03), round: 0.02, slot: Slot.taillight.rawValue, blend: 0.01)
            }
            m.box(V3(0, 1.17, 0.95), V3(0.7, 0.16, 0.08), round: 0.05, rotation: V3(-0.9, 0, 0),
                  slot: paint, blend: 0.02, subtract: true)
            m.box(V3(0, 1.17, 0.92), V3(0.7, 0.16, 0.03), round: 0.012, rotation: V3(-0.9, 0, 0),
                  slot: glass, blend: 0.002)
            m.box(V3(0, 1.17, -1.2), V3(0.66, 0.14, 0.08), round: 0.05, rotation: V3(0.8, 0, 0),
                  slot: paint, blend: 0.02, subtract: true)
            m.box(V3(0, 1.17, -1.17), V3(0.66, 0.14, 0.03), round: 0.012, rotation: V3(0.8, 0, 0),
                  slot: glass, blend: 0.002)
            m.box(V3(0, 0.5, 2.3), V3(0.85, 0.08, 0.06), round: 0.04, slot: trim, blend: 0.02)
            m.box(V3(0, 0.5, -2.3), V3(0.85, 0.08, 0.06), round: 0.04, slot: trim, blend: 0.02)
            m.box(V3(0, 1.05, -0.15), V3(0.72, 0.2, 0.95), round: 0.05, slot: Slot.interior.rawValue, blend: 0)
            return m.mesh(cell: 0.017, uvScale: 1)
        }
        return Vehicle(mesh: mesh, paintColor: color,
                       wheelSpots: [V3(0.82, 0.36, 1.42), V3(-0.82, 0.36, 1.42), V3(0.82, 0.36, -1.42), V3(-0.82, 0.36, -1.42)],
                       wheelRadius: 0.36,
                       headlightSpots: [], metallic: metallic)
    }
}

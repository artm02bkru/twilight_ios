import SceneKit
import UIKit
import simd

/// Персонаж со скелетом и цельной гладкой кожей.
///
/// Тело — одна сетка, построенная из поля расстояний и привязанная к костям через
/// `SCNSkinner` (как в студийных движках): плечи, локти, колени гнутся без швов.
/// Лицо, кисти, обувь и волосы — отдельные детализированные сетки на своих костях.
///
/// Персонаж смотрит вдоль +Z, левая рука — на стороне +X.
/// Положение в мире задаётся через `position` и `yaw`, поза — через `target`.
final class Humanoid {

    let look: CharacterLook

    /// Узел размещения: позиция, поворот по вертикали и рост (масштаб).
    let node = SCNNode()
    /// Корень скелета: приседание, наклон, «лёжа».
    private let body = SCNNode()

    let hips = SCNNode()
    let spine = SCNNode()
    let chest = SCNNode()
    let neck = SCNNode()
    let head = SCNNode()
    let shoulderL = SCNNode()
    let shoulderR = SCNNode()
    let elbowL = SCNNode()
    let elbowR = SCNNode()
    /// Кисти — к ним крепится реквизит (бита, мяч).
    let handL = SCNNode()
    let handR = SCNNode()
    let hipL = SCNNode()
    let hipR = SCNNode()
    let kneeL = SCNNode()
    let kneeR = SCNNode()
    private let ankleL = SCNNode()
    private let ankleR = SCNNode()

    /// Порядок костей совпадает с `CharacterSculpt.Bone`.
    private var bones: [SCNNode] {
        [hips, spine, chest, neck, head, shoulderL, elbowL, shoulderR, elbowR, hipL, kneeL, hipR, kneeR]
    }

    /// Текущая поза и поза, к которой персонаж плавно стремится.
    private(set) var pose = Pose.stand
    var target = Pose.stand
    /// Скорость перехода к целевой позе (больше — резче).
    var rate: Float = 7
    /// Амплитуда дыхания (0 — замер).
    var breathing: Float = 1
    /// Точка в мире, куда смотреть (голова поворачивается в пределах шеи).
    var lookAt: V3? = nil

    private let skin: SCNMaterial
    private let iris: SCNMaterial
    /// Готовое тело из модели (Белла, Эдвард); nil — процедурное тело.
    private(set) var avatar: AvatarBody?
    /// Материалы одежды — для перекраски (свадебные наряды).
    private var topMaterial: SCNMaterial?
    private var bottomMaterial: SCNMaterial?
    private var sparkleSystems: [SCNParticleSystem] = []
    /// Веки для моргания.
    private var lids: [SCNNode] = []
    private var blinkTimer: Float = 2
    private var blinkPhase: Float = -1
    private var lookYaw: Float = 0
    private var lookPitch: Float = 0
    private let phase: Float

    // MARK: - Сборка

    init(_ look: CharacterLook) {
        self.look = look
        phase = Float(Humanoid.stableHash(look.name) % 1000) / 1000 * 6.28

        skin = Materials.pbr(look.skin, roughness: look.vampire ? 0.48 : 0.58,
                             normal: Textures.skinNormal, normalIntensity: 0.3, tile: 1)
        skin.normal.contentsTransform = SCNMatrix4MakeScale(30, 30, 1)
        skin.normal.wrapS = .repeat
        skin.normal.wrapT = .repeat
        if look.vampire {
            // Алмазная кожа: россыпь искр в эмиссии, по умолчанию погашена.
            skin.emission.contents = Textures.sparkle
            skin.emission.intensity = 0
            skin.emission.contentsTransform = SCNMatrix4MakeScale(18, 18, 1)
            skin.emission.wrapS = .repeat
            skin.emission.wrapT = .repeat
            skin.clearCoat.contents = 0.08
            skin.clearCoatRoughness.contents = 0.4
        } else {
            // Тёплый подповерхностный оттенок у живой кожи.
            skin.emission.contents = UIColor(red: 0.35, green: 0.08, blue: 0.05, alpha: 1)
            skin.emission.intensity = 0.04
        }
        // Мягкий подповерхностный отсвет по краю силуэта — кожа перестаёт быть «пластиковой».
        let rimColor = look.vampire ? "float3(0.55, 0.62, 0.75)" : "float3(0.75, 0.28, 0.18)"
        skin.shaderModifiers = [.surface: """
        float skinRim = 1.0 - max(dot(_surface.normal, _surface.view), 0.0);
        _surface.emission.rgb += \(rimColor) * pow(skinRim, 3.0) * 0.12;
        """]
        iris = Materials.pbr(look.eyes, roughness: 0.12)
        iris.clearCoat.contents = 1.0
        if look.vampire {
            iris.emission.contents = look.eyes
            iris.emission.intensity = 0.3
        }

        node.name = look.name
        node.addChildNode(body)
        buildSkeleton()

        // Поза привязки — «A»: руки и ноги разведены, чтобы поверхности не слиплись.
        var bind = Pose()
        bind.shoulderL = V3(0, 0, 0.42)
        bind.shoulderR = V3(0, 0, -0.42)
        bind.elbowL = -0.05
        bind.elbowR = -0.05
        bind.hipL = V3(0, 0, 0.07)
        bind.hipR = V3(0, 0, -0.07)
        apply(bind, time: 0, breathe: false)

        if let name = look.avatar, let model = ModelAsset.named(name),
           let body = AvatarBody(model: model, vampire: look.vampire) {
            avatar = body
            node.addChildNode(body.root)
            apply(AvatarBody.referencePose, time: 0, breathe: false)
            body.calibrate(owner: node, joints: [
                "hips": hips, "spine": spine, "chest": chest, "neck": neck, "head": head,
                "shoulderL": shoulderL, "elbowL": elbowL, "handL": handL,
                "shoulderR": shoulderR, "elbowR": elbowR, "handR": handR,
                "hipL": hipL, "kneeL": kneeL, "ankleL": ankleL,
                "hipR": hipR, "kneeR": kneeR, "ankleR": ankleR
            ])
            if look.vampire { body.setEyes(look.eyes, glow: 0.3) }
            dressAvatar(body)
        } else {
            buildSkin()
            buildFace()
            buildExtremities()
        }

        node.scale = SCNVector3(look.height / 1.79, look.height / 1.79, look.height / 1.79)
        snap(.stand)
    }

    private func buildSkeleton() {
        let w = look.build
        body.addChildNode(hips)
        hips.simdPosition = V3(0, 0.98, 0)
        hips.addChildNode(spine)
        spine.simdPosition = V3(0, 0.10, 0)
        spine.addChildNode(chest)
        chest.simdPosition = V3(0, 0.16, 0)
        chest.addChildNode(neck)
        neck.simdPosition = V3(0, 0.25, -0.01)
        neck.addChildNode(head)
        head.simdPosition = V3(0, 0.075, 0.005)

        let shoulderX: Float = (look.female ? 0.158 : 0.172) * w
        chest.addChildNode(shoulderL)
        shoulderL.simdPosition = V3(shoulderX, 0.2, -0.01)
        chest.addChildNode(shoulderR)
        shoulderR.simdPosition = V3(-shoulderX, 0.2, -0.01)
        shoulderL.addChildNode(elbowL)
        elbowL.simdPosition = V3(0, -0.29, 0)
        shoulderR.addChildNode(elbowR)
        elbowR.simdPosition = V3(0, -0.29, 0)
        elbowL.addChildNode(handL)
        handL.simdPosition = V3(0, -0.25, 0)
        elbowR.addChildNode(handR)
        handR.simdPosition = V3(0, -0.25, 0)

        let hipX: Float = look.female ? 0.095 : 0.09
        hips.addChildNode(hipL)
        hipL.simdPosition = V3(hipX, -0.07, 0)
        hips.addChildNode(hipR)
        hipR.simdPosition = V3(-hipX, -0.07, 0)
        hipL.addChildNode(kneeL)
        kneeL.simdPosition = V3(0, -0.445, 0)
        hipR.addChildNode(kneeR)
        kneeR.simdPosition = V3(0, -0.445, 0)
        kneeL.addChildNode(ankleL)
        ankleL.simdPosition = V3(0, -0.415, 0)
        kneeR.addChildNode(ankleR)
        ankleR.simdPosition = V3(0, -0.415, 0)
    }

    // MARK: Кожа тела со скиннингом

    private var meshKey: String {
        "\(look.name)-\(look.female)-\(look.build)-\(look.skirt)\(look.longSkirt)\(look.coat)\(look.legCast)\(look.collar)\(look.bowTie)-\(look.skirtFlare ?? 0)"
    }

    private func buildSkin() {
        let frames: [CharacterSculpt.BoneFrame] = bones.map { bone in
            let m = body.simdConvertTransform(matrix_identity_float4x4, from: bone)
            let r = simd_float3x3(V3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                                  V3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                                  V3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
            return CharacterSculpt.BoneFrame(origin: V3(m.columns.3.x, m.columns.3.y, m.columns.3.z), rotation: r)
        }
        let look = self.look
        let mesh = MeshCache.mesh("body-" + meshKey) {
            CharacterSculpt.body(look) { frames[$0.rawValue] }
                .mesh(cell: 0.0082, boneCount: frames.count, uvScale: 4)
        }
        guard !mesh.isEmpty else { return }

        let top = Materials.cloth(look.top, sheen: look.coat || look.bowTie)
        let bottom = Materials.cloth(look.bottom, roughness: look.skirt ? 0.6 : 0.78, sheen: look.skirt)
        let plaster = Materials.pbr(UIColor(white: 0.93, alpha: 1), roughness: 0.9)
        let shirt = Materials.cloth(.white, roughness: 0.55)
        let tie = Materials.cloth(UIColor(white: 0.03, alpha: 1), roughness: 0.35, sheen: true)
        topMaterial = top
        bottomMaterial = bottom
        let leather = Materials.pbr(UIColor(hex: 0x2A1C14), roughness: 0.4)
        leather.clearCoat.contents = 0.5
        let metal = Materials.pbr(UIColor(white: 0.75, alpha: 1), roughness: 0.25, metalness: 1)
        let geometry = mesh.geometry(materials: [skin, top, bottom, plaster, shirt, tie, leather, metal])

        let skinned = SCNNode(geometry: geometry)
        skinned.name = "skin"
        body.addChildNode(skinned)

        let inverseBind = bones.map { bone -> NSValue in
            let m = body.simdConvertTransform(matrix_identity_float4x4, from: bone)
            return NSValue(scnMatrix4: SCNMatrix4(simd_inverse(m)))
        }
        let skinner = SCNSkinner(baseGeometry: geometry,
                                 bones: bones,
                                 boneInverseBindTransforms: inverseBind,
                                 boneWeights: mesh.boneWeightSource(),
                                 boneIndices: mesh.boneIndexSource())
        skinner.skeleton = body
        skinned.skinner = skinner
    }

    // MARK: Лицо и волосы

    private func buildFace() {
        let look = self.look
        let lip = Materials.pbr(look.lips, roughness: 0.32)
        lip.clearCoat.contents = 0.5
        let brow = Materials.pbr(look.hairColor.darkened(0.05), roughness: 0.8)

        let faceMesh = MeshCache.mesh("head-\(look.name)-\(look.female)") {
            CharacterSculpt.head(look).mesh(cell: 0.003, uvScale: 30)
        }
        head.addChildNode(SCNNode(geometry: faceMesh.geometry(materials: [skin, lip, brow])))

        // Глаза: влажный белок, радужка, зрачок, блик роговицы.
        let white = Materials.pbr(UIColor(red: 0.95, green: 0.93, blue: 0.92, alpha: 1), roughness: 0.08)
        white.clearCoat.contents = 1.0
        let pupil = Materials.pbr(UIColor(white: 0.01, alpha: 1), roughness: 0.05)
        for side: Float in [1, -1] {
            let x = side * 0.034
            let ball = SCNSphere(radius: 0.0128)
            ball.segmentCount = 24
            head.add(SCNNode(ball, white).at(x, 0.119, 0.081))
            let irisNode = SCNNode(SCNSphere(radius: 1), iris)
            irisNode.simdScale = V3(0.0079, 0.0079, 0.0032)
            irisNode.simdPosition = V3(x, 0.119, 0.0928)
            head.add(irisNode)
            let pupilNode = SCNNode(SCNSphere(radius: 1), pupil)
            pupilNode.simdScale = V3(0.0035, 0.0035, 0.0016)
            pupilNode.simdPosition = V3(x, 0.119, 0.0955)
            head.add(pupilNode)

            // Ресницы по краю верхнего века.
            let lashes = SCNNode(SCNBox(width: 0.029, height: 0.0022, length: 0.009, chamferRadius: 0.001),
                                 Materials.pbr(look.hairColor.darkened(0.2), roughness: 0.6))
            lashes.simdPosition = V3(x, 0.1262, 0.0945)
            lashes.eulerAngles = SCNVector3(-0.5, 0, side * -0.08)
            head.add(lashes)

            // Веко: в открытом глазу почти целиком спрятано под надбровьем.
            let lidPivot = SCNNode()
            lidPivot.simdPosition = V3(x, 0.1255, 0.0815)
            let lid = SCNNode(SCNSphere(radius: 1), skin)
            lid.simdScale = V3(0.0142, 0.0142, 0.0142)
            lid.simdPosition = V3(0, -0.0065, 0)
            lidPivot.addChildNode(lid)
            lidPivot.simdScale = V3(1, 0.05, 1)
            head.add(lidPivot)
            lids.append(lidPivot)
        }

        let hairMesh = MeshCache.mesh("hair-\(look.name)-\(look.hair)") {
            CharacterSculpt.hair(look).mesh(cell: 0.0038, uvScale: 1)
        }
        let hair = Materials.pbr(look.hairColor, roughness: 0.45, normal: Textures.hairStrands,
                                 normalIntensity: 0.6)
        hair.normal.contentsTransform = SCNMatrix4MakeScale(18, 4, 1)
        hair.normal.wrapS = .repeat
        hair.normal.wrapT = .repeat
        hair.clearCoat.contents = 0.45
        hair.clearCoatRoughness.contents = 0.3
        head.addChildNode(SCNNode(geometry: hairMesh.geometry(materials: [hair])))
    }

    // MARK: Кисти и обувь

    /// Наряды поверх готовой модели: длинное платье (юбка на тазу), тёмный костюм, бабочка.
    private func dressAvatar(_ body: AvatarBody) {
        let formal = look.skirt || look.bowTie || look.coat
        guard formal else { return }
        body.tintOutfit(Self.outfitTint(look.top))
        if look.skirt {
            let flare = look.skirtFlare ?? (look.longSkirt ? 0.4 : 0.3)
            let length: Float = look.longSkirt ? 0.98 : 0.55
            let cloth = Materials.cloth(look.bottom, roughness: 0.5, sheen: true)
            cloth.isDoubleSided = true
            bottomMaterial = cloth
            let cone = SCNCone(topRadius: 0.15, bottomRadius: CGFloat(flare), height: CGFloat(length))
            cone.radialSegmentCount = 48
            cone.heightSegmentCount = 6
            let skirt = SCNNode(cone, cloth)
            skirt.name = "skirt"
            // Верх юбки — на талии чуть выше тазовой кости.
            skirt.simdPosition = V3(0, 0.1 - length / 2, 0.01)
            skirt.castsShadow = true
            hips.addChildNode(skirt)
        }
        if look.bowTie {
            let bow = Materials.cloth(UIColor(white: 0.03, alpha: 1), roughness: 0.35, sheen: true)
            for side: Float in [-1, 1] {
                let wing = SCNNode(SCNBox(width: 0.045, height: 0.035, length: 0.015, chamferRadius: 0.008), bow)
                wing.simdPosition = V3(side * 0.024, 0.0, 0.075)
                wing.simdEulerAngles.z = side * 0.25
                neck.addChildNode(wing)
            }
        }
    }

    /// Цвет одежды как множитель текстуры: чёрный не делаем совсем чёрным — пропадёт ткань.
    private static func outfitTint(_ c: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: max(r, 0.11), green: max(g, 0.11), blue: max(b, 0.12), alpha: 1)
    }

    private func buildExtremities() {
        let female = look.female
        let left = MeshCache.mesh("hand-L-\(female)") {
            CharacterSculpt.hand(side: 1, female: female).mesh(cell: 0.0027, uvScale: 30)
        }
        let right = MeshCache.mesh("hand-R-\(female)") {
            CharacterSculpt.hand(side: -1, female: female).mesh(cell: 0.0027, uvScale: 30)
        }
        let nail = Materials.pbr(look.skin.lightened(0.06), roughness: 0.15)
        nail.clearCoat.contents = 1
        handL.addChildNode(SCNNode(geometry: left.geometry(materials: [skin, nail])))
        handR.addChildNode(SCNNode(geometry: right.geometry(materials: [skin, nail])))

        let boot = look.skirt && !look.longSkirt
        let shoeMesh = MeshCache.mesh("shoe-\(boot)") {
            CharacterSculpt.shoe(boot: boot).mesh(cell: 0.005, uvScale: 10)
        }
        let leather = Materials.pbr(look.shoes, roughness: 0.32)
        leather.clearCoat.contents = 0.7
        leather.clearCoatRoughness.contents = 0.2
        let sole = Materials.rubber()
        for ankle in [ankleL, ankleR] {
            ankle.addChildNode(SCNNode(geometry: shoeMesh.geometry(materials: [leather, sole])))
        }
    }

    /// Хеш имени, одинаковый между запусками (hashValue в Swift каждый раз разный).
    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for u in s.unicodeScalars {
            h = (h ^ UInt64(u.value)) &* 1099511628211
        }
        return h
    }

    // MARK: - Управление

    var position: V3 {
        get { node.simdPosition }
        set { node.simdPosition = newValue }
    }

    var yaw: Float {
        get { node.simdEulerAngles.y }
        set { node.simdEulerAngles.y = newValue }
    }

    var opacity: Float {
        get { Float(node.opacity) }
        set { node.opacity = CGFloat(newValue) }
    }

    var isHidden: Bool {
        get { node.isHidden }
        set { node.isHidden = newValue }
    }

    func place(_ p: V3, yaw: Float) {
        position = p
        self.yaw = yaw
    }

    /// Мгновенно принять позу (смена кадра).
    func snap(_ p: Pose) {
        pose = p
        target = p
        apply(p, time: 0, breathe: false)
        avatar?.sync(owner: node)
    }

    /// Алмазный блеск кожи на солнце, 0...1.
    func setSparkle(_ value: Float) {
        guard look.vampire else { return }
        skin.emission.intensity = CGFloat(value * 3.5)
        avatar?.setSparkle(value)
        if sparkleSystems.isEmpty && value > 0 {
            for (n, r) in [(head, 0.11), (handL, 0.06), (handR, 0.06), (neck, 0.06)] {
                let ps = Nature.sparkles(shape: SCNSphere(radius: CGFloat(r)))
                n.addParticleSystem(ps)
                sparkleSystems.append(ps)
            }
        }
        for ps in sparkleSystems {
            ps.birthRate = CGFloat(value * 70)
        }
    }

    /// Перекрасить одежду (платье, костюм) без пересборки сетки.
    func setOutfit(top: UIColor, bottom: UIColor? = nil) {
        topMaterial?.diffuse.contents = top
        bottomMaterial?.diffuse.contents = bottom ?? top
        if let avatar, look.skirt || look.bowTie || look.coat { avatar.tintOutfit(Self.outfitTint(top)) }
    }

    /// Свечение глаз (жажда — красным).
    func setEyes(_ color: UIColor, glow: CGFloat) {
        iris.diffuse.contents = color
        iris.emission.contents = color
        iris.emission.intensity = glow
        avatar?.setEyes(color, glow: glow)
    }

    func update(dt: Float, time: Float) {
        let k = 1 - exp(-rate * dt)
        pose = Pose.mix(pose, target, k)
        apply(pose, time: time, breathe: true)

        if let lookAt {
            // Поворот головы к точке относительно направления тела.
            let headWorld = head.simdWorldPosition
            let toTarget = lookAt - headWorld
            let worldYaw = atan2(toTarget.x, toTarget.z)
            var rel = worldYaw - yaw
            while rel > Float.pi { rel -= 2 * Float.pi }
            while rel < -Float.pi { rel += 2 * Float.pi }
            let flat = max(0.01, simd_length(V3(toTarget.x, 0, toTarget.z)))
            let pitch = -atan2(toTarget.y, flat)
            lookYaw = damp(lookYaw, clampf(rel, -1.1, 1.1), 6, dt)
            lookPitch = damp(lookPitch, clampf(pitch, -0.5, 0.6), 6, dt)
        } else {
            lookYaw = damp(lookYaw, 0, 4, dt)
            lookPitch = damp(lookPitch, 0, 4, dt)
        }
        neck.simdEulerAngles += V3(lookPitch * 0.4, lookYaw * 0.4, 0)
        head.simdEulerAngles += V3(lookPitch * 0.6, lookYaw * 0.6, 0)
        updateBlink(dt: dt)
        avatar?.sync(owner: node)
    }

    /// Моргание раз в 2–6 секунд: веко опускается и поднимается за ~0.15 с.
    private func updateBlink(dt: Float) {
        guard dt > 0 else { return }
        if blinkPhase < 0 {
            blinkTimer -= dt
            if blinkTimer <= 0 {
                blinkPhase = 0
                blinkTimer = Float.random(in: 2...6)
            }
        } else {
            blinkPhase += dt / 0.16
            if blinkPhase >= 1 { blinkPhase = -1 }
        }
        let closed: Float = blinkPhase < 0 ? 0 : sin(blinkPhase * Float.pi)
        for lid in lids {
            lid.simdScale = V3(1, 0.05 + closed * 0.95, 1)
        }
    }

    private func apply(_ p: Pose, time: Float, breathe: Bool) {
        // Дыхание: грудь чуть поднимается, плечи следуют, корпус едва покачивается.
        let amount = breathe ? breathing : 0
        let breath = sin(time * 1.7 + phase) * 0.018 * amount
        let sway = sin(time * 0.6 + phase) * 0.012 * amount

        body.simdPosition = V3(0, p.rootY, 0)
        body.simdEulerAngles = V3(p.rootPitch, 0, p.rootRoll + sway * 0.3)

        hips.simdEulerAngles = p.hips
        spine.simdEulerAngles = p.spine + V3(breath * 0.4, 0, sway)
        chest.simdEulerAngles = p.chest + V3(-breath, 0, 0)
        neck.simdEulerAngles = p.neck
        head.simdEulerAngles = p.head + V3(breath * 0.5, 0, 0)
        shoulderL.simdEulerAngles = p.shoulderL + V3(0, 0, breath * 0.3)
        shoulderR.simdEulerAngles = p.shoulderR - V3(0, 0, breath * 0.3)
        elbowL.simdEulerAngles = V3(p.elbowL, 0, 0)
        elbowR.simdEulerAngles = V3(p.elbowR, 0, 0)
        handL.simdEulerAngles = p.wristL
        handR.simdEulerAngles = p.wristR
        hipL.simdEulerAngles = p.hipL
        hipR.simdEulerAngles = p.hipR
        kneeL.simdEulerAngles = V3(p.kneeL, 0, 0)
        kneeR.simdEulerAngles = V3(p.kneeR, 0, 0)
    }
}

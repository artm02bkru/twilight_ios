import simd

/// «Скульптор»: описывает тело, лицо, кисти, обувь и причёски полями расстояний.
/// Из этих полей строятся гладкие сетки — без швов на суставах.
enum CharacterSculpt {

    // Слоты материалов тела.
    enum BodySlot: Int { case skin = 0, top, bottom, plaster, shirt, tie }
    // Слоты лица.
    enum HeadSlot: Int { case skin = 0, lips, brow }

    /// Индексы костей скелета (порядок совпадает с `Humanoid.bones`).
    enum Bone: Int {
        case hips = 0, spine, chest, neck, head
        case shoulderL, elbowL, shoulderR, elbowR
        case hipL, kneeL, hipR, kneeR
    }

    /// Положение и поворот кости в пространстве тела (в позе привязки).
    struct BoneFrame {
        var origin: V3
        var rotation: simd_float3x3

        func point(_ p: V3) -> V3 { origin + rotation * p }
    }

    // MARK: - Тело

    static func body(_ look: CharacterLook, frame: (Bone) -> BoneFrame) -> SDFModel {
        let m = SDFModel()
        let f = look.female
        let w = look.build
        let top = BodySlot.top.rawValue
        let bottom = BodySlot.bottom.rawValue
        let skin = BodySlot.skin.rawValue

        func caps(_ bone: Bone, _ a: V3, _ b: V3, _ ra: Float, _ rb: Float, _ slot: Int, blend: Float) {
            let fr = frame(bone)
            m.capsule(fr.point(a), fr.point(b), ra, rb, slot: slot, bone: bone.rawValue, blend: blend)
        }
        func ell(_ bone: Bone, _ c: V3, _ r: V3, _ slot: Int, blend: Float, subtract: Bool = false) {
            let fr = frame(bone)
            m.add(SDFPrim(.ellipsoid(fr.point(c), r, fr.rotation.transpose),
                          slot: slot, bone: bone.rawValue, blend: blend, subtract: subtract))
        }
        func box(_ bone: Bone, _ c: V3, _ half: V3, round: Float, _ slot: Int, blend: Float) {
            let fr = frame(bone)
            m.add(SDFPrim(.box(fr.point(c), half, round, fr.rotation.transpose),
                          slot: slot, bone: bone.rawValue, blend: blend))
        }

        // Таз и ягодицы.
        ell(.hips, V3(0, -0.03, 0), V3((f ? 0.172 : 0.158) * w, 0.12, 0.112), bottom, blend: 0.04)
        ell(.hips, V3(0.068, -0.075, -0.045), V3(0.075, 0.085, 0.07), bottom, blend: 0.03)
        ell(.hips, V3(-0.068, -0.075, -0.045), V3(0.075, 0.085, 0.07), bottom, blend: 0.03)

        // Живот и талия.
        ell(.spine, V3(0, 0.045, f ? 0.006 : -0.004), V3((f ? 0.122 : 0.132) * w, 0.15, f ? 0.1 : 0.09), top, blend: 0.05)

        // Грудная клетка, грудь, трапеции.
        ell(.chest, V3(0, 0.1, 0), V3((f ? 0.152 : 0.178) * w, 0.168, 0.114), top, blend: 0.05)
        if f {
            ell(.chest, V3(0.05, 0.08, 0.07), V3(0.058, 0.054, 0.052), top, blend: 0.035)
            ell(.chest, V3(-0.05, 0.08, 0.07), V3(0.058, 0.054, 0.052), top, blend: 0.035)
        } else {
            ell(.chest, V3(0.06, 0.12, 0.058), V3(0.08 * w, 0.06, 0.05), top, blend: 0.045)
            ell(.chest, V3(-0.06, 0.12, 0.058), V3(0.08 * w, 0.06, 0.05), top, blend: 0.045)
        }
        ell(.chest, V3(0, 0.2, -0.022), V3(0.125 * w, 0.06, 0.075), top, blend: 0.045)
        // Лопатки.
        ell(.chest, V3(0.07, 0.13, -0.075), V3(0.06, 0.08, 0.04), top, blend: 0.04)
        ell(.chest, V3(-0.07, 0.13, -0.075), V3(0.06, 0.08, 0.04), top, blend: 0.04)

        if look.collar {
            ell(.neck, V3(0, -0.025, 0.0), V3(0.078, 0.028, 0.072), top, blend: 0.015)
        }
        if look.bowTie {
            ell(.chest, V3(0, 0.15, 0.104), V3(0.05, 0.1, 0.018), BodySlot.shirt.rawValue, blend: 0.006)
            box(.chest, V3(0, 0.232, 0.092), V3(0.036, 0.014, 0.01), round: 0.006, BodySlot.tie.rawValue, blend: 0.003)
        }

        // Шея (верх уходит внутрь головы).
        caps(.neck, V3(0, -0.04, 0), V3(0, 0.1, 0.012), 0.05, 0.046, skin, blend: 0.03)

        // Руки.
        for (shoulder, elbow) in [(Bone.shoulderL, Bone.elbowL), (Bone.shoulderR, Bone.elbowR)] {
            ell(shoulder, V3(0, -0.025, 0), V3(0.064, 0.074, 0.066), top, blend: 0.035)
            caps(shoulder, V3(0, -0.03, 0), V3(0, -0.27, 0), (f ? 0.046 : 0.052) * w, f ? 0.038 : 0.043, top, blend: 0.03)
            ell(shoulder, V3(0, -0.13, 0.014), V3(0.045 * w, 0.09, f ? 0.04 : 0.047), top, blend: 0.03)
            caps(elbow, V3(0, 0, 0), V3(0, -0.225, 0), f ? 0.04 : 0.045, f ? 0.031 : 0.035, top, blend: 0.03)
            ell(elbow, V3(0, -0.07, 0.005), V3(0.046, 0.08, 0.043), top, blend: 0.03)
            // Манжета.
            caps(elbow, V3(0, -0.215, 0), V3(0, -0.245, 0), 0.039, 0.039, top, blend: 0.006)
        }

        // Ноги.
        for (hip, knee, left) in [(Bone.hipL, Bone.kneeL, true), (Bone.hipR, Bone.kneeR, false)] {
            caps(hip, V3(0, 0, 0), V3(0, -0.43, 0), f ? 0.086 : 0.081, 0.056, bottom, blend: 0.04)
            ell(hip, V3(0, -0.16, 0.022), V3(0.07, 0.15, 0.07), bottom, blend: 0.04)
            ell(knee, V3(0, 0, 0.012), V3(0.056, 0.06, 0.056), bottom, blend: 0.03)
            caps(knee, V3(0, 0, 0), V3(0, -0.39, 0), 0.052, 0.042, bottom, blend: 0.03)
            ell(knee, V3(0, -0.12, -0.026), V3(0.055, 0.1, 0.06), bottom, blend: 0.03)
            // Низ брючины чуть расширяется над ботинком.
            caps(knee, V3(0, -0.37, 0), V3(0, -0.41, 0.005), 0.047, 0.052, bottom, blend: 0.012)
            if look.legCast && left {
                caps(knee, V3(0, -0.04, 0), V3(0, -0.41, 0.01), 0.068, 0.07, BodySlot.plaster.rawValue, blend: 0.01)
            }
        }

        // Юбка или платье — объём вокруг ног.
        if look.skirt {
            let len: Float = look.longSkirt ? 0.84 : 0.46
            let flare: Float = look.skirtFlare ?? (look.longSkirt ? 0.36 : 0.27)
            caps(.hips, V3(0, 0.03, 0), V3(0, -len, 0), 0.168, flare, bottom, blend: 0.03)
        }
        // Полы пальто.
        if look.coat {
            box(.hips, V3(0, -0.2, -0.01), V3(0.19 * w, 0.26, 0.13), round: 0.06, top, blend: 0.04)
        }
        return m
    }

    // MARK: - Голова и лицо

    static func head(_ look: CharacterLook) -> SDFModel {
        let m = SDFModel()
        let skin = HeadSlot.skin.rawValue
        let lips = HeadSlot.lips.rawValue
        let brow = HeadSlot.brow.rawValue
        let f = look.female
        let detail: Float = 0.0012

        // Череп, лицо, челюсть, подбородок.
        m.ellipsoid(V3(0, 0.122, -0.008), V3(0.09, 0.1, 0.097), slot: skin, blend: 0.03)
        m.ellipsoid(V3(0, 0.088, 0.028), V3(f ? 0.064 : 0.07, 0.07, 0.072), slot: skin, blend: 0.035)
        m.ellipsoid(V3(0, 0.05, 0.032), V3(f ? 0.052 : 0.062, 0.044, 0.062), slot: skin, blend: 0.035)
        m.ellipsoid(V3(0, 0.024, 0.072), V3(f ? 0.021 : 0.026, 0.019, 0.02), slot: skin, blend: 0.022)
        if !f {
            // Углы нижней челюсти — более мужской силуэт.
            m.ellipsoid(V3(0.05, 0.042, 0.004), V3(0.022, 0.026, 0.032), slot: skin, blend: 0.025)
            m.ellipsoid(V3(-0.05, 0.042, 0.004), V3(0.022, 0.026, 0.032), slot: skin, blend: 0.025)
        }
        // Скулы и надбровье.
        m.ellipsoid(V3(0.047, 0.094, 0.06), V3(0.026, 0.018, 0.024), slot: skin, blend: 0.025)
        m.ellipsoid(V3(-0.047, 0.094, 0.06), V3(0.026, 0.018, 0.024), slot: skin, blend: 0.025)
        m.ellipsoid(V3(0, 0.137, 0.078), V3(0.056, 0.012, 0.018), slot: skin, blend: 0.02)

        // Нос: спинка, кончик, крылья.
        m.capsule(V3(0, 0.128, 0.089), V3(0, 0.092, 0.111), 0.0072, 0.0105, slot: skin, blend: 0.012)
        m.ellipsoid(V3(0, 0.088, 0.111), V3(0.0125, 0.011, 0.012), slot: skin, blend: 0.01)

        for side: Float in [1, -1] {
            m.ellipsoid(V3(side * 0.0115, 0.085, 0.1), V3(0.0085, 0.006, 0.008), slot: skin, blend: 0.008)
            // Глазница и веки.
            m.ellipsoid(V3(side * 0.034, 0.119, 0.093), V3(0.017, 0.012, 0.012), slot: skin,
                        blend: 0.008, subtract: true)
            m.ellipsoid(V3(side * 0.034, 0.1272, 0.0846), V3(0.0156, 0.0054, 0.0106), slot: skin, blend: 0.004)
            m.ellipsoid(V3(side * 0.034, 0.1108, 0.0858), V3(0.0148, 0.0038, 0.0092), slot: skin, blend: 0.004)
            // Брови.
            m.box(V3(side * 0.036, 0.1465, 0.0895), V3(0.0155, 0.0024, 0.0045), round: 0.0018,
                  rotation: V3(0, 0, -side * 0.14), slot: brow, blend: 0.003, claim: detail)
            // Уши.
            m.ellipsoid(V3(side * 0.091, 0.11, -0.002), V3(0.011, 0.028, 0.019), slot: skin, blend: 0.01)
            m.ellipsoid(V3(side * 0.097, 0.11, 0.0), V3(0.006, 0.016, 0.01), slot: skin,
                        blend: 0.004, subtract: true)
        }

        // Губы и линия рта.
        m.ellipsoid(V3(0, 0.0628, 0.0985), V3(0.0185, 0.0058, 0.0088), slot: lips, blend: 0.006, claim: detail)
        m.ellipsoid(V3(0, 0.0525, 0.0965), V3(0.0168, 0.0066, 0.0088), slot: lips, blend: 0.006, claim: detail)
        m.box(V3(0, 0.0575, 0.106), V3(0.018, 0.0007, 0.012), round: 0.0008, slot: skin,
              blend: 0.0015, subtract: true)

        // Обрубок шеи — уходит внутрь шеи тела, скрывает стык.
        m.capsule(V3(0, 0.03, -0.012), V3(0, -0.06, -0.016), 0.047, 0.047, slot: skin, blend: 0.02)
        return m
    }

    // MARK: - Волосы

    static func hair(_ look: CharacterLook) -> SDFModel {
        let m = SDFModel()
        var rng = SeededRandom(seed: 77 &+ UInt64(look.name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }))

        // Основа: шапка волос над лбом и затылком.
        m.ellipsoid(V3(0, 0.146, -0.034), V3(0.106, 0.106, 0.113), slot: 0, blend: 0.02)

        switch look.hair {
        case .messy:
            for i in 0..<11 {
                let a = Float(i) / 11 * Float.pi - Float.pi / 2
                m.ellipsoid(V3(sin(a) * 0.06, 0.21 + rng.range(-0.008, 0.016), 0.005 + cos(a) * 0.045),
                            V3(0.04, 0.026, 0.058),
                            rotation: V3(rng.range(-0.7, -0.2), rng.range(-0.6, 0.6), rng.range(-0.4, 0.4)),
                            slot: 0, blend: 0.014)
            }
            m.ellipsoid(V3(0.025, 0.198, 0.072), V3(0.05, 0.022, 0.035), rotation: V3(-0.4, 0, -0.3),
                        slot: 0, blend: 0.012)

        case .long, .wavy:
            let len: Float = look.hair == .long ? 0.36 : 0.2
            m.box(V3(0, 0.12 - len / 2, -0.088), V3(0.098, len / 2, 0.026), round: 0.022, slot: 0, blend: 0.03)
            for side: Float in [1, -1] {
                m.box(V3(side * 0.088, 0.11 - len * 0.42, -0.02), V3(0.022, len * 0.42, 0.03), round: 0.016,
                      rotation: V3(0, 0, side * 0.06), slot: 0, blend: 0.025)
            }
            // Пряди — волны по поверхности.
            for i in 0..<14 {
                let x = rng.range(-0.1, 0.1)
                let y = rng.range(0.12 - len, 0.1)
                let z = -0.1 + abs(x) * 0.3
                m.ellipsoid(V3(x, y, z), V3(0.02, 0.06, 0.014), rotation: V3(0, 0, rng.range(-0.2, 0.2)),
                            slot: 0, blend: 0.015)
            }

        case .spiky:
            for i in 0..<16 {
                let a = Float(i) / 16 * Float.pi * 2
                let base = V3(cos(a) * 0.07, 0.17 + rng.range(-0.02, 0.03), -0.02 + sin(a) * 0.07)
                let tip = base + V3(cos(a) * 0.05, rng.range(0.0, 0.04), sin(a) * 0.05)
                m.capsule(base, tip, 0.022, 0.004, slot: 0, blend: 0.01)
            }

        case .curly:
            for _ in 0..<40 {
                let a = rng.range(0, Float.pi * 2)
                let e = rng.range(0.1, 1.4)
                let ce: Float = cos(e)
                let p = V3(cos(a) * ce * 0.104, 0.135 + sin(e) * 0.1, sin(a) * ce * 0.106 - 0.025)
                if p.z > 0.05 && p.y < 0.17 { continue }
                m.ellipsoid(p, V3(repeating: rng.range(0.018, 0.026)), slot: 0, blend: 0.008)
            }

        case .ponytail:
            m.capsule(V3(0, 0.15, -0.11), V3(0, -0.14, -0.16), 0.036, 0.014, slot: 0, blend: 0.02)
            m.ellipsoid(V3(0, 0.148, -0.12), V3(0.028, 0.022, 0.026), slot: 0, blend: 0.005)

        case .slicked:
            m.ellipsoid(V3(0, 0.18, -0.02), V3(0.1, 0.07, 0.112), slot: 0, blend: 0.02)
            m.ellipsoid(V3(-0.035, 0.205, 0.04), V3(0.045, 0.02, 0.06), rotation: V3(0, 0, 0.3), slot: 0, blend: 0.01)

        case .wild:
            for _ in 0..<34 {
                let a = rng.range(0, Float.pi * 2)
                let e = rng.range(-0.8, 1.2)
                let r = rng.range(0.11, 0.17)
                let cr: Float = cos(e) * r
                let p = V3(cos(a) * cr, 0.12 + sin(e) * r * 0.8, sin(a) * cr - 0.045)
                if p.z > 0.04 && p.y < 0.19 { continue }
                m.ellipsoid(p, V3(repeating: rng.range(0.035, 0.06)), slot: 0, blend: 0.03)
            }

        case .dreads:
            for i in 0..<18 {
                let a = Float(i) / 18 * Float.pi * 1.6 + Float.pi * 0.7
                let top = V3(sin(a) * 0.095, 0.12, cos(a) * 0.095 - 0.015)
                let bottom = top + V3(sin(a) * 0.04, -0.3, cos(a) * 0.03)
                m.capsule(top, bottom, 0.013, 0.011, slot: 0, blend: 0.008)
            }
        }
        return m
    }

    // MARK: - Кисти

    /// Кисть в пространстве запястья: пальцы вниз (−Y), большой палец вперёд (+Z).
    /// side = 1 — левая (ладонь смотрит в −X), −1 — правая.
    static func hand(side: Float, female: Bool) -> SDFModel {
        let m = SDFModel()
        let s: Float = female ? 0.92 : 1
        // Запястье (уходит в манжету), ладонь, пясть.
        m.capsule(V3(0, 0.03, 0) * s, V3(0, -0.01, 0) * s, 0.026 * s, 0.028 * s, slot: 0, blend: 0.01)
        m.ellipsoid(V3(0, -0.048, 0) * s, V3(0.015, 0.042, 0.038) * s, slot: 0, blend: 0.02)
        m.box(V3(0, -0.055, 0) * s, V3(0.006, 0.026, 0.026) * s, round: 0.01 * s, slot: 0, blend: 0.015)

        // Четыре пальца по три фаланги, с естественным изгибом к ладони.
        let lengths: [Float] = [0.085, 0.095, 0.09, 0.072]
        let zs: [Float] = [0.024, 0.008, -0.008, -0.023]
        for i in 0..<4 {
            let len = lengths[i]
            let knuckle = V3(-side * 0.002, -0.083, zs[i])
            let a = knuckle + V3(-side * 0.006, -len * 0.45, 0)
            let b = a + V3(-side * 0.01, -len * 0.3, 0)
            let c = b + V3(-side * 0.012, -len * 0.22, zs[i] * 0.04)
            m.capsule(knuckle * s, a * s, 0.0092 * s, 0.0085 * s, slot: 0, blend: 0.008)
            m.capsule(a * s, b * s, 0.0085 * s, 0.0078 * s, slot: 0, blend: 0.004)
            m.capsule(b * s, c * s, 0.0078 * s, 0.0068 * s, slot: 0, blend: 0.003)
        }
        // Большой палец.
        let t0 = V3(-side * 0.006, -0.025, 0.026)
        let t1 = V3(-side * 0.016, -0.052, 0.045)
        let t2 = V3(-side * 0.026, -0.074, 0.052)
        let t3 = V3(-side * 0.033, -0.092, 0.052)
        m.capsule(t0 * s, t1 * s, 0.0125 * s, 0.0105 * s, slot: 0, blend: 0.012)
        m.capsule(t1 * s, t2 * s, 0.0105 * s, 0.0088 * s, slot: 0, blend: 0.004)
        m.capsule(t2 * s, t3 * s, 0.0088 * s, 0.0075 * s, slot: 0, blend: 0.003)
        return m
    }

    // MARK: - Обувь

    /// Ботинок в пространстве лодыжки: носок вперёд (+Z). Слот 0 — верх, 1 — подошва.
    static func shoe(boot: Bool) -> SDFModel {
        let m = SDFModel()
        // Голенище уходит в брючину; у сапожек — выше.
        m.capsule(V3(0, boot ? 0.13 : 0.05, -0.008), V3(0, 0.0, -0.004), 0.044, 0.045, slot: 0, blend: 0.02)
        m.box(V3(0, -0.012, 0.045), V3(0.016, 0.006, 0.085), round: 0.03, slot: 0, blend: 0.025)
        m.ellipsoid(V3(0, -0.02, 0.135), V3(0.042, 0.023, 0.05), slot: 0, blend: 0.02)
        m.ellipsoid(V3(0, -0.012, -0.035), V3(0.04, 0.032, 0.04), slot: 0, blend: 0.02)
        // Подошва.
        m.box(V3(0, -0.044, 0.045), V3(0.035, 0.003, 0.115), round: 0.009, slot: 1, blend: 0.003)
        return m
    }
}

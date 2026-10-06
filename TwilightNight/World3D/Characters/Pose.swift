import Foundation
import simd

/// Поза персонажа: углы суставов в радианах.
///
/// Условности (персонаж смотрит вдоль +Z, левая сторона — +X):
/// * руки и бёдра вперёд — отрицательный X, назад — положительный;
/// * локоть сгибается отрицательным X, колено — положительным;
/// * наклон корпуса и головы вперёд — положительный X;
/// * левая рука в сторону — +Z, правая — −Z;
/// * поворот (Y) положительный — к левому плечу.
struct Pose {
    /// Сдвиг всего тела по вертикали, метры (присед, сидя, лёжа).
    var rootY: Float = 0
    /// Наклон всего тела вокруг ступней (−π/2 — лёжа на спине).
    var rootPitch: Float = 0
    var rootRoll: Float = 0

    var hips = V3.zero
    var spine = V3.zero
    var chest = V3.zero
    var neck = V3.zero
    var head = V3.zero

    var shoulderL = V3(0, 0, 0.07)
    var shoulderR = V3(0, 0, -0.07)
    var elbowL: Float = -0.12
    var elbowR: Float = -0.12
    var wristL = V3.zero
    var wristR = V3.zero

    var hipL = V3.zero
    var hipR = V3.zero
    var kneeL: Float = 0
    var kneeR: Float = 0

    static func mix(_ a: Pose, _ b: Pose, _ t: Float) -> Pose {
        var p = Pose()
        p.rootY = lerpf(a.rootY, b.rootY, t)
        p.rootPitch = lerpf(a.rootPitch, b.rootPitch, t)
        p.rootRoll = lerpf(a.rootRoll, b.rootRoll, t)
        p.hips = mixv(a.hips, b.hips, t)
        p.spine = mixv(a.spine, b.spine, t)
        p.chest = mixv(a.chest, b.chest, t)
        p.neck = mixv(a.neck, b.neck, t)
        p.head = mixv(a.head, b.head, t)
        p.shoulderL = mixv(a.shoulderL, b.shoulderL, t)
        p.shoulderR = mixv(a.shoulderR, b.shoulderR, t)
        p.elbowL = lerpf(a.elbowL, b.elbowL, t)
        p.elbowR = lerpf(a.elbowR, b.elbowR, t)
        p.wristL = mixv(a.wristL, b.wristL, t)
        p.wristR = mixv(a.wristR, b.wristR, t)
        p.hipL = mixv(a.hipL, b.hipL, t)
        p.hipR = mixv(a.hipR, b.hipR, t)
        p.kneeL = lerpf(a.kneeL, b.kneeL, t)
        p.kneeR = lerpf(a.kneeR, b.kneeR, t)
        return p
    }

    // MARK: - Библиотека поз

    static let stand = Pose()

    /// Руки в карманах куртки — расслабленно.
    static let handsInPockets: Pose = {
        var p = Pose()
        p.shoulderL = V3(0.12, 0, 0.16)
        p.shoulderR = V3(0.12, 0, -0.16)
        p.elbowL = -0.55
        p.elbowR = -0.55
        p.head = V3(0.05, 0, 0)
        return p
    }()

    /// Присела у колеса пикапа.
    static let crouchTire: Pose = {
        var p = Pose()
        p.rootY = -0.56
        p.hipL = V3(-1.7, 0, 0.15)
        p.hipR = V3(-1.5, 0, -0.15)
        p.kneeL = 2.3
        p.kneeR = 2.1
        p.spine = V3(0.35, 0, 0)
        p.chest = V3(0.15, 0, 0)
        p.head = V3(0.15, 0, 0)
        p.shoulderL = V3(-0.9, 0, 0.15)
        p.shoulderR = V3(-0.6, 0, -0.15)
        p.elbowL = -0.6
        p.elbowR = -0.8
        return p
    }()

    /// Удар ладонями: Эдвард останавливает фургон.
    static let reachPush: Pose = {
        var p = Pose()
        p.rootY = -0.12
        p.spine = V3(0.3, 0, 0)
        p.chest = V3(0.1, 0, 0)
        p.head = V3(-0.2, 0, 0)
        p.shoulderL = V3(-1.35, 0, 0.12)
        p.shoulderR = V3(-1.35, 0, -0.12)
        p.elbowL = -0.2
        p.elbowR = -0.2
        p.wristL = V3(0.9, 0, 0)
        p.wristR = V3(0.9, 0, 0)
        p.hipL = V3(-0.75, 0, 0.05)
        p.kneeL = 0.85
        p.hipR = V3(0.45, 0, -0.05)
        p.kneeR = 0.25
        return p
    }()

    /// Сидит на земле, одна нога согнута, опирается на руки.
    static let sitGround: Pose = {
        var p = Pose()
        p.rootY = -0.81
        p.hipL = V3(-1.52, 0, 0.08)
        p.kneeL = 0
        p.hipR = V3(-2.0, 0, -0.06)
        p.kneeR = 0.89
        p.spine = V3(-0.25, 0, 0)
        p.chest = V3(-0.05, 0, 0)
        p.head = V3(0.2, 0, 0)
        p.shoulderL = V3(0.55, 0, 0.25)
        p.shoulderR = V3(0.55, 0, -0.25)
        p.elbowL = -0.05
        p.elbowR = -0.05
        return p
    }()

    /// Лежит на спине.
    static let lieBack: Pose = {
        var p = Pose()
        p.rootPitch = -Float.pi / 2
        p.rootY = 0.11
        p.shoulderL = V3(0, 0, 0.22)
        p.shoulderR = V3(0, 0, -0.22)
        p.elbowL = -0.15
        p.elbowR = -0.15
        p.hipL = V3(0, 0, 0.04)
        p.hipR = V3(0, 0, -0.04)
        p.kneeL = 0.08
        p.kneeR = 0.15
        return p
    }()

    /// Лежит, правая рука откинута в сторону, лицо повёрнуто вправо.
    static let lieArmOut: Pose = {
        var p = lieBack
        p.shoulderR = V3(0, 0, -1.35)
        p.elbowR = -0.1
        p.head = V3(0, -0.45, 0)
        return p
    }()

    /// На одном колене, наклонился вперёд.
    static let kneel: Pose = {
        var p = Pose()
        p.rootY = -0.42
        p.hipL = V3(-1.3, 0, 0.1)
        p.kneeL = 0.61
        p.hipR = V3(0.15, 0, -0.08)
        p.kneeR = 1.6
        p.spine = V3(0.45, 0, 0)
        p.chest = V3(0.2, 0, 0)
        p.head = V3(0.3, 0, 0)
        p.shoulderL = V3(-1.0, 0, 0.1)
        p.shoulderR = V3(-0.9, 0, -0.1)
        p.elbowL = -0.5
        p.elbowR = -0.6
        return p
    }()

    /// На колене, низко склонился к ране.
    static let kneelBend: Pose = {
        var p = kneel
        p.spine = V3(0.85, 0, 0)
        p.chest = V3(0.35, 0, 0)
        p.head = V3(0.45, 0, 0)
        p.shoulderL = V3(-0.7, 0, 0.15)
        p.shoulderR = V3(-0.6, 0, -0.15)
        p.elbowL = -0.4
        p.elbowR = -0.3
        return p
    }()

    /// На колене, выпрямился и держит её на руках.
    static let kneelHold: Pose = {
        var p = kneel
        p.spine = V3(0.2, 0, 0)
        p.chest = V3(0.05, 0, 0)
        p.head = V3(0.35, 0, 0)
        p.shoulderL = V3(-0.95, 0, 0.3)
        p.shoulderR = V3(-0.95, 0, -0.3)
        p.elbowL = -1.25
        p.elbowR = -1.25
        return p
    }()

    /// Бэттер в стойке: бита на правом плече, взгляд на питчера.
    static let batReady: Pose = {
        var p = Pose()
        p.rootY = -0.05
        p.hipL = V3(-0.05, 0, 0.2)
        p.hipR = V3(0.05, 0, -0.2)
        p.kneeL = 0.3
        p.kneeR = 0.3
        p.spine = V3(0.2, -0.2, 0)
        p.chest = V3(0.05, -0.45, 0)
        p.head = V3(0.1, 1.1, 0)
        p.shoulderL = V3(-1.1, 0, -0.55)
        p.elbowL = -0.9
        p.shoulderR = V3(-0.45, 0, -0.35)
        p.elbowR = -1.7
        p.wristR = V3(-0.4, 0, 0)
        return p
    }()

    /// Бэттер после удара: корпус развернулся, руки ушли вперёд.
    static let batFollow: Pose = {
        var p = Pose()
        p.rootY = -0.05
        p.hipL = V3(-0.05, 0, 0.2)
        p.hipR = V3(0.1, 0, -0.2)
        p.kneeL = 0.15
        p.kneeR = 0.45
        p.hips = V3(0, 0.5, 0)
        p.spine = V3(0.15, 0.5, 0)
        p.chest = V3(0.0, 0.6, 0)
        p.head = V3(0.0, 0.2, 0)
        p.shoulderL = V3(-1.25, 0, 0.7)
        p.elbowL = -0.4
        p.shoulderR = V3(-1.45, 0, 0.3)
        p.elbowR = -0.3
        p.wristR = V3(0.6, 0, 0)
        return p
    }()

    /// Питчер: замах с поднятым коленом.
    static let pitchWindup: Pose = {
        var p = Pose()
        p.hipL = V3(-1.35, 0, 0)
        p.kneeL = 1.5
        p.chest = V3(0, -0.6, 0)
        p.head = V3(0, 0.6, 0)
        p.shoulderR = V3(0.6, 0, -1.3)
        p.elbowR = -1.2
        p.shoulderL = V3(-0.9, 0, 0.9)
        p.elbowL = -0.5
        return p
    }()

    /// Питчер: бросок.
    static let pitchRelease: Pose = {
        var p = Pose()
        p.rootY = -0.12
        p.hipL = V3(-0.6, 0, 0)
        p.kneeL = 0.5
        p.hipR = V3(0.5, 0, 0)
        p.kneeR = 0.6
        p.spine = V3(0.45, 0, 0)
        p.chest = V3(0.2, 0.5, 0)
        p.shoulderR = V3(-1.7, 0, -0.2)
        p.elbowR = -0.2
        p.shoulderL = V3(0.3, 0, 0.4)
        p.elbowL = -0.3
        return p
    }()

    /// Кэтчер на корточках с ловушкой.
    static let catcher: Pose = {
        var p = crouchTire
        p.hipL = V3(-1.6, 0, 0.45)
        p.hipR = V3(-1.6, 0, -0.45)
        p.kneeL = 2.2
        p.kneeR = 2.2
        p.spine = V3(0.25, 0, 0)
        p.head = V3(-0.15, 0, 0)
        p.shoulderL = V3(-1.3, 0, 0.2)
        p.elbowL = -0.5
        p.shoulderR = V3(-0.2, 0, -0.3)
        p.elbowR = -0.9
        return p
    }()

    /// Полевой игрок наготове.
    static let fielder: Pose = {
        var p = Pose()
        p.rootY = -0.09
        p.hipL = V3(-0.35, 0, 0.18)
        p.hipR = V3(-0.35, 0, -0.18)
        p.kneeL = 0.6
        p.kneeR = 0.6
        p.spine = V3(0.45, 0, 0)
        p.head = V3(-0.35, 0, 0)
        p.shoulderL = V3(-0.55, 0, 0.12)
        p.shoulderR = V3(-0.55, 0, -0.12)
        p.elbowL = -0.25
        p.elbowR = -0.25
        return p
    }()

    /// Охотничья стойка: Эдвард заслоняет Беллу.
    static let crouchDefend: Pose = {
        var p = Pose()
        p.rootY = -0.22
        p.hipL = V3(-1.0, 0, 0.25)
        p.hipR = V3(-0.6, 0, -0.25)
        p.kneeL = 1.4
        p.kneeR = 1.2
        p.spine = V3(0.5, 0, 0)
        p.chest = V3(0.1, 0, 0)
        p.head = V3(-0.45, 0, 0)
        p.shoulderL = V3(-0.5, 0, 0.6)
        p.shoulderR = V3(-0.5, 0, -0.6)
        p.elbowL = -0.9
        p.elbowR = -0.9
        return p
    }()

    /// Медленный танец: одна рука на плече партнёра, другая держит ладонь.
    static let dance: Pose = {
        var p = Pose()
        p.shoulderL = V3(-0.75, 0, 0.45)
        p.elbowL = -1.3
        p.shoulderR = V3(-0.9, 0, -0.35)
        p.elbowR = -0.9
        p.head = V3(0.15, 0, 0)
        return p
    }()

    /// Прикрывает лицо рукой — испуг.
    static let flinch: Pose = {
        var p = Pose()
        p.rootY = -0.06
        p.spine = V3(-0.15, 0, 0)
        p.head = V3(-0.1, 0.35, 0)
        p.shoulderL = V3(-1.6, 0, -0.3)
        p.elbowL = -1.9
        p.shoulderR = V3(-0.5, 0, -0.5)
        p.elbowR = -1.2
        p.kneeL = 0.2
        p.kneeR = 0.2
        return p
    }()

    /// Сидит на высоком лабораторном табурете, руки на столе.
    static let sitChair: Pose = {
        var p = Pose()
        p.rootY = -0.3
        p.hipL = V3(-1.5, 0, 0.06)
        p.hipR = V3(-1.5, 0, -0.06)
        p.kneeL = 1.35
        p.kneeR = 1.5
        p.spine = V3(0.12, 0, 0)
        p.head = V3(0.1, 0, 0)
        p.shoulderL = V3(-0.75, 0, 0.12)
        p.shoulderR = V3(-0.75, 0, -0.12)
        p.elbowL = -1.15
        p.elbowR = -1.15
        return p
    }()

    /// Сидит и смотрит в окуляр микроскопа.
    static let sitMicroscope: Pose = {
        var p = sitChair
        p.spine = V3(0.42, 0, 0)
        p.chest = V3(0.15, 0, 0)
        p.head = V3(0.3, 0, 0)
        p.shoulderL = V3(-1.0, 0, 0.2)
        p.shoulderR = V3(-0.9, 0, -0.25)
        p.elbowL = -1.5
        p.elbowR = -1.3
        return p
    }()

    /// Сидит, отстранившись и скрестив руки.
    static let sitAloof: Pose = {
        var p = sitChair
        p.spine = V3(-0.05, 0.25, 0)
        p.head = V3(0.05, -0.35, 0)
        p.shoulderL = V3(-0.7, 0, -0.35)
        p.shoulderR = V3(-0.7, 0, 0.35)
        p.elbowL = -1.7
        p.elbowR = -1.7
        return p
    }()

    /// Бег. phase — фаза цикла в радианах.
    static func run(_ phase: Float, power: Float = 1) -> Pose {
        var p = Pose()
        let s = sin(phase), c = cos(phase)
        p.hipL = V3(-s * 0.85 * power - 0.15, 0, 0.04)
        p.hipR = V3(s * 0.85 * power - 0.15, 0, -0.04)
        p.kneeL = (max(0, c) * 1.6 + 0.25) * power
        p.kneeR = (max(0, -c) * 1.6 + 0.25) * power
        p.shoulderL = V3(s * 0.75 * power, 0, 0.1)
        p.shoulderR = V3(-s * 0.75 * power, 0, -0.1)
        p.elbowL = -1.4
        p.elbowR = -1.4
        p.spine = V3(0.22 * power, 0, 0)
        p.chest = V3(0.04, -s * 0.15 * power, 0)
        p.head = V3(-0.12 * power, 0, 0)
        p.rootY = -abs(c) * 0.06 * power - 0.04
        p.hips = V3(0, s * 0.12 * power, 0)
        return p
    }

    /// Белла на спине у Эдварда: обхватила ногами и руками.
    static let piggyback: Pose = {
        var p = Pose()
        p.hipL = V3(-1.25, 0, 0.45)
        p.hipR = V3(-1.25, 0, -0.45)
        p.kneeL = 1.6
        p.kneeR = 1.6
        p.spine = V3(0.35, 0, 0)
        p.head = V3(0.15, 0.35, 0)
        // Руки вперёд и внутрь — обнимает его за шею, а не тянет вверх.
        p.shoulderL = V3(-1.15, 0, -0.62)
        p.shoulderR = V3(-1.15, 0, 0.62)
        p.elbowL = -0.55
        p.elbowR = -0.55
        return p
    }()

    /// Эдвард бежит, придерживая Беллу за ноги.
    static func carryRun(_ phase: Float) -> Pose {
        var p = run(phase, power: 0.85)
        p.shoulderL = V3(0.35, 0, 0.3)
        p.shoulderR = V3(0.35, 0, -0.3)
        p.elbowL = -1.2
        p.elbowR = -1.2
        return p
    }

    /// Держит букет двумя руками перед собой.
    static let holdBouquet: Pose = {
        var p = Pose()
        p.shoulderL = V3(-0.55, 0, -0.18)
        p.shoulderR = V3(-0.55, 0, 0.18)
        p.elbowL = -1.25
        p.elbowR = -1.25
        p.head = V3(0.08, 0, 0)
        return p
    }()

    /// Держит яблоко в ладонях (обложка книги).
    static let holdApple: Pose = {
        var p = Pose()
        p.shoulderL = V3(-0.6, 0, -0.08)
        p.shoulderR = V3(-0.6, 0, 0.08)
        p.elbowL = -1.45
        p.elbowR = -1.45
        p.wristL = V3(0.2, 0, 0)
        p.wristR = V3(0.2, 0, 0)
        p.head = V3(0.15, 0, 0)
        return p
    }()

    /// Ведёт под руку (Чарли у алтаря).
    static let escort: Pose = {
        var p = Pose()
        p.shoulderL = V3(-0.25, 0, 0.12)
        p.elbowL = -1.4
        p.head = V3(0.05, 0, 0)
        return p
    }()

    /// Прыжок: колени подтянуты, руки вверх.
    static let jump: Pose = {
        var p = Pose()
        p.hipL = V3(-1.1, 0, 0.1)
        p.hipR = V3(-0.6, 0, -0.1)
        p.kneeL = 1.6
        p.kneeR = 1.4
        p.spine = V3(0.2, 0, 0)
        p.shoulderL = V3(-0.4, 0, 0.9)
        p.shoulderR = V3(-0.4, 0, -0.9)
        p.elbowL = -0.6
        p.elbowR = -0.6
        return p
    }()

    /// Подкат: низко присел и откинулся назад.
    static let slide: Pose = {
        var p = Pose()
        p.rootY = -0.62
        p.hipL = V3(-1.55, 0, 0.1)
        p.hipR = V3(-1.2, 0, -0.1)
        p.kneeL = 0.4
        p.kneeR = 1.8
        p.spine = V3(-0.35, 0, 0)
        p.head = V3(0.3, 0, 0)
        p.shoulderL = V3(0.4, 0, 0.5)
        p.shoulderR = V3(0.4, 0, -0.5)
        p.elbowL = -0.2
        p.elbowR = -0.2
        return p
    }()

    /// Шаг ходьбы. phase — фаза цикла в радианах, stride — 0...1.
    static func walk(_ phase: Float, stride: Float = 1) -> Pose {
        var p = Pose()
        let s = sin(phase), c = cos(phase)
        p.hipL = V3(-s * 0.42 * stride, 0, 0.03)
        p.hipR = V3(s * 0.42 * stride, 0, -0.03)
        p.kneeL = max(0, c) * 0.75 * stride + 0.05
        p.kneeR = max(0, -c) * 0.75 * stride + 0.05
        p.shoulderL = V3(s * 0.3 * stride, 0, 0.08)
        p.shoulderR = V3(-s * 0.3 * stride, 0, -0.08)
        p.elbowL = -0.25 - max(0, -s) * 0.3
        p.elbowR = -0.25 - max(0, s) * 0.3
        p.rootY = -abs(c) * 0.025 * stride
        p.hips = V3(0, s * 0.08 * stride, 0)
        p.chest = V3(0.03, -s * 0.1 * stride, 0)
        return p
    }
}

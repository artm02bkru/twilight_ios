import UIKit

/// Причёска персонажа.
enum HairStyle {
    /// Растрёпанный «бронзовый» вихор — Эдвард.
    case messy
    /// Длинные прямые волосы — Белла, Розали, Виктория.
    case long
    /// Короткие торчащие пряди — Элис.
    case spiky
    /// Короткие тёмные кудри — Эмметт.
    case curly
    /// Длинные волосы, собранные в хвост — Джеймс.
    case ponytail
    /// Гладко зачёсаны назад — Карлайл.
    case slicked
    /// Пышная копна — Виктория.
    case wild
    /// Дреды — Лоран.
    case dreads
    /// Волнистые до плеч — Джаспер, Эсме.
    case wavy
}

/// Как персонаж выглядит: рост, телосложение, кожа, волосы и одежда.
struct CharacterLook {
    var name: String
    var height: Float = 1.75
    /// Ширина плеч (1 — обычная).
    var build: Float = 1.0
    var female: Bool = false
    var skin: UIColor
    var vampire: Bool = false
    var eyes: UIColor
    var lips: UIColor = UIColor(hex: 0xB0706A)
    var hair: HairStyle
    var hairColor: UIColor
    var top: UIColor
    var bottom: UIColor
    var shoes: UIColor = UIColor(hex: 0x1D1B1A)
    /// Юбка или платье поверх ног.
    var skirt: Bool = false
    var longSkirt: Bool = false
    /// Длинное пальто с полами.
    var coat: Bool = false
    /// Воротник куртки.
    var collar: Bool = true
    /// Гипс на левой ноге (финал).
    var legCast: Bool = false
    /// Галстук-бабочка (финал).
    var bowTie: Bool = false
    /// Ширина подола (по умолчанию — 0.36 у длинной юбки, 0.27 у короткой).
    var skirtFlare: Float? = nil
}

/// Актёрский состав.
enum Cast {

    static let humanSkin = UIColor(hex: 0xE9C3A6)
    static let paleSkin = UIColor(hex: 0xF1E6E0)
    /// Глаза Калленов — топаз.
    static let topaz = UIColor(hex: 0xC8902C)
    /// Глаза кочевников — алые.
    static let crimson = UIColor(hex: 0xA3141C)

    static let bella = CharacterLook(
        name: "Белла", height: 1.64, build: 0.86, female: true,
        skin: UIColor(hex: 0xF2D2BE), eyes: UIColor(hex: 0x4A2E1C),
        lips: UIColor(hex: 0xC27D78),
        hair: .long, hairColor: UIColor(hex: 0x3A2316),
        top: UIColor(hex: 0x3C4B5C), bottom: UIColor(hex: 0x2E3B55))

    static let edward = CharacterLook(
        name: "Эдвард", height: 1.87, build: 1.0,
        skin: paleSkin, vampire: true, eyes: topaz,
        lips: UIColor(hex: 0xC9A2A0),
        hair: .messy, hairColor: UIColor(hex: 0x7A4A28),
        top: UIColor(hex: 0x2B2B2E), bottom: UIColor(hex: 0x3A3A40))

    static let alice = CharacterLook(
        name: "Элис", height: 1.52, build: 0.8, female: true,
        skin: paleSkin, vampire: true, eyes: topaz,
        lips: UIColor(hex: 0xC8949A),
        hair: .spiky, hairColor: UIColor(hex: 0x141218),
        top: UIColor(hex: 0x3A1E3E), bottom: UIColor(hex: 0x1C1C22), skirt: true)

    static let rosalie = CharacterLook(
        name: "Розали", height: 1.75, build: 0.88, female: true,
        skin: paleSkin, vampire: true, eyes: topaz,
        lips: UIColor(hex: 0xC97F86),
        hair: .long, hairColor: UIColor(hex: 0xE6CB8A),
        top: UIColor(hex: 0xE8E4DC), bottom: UIColor(hex: 0x3B3F4A))

    static let jasper = CharacterLook(
        name: "Джаспер", height: 1.90, build: 0.98,
        skin: paleSkin, vampire: true, eyes: topaz,
        hair: .wavy, hairColor: UIColor(hex: 0xC9A15E),
        top: UIColor(hex: 0x46505A), bottom: UIColor(hex: 0x2C3036))

    static let emmett = CharacterLook(
        name: "Эмметт", height: 1.95, build: 1.25,
        skin: paleSkin, vampire: true, eyes: topaz,
        hair: .curly, hairColor: UIColor(hex: 0x231711),
        top: UIColor(hex: 0x5A6A50), bottom: UIColor(hex: 0x2A2C30))

    static let carlisle = CharacterLook(
        name: "Карлайл", height: 1.85, build: 1.0,
        skin: paleSkin, vampire: true, eyes: topaz,
        hair: .slicked, hairColor: UIColor(hex: 0xE2C885),
        top: UIColor(hex: 0x6C6A66), bottom: UIColor(hex: 0x2E2E33), coat: true)

    static let esme = CharacterLook(
        name: "Эсме", height: 1.66, build: 0.86, female: true,
        skin: paleSkin, vampire: true, eyes: topaz,
        hair: .wavy, hairColor: UIColor(hex: 0x6E4428),
        top: UIColor(hex: 0x7A5C4E), bottom: UIColor(hex: 0x3A3036), skirt: true, longSkirt: true)

    static let james = CharacterLook(
        name: "Джеймс", height: 1.80, build: 0.95,
        skin: UIColor(hex: 0xEBDDD2), vampire: true, eyes: crimson,
        hair: .ponytail, hairColor: UIColor(hex: 0xB89A62),
        top: UIColor(hex: 0x4A3A2C), bottom: UIColor(hex: 0x30302E), coat: true)

    static let laurent = CharacterLook(
        name: "Лоран", height: 1.86, build: 1.0,
        skin: UIColor(hex: 0x6E4A36), vampire: true, eyes: crimson,
        lips: UIColor(hex: 0x5E3A30),
        hair: .dreads, hairColor: UIColor(hex: 0x1A120E),
        top: UIColor(hex: 0x8A8476), bottom: UIColor(hex: 0x3A3630))

    static let victoria = CharacterLook(
        name: "Виктория", height: 1.70, build: 0.86, female: true,
        skin: UIColor(hex: 0xF0E2DA), vampire: true, eyes: crimson,
        hair: .wild, hairColor: UIColor(hex: 0xC2461C),
        top: UIColor(hex: 0x3E4A2E), bottom: UIColor(hex: 0x2C2A26))

    // MARK: Второй план

    static let banner = CharacterLook(
        name: "Мистер Баннер", height: 1.78, build: 1.1,
        skin: humanSkin, eyes: UIColor(hex: 0x3B4A5A),
        hair: .slicked, hairColor: UIColor(hex: 0x6A5A48),
        top: UIColor(hex: 0x8C7A62), bottom: UIColor(hex: 0x3E3A34), coat: true)

    static let mike = CharacterLook(
        name: "Майк", height: 1.78, build: 1.0,
        skin: UIColor(hex: 0xEBC4A4), eyes: UIColor(hex: 0x4A6A8A),
        hair: .messy, hairColor: UIColor(hex: 0xD8B96A),
        top: UIColor(hex: 0x5A6E8C), bottom: UIColor(hex: 0x2F3B52))

    static let jessica = CharacterLook(
        name: "Джессика", height: 1.6, build: 0.84, female: true,
        skin: UIColor(hex: 0xEDC8AE), eyes: UIColor(hex: 0x5A3A22),
        hair: .wavy, hairColor: UIColor(hex: 0x4A2C1A),
        top: UIColor(hex: 0xB04A5A), bottom: UIColor(hex: 0x2E3B55))

    static let angela = CharacterLook(
        name: "Анджела", height: 1.66, build: 0.84, female: true,
        skin: UIColor(hex: 0xE2B896), eyes: UIColor(hex: 0x3A2A1A),
        hair: .long, hairColor: UIColor(hex: 0x2A1C14),
        top: UIColor(hex: 0x6B7A5A), bottom: UIColor(hex: 0x3A3A44))

    static let charlie = CharacterLook(
        name: "Чарли", height: 1.8, build: 1.08,
        skin: UIColor(hex: 0xE4B898), eyes: UIColor(hex: 0x4A2E1C),
        hair: .curly, hairColor: UIColor(hex: 0x3A2A1C),
        top: UIColor(hex: 0x3A3A40), bottom: UIColor(hex: 0x3A3A40), coat: true)

    static let thugA = CharacterLook(
        name: "Незнакомец", height: 1.85, build: 1.15,
        skin: UIColor(hex: 0xD9AE8C), eyes: UIColor(hex: 0x2A2A2A),
        hair: .slicked, hairColor: UIColor(hex: 0x1A1A1A),
        top: UIColor(hex: 0x2B2B2B), bottom: UIColor(hex: 0x25272C), coat: true)

    static let thugB = CharacterLook(
        name: "Второй незнакомец", height: 1.8, build: 1.1,
        skin: UIColor(hex: 0xC99A78), eyes: UIColor(hex: 0x2A2A2A),
        hair: .curly, hairColor: UIColor(hex: 0x241A14),
        top: UIColor(hex: 0x3B3226), bottom: UIColor(hex: 0x2A2A2E))

    /// Свадебное платье: облегающее (шёлк, кружево, атлас, голубое).
    static let bellaBride: CharacterLook = {
        var look = bella
        look.name = "Белла (невеста)"
        look.top = UIColor(hex: 0xF5EFE2)
        look.bottom = UIColor(hex: 0xF5EFE2)
        look.skirt = true
        look.longSkirt = true
        look.collar = false
        return look
    }()

    /// Свадебное платье-«принцесса» с пышной юбкой.
    static let bellaPrincess: CharacterLook = {
        var look = bellaBride
        look.name = "Белла (принцесса)"
        look.skirtFlare = 0.58
        return look
    }()

    static let edwardGroom: CharacterLook = {
        var look = edward
        look.name = "Эдвард (жених)"
        look.top = UIColor(hex: 0x111114)
        look.bottom = UIColor(hex: 0x111114)
        look.bowTie = true
        look.coat = true
        return look
    }()

    /// Белла на выпускном: голубое платье и гипс на ноге.
    static let bellaProm: CharacterLook = {
        var look = bella
        look.top = UIColor(hex: 0x5C86B8)
        look.bottom = UIColor(hex: 0x5C86B8)
        look.skirt = true
        look.longSkirt = true
        look.collar = false
        look.legCast = true
        return look
    }()

    /// Эдвард в смокинге.
    static let edwardProm: CharacterLook = {
        var look = edward
        look.top = UIColor(hex: 0x111114)
        look.bottom = UIColor(hex: 0x111114)
        look.bowTie = true
        return look
    }()
}

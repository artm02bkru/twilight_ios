import SwiftUI

/// Девять глав истории — от первого взгляда до выпускного.
enum Chapter: Int, CaseIterable, Identifiable {
    case biology = 0
    case van
    case portAngeles
    case meadow
    case forest
    case baseball
    case chase
    case studio
    case prom
    case wedding

    var id: Int { rawValue }

    var number: String {
        switch self {
        case .biology:     return "ГЛАВА 1"
        case .van:         return "ГЛАВА 3"
        case .portAngeles: return "ГЛАВА 8"
        case .meadow:      return "ГЛАВА 13"
        case .forest:      return "ГЛАВА 14"
        case .baseball:    return "ГЛАВА 17"
        case .chase:       return "ГЛАВА 18"
        case .studio:      return "ГЛАВА 19"
        case .prom:        return "ЭПИЛОГ"
        case .wedding:     return "РАССВЕТ"
        }
    }

    var title: String {
        switch self {
        case .biology:     return "Первый взгляд"
        case .van:         return "Феномен"
        case .portAngeles: return "Порт-Анджелес"
        case .meadow:      return "Признание"
        case .forest:      return "Над лесом"
        case .baseball:    return "Игра"
        case .chase:       return "Охота"
        case .studio:      return "Прощание"
        case .prom:        return "Выпускной"
        case .wedding:     return "Свадьба"
        }
    }

    var place: String {
        switch self {
        case .biology:     return "Кабинет биологии. Школа Форкса"
        case .van:         return "Парковка школы Форкса"
        case .portAngeles: return "Ночные улицы Порт-Анджелеса"
        case .meadow:      return "Тайный луг в лесу"
        case .forest:      return "Лес Олимпийского полуострова"
        case .baseball:    return "Поле в глубине леса. Гроза"
        case .chase:       return "Шоссе на юг. Ночь"
        case .studio:      return "Балетная студия. Феникс"
        case .prom:        return "Беседка у школы. Сумерки"
        case .wedding:     return "Сад у дома Калленов"
        }
    }

    /// Атмосферная строка — пересказ сцены своими словами.
    var line: String {
        switch self {
        case .biology:
            return "Единственное свободное место — рядом с Эдвардом Калленом. Он смотрит так, будто она ему враг. Впереди лабораторная: определить фазы деления клетки."
        case .van:
            return "Фургон Тайлера вылетает на лёд и несётся прямо на Беллу. Между ними четыре метра и полсекунды."
        case .portAngeles:
            return "Белла заблудилась в незнакомом городе. Шаги за спиной становятся всё ближе. Нужно добраться до освещённой улицы."
        case .meadow:
            return "Облака расходятся, и Эдвард загорается тысячей алмазов. Этого не должен увидеть никто."
        case .forest:
            return "«Держись крепче». Эдвард бежит сквозь лес быстрее ветра — а Белла у него на спине."
        case .baseball:
            return "Каллены играют в бейсбол только в грозу: раскат грома — единственное, что скрывает звук удара."
        case .chase:
            return "Джеймс взял след. Элис и Джаспер увозят Беллу на юг. Фары охотника уже в зеркале."
        case .studio:
            return "Джеймс мёртв, но его яд уже в крови Беллы. Эдвард должен высосать его — и не убить её при этом."
        case .prom:
            return "Гипс на ноге, платье и Эдвард, который не принимает отказов. Последний танец этой весны."
        case .wedding:
            return "Элис взяла подготовку к свадьбе в свои руки. Но последнее слово — за тобой: платье, цветы, свет и сад."
        }
    }

    /// Что делать игроку — короткая подсказка на карточке главы.
    var rule: String {
        switch self {
        case .biology:     return "СМОТРИТЕ В МИКРОСКОП на клетку в центре и нажмите кнопку с такой же картинкой — на каждой есть подсказка. Ошибки не отнимают жизни."
        case .van:         return "КОСНИТЕСЬ ЭКРАНА, когда фургон въедет в светящуюся зону. У зоны время замедляется."
        case .portAngeles: return "СВАЙП влево/вправо — сменить полосу, ВВЕРХ — перепрыгнуть бак, ВНИЗ — пролезть под лесами. Незнакомцев обходите."
        case .meadow:      return "ВЕДИТЕ ПАЛЬЦЕМ и уводите Эдварда из солнечных лучей. В тени копятся искры."
        case .forest:      return "СВАЙП влево/вправо — обойти дерево, ВВЕРХ — прыжок через бревно, ВНИЗ — под низкую ветку."
        case .baseball:    return "КОСНИТЕСЬ ЭКРАНА, когда мяч в зоне удара. Гром заглушает звук — это лучший удар."
        case .chase:       return "СВАЙП влево/вправо — перестроиться, объезжая машины и завалы. Каждое столкновение приближает охотника."
        case .studio:      return "УДЕРЖИВАЙТЕ палец, чтобы вытянуть яд, и ОТПУСКАЙТЕ, пока жажда не взяла верх."
        case .prom:        return "КАСАЙТЕСЬ ЭКРАНА в такт: когда кольцо сойдётся с кругом. Серии без ошибок дают бонус."
        case .wedding:     return "ВЫБИРАЙТЕ наряды и оформление по пожеланиям Элис. Совпадения с её задумкой приносят очки."
        }
    }

    var accent: Color {
        switch self {
        case .biology:     return Theme.mist
        case .van:         return Theme.ice
        case .portAngeles: return Theme.amber
        case .meadow:      return Theme.amber
        case .forest:      return Theme.ice
        case .baseball:    return Theme.ice
        case .chase:       return Theme.bloodLight
        case .studio:      return Theme.bloodLight
        case .prom:        return Theme.gold
        case .wedding:     return Theme.ice
        }
    }

    var symbol: String {
        switch self {
        case .biology:     return "eye.fill"
        case .van:         return "car.side.fill"
        case .portAngeles: return "figure.run"
        case .meadow:      return "sun.max.fill"
        case .forest:      return "tree.fill"
        case .baseball:    return "bolt.fill"
        case .chase:       return "car.rear.road.lane"
        case .studio:      return "heart.slash.fill"
        case .prom:        return "music.note"
        case .wedding:     return "sparkles"
        }
    }
}

/// Сложность игры: множитель скорости и узости окон.
enum Difficulty: Int, CaseIterable, Identifiable {
    case story = 0
    case normal
    case hard

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .story:  return "История"
        case .normal: return "Обычная"
        case .hard:   return "Бессмертная"
        }
    }

    var hint: String {
        switch self {
        case .story:  return "Для тех, кто пришёл за сюжетом"
        case .normal: return "Как задумано"
        case .hard:   return "Для настоящих Калленов"
        }
    }

    /// Больше 1 — сложнее (быстрее, уже окна).
    var factor: CGFloat {
        switch self {
        case .story:  return 0.78
        case .normal: return 1.0
        case .hard:   return 1.22
        }
    }
}

/// Итог главы для экрана результата.
struct ChapterResult {
    var chapter: Chapter
    var score: Int
    var livesLeft: Int
    var rank: String
    var note: String
}

enum Ranks {
    static func rank(forScore score: Int, chapter: Chapter) -> String {
        let thresholds: (Int, Int, Int)
        switch chapter {
        case .biology:     thresholds = (300, 200, 110)
        case .van:         thresholds = (330, 220, 120)
        case .portAngeles: thresholds = (420, 280, 150)
        case .meadow:      thresholds = (400, 260, 140)
        case .forest:      thresholds = (420, 280, 150)
        case .baseball:    thresholds = (320, 210, 110)
        case .chase:       thresholds = (460, 300, 160)
        case .studio:      thresholds = (240, 160, 90)
        case .prom:        thresholds = (900, 600, 300)
        case .wedding:     thresholds = (520, 360, 200)
        }
        if score >= thresholds.0 { return "ИДЕАЛЬНО" }
        if score >= thresholds.1 { return "ОТЛИЧНО" }
        if score >= thresholds.2 { return "НОРМАЛЬНО" }
        return "СЛАБО"
    }

    static func finalRank(forScore score: Int) -> String {
        switch score {
        case 4000...: return "Бессмертная"
        case 3000...: return "Каллен"
        case 2000...: return "Посвящённая"
        case 1000...: return "Новичок из Форкса"
        default:      return "Человек"
        }
    }
}

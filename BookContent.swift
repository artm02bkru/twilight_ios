import SwiftUI

/// Четыре главы — четыре сцены книги.
enum Chapter: Int, CaseIterable, Identifiable {
    case van = 0
    case meadow
    case baseball
    case studio

    var id: Int { rawValue }

    var number: String {
        switch self {
        case .van:      return "ГЛАВА 3"
        case .meadow:   return "ГЛАВА 13"
        case .baseball: return "ГЛАВА 17"
        case .studio:   return "ГЛАВА 19"
        }
    }

    var title: String {
        switch self {
        case .van:      return "Феномен"
        case .meadow:   return "Признание"
        case .baseball: return "Игра"
        case .studio:   return "Прощание"
        }
    }

    var place: String {
        switch self {
        case .van:      return "Парковка школы Форкса"
        case .meadow:   return "Тайный луг в лесу"
        case .baseball: return "Поле в глубине леса. Гроза"
        case .studio:   return "Балетная студия. Феникс"
        }
    }

    /// Атмосферная строка — пересказ сцены своими словами.
    var line: String {
        switch self {
        case .van:
            return "Фургон Тайлера вылетает на лёд и несётся прямо на Беллу. Между ними четыре метра и полсекунды."
        case .meadow:
            return "Облака расходятся, и Эдвард загорается тысячей алмазов. Этого не должен увидеть никто."
        case .baseball:
            return "Каллены играют в бейсбол только в грозу: раскат грома — единственное, что скрывает звук удара."
        case .studio:
            return "Джеймс мёртв, но его яд уже в крови Беллы. Эдвард должен высосать его — и не убить её при этом."
        }
    }

    /// Что делать игроку — короткая подсказка на карточке главы.
    var rule: String {
        switch self {
        case .van:      return "КОСНИТЕСЬ ЭКРАНА в тот момент, когда фургон войдёт в светящуюся зону."
        case .meadow:   return "ВЕДИТЕ ПАЛЬЦЕМ и уводите Эдварда из солнечных лучей. В тени копятся искры."
        case .baseball: return "КОСНИТЕСЬ ЭКРАНА, когда мяч в зоне удара. Гром заглушает звук — это лучший удар."
        case .studio:   return "УДЕРЖИВАЙТЕ палец, чтобы вытянуть яд, и ОТПУСКАЙТЕ, пока жажда не взяла верх."
        }
    }

    var accent: Color {
        switch self {
        case .van:      return Theme.ice
        case .meadow:   return Theme.amber
        case .baseball: return Theme.ice
        case .studio:   return Theme.bloodLight
        }
    }

    var symbol: String {
        switch self {
        case .van:      return "car.side.fill"
        case .meadow:   return "sun.max.fill"
        case .baseball: return "bolt.fill"
        case .studio:   return "heart.slash.fill"
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
        case .van:      thresholds = (150, 100, 60)
        case .meadow:   thresholds = (230, 150, 80)
        case .baseball: thresholds = (190, 120, 60)
        case .studio:   thresholds = (170, 110, 60)
        }
        if score >= thresholds.0 { return "ИДЕАЛЬНО" }
        if score >= thresholds.1 { return "ОТЛИЧНО" }
        if score >= thresholds.2 { return "НОРМАЛЬНО" }
        return "СЛАБО"
    }

    static func finalRank(forScore score: Int) -> String {
        switch score {
        case 900...:  return "Бессмертная"
        case 650...:  return "Каллен"
        case 420...:  return "Посвящённая"
        case 200...:  return "Новичок из Форкса"
        default:      return "Человек"
        }
    }
}

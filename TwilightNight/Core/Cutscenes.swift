import Foundation

// MARK: - Где снимается

/// 3D-площадка. Каждая глава — своя площадка, плюс дорога (меню и пролог) и финал.
enum StageID: Hashable, CaseIterable {
    case road
    case van
    case meadow
    case baseball
    case studio
    case finale
}

extension Chapter {
    var stage: StageID {
        switch self {
        case .van:      return .van
        case .meadow:   return .meadow
        case .baseball: return .baseball
        case .studio:   return .studio
        }
    }
}

// MARK: - Какая кат-сцена

enum CutsceneID: Equatable, CustomStringConvertible {
    case prologue
    case intro(Chapter)
    case outro(Chapter)
    case finale

    var stage: StageID {
        switch self {
        case .prologue:          return .road
        case .intro(let c):      return c.stage
        case .outro(let c):      return c.stage
        case .finale:            return .finale
        }
    }

    var description: String {
        switch self {
        case .prologue:          return "prologue"
        case .intro(let c):      return "intro-\(c.rawValue)"
        case .outro(let c):      return "outro-\(c.rawValue)"
        case .finale:            return "finale"
        }
    }
}

// MARK: - Что происходит в кадре

/// Режиссёрская метка кадра. Площадка сама решает, где стоит камера
/// и что делают актёры, — сценарий хранит только порядок, длительность и реплики.
enum Cue: Equatable {
    // Пролог — дорога в Форкс
    case roadAerial, roadTruckFollow, roadTruckSide, roadTitle

    // Глава 3 — парковка
    case lotEstablish, lotBella, lotEdward, lotVanSkid, lotVanClose
    case lotDent, lotFacesBella, lotFacesEdward

    // Глава 13 — луг
    case forestHike, meadowReveal, edwardHesitates, edwardSteps, cloudsMove
    case meadowLying, meadowLyingClose, meadowSunset

    // Глава 17 — бейсбол
    case stormSky, cullensField, alicePitch, nomadsTree
    case nomadsArrive, jamesSniffs, edwardShields

    // Глава 19 — студия
    case studioEstablish, studioBite, studioCarlisle, studioEdward
    case studioCalm, studioEmbrace

    // Финал — выпускной
    case finaleDance, finaleClose, finaleCrane
}

enum ShotStyle {
    /// Обычный кадр с субтитром внизу.
    case subtitle
    /// Крупный титр по центру.
    case title
}

struct CutsceneShot {
    let cue: Cue
    let duration: Double
    /// Кто говорит. nil — закадровый текст.
    let speaker: String?
    let line: String
    var style: ShotStyle = .subtitle
}

struct Cutscene {
    let id: CutsceneID
    /// Надпись в углу кадра («ГЛАВА 3 · ФЕНОМЕН»).
    let caption: String?
    let shots: [CutsceneShot]
}

/// Где мы сейчас в кат-сцене.
struct CutscenePlayback {
    let script: Cutscene
    var index: Int = 0
    var shotTime: Double = 0

    var isFinished: Bool { index >= script.shots.count }

    var shot: CutsceneShot {
        script.shots[min(index, script.shots.count - 1)]
    }

    /// 0...1 внутри текущего кадра.
    var progress: Double {
        clamp(shotTime / max(0.01, shot.duration), 0, 1)
    }
}

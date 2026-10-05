import SwiftUI

/// Глава 1. Лабораторная по биологии: определить фазу деления клетки под микроскопом.
/// Белла и Эдвард работают в паре; быстрый верный ответ даёт больше очков.
struct BiologyScene {

    enum Phase: Int, CaseIterable {
        case interphase, prophase, metaphase, anaphase, telophase

        var title: String {
            switch self {
            case .interphase: return "Интерфаза"
            case .prophase:   return "Профаза"
            case .metaphase:  return "Метафаза"
            case .anaphase:   return "Анафаза"
            case .telophase:  return "Телофаза"
            }
        }

        /// Подсказка, которую шепчет Эдвард после ошибки.
        var clue: String {
            switch self {
            case .interphase: return "Ядро целое, хромосом не видно"
            case .prophase:   return "Хромосомы скручиваются внутри ядра"
            case .metaphase:  return "Хромосомы выстроились по центру"
            case .anaphase:   return "Хромосомы расходятся к полюсам"
            case .telophase:  return "Два новых ядра, клетка делится"
            }
        }
    }

    enum Stage { case showing, feedback }

    static let slides = 15

    var slide = 0
    var current: Phase = .prophase
    var options: [Phase] = []
    /// Случайное зерно рисунка препарата.
    var seed: Int = 1
    var stage: Stage = .showing
    var timer: Double = 0
    var timeLimit: Double = 9
    var lastCorrect: Bool? = nil
    var chosen: Phase? = nil
    var feedbackTimer: Double = 0
    var mistakes = 0
    var finished = false
    /// 0...1 — насколько микроскоп сфокусирован (анимация смены препарата).
    var focus: Double = 0
    private var difficulty: CGFloat = 1

    mutating func start(difficulty: CGFloat = 1) {
        self = BiologyScene()
        self.difficulty = difficulty
        nextSlide()
    }

    private mutating func nextSlide() {
        var phase = Phase.allCases.randomElement() ?? .prophase
        if phase == current && slide > 0 {
            phase = Phase(rawValue: (phase.rawValue + 1) % Phase.allCases.count) ?? .prophase
        }
        current = phase
        var pool = Phase.allCases.filter { $0 != phase }.shuffled()
        pool = Array(pool.prefix(3))
        options = (pool + [phase]).shuffled()
        seed = Int.random(in: 1...100_000)
        timeLimit = max(5, 9.5 - Double(slide) * 0.25) / Double(difficulty)
        timer = timeLimit
        stage = .showing
        chosen = nil
        lastCorrect = nil
        focus = 0
    }

    mutating func update(_ ctx: SceneContext) -> SceneOutcome {
        var outcome = SceneOutcome.none
        focus = min(1, focus + Double(ctx.dt) * 2.2)

        switch stage {
        case .showing:
            timer -= Double(ctx.dt)
            if let index = ctx.choice, index >= 0, index < options.count {
                answer(options[index], outcome: &outcome)
            } else if timer <= 0 {
                answer(nil, outcome: &outcome)
            }

        case .feedback:
            feedbackTimer -= Double(ctx.dt)
            if feedbackTimer <= 0 {
                slide += 1
                if slide >= Self.slides {
                    finished = true
                    outcome.chapterDone = true
                } else {
                    nextSlide()
                }
            }
        }
        return outcome
    }

    private mutating func answer(_ phase: Phase?, outcome: inout SceneOutcome) {
        chosen = phase
        stage = .feedback
        if phase == current {
            lastCorrect = true
            let speedBonus = Int(max(0, timer) / timeLimit * 20)
            let gained = 10 + speedBonus
            outcome.score = gained
            outcome.banner = Banner(text: speedBonus > 12 ? "БЛЕСТЯЩЕ  +\(gained)" : "ВЕРНО  +\(gained)",
                                    color: speedBonus > 12 ? Theme.amber : Theme.ice,
                                    x: 0.5, y: 0.2, life: 1.0, total: 1.0)
            feedbackTimer = 0.9
        } else {
            lastCorrect = false
            mistakes += 1
            outcome.banner = Banner(text: phase == nil ? "ВРЕМЯ ВЫШЛО" : "ЭТО \(current.title.uppercased())",
                                    color: Theme.bloodLight, x: 0.5, y: 0.2, life: 1.6, total: 1.6, big: true)
            // Каждая третья ошибка стоит жизни.
            if mistakes % 3 == 0 { outcome.lifeDelta = -1 }
            feedbackTimer = 1.8
        }
    }
}

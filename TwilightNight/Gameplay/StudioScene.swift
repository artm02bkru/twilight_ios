import SwiftUI

/// Глава 19. Прощание.
/// Удержание: вытянуть яд из раны, но не дать жажде взять верх.
/// Чем меньше яда осталось, тем быстрее растёт жажда — как в книге.
struct StudioScene {

    var venom: Double = 1.0
    var thirst: Double = 0
    var finished = false
    var lostControl: Double = 0
    var pulse: Double = 0
    var extracted: Double = 0
    private var scoreStep: Double = 0

    static let venomRate: Double = 0.11
    private var difficulty: Double = 1

    var thirstRate: Double {
        // Ближе к концу яда соблазн сильнее.
        (0.24 + 0.30 * (1 - venom)) * difficulty
    }

    mutating func start(difficulty: CGFloat = 1) {
        self = StudioScene()
        self.difficulty = Double(difficulty)
    }

    mutating func update(_ ctx: SceneContext) -> SceneOutcome {
        var outcome = SceneOutcome.none
        lostControl.decay(ctx.dt * 1.6)
        pulse += Double(ctx.dt) * 3.4

        if finished { return outcome }

        if ctx.touching {
            let before = venom
            venom = max(0, venom - Self.venomRate * Double(ctx.dt))
            extracted += before - venom
            thirst = min(1, thirst + thirstRate * Double(ctx.dt))

            scoreStep += before - venom
            if scoreStep >= 0.05 {
                scoreStep -= 0.05
                outcome.score = 8
            }
        } else {
            thirst = max(0, thirst - 0.50 * Double(ctx.dt))
        }

        if thirst >= 1 {
            thirst = 0.42
            lostControl = 1
            outcome.lifeDelta = -1
            outcome.banner = Banner(text: "ОН ПОТЕРЯЛ КОНТРОЛЬ", color: Theme.bloodLight,
                                    x: 0.5, y: 0.34, life: 1.25, total: 1.25, big: true)
        }

        if venom <= 0 {
            finished = true
            outcome.score = 90
            outcome.banner = Banner(text: "ЯД ВЫВЕДЕН", color: Theme.ice,
                                    x: 0.5, y: 0.34, life: 1.4, total: 1.4, big: true)
            outcome.chapterDone = true
        }

        return outcome
    }
}

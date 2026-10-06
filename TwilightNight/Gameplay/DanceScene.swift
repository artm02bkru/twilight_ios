import SwiftUI

/// Эпилог. Танец на выпускном: касаться в такт, когда кольцо сходится с кругом.
/// Серии без промахов дают бонус; на промахах Белла спотыкается на гипсе.
struct DanceScene {

    enum Judgement { case perfect, good, miss }

    struct Step {
        let time: Double
        /// Положение кольца на экране (0...1), чтобы точки «гуляли» по сцене.
        let x: CGFloat
        let y: CGFloat
        var judged: Judgement? = nil
    }

    static let approach: Double = 1.25
    static let perfectWindow: Double = 0.1
    static let goodWindow: Double = 0.2

    var steps: [Step] = []
    var time: Double = -1.5
    var combo = 0
    var bestCombo = 0
    var misses = 0
    var lastJudgement: Judgement? = nil
    var judgeTimer: Double = 0
    var finished = false
    /// 0...1 — пульс бита для подсветки сцены.
    var beatPulse: Double = 0
    private var nextBeatIndex = 0
    private var difficulty: CGFloat = 1

    var duration: Double { (steps.last?.time ?? 0) + 1.5 }
    var progress: Double { max(0, min(1, time / max(1, duration))) }

    mutating func start(difficulty: CGFloat = 1) {
        self = DanceScene()
        self.difficulty = difficulty
        // Медленный вальс: в начале редкие шаги, к концу — чаще и с синкопами.
        var t: Double = 0.5
        var i = 0
        while t < 80 {
            let phase = t / 80
            let interval = (1.3 - phase * 0.45) / Double(difficulty)
            let angle = Double(i) * 0.9
            let x = CGFloat(0.5 + cos(angle) * 0.22)
            let y = CGFloat(0.5 + sin(angle * 1.3) * 0.14)
            steps.append(Step(time: t, x: x, y: y))
            // Иногда двойной шаг.
            if phase > 0.4 && i % 5 == 4 {
                steps.append(Step(time: t + interval * 0.5, x: x, y: y + 0.06))
            }
            t += interval
            i += 1
        }
    }

    /// Шаг, к которому сейчас тянется кольцо.
    var upcoming: [Step] {
        steps.filter { $0.judged == nil && $0.time - time < Self.approach && $0.time - time > -Self.goodWindow }
    }

    mutating func update(_ ctx: SceneContext) -> SceneOutcome {
        var outcome = SceneOutcome.none
        let dt = Double(ctx.dt)
        time += dt
        judgeTimer = max(0, judgeTimer - dt)
        beatPulse = max(0, beatPulse - dt * 3)

        while nextBeatIndex < steps.count && steps[nextBeatIndex].time <= time {
            beatPulse = 1
            nextBeatIndex += 1
        }

        if ctx.tap != nil {
            // Ближайший неоценённый шаг.
            var bestIndex: Int? = nil
            var bestDelta = Double.greatestFiniteMagnitude
            for (i, step) in steps.enumerated() where step.judged == nil {
                let d = abs(step.time - time)
                if d < bestDelta {
                    bestDelta = d
                    bestIndex = i
                }
            }
            if let i = bestIndex, bestDelta < 0.35 {
                if bestDelta <= Self.perfectWindow {
                    judge(i, .perfect, &outcome)
                } else if bestDelta <= Self.goodWindow {
                    judge(i, .good, &outcome)
                } else {
                    judge(i, .miss, &outcome)
                }
            }
        }

        // Пропущенные шаги.
        for i in steps.indices where steps[i].judged == nil && time - steps[i].time > Self.goodWindow {
            judge(i, .miss, &outcome)
        }

        if time >= duration && !finished {
            finished = true
            outcome.chapterDone = true
            outcome.score += bestCombo * 5
            outcome.banner = Banner(text: "ЛУЧШАЯ СЕРИЯ: \(bestCombo)", color: Theme.gold, x: 0.5, y: 0.3,
                                    life: 1.5, total: 1.5, big: true)
        }
        return outcome
    }

    private mutating func judge(_ index: Int, _ j: Judgement, _ outcome: inout SceneOutcome) {
        steps[index].judged = j
        lastJudgement = j
        judgeTimer = 0.5
        switch j {
        case .perfect:
            combo += 1
            let gained = 20 + min(combo, 20)
            outcome.score += gained
            outcome.banner = Banner(text: combo >= 5 ? "×\(combo)  +\(gained)" : "ИДЕАЛЬНО", color: Theme.gold,
                                    x: steps[index].x, y: steps[index].y - 0.08, life: 0.6, total: 0.6)
        case .good:
            combo += 1
            outcome.score += 10
            outcome.banner = Banner(text: "ХОРОШО", color: Theme.ice, x: steps[index].x,
                                    y: steps[index].y - 0.08, life: 0.5, total: 0.5)
        case .miss:
            combo = 0
            misses += 1
            outcome.banner = Banner(text: "СБИЛАСЬ", color: Theme.bloodLight, x: steps[index].x,
                                    y: steps[index].y - 0.08, life: 0.6, total: 0.6)
            if misses % 5 == 0 { outcome.lifeDelta = -1 }
        }
        bestCombo = max(bestCombo, combo)
    }
}

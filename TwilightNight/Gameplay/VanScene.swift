import SwiftUI

/// Глава 3. Фургон.
/// Одно касание: остановить фургон ровно в тот момент, когда он входит в зону у Беллы.
/// У зоны время замедляется (как в фильме), а касание «почти вовремя» не стоит жизни.
struct VanScene {

    static let beats = 8

    enum Stage { case waiting, sliding, resolving }
    enum Quality { case perfect, good, close, missed }

    var beat = 0
    /// Позиция фургона по горизонтали, 1.4 — за правым краем.
    var vanX: CGFloat = 1.4
    var vanSpeed: CGFloat = 0.45
    var zoneX: CGFloat = 0.44
    var zoneHalf: CGFloat = 0.09

    var stage: Stage = .waiting
    var timer: Double = 0.85

    var quality: Quality? = nil
    /// 0...1 — амплитуда вспышки от удара ладонью.
    var impact: Double = 0
    /// Насколько сильно фургон смялся.
    var crumple: Double = 0
    var edwardAlpha: Double = 0
    var finished = false
    var bellaFlinch: Double = 0
    /// 0...1 — насколько сейчас замедлено время (для звука и камеры).
    var slowMotion: Double = 0

    private var difficulty: CGFloat = 1

    var currentSpeed: CGFloat { (0.40 + CGFloat(beat) * 0.03) * difficulty }
    var currentHalf: CGFloat { max(0.055, 0.1 - CGFloat(beat) * 0.005) / difficulty }

    mutating func start(difficulty: CGFloat = 1) {
        self = VanScene()
        self.difficulty = difficulty
        beginBeat()
    }

    private mutating func beginBeat() {
        vanX = 1.4
        vanSpeed = currentSpeed
        zoneHalf = currentHalf
        zoneX = CGFloat.random(in: 0.36...0.52)
        stage = .waiting
        timer = 0.9
        quality = nil
        crumple = 0
        edwardAlpha = 0
    }

    mutating func update(_ ctx: SceneContext) -> SceneOutcome {
        var outcome = SceneOutcome.none

        impact.decay(ctx.dt * 2.6)
        bellaFlinch.decay(ctx.dt * 2.2)

        switch stage {
        case .waiting:
            slowMotion.decay(ctx.dt * 3)
            timer -= Double(ctx.dt)
            if timer <= 0 { stage = .sliding }

        case .sliding:
            // У зоны — замедленная съёмка: так легче поймать момент.
            let distance = abs(vanX - zoneX)
            let near = distance < zoneHalf * 3
            let targetSlow: Double = near ? 1 : 0
            slowMotion += (targetSlow - slowMotion) * min(1, Double(ctx.dt) * 8)
            let timeScale = CGFloat(1 - slowMotion * 0.62)
            vanX -= vanSpeed * ctx.dt * timeScale

            if ctx.tap != nil {
                let dx = abs(vanX - zoneX)
                if dx <= zoneHalf {
                    // Точность: 1 — идеально по центру зоны, 0 — на самой границе.
                    let precision = 1 - Double(dx / zoneHalf)
                    quality = precision > 0.6 ? .perfect : .good
                    impact = 1
                    crumple = min(1, 0.55 + precision * 0.45)
                    edwardAlpha = 1
                    bellaFlinch = 1

                    let gained = 20 + Int(30 * precision)
                    outcome.score = gained
                    outcome.banner = Banner(
                        text: quality == .perfect ? "ИДЕАЛЬНО  +\(gained)" : "ВОВРЕМЯ  +\(gained)",
                        color: quality == .perfect ? Theme.amber : Theme.ice,
                        x: 0.5, y: 0.7, life: 1.0, total: 1.0
                    )
                    stage = .resolving
                    timer = 1.25
                } else if dx <= zoneHalf * 2.2 {
                    // Почти успел — Эдвард всё равно дотянулся, но без очков за точность.
                    quality = .close
                    impact = 0.7
                    crumple = 0.45
                    edwardAlpha = 1
                    bellaFlinch = 1
                    outcome.score = 8
                    outcome.banner = Banner(text: "ЕДВА УСПЕЛ  +8", color: Theme.mist,
                                            x: 0.5, y: 0.7, life: 1.0, total: 1.0)
                    stage = .resolving
                    timer = 1.25
                } else {
                    miss(&outcome)
                }
            } else if vanX < zoneX - zoneHalf * 2.4 {
                miss(&outcome)
            }

        case .resolving:
            slowMotion.decay(ctx.dt * 2)
            if quality != .missed {
                // Фургон замер в руке Эдварда и медленно оседает.
                vanX -= 0.02 * ctx.dt
                edwardAlpha = min(1, edwardAlpha + Double(ctx.dt) * 6)
            } else {
                vanX -= vanSpeed * 0.7 * ctx.dt
            }
            timer -= Double(ctx.dt)
            if timer <= 0 {
                beat += 1
                if beat >= Self.beats {
                    finished = true
                    outcome.chapterDone = true
                } else {
                    beginBeat()
                }
            }
        }

        return outcome
    }

    private mutating func miss(_ outcome: inout SceneOutcome) {
        quality = .missed
        outcome.lifeDelta = -1
        outcome.banner = Banner(text: "НЕ УСПЕЛ", color: Theme.bloodLight,
                                x: 0.5, y: 0.66, life: 1.1, total: 1.1, big: true)
        stage = .resolving
        timer = 1.3
    }
}

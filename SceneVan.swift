import SwiftUI

/// Глава 3. Фургон.
/// Одно касание: остановить фургон ровно в тот момент, когда он входит в зону у Беллы.
struct VanScene {

    static let beats = 5

    enum Stage { case waiting, sliding, resolving }
    enum Quality { case perfect, good, missed }

    var beat = 0
    /// Позиция фургона по горизонтали, 1.35 — за правым краем.
    var vanX: CGFloat = 1.4
    var vanSpeed: CGFloat = 0.62
    var zoneX: CGFloat = 0.44
    var zoneHalf: CGFloat = 0.055

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

    var currentSpeed: CGFloat { 0.62 + CGFloat(beat) * 0.095 }
    var currentHalf: CGFloat { max(0.030, 0.055 - CGFloat(beat) * 0.005) }

    mutating func start() {
        self = VanScene()
        beginBeat()
    }

    private mutating func beginBeat() {
        vanX = 1.4
        vanSpeed = currentSpeed
        zoneHalf = currentHalf
        zoneX = CGFloat.random(in: 0.36...0.52)
        stage = .waiting
        timer = 0.75
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
            timer -= Double(ctx.dt)
            if timer <= 0 { stage = .sliding }

        case .sliding:
            vanX -= vanSpeed * ctx.dt

            if let tap = ctx.tap {
                _ = tap
                // Точность: 1 — идеально по центру зоны, 0 — на самой границе.
                let dx = abs(vanX - zoneX)
                if dx <= zoneHalf {
                    let precision = 1 - Double(dx / zoneHalf)
                    quality = precision > 0.68 ? .perfect : .good
                    impact = 1
                    crumple = min(1, 0.55 + precision * 0.45)
                    edwardAlpha = 1
                    bellaFlinch = 1

                    let gained = 15 + Int(45 * precision)
                    outcome.score = gained
                    outcome.banner = Banner(
                        text: quality == .perfect ? "ИДЕАЛЬНО  +\(gained)" : "ВОВРЕМЯ  +\(gained)",
                        color: quality == .perfect ? Theme.amber : Theme.ice,
                        x: zoneX,
                        y: 0.74,
                        life: 0.95,
                        total: 0.95
                    )
                    stage = .resolving
                    timer = 1.05
                } else {
                    // Промах по времени — Эдвард не успел.
                    quality = .missed
                    outcome.lifeDelta = -1
                    outcome.banner = Banner(text: "НЕ УСПЕЛ", color: Theme.bloodLight,
                                            x: 0.5, y: 0.66, life: 1.0, total: 1.0, big: true)
                    stage = .resolving
                    timer = 1.15
                }
            } else if vanX < -0.25 {
                quality = .missed
                outcome.lifeDelta = -1
                outcome.banner = Banner(text: "НЕ УСПЕЛ", color: Theme.bloodLight,
                                        x: 0.5, y: 0.66, life: 1.0, total: 1.0, big: true)
                stage = .resolving
                timer = 1.15
            }

        case .resolving:
            if quality != .missed {
                // Фургон замер в руке Эдварда и медленно оседает.
                vanX -= 0.02 * ctx.dt
            } else {
                vanX -= vanSpeed * 0.7 * ctx.dt
            }
            if quality != .missed { edwardAlpha = min(1, edwardAlpha + Double(ctx.dt) * 6) }
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
}

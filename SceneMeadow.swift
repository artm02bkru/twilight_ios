import SwiftUI

/// Глава 13. Луг.
/// Ведение пальцем: уводить Эдварда из солнечных лучей. В тени копятся искры-алмазы.
struct MeadowScene {

    struct Beam: Identifiable {
        let id = UUID()
        var x: CGFloat
        var half: CGFloat
        var speed: CGFloat
        var born: Double
    }

    static let duration: Double = 21

    var edwardX: CGFloat = 0.5
    var targetX: CGFloat = 0.5
    /// 0...1 — насколько солнце уже выдало Эдварда.
    var exposure: Double = 0
    var beams: [Beam] = []
    var spawnTimer: Double = 0
    var sparkTimer: Double = 0
    var sparkles: Double = 0
    /// Мелкие блёстки на коже — просто для красоты.
    var glitter: Double = 0
    var finished = false
    var hurtFlash: Double = 0

    mutating func start() {
        self = MeadowScene()
        spawnTimer = 0.4
    }

    mutating func update(_ ctx: SceneContext) -> SceneOutcome {
        var outcome = SceneOutcome.none
        hurtFlash.decay(ctx.dt * 2.2)

        if ctx.touching {
            targetX = clamp(ctx.touchX, 0.10, 0.90)
        }
        edwardX += (targetX - edwardX) * min(1, ctx.dt * 11)

        // Лучи света выезжают из-за облаков.
        spawnTimer -= Double(ctx.dt)
        if spawnTimer <= 0 {
            let fromLeft = Bool.random()
            beams.append(Beam(
                x: fromLeft ? -0.25 : 1.25,
                half: CGFloat.random(in: 0.055...0.095),
                speed: (fromLeft ? 1 : -1) * CGFloat.random(in: 0.11...0.20),
                born: ctx.time
            ))
            spawnTimer = Double.random(in: 1.1...2.1)
        }

        for index in beams.indices {
            beams[index].x += beams[index].speed * ctx.dt
        }
        beams.removeAll { $0.x < -0.45 || $0.x > 1.45 }

        // Стоит ли Эдвард на солнце?
        let inSun = beams.contains { abs($0.x - edwardX) < $0.half + 0.028 }

        if inSun {
            exposure += Double(ctx.dt) * 0.62
            sparkTimer = 0
            if exposure >= 1 {
                exposure = 0
                hurtFlash = 1
                outcome.lifeDelta = -1
                outcome.banner = Banner(text: "ЕГО УВИДЕЛИ", color: Theme.bloodLight,
                                        x: edwardX, y: 0.60, life: 1.1, total: 1.1, big: true)
            }
        } else {
            exposure = max(0, exposure - Double(ctx.dt) * 0.42)
            glitter = min(1, glitter + Double(ctx.dt) * 1.6)

            // В тени на коже вспыхивают алмазы — это и есть очки.
            sparkTimer += Double(ctx.dt)
            if sparkTimer >= 0.38 {
                sparkTimer = 0
                sparkles += 1
                let gained = 6
                outcome.score = gained
                if Int(sparkles) % 3 == 0 {
                    outcome.banner = Banner(text: "+\(gained)", color: Theme.ice,
                                            x: edwardX + CGFloat.random(in: -0.06...0.06),
                                            y: 0.50, life: 0.7, total: 0.7)
                }
            }
        }

        if ctx.time >= Self.duration {
            finished = true
            outcome.chapterDone = true
        }

        return outcome
    }
}

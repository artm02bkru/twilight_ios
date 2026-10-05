import SwiftUI

/// Глава 17. Игра.
/// Одно касание: ударить, когда мяч в зоне. Раскат грома заглушает звук — это лучший удар.
/// Тихий удар слышно на весь лес, и кочевники подходят ближе.
struct BaseballScene {

    static let beats = 8
    static let noiseLimit = 3

    enum Stage { case waiting, flight, resolving }
    enum Quality { case perfect, normal, noisy, missed }

    var beat = 0
    /// 0 — мяч у Алисы, 1 — у биты, дальше улетает.
    var ballT: CGFloat = -0.35
    var ballSpeed: CGFloat = 0.62

    var stage: Stage = .waiting
    var timer: Double = 0.7
    var thunder: Double = 0
    var thunderPhase: Double = 0

    var noise = 0
    var quality: Quality? = nil
    var impact: Double = 0
    var ballFlight: Double = 0        // 0...1 — мяч улетает в поле
    var ballFlightX: CGFloat = 0
    var finished = false
    var noiseWarning: Double = 0

    /// Зона удара по шкале полёта мяча.
    static let strikeLow: CGFloat = 0.52
    static let strikeHigh: CGFloat = 1.02

    private var difficulty: CGFloat = 1

    mutating func start(difficulty: CGFloat = 1) {
        self = BaseballScene()
        self.difficulty = difficulty
        thunderPhase = 0.6
        beginBeat()
    }

    private mutating func beginBeat() {
        ballT = -0.35
        ballSpeed = (0.55 + CGFloat(beat) * 0.045) * difficulty
        stage = .waiting
        timer = 0.55
        quality = nil
        ballFlight = 0
    }

    mutating func update(_ ctx: SceneContext) -> SceneOutcome {
        var outcome = SceneOutcome.none

        impact.decay(ctx.dt * 3.0)
        noiseWarning.decay(ctx.dt * 1.4)
        ballFlight.decay(ctx.dt * 0.9)

        // Гром ходит волной примерно раз в 3.5 секунды.
        thunderPhase += Double(ctx.dt) * 1.75
        thunder = 0.5 - 0.5 * cos(thunderPhase)

        switch stage {
        case .waiting:
            timer -= Double(ctx.dt)
            if timer <= 0 { stage = .flight }

        case .flight:
            ballT += ballSpeed * ctx.dt

            if let _ = ctx.tap {
                if ballT >= Self.strikeLow && ballT <= Self.strikeHigh {
                    resolveSwing(&outcome, ctx: ctx)
                } else if ballT < Self.strikeLow {
                    // Слишком рано — замах в воздух.
                    quality = .missed
                    outcome.lifeDelta = -1
                    outcome.banner = Banner(text: "РАНО", color: Theme.bloodLight,
                                            x: 0.5, y: 0.60, life: 1.0, total: 1.0, big: true)
                    stage = .resolving
                    timer = 1.0
                } else {
                    quality = .missed
                    outcome.lifeDelta = -1
                    outcome.banner = Banner(text: "ПОЗДНО", color: Theme.bloodLight,
                                            x: 0.5, y: 0.60, life: 1.0, total: 1.0, big: true)
                    stage = .resolving
                    timer = 1.0
                }
            } else if ballT > Self.strikeHigh {
                quality = .missed
                outcome.lifeDelta = -1
                outcome.banner = Banner(text: "СТРАЙК", color: Theme.bloodLight,
                                        x: 0.5, y: 0.60, life: 1.0, total: 1.0, big: true)
                stage = .resolving
                timer = 1.0
            }

        case .resolving:
            ballT += ballSpeed * ctx.dt * 0.4
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

    private mutating func resolveSwing(_ outcome: inout SceneOutcome, ctx: SceneContext) {
        impact = 1
        ballFlight = 1
        ballFlightX = CGFloat.random(in: -0.35...0.35)

        let loud = thunder
        if loud > 0.66 {
            quality = .perfect
            let gained = 34 + Int(loud * 26)
            outcome.score = gained
            outcome.banner = Banner(text: "ГРОМ ЗАГЛУШИЛ УДАР  +\(gained)", color: Theme.amber,
                                    x: 0.5, y: 0.34, life: 1.1, total: 1.1, big: true)
        } else if loud > 0.34 {
            quality = .normal
            let gained = 18 + Int(loud * 14)
            outcome.score = gained
            outcome.banner = Banner(text: "ОТБИЛ  +\(gained)", color: Theme.ice,
                                    x: 0.5, y: 0.36, life: 0.9, total: 0.9)
        } else {
            quality = .noisy
            let gained = 8
            outcome.score = gained
            noise += 1
            noiseWarning = 1
            if noise >= Self.noiseLimit {
                noise = 0
                outcome.lifeDelta = -1
                outcome.banner = Banner(text: "КОЧЕВНИКИ УСЛЫШАЛИ", color: Theme.bloodLight,
                                        x: 0.5, y: 0.56, life: 1.2, total: 1.2, big: true)
            } else {
                outcome.banner = Banner(text: "ТИХО!  +\(gained)", color: Theme.bloodLight,
                                        x: 0.5, y: 0.36, life: 0.95, total: 0.95)
            }
        }

        stage = .resolving
        timer = 1.05
    }
}

import SwiftUI

/// Раннер для трёх глав: бегство по Порт-Анджелесу, полёт через лес, ночная погоня.
/// Игрок ведёт пальцем влево-вправо, препятствия набегают навстречу.
struct RunnerScene {

    enum Kind {
        /// Ночная улица: три полосы, преследователи и мусорные баки.
        case street
        /// Лес: свободное руление между стволами, высокая скорость.
        case forest
        /// Шоссе: руление между машинами и завалами, за спиной — охотник.
        case chase
    }

    struct Obstacle: Identifiable {
        let id = UUID()
        /// Горизонталь, −1...1.
        var x: CGFloat
        /// Дистанция, на которой препятствие стоит на трассе (метры).
        var at: Double
        /// Вариант модели (бак, человек, ствол, машина…).
        var variant: Int
        /// Полуширина для столкновения, в единицах x.
        var half: CGFloat
        /// Огонёк-бонус вместо препятствия.
        var pickup: Bool = false
        var consumed: Bool = false
    }

    let kind: Kind
    var duration: Double
    var time: Double = 0
    /// Пройденная дистанция, метры.
    var distance: Double = 0
    var speed: Double
    var baseSpeed: Double

    /// Положение игрока по горизонтали, −1...1.
    var playerX: CGFloat = 0
    var obstacles: [Obstacle] = []
    var spawnAt: Double = 25
    var hits = 0
    var collected = 0
    /// Неуязвимость после столкновения, секунды.
    var invulnerable: Double = 0
    /// 0...1 — насколько близко преследователь (для погони).
    var danger: Double = 0.25
    /// 0...1 — анимация спотыкания.
    var stumble: Double = 0
    var finished = false
    private var scoreStep: Double = 0
    private var difficulty: CGFloat = 1

    /// Сколько метров впереди видно и где появляются препятствия.
    static let viewAhead: Double = 70

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .street:
            duration = 75
            baseSpeed = 8.5
        case .forest:
            duration = 70
            baseSpeed = 19
        case .chase:
            duration = 80
            baseSpeed = 28
        }
        speed = baseSpeed
    }

    var lanes: Bool { kind == .street }

    static func laneX(_ lane: Int) -> CGFloat { CGFloat(lane - 1) * 0.66 }

    mutating func start(difficulty: CGFloat = 1) {
        self = RunnerScene(kind: kind)
        self.difficulty = difficulty
        speed = baseSpeed * Double(difficulty)
        spawnAt = 30
    }

    var progress: Double { min(1, time / duration) }

    mutating func update(_ ctx: SceneContext) -> SceneOutcome {
        var outcome = SceneOutcome.none
        let dt = Double(ctx.dt)
        time += dt
        invulnerable = max(0, invulnerable - dt)
        stumble.decay(ctx.dt * 2.5)

        // Управление: полосы на улице, свободное руление в лесу и на шоссе.
        if ctx.touching {
            let target: CGFloat
            if lanes {
                let lane = min(2, max(0, Int(ctx.touchX * 3)))
                target = Self.laneX(lane)
            } else {
                target = clamp((ctx.touchX - 0.5) * 2.2, -0.95, 0.95)
            }
            let rate: CGFloat = lanes ? 14 : 7
            playerX += (target - playerX) * min(1, ctx.dt * rate)
        }

        // Скорость растёт к концу главы; после удара — проседает.
        let ramp = 1 + progress * (kind == .street ? 0.35 : 0.5)
        let targetSpeed = baseSpeed * Double(difficulty) * ramp * (stumble > 0.3 ? 0.6 : 1)
        speed += (targetSpeed - speed) * min(1, dt * 2)
        distance += speed * dt

        // Новые препятствия впереди.
        while spawnAt < distance + Self.viewAhead {
            spawn(at: spawnAt)
            let gap = spacing() / Double(difficulty)
            spawnAt += gap * Double.random(in: 0.75...1.25)
        }

        // Столкновения и бонусы.
        for i in obstacles.indices where !obstacles[i].consumed {
            let rel = obstacles[i].at - distance
            guard rel < 0.8 && rel > -1.2 else { continue }
            let dx = abs(obstacles[i].x - playerX)
            if obstacles[i].pickup {
                if dx < obstacles[i].half + 0.14 {
                    obstacles[i].consumed = true
                    collected += 1
                    outcome.score += 10
                    outcome.banner = Banner(text: "+10", color: Theme.amber, x: 0.5 + playerX * 0.3,
                                            y: 0.62, life: 0.6, total: 0.6)
                }
            } else if dx < obstacles[i].half + playerHalf, invulnerable <= 0 {
                obstacles[i].consumed = true
                hit(&outcome)
            }
        }
        obstacles.removeAll { $0.at < distance - 8 }

        // Очки за пройденный путь.
        scoreStep += speed * dt
        let step = kind == .street ? 12.0 : 30.0
        if scoreStep >= step {
            scoreStep -= step
            outcome.score += 3
        }

        // Погоня: охотник отстаёт, пока едешь чисто.
        if kind == .chase {
            danger = max(0, danger - dt * 0.035)
        }

        if time >= duration {
            finished = true
            outcome.chapterDone = true
            outcome.score += 60
            outcome.banner = Banner(text: finishLine, color: Theme.ice, x: 0.5, y: 0.4,
                                    life: 1.4, total: 1.4, big: true)
        }
        return outcome
    }

    private var playerHalf: CGFloat {
        switch kind {
        case .street: return 0.12
        case .forest: return 0.07
        case .chase:  return 0.16
        }
    }

    private var finishLine: String {
        switch kind {
        case .street: return "ФАРЫ «ВОЛЬВО»!"
        case .forest: return "ДОБРАЛИСЬ"
        case .chase:  return "ОТОРВАЛИСЬ"
        }
    }

    private func spacing() -> Double {
        switch kind {
        case .street: return 9
        case .forest: return 14
        case .chase:  return 26
        }
    }

    private mutating func spawn(at position: Double) {
        // Иногда — огонёк вместо препятствия.
        if Double.random(in: 0...1) < 0.22 {
            let x: CGFloat = lanes ? Self.laneX(Int.random(in: 0...2)) : CGFloat.random(in: -0.8...0.8)
            obstacles.append(Obstacle(x: x, at: position, variant: 0, half: 0.08, pickup: true))
            return
        }
        switch kind {
        case .street:
            // Одна-две полосы перекрыты, одна всегда свободна.
            var lanesFree = [0, 1, 2].shuffled()
            let blocked = Double.random(in: 0...1) < 0.35 ? 2 : 1
            for _ in 0..<blocked {
                let lane = lanesFree.removeFirst()
                obstacles.append(Obstacle(x: Self.laneX(lane), at: position, variant: Int.random(in: 0...3), half: 0.2))
            }
        case .forest:
            let count = Double.random(in: 0...1) < 0.45 ? 2 : 1
            for _ in 0..<count {
                obstacles.append(Obstacle(x: CGFloat.random(in: -0.9...0.9), at: position + Double.random(in: -2...2),
                                          variant: Int.random(in: 0...2), half: CGFloat.random(in: 0.07...0.12)))
            }
        case .chase:
            let x = CGFloat([-0.55, 0, 0.55].randomElement() ?? 0) + CGFloat.random(in: -0.12...0.12)
            obstacles.append(Obstacle(x: x, at: position, variant: Int.random(in: 0...2), half: 0.18))
        }
    }

    private mutating func hit(_ outcome: inout SceneOutcome) {
        hits += 1
        stumble = 1
        invulnerable = 1.0
        switch kind {
        case .chase:
            danger += 0.34
            if danger >= 1 {
                danger = 0.45
                outcome.lifeDelta = -1
                outcome.banner = Banner(text: "ДЖЕЙМС НАСТИГ", color: Theme.bloodLight, x: 0.5, y: 0.45,
                                        life: 1.3, total: 1.3, big: true)
            } else {
                outcome.banner = Banner(text: "УДАР!", color: Theme.bloodLight, x: 0.5, y: 0.5, life: 0.8, total: 0.8)
            }
        case .street, .forest:
            // Каждое третье столкновение стоит жизни.
            if hits % 3 == 0 {
                outcome.lifeDelta = -1
                outcome.banner = Banner(text: kind == .street ? "ПОЙМАЛИ" : "ВРЕЗАЛИСЬ",
                                        color: Theme.bloodLight, x: 0.5, y: 0.45, life: 1.2, total: 1.2, big: true)
            } else {
                outcome.banner = Banner(text: "ОСТОРОЖНО", color: Theme.bloodLight, x: 0.5, y: 0.5,
                                        life: 0.8, total: 0.8)
            }
        }
    }
}

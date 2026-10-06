import SwiftUI

/// Раннер в духе Subway Surfers для трёх глав: Порт-Анджелес, полёт через лес, ночная погоня.
/// Три полосы; свайп влево-вправо — смена полосы, вверх — прыжок, вниз — подкат.
struct RunnerScene {

    enum Kind {
        /// Ночная улица: незнакомцы, баки, вывески над головой.
        case street
        /// Лес: стволы, поваленные деревья, низкие ветви.
        case forest
        /// Шоссе: только смена полосы, за спиной — охотник.
        case chase
    }

    /// Тип препятствия определяет, как его пройти.
    enum ObstacleType: Int {
        /// Перегораживает полосу целиком — только обойти.
        case block = 0
        /// Низкое — перепрыгнуть.
        case low = 1
        /// Высокое — пролезть подкатом.
        case high = 2
    }

    enum Swipe { case left, right, up, down }

    struct Obstacle: Identifiable {
        let id = UUID()
        var lane: Int
        /// Дистанция, на которой препятствие стоит на трассе (метры).
        var at: Double
        var type: ObstacleType
        /// Огонёк-монета вместо препятствия.
        var pickup: Bool = false
        var consumed: Bool = false

        /// Горизонталь −1...1 для сцены.
        var x: CGFloat { RunnerScene.laneX(lane) }
        /// Номер модели в сцене.
        var variant: Int { type.rawValue }
    }

    let kind: Kind
    var duration: Double
    var time: Double = 0
    var distance: Double = 0
    var speed: Double
    var baseSpeed: Double

    var lane = 1
    /// Плавное положение игрока по горизонтали, −1...1.
    var playerX: CGFloat = 0
    /// Прыжок: оставшееся время и высота (0...1).
    var jumpTime: Double = 0
    var jumpHeight: Double = 0
    /// Подкат: оставшееся время.
    var slideTime: Double = 0

    var obstacles: [Obstacle] = []
    var spawnAt: Double = 30
    var hits = 0
    var collected = 0
    var invulnerable: Double = 0
    /// 0...1 — насколько близко преследователь (для погони).
    var danger: Double = 0.25
    /// 0...1 — анимация спотыкания.
    var stumble: Double = 0
    var finished = false
    private var scoreStep: Double = 0
    private var difficulty: CGFloat = 1

    static let viewAhead: Double = 80
    static let jumpDuration: Double = 0.75
    static let slideDuration: Double = 0.8

    init(kind: Kind) {
        self.kind = kind
        switch kind {
        case .street:
            duration = 75
            baseSpeed = 11
        case .forest:
            duration = 70
            baseSpeed = 16
        case .chase:
            duration = 80
            baseSpeed = 24
        }
        speed = baseSpeed
    }

    static func laneX(_ lane: Int) -> CGFloat { CGFloat(lane - 1) * 0.66 }

    var isJumping: Bool { jumpTime > 0 }
    var isSliding: Bool { slideTime > 0 }
    var canJump: Bool { kind != .chase }

    mutating func start(difficulty: CGFloat = 1) {
        self = RunnerScene(kind: kind)
        self.difficulty = difficulty
        speed = baseSpeed * Double(difficulty)
    }

    var progress: Double { min(1, time / duration) }

    mutating func update(_ ctx: SceneContext) -> SceneOutcome {
        var outcome = SceneOutcome.none
        let dt = Double(ctx.dt)
        time += dt
        invulnerable = max(0, invulnerable - dt)
        stumble.decay(ctx.dt * 2.5)

        // Свайпы.
        switch ctx.swipe {
        case .left?:  lane = max(0, lane - 1)
        case .right?: lane = min(2, lane + 1)
        case .up?:
            if canJump && !isJumping {
                jumpTime = Self.jumpDuration
                slideTime = 0
            }
        case .down?:
            if canJump {
                slideTime = Self.slideDuration
                jumpTime = 0
            }
        case nil:
            break
        }
        let target = Self.laneX(lane)
        playerX += (target - playerX) * min(1, ctx.dt * 16)

        if jumpTime > 0 {
            jumpTime = max(0, jumpTime - dt)
            let t = 1 - jumpTime / Self.jumpDuration
            jumpHeight = sin(t * .pi)
        } else {
            jumpHeight = 0
        }
        slideTime = max(0, slideTime - dt)

        // Скорость растёт к концу главы; после удара — проседает.
        let ramp = 1 + progress * 0.4
        let targetSpeed = baseSpeed * Double(difficulty) * ramp * (stumble > 0.3 ? 0.65 : 1)
        speed += (targetSpeed - speed) * min(1, dt * 2)
        distance += speed * dt

        while spawnAt < distance + Self.viewAhead {
            spawnRow(at: spawnAt)
            let gap = spacing() / Double(difficulty)
            spawnAt += gap * Double.random(in: 0.85...1.2)
        }

        // Столкновения: своя полоса и короткое окно по дистанции.
        for i in obstacles.indices where !obstacles[i].consumed {
            let rel = obstacles[i].at - distance
            guard rel < 0.6 && rel > -0.8, obstacles[i].lane == lane else { continue }
            if obstacles[i].pickup {
                obstacles[i].consumed = true
                collected += 1
                outcome.score += 5
                continue
            }
            let cleared: Bool
            switch obstacles[i].type {
            case .block: cleared = false
            case .low:   cleared = jumpHeight > 0.45
            case .high:  cleared = isSliding
            }
            if !cleared && invulnerable <= 0 {
                obstacles[i].consumed = true
                hit(&outcome)
            }
        }
        obstacles.removeAll { $0.at < distance - 10 }

        scoreStep += speed * dt
        if scoreStep >= 15 {
            scoreStep -= 15
            outcome.score += 2
        }

        if kind == .chase {
            danger = max(0, danger - dt * 0.03)
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

    private var finishLine: String {
        switch kind {
        case .street: return "ФАРЫ «ВОЛЬВО»!"
        case .forest: return "ДОБРАЛИСЬ"
        case .chase:  return "ОТОРВАЛИСЬ"
        }
    }

    private func spacing() -> Double {
        switch kind {
        case .street: return 16
        case .forest: return 20
        case .chase:  return 30
        }
    }

    /// Ряд препятствий: хотя бы одна полоса всегда свободна или проходима.
    private mutating func spawnRow(at position: Double) {
        let free = Int.random(in: 0...2)
        for l in 0..<3 where l != free {
            guard Double.random(in: 0...1) < 0.75 else { continue }
            let type: ObstacleType
            if canJump {
                switch Int.random(in: 0...2) {
                case 0:  type = .block
                case 1:  type = .low
                default: type = .high
                }
            } else {
                type = .block
            }
            obstacles.append(Obstacle(lane: l, at: position, type: type))
        }
        // Дорожка монет по свободной полосе.
        if Double.random(in: 0...1) < 0.6 {
            for k in 0..<5 {
                obstacles.append(Obstacle(lane: free, at: position - 8 + Double(k) * 2.5, type: .block, pickup: true))
            }
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

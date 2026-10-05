import SwiftUI

// MARK: - Общие типы сцен

/// Всплывающая надпись на поле («+40», «ЯД ВЫВЕДЕН», «ПОЗДНО»).
struct Banner: Identifiable {
    let id = UUID()
    var text: String
    var color: Color
    var x: CGFloat
    var y: CGFloat
    var life: Double
    var total: Double
    var big: Bool = false
}

/// Всё, что сцена знает о вводе и мире в этом кадре.
struct SceneContext {
    var dt: CGFloat
    var time: Double
    var aspect: CGFloat
    /// Горизонталь пальца, 0...1.
    var touchX: CGFloat
    /// Палец сейчас на экране (нужно для удержания в студии).
    var touching: Bool
    /// Тап, случившийся в этом кадре, в нормированных координатах.
    var tap: CGPoint?
}

/// Что сцена сообщает движку после кадра.
struct SceneOutcome {
    var score: Int = 0
    var lifeDelta: Int = 0
    var banner: Banner? = nil
    var chapterDone: Bool = false

    static let none = SceneOutcome()
}

/// Фазы всей игры.
enum GamePhase {
    case menu
    case chapterCard
    case playing
    case paused
    case chapterResult
    case gameOver
    case finale
}

// MARK: - Мелкая математика

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(hi, max(lo, v)) }

func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

extension Double {
    /// Плавное затухание к нулю.
    mutating func decay(_ amount: Double) {
        self = max(0, self - amount)
    }
}

import SwiftUI

/// Доступ к PNG-спрайтам персонажей и их пропорции.
enum Sprite: String {
    case bella = "Bella"
    case edward = "Edward"
    case alice = "Alice"
    case rosalie = "Rosalie"
    case jasper = "Jasper"
    case emmett = "Emmett"
    case james = "James"

    case edwardReach = "Edward_reach"
    case edwardBat = "Edward_bat"
    case edwardKneel = "Edward_kneel"
    case alicePitch = "Alice_pitch"
    case emmettReach = "Emmett_reach"
    case rosalieReach = "Rosalie_reach"
    case jasperReach = "Jasper_reach"

    case van = "Van"
    case wound = "Wound"

    var image: Image { Image(rawValue) }

    /// ширина / высота исходника — чтобы не растягивать спрайт.
    var aspect: CGFloat {
        switch self {
        case .van:   return 640.0 / 340.0
        case .wound: return 900.0 / 430.0
        default:     return 400.0 / 900.0
        }
    }

    /// Прямоугольник с сохранением пропорций: `bottomY` — линия стоп фигуры.
    func rect(centerX: CGFloat, bottomY: CGFloat, height: CGFloat) -> CGRect {
        let w = height * aspect
        return CGRect(x: centerX - w / 2, y: bottomY - height, width: w, height: height)
    }

    /// Прямоугольник с сохранением пропорций вокруг центра.
    func rect(center: CGPoint, height: CGFloat) -> CGRect {
        let w = height * aspect
        return CGRect(x: center.x - w / 2, y: center.y - height / 2, width: w, height: height)
    }
}

extension GraphicsContext {

    func withOpacity(_ value: Double, _ body: (inout GraphicsContext) -> Void) {
        var copy = self
        copy.opacity = value
        body(&copy)
    }

    /// Рисует спрайт в прямоугольнике, сохраняя исходные цвета.
    func drawSprite(_ sprite: Sprite, in rect: CGRect, opacity: Double = 1) {
        guard opacity > 0.01, rect.width > 1, rect.height > 1 else { return }
        withOpacity(opacity) { ctx in
            ctx.draw(ctx.resolve(sprite.image), in: rect)
        }
    }

    /// Рисует спрайт, ставя его «стопы» на `bottomY`.
    func drawSprite(_ sprite: Sprite, centerX: CGFloat, bottomY: CGFloat,
                    height: CGFloat, opacity: Double = 1) {
        drawSprite(sprite, in: sprite.rect(centerX: centerX, bottomY: bottomY, height: height),
                   opacity: opacity)
    }
}

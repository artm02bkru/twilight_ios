import SwiftUI

/// Рисует активную сцену: фон + персонажи + эффекты + всплывающие надписи.
struct SceneCanvas: View {

    @ObservedObject var engine: GameEngine

    var body: some View {
        Canvas { context, size in
            var ctx = context
            let t = engine.time

            switch engine.chapter {
            case .van:
                drawVanScene(&ctx, size, t)
            case .meadow:
                drawMeadowScene(&ctx, size, t)
            case .baseball:
                drawBaseballScene(&ctx, size, t)
            case .studio:
                drawStudioScene(&ctx, size, t)
            }

            drawBanners(&ctx, size)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Глава 3. Фургон

    private func drawVanScene(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let scene = engine.van
        let w = size.width, h = size.height
        let ground = h * Layout.vanGround

        Backdrops.parkingLot(&ctx, size, t)

        // Зона, в которой Эдвард успевает.
        let zoneX = scene.zoneX * w
        let half = scene.zoneHalf * w
        let zoneRect = CGRect(x: zoneX - half, y: ground - h * 0.012,
                              width: half * 2, height: h * 0.026)
        ctx.fill(Path(roundedRect: zoneRect, cornerRadius: h * 0.012),
                 with: .linearGradient(
                    Gradient(colors: [Theme.ice.opacity(0.10), Theme.ice.opacity(0.85), Theme.ice.opacity(0.10)]),
                    startPoint: CGPoint(x: zoneRect.minX, y: 0),
                    endPoint: CGPoint(x: zoneRect.maxX, y: 0)))
        ctx.withOpacity(0.55) { inner in
            inner.addFilter(.blur(radius: h * 0.020))
            inner.fill(Path(roundedRect: zoneRect.insetBy(dx: -h * 0.010, dy: -h * 0.014),
                            cornerRadius: h * 0.020), with: .color(Theme.ice))
        }
        for side in [-1.0, 1.0] {
            let x = zoneX + CGFloat(side) * half
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: ground - h * 0.055))
            tick.addLine(to: CGPoint(x: x, y: ground + h * 0.012))
            ctx.stroke(tick, with: .color(Theme.ice.opacity(0.85)), lineWidth: max(2, h * 0.0035))
        }

        // Белла.
        let bellaX = w * 0.245
        let bellaH = h * 0.235
        let flinch = scene.bellaFlinch
        ctx.drawSprite(.bella,
                       in: Sprite.bella.rect(centerX: bellaX + CGFloat(flinch) * w * 0.012,
                                             bottomY: ground + h * 0.004,
                                             height: bellaH),
                       opacity: 1)

        // Следы скольжения по льду.
        if scene.stage == .sliding || scene.vanX > 0.7 {
            for i in 0..<5 {
                let y = ground + h * 0.012 + CGFloat(i) * h * 0.009
                let len = w * (0.10 + 0.06 * CGFloat(i))
                let rect = CGRect(x: scene.vanX * w + w * 0.06, y: y, width: len, height: max(1, h * 0.0025))
                ctx.fill(Path(roundedRect: rect, cornerRadius: h * 0.002),
                         with: .color(Color.white.opacity(0.20 - Double(i) * 0.03)))
            }
        }

        // Фургон.
        let vanH = h * 0.115
        let vanRect = Sprite.van.rect(centerX: scene.vanX * w, bottomY: ground + h * 0.010, height: vanH)
        var mangled = vanRect
        if scene.crumple > 0 {
            // Мятая морда: сжимаем по горизонтали со стороны удара.
            let squeeze = CGFloat(scene.crumple) * vanRect.width * 0.06
            mangled = CGRect(x: vanRect.minX + squeeze, y: vanRect.minY,
                             width: vanRect.width - squeeze, height: vanRect.height)
        }
        ctx.drawSprite(.van, in: mangled, opacity: scene.stage == .waiting && scene.vanX > 1.34 ? 0.95 : 1)

        // Эдвард появляется в момент удара.
        if scene.edwardAlpha > 0.01 {
            let edwardX = scene.vanX * w - vanRect.width * 0.46
            ctx.withOpacity(scene.edwardAlpha) { inner in
                inner.drawSprite(.edwardReach,
                                 in: Sprite.edwardReach.rect(centerX: edwardX,
                                                             bottomY: ground + h * 0.008,
                                                             height: h * 0.255))
            }
            // Ударная волна.
            if scene.impact > 0.01 {
                let r = h * 0.04 + h * 0.20 * CGFloat(1 - scene.impact)
                ctx.stroke(Path(ellipseIn: CGRect(x: edwardX - r, y: ground - h * 0.12 - r,
                                                  width: r * 2, height: r * 2)),
                           with: .color(Theme.ice.opacity(Double(scene.impact) * 0.7)),
                           lineWidth: max(2, h * 0.004))
            }
            // Ледяная крошка.
            if scene.impact > 0.05 {
                for i in 0..<14 {
                    let angle = Double(i) / 14 * .pi * 2
                    let dist = h * 0.20 * CGFloat(1 - scene.impact)
                    let px = edwardX + CGFloat(cos(angle)) * dist * 1.6
                    let py = ground - h * 0.05 + CGFloat(sin(angle)) * dist
                    let r = h * 0.004 * CGFloat(scene.impact)
                    ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                             with: .color(Color.white.opacity(Double(scene.impact) * 0.8)))
                }
            }
        }
    }

    // MARK: - Глава 13. Луг

    private func drawMeadowScene(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let scene = engine.meadow
        let w = size.width, h = size.height
        let ground = h * Layout.meadowGround

        Backdrops.meadow(&ctx, size, t)

        // Солнечные лучи — широкие тёплые столбы света.
        for beam in scene.beams {
            let cx = beam.x * w
            let halfW = beam.half * w
            let rect = CGRect(x: cx - halfW, y: -h * 0.05, width: halfW * 2, height: ground + h * 0.05)
            ctx.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [Color(red: 1.0, green: 0.96, blue: 0.78).opacity(0.10),
                                  Color(red: 1.0, green: 0.93, blue: 0.66).opacity(0.30),
                                  Color(red: 1.0, green: 0.90, blue: 0.60).opacity(0.42)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: ground)))
            // Яркое пятно на земле.
            ctx.fill(Path(ellipseIn: CGRect(x: cx - halfW * 1.05, y: ground - h * 0.032,
                                            width: halfW * 2.1, height: h * 0.048)),
                     with: .color(Color(red: 1.0, green: 0.96, blue: 0.76).opacity(0.34)))
        }

        // Белла чуть позади и слева.
        let bellaX = min(w * 0.90, max(w * 0.10, w * (0.5 + (scene.edwardX - 0.5) * 0.88) - w * 0.115))
        ctx.drawSprite(.bella,
                       in: Sprite.bella.rect(centerX: bellaX, bottomY: ground + h * 0.012, height: h * 0.215),
                       opacity: 0.95)

        // Эдвард.
        let edwardH = h * 0.275
        let edwardBottom = ground + h * 0.030
        ctx.drawSprite(.edward,
                       in: Sprite.edward.rect(centerX: scene.edwardX * w, bottomY: edwardBottom, height: edwardH))

        // Алмазные искры, когда он в тени.
        let exposed = scene.beams.contains { abs($0.x - scene.edwardX) < $0.half + 0.028 }
        if !exposed {
            let glitter = scene.glitter
            for i in 0..<22 {
                let phase = (t * 1.7 + Double(noise(i, 201)) * 3.1).truncatingRemainder(dividingBy: 1.0)
                let px = scene.edwardX * w + (noise(i, 202) - 0.5) * w * 0.10
                let py = edwardBottom - edwardH * (0.28 + 0.66 * noise(i, 203))
                let r = h * 0.0034 * CGFloat(1 - phase) * CGFloat(0.55 + 0.65 * glitter)
                guard r > 0.2 else { continue }
                let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                ctx.fill(Path(rect), with: .color(Color.white.opacity(0.85 * (1 - phase))))
                // Четырёхлучевая вспышка.
                var star = Path()
                star.move(to: CGPoint(x: px - r * 2.6, y: py)); star.addLine(to: CGPoint(x: px + r * 2.6, y: py))
                star.move(to: CGPoint(x: px, y: py - r * 2.6)); star.addLine(to: CGPoint(x: px, y: py + r * 2.6))
                ctx.stroke(star, with: .color(Color.white.opacity(0.45 * (1 - phase))),
                           lineWidth: max(1, r * 0.5))
            }
        }

        // Солнце припекает — тёплая пелена и предупреждение.
        if scene.exposure > 0.02 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                     with: .radialGradient(
                        Gradient(colors: [Color(red: 1.0, green: 0.86, blue: 0.55).opacity(0.0),
                                          Color(red: 1.0, green: 0.72, blue: 0.35).opacity(0.42 * scene.exposure)]),
                        center: CGPoint(x: scene.edwardX * w, y: edwardBottom - edwardH * 0.55),
                        startRadius: h * 0.05, endRadius: h * 0.55))
        }
        if scene.hurtFlash > 0.01 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                     with: .color(Theme.blood.opacity(0.35 * scene.hurtFlash)))
        }
    }

    // MARK: - Глава 17. Бейсбол

    private func drawBaseballScene(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let scene = engine.baseball
        let w = size.width, h = size.height
        let ground = h * Layout.fieldGround

        // Небо вспыхивает, когда гром громкий.
        let flash = max(0, scene.thunder - 0.55) / 0.45
        Backdrops.field(&ctx, size, t, lightning: flash * 0.9)

        // Игроки в поле — дальше, значит меньше и выше.
        let fielderH = h * 0.128
        let fielderBottom = ground - h * 0.045
        ctx.drawSprite(.emmettReach, in: Sprite.emmettReach.rect(centerX: w * 0.17, bottomY: fielderBottom, height: fielderH))
        ctx.drawSprite(.rosalieReach, in: Sprite.rosalieReach.rect(centerX: w * 0.47, bottomY: fielderBottom - h * 0.012, height: fielderH))
        ctx.drawSprite(.jasperReach, in: Sprite.jasperReach.rect(centerX: w * 0.80, bottomY: fielderBottom - h * 0.004, height: fielderH))

        // Ближние — Питчер и бьющий.
        let pitcherH = h * 0.145
        let pitcherBottom = ground - h * 0.012
        let pitcherX = w * 0.30
        ctx.drawSprite(.alicePitch, in: Sprite.alicePitch.rect(centerX: pitcherX, bottomY: pitcherBottom, height: pitcherH))

        let batterH = h * 0.225
        let batterX = w * 0.70
        let batterBottom = ground + h * 0.045
        ctx.drawSprite(.edwardBat, in: Sprite.edwardBat.rect(centerX: batterX, bottomY: batterBottom, height: batterH))

        // Бита.
        let batPivot = CGPoint(x: batterX + w * 0.028, y: batterBottom - batterH * 0.60)
        let swing = scene.impact
        var bat = Path()
        bat.move(to: batPivot)
        let angle = -1.45 + Double(swing) * 2.3
        bat.addLine(to: CGPoint(x: batPivot.x + CGFloat(cos(angle)) * h * 0.135,
                                y: batPivot.y + CGFloat(sin(angle)) * h * 0.135))
        ctx.stroke(bat, with: .color(Color(red: 0.78, green: 0.62, blue: 0.40)),
                   style: StrokeStyle(lineWidth: max(3, h * 0.009), lineCap: .round))

        // Мяч.
        if scene.stage == .flight || scene.stage == .resolving {
            let tt = scene.ballT
            if scene.ballFlight > 0.01 {
                // Улетает в поле: вверх и вдаль, уменьшаясь.
                let dist = CGFloat(1 - scene.ballFlight)
                let bx = batPivot.x + scene.ballFlightX * w * 0.55 * dist + w * 0.12 * dist
                let by = batPivot.y - h * 0.30 * dist + h * 0.16 * dist * dist
                let r = max(1.5, h * 0.011 * (1 - dist * 0.85))
                ctx.fill(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)),
                         with: .color(.white))
            } else if tt > -0.1 {
                let p = clamp(tt, 0, 1.2)
                let bx = lerp(pitcherX + w * 0.03, batPivot.x, min(1, p))
                let by = lerp(pitcherBottom - pitcherH * 0.72, batPivot.y, min(1, p))
                let r = lerp(h * 0.0045, h * 0.0115, min(1, p))
                // Ореол скорости.
                ctx.withOpacity(0.35) { inner in
                    var trail = Path()
                    trail.move(to: CGPoint(x: bx - w * 0.055, y: by - h * 0.012))
                    trail.addLine(to: CGPoint(x: bx, y: by))
                    inner.stroke(trail, with: .color(Theme.ice), lineWidth: r * 2.2)
                }
                ctx.fill(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(
                            Gradient(colors: [.white, Color(red: 0.80, green: 0.78, blue: 0.74)]),
                            center: CGPoint(x: bx - r * 0.3, y: by - r * 0.3),
                            startRadius: 0, endRadius: r * 1.4))
            }
        }

        // Вспышка от удара.
        if scene.impact > 0.02 {
            let r = h * 0.03 + h * 0.13 * CGFloat(1 - scene.impact)
            ctx.stroke(Path(ellipseIn: CGRect(x: batPivot.x - r, y: batPivot.y - r, width: r * 2, height: r * 2)),
                       with: .color(Theme.amber.opacity(Double(scene.impact) * 0.8)),
                       lineWidth: max(2, h * 0.005))
        }
    }

    // MARK: - Глава 19. Студия

    private func drawStudioScene(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let scene = engine.studio
        let w = size.width, h = size.height

        Backdrops.studio(&ctx, size, t)

        let cw = min(w * 0.92, h * 0.95)
        let ch = cw / Sprite.wound.aspect
        let center = CGPoint(x: w * 0.5, y: h * 0.50 + CGFloat(lostPulse(scene)) * h * 0.006)
        let rect = CGRect(x: center.x - cw / 2, y: center.y - ch / 2, width: cw, height: ch)

        // Тревожное свечение под руками.
        let glow = 0.18 + 0.42 * scene.thirst
        ctx.withOpacity(glow) { inner in
            inner.addFilter(.blur(radius: h * 0.05))
            inner.fill(Path(ellipseIn: rect.insetBy(dx: -cw * 0.05, dy: -ch * 0.10)),
                       with: .color(scene.thirst > 0.6 ? Theme.bloodLight : Theme.venom))
        }

        ctx.drawSprite(.wound, in: rect)

        if scene.lostControl > 0.01 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                     with: .color(Theme.blood.opacity(0.42 * scene.lostControl)))
        }
    }

    private func lostPulse(_ scene: StudioScene) -> Double {
        sin(scene.pulse) * scene.thirst * 0.6
    }

    // MARK: - Надписи

    private func drawBanners(_ ctx: inout GraphicsContext, _ size: CGSize) {
        for banner in engine.banners {
            let progress = min(1, max(0, banner.life / banner.total) * 2.3)
            let point = CGPoint(x: banner.x * size.width, y: banner.y * size.height)
            let fontSize = size.height * (banner.big ? 0.030 : 0.024) * CGFloat(1 + (1 - progress) * 0.12)
            let text = Text(banner.text)
                .font(.system(size: fontSize, weight: .black, design: .rounded))
            let plate = CGRect(x: point.x - size.width * 0.46, y: point.y - fontSize * 0.92,
                               width: size.width * 0.92, height: fontSize * 1.84)
            ctx.withOpacity(progress * 0.55) { inner in
                inner.addFilter(.blur(radius: size.height * 0.012))
                inner.fill(Path(roundedRect: plate, cornerRadius: fontSize), with: .color(.black))
            }
            ctx.withOpacity(progress) { inner in
                var shadow = inner
                shadow.addFilter(.blur(radius: size.height * 0.004))
                shadow.draw(text.foregroundColor(.black.opacity(0.9)),
                            at: CGPoint(x: point.x, y: point.y + fontSize * 0.06), anchor: .center)
                inner.draw(text.foregroundColor(banner.color), at: point, anchor: .center)
            }
        }
    }
}

import SwiftUI

/// Ключевые линии сцен — чтобы фоны и персонажи стояли на одной земле.
enum Layout {
    static let horizon: CGFloat = 0.60
    static let vanGround: CGFloat = 0.815
    static let meadowGround: CGFloat = 0.800
    static let fieldGround: CGFloat = 0.830
    static let studioFloor: CGFloat = 0.660
}

/// Детерминированный «шум» — чтобы звёзды, ели и снежинки не прыгали между кадрами.
func noise(_ i: Int, _ salt: Int = 0) -> CGFloat {
    let x = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
    return CGFloat(x - floor(x))
}

enum Backdrops {

    // MARK: - Глава 3. Парковка школы

    static func parkingLot(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        let horizon = h * Layout.horizon

        // Небо: плотная, но светлая хмарь Форкса.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.58, green: 0.63, blue: 0.69),
                                      Color(red: 0.80, green: 0.84, blue: 0.87)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))

        // Дальний лес.
        firRow(&ctx, size, baseY: horizon + h * 0.008, count: 24, height: h * 0.070,
               width: w * 0.052, color: Color(red: 0.26, green: 0.33, blue: 0.33), salt: 3)

        // Школа: два этажа окон, крыша, вход.
        let schoolTop = horizon - h * 0.185
        let schoolBottom = horizon + h * 0.010
        ctx.fill(Path(CGRect(x: -w * 0.05, y: schoolTop, width: w * 1.1, height: schoolBottom - schoolTop)),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.80, green: 0.75, blue: 0.68),
                                      Color(red: 0.62, green: 0.57, blue: 0.52)]),
                    startPoint: CGPoint(x: 0, y: schoolTop), endPoint: CGPoint(x: 0, y: schoolBottom)))
        ctx.fill(Path(CGRect(x: -w * 0.05, y: schoolTop - h * 0.016, width: w * 1.1, height: h * 0.020)),
                 with: .color(Color(red: 0.36, green: 0.34, blue: 0.33)))
        for row in 0..<2 {
            for i in 0..<13 {
                let x = w * 0.015 + CGFloat(i) * w * 0.076
                let y = schoolTop + h * 0.026 + CGFloat(row) * h * 0.078
                let rect = CGRect(x: x, y: y, width: w * 0.042, height: h * 0.056)
                ctx.fill(Path(rect), with: .color(Color(red: 0.30, green: 0.38, blue: 0.45)))
                ctx.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.42)),
                         with: .color(Color(red: 0.68, green: 0.76, blue: 0.82).opacity(0.85)))
                ctx.stroke(Path(rect), with: .color(Color(red: 0.42, green: 0.38, blue: 0.35)),
                           lineWidth: max(1, h * 0.0022))
            }
        }
        // Вход.
        let door = CGRect(x: w * 0.44, y: schoolBottom - h * 0.058, width: w * 0.075, height: h * 0.058)
        ctx.fill(Path(door), with: .color(Color(red: 0.33, green: 0.30, blue: 0.29)))

        // Асфальт.
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.62, green: 0.65, blue: 0.68),
                                      Color(red: 0.42, green: 0.45, blue: 0.49)]),
                    startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
        // Наледь.
        for i in 0..<11 {
            let y = horizon + (h - horizon) * (0.05 + 0.11 * noise(i, 11))
            let x = w * (noise(i, 12) * 1.2 - 0.1)
            let rw = w * (0.16 + 0.26 * noise(i, 13))
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: rw, height: h * 0.012),
                          cornerRadius: h * 0.006),
                     with: .color(Color(red: 0.86, green: 0.92, blue: 0.97).opacity(0.30)))
        }
        // Разметка парковки.
        for i in 0..<8 {
            let x = w * 0.03 + CGFloat(i) * w * 0.14
            var p = Path()
            p.move(to: CGPoint(x: x, y: horizon + h * 0.05))
            p.addLine(to: CGPoint(x: x - w * 0.03, y: h))
            ctx.stroke(p, with: .color(Color.white.opacity(0.30)), lineWidth: max(2, h * 0.0045))
        }
        // Снежные валы по нижним углам.
        snowBank(&ctx, size, x: -w * 0.10, y: h * 0.965, w: w * 0.42, h: h * 0.075)
        snowBank(&ctx, size, x: w * 0.78, y: h * 0.955, w: w * 0.36, h: h * 0.090)

        // Снег.
        precipitation(&ctx, size, t: t, count: 130, speed: 0.048, slant: -0.20,
                      color: .white, alpha: 0.75)

        // Дымка над асфальтом.
        ctx.fill(Path(CGRect(x: 0, y: horizon - h * 0.05, width: w, height: h * 0.26)),
                 with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.0), Color.white.opacity(0.16), Color.white.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: horizon - h * 0.05),
                    endPoint: CGPoint(x: 0, y: horizon + h * 0.21)))
    }

    // MARK: - Глава 13. Луг

    static func meadow(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        let horizon = h * 0.545

        // Небо: наконец-то синее.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.24, green: 0.48, blue: 0.78),
                                      Color(red: 0.62, green: 0.78, blue: 0.90)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))

        // Облака, плывущие медленно.
        clouds(&ctx, size, t: t, horizon: horizon)

        // Дальние горы.
        mountains(&ctx, size, baseY: horizon, height: h * 0.14,
                  color: Color(red: 0.36, green: 0.42, blue: 0.50), salt: 5)
        mountains(&ctx, size, baseY: horizon + h * 0.012, height: h * 0.10,
                  color: Color(red: 0.26, green: 0.34, blue: 0.36), salt: 9)

        // Стена елей по краю луга.
        firRow(&ctx, size, baseY: horizon + h * 0.030, count: 26, height: h * 0.115,
               width: w * 0.062, color: Color(red: 0.10, green: 0.22, blue: 0.16), salt: 21)
        firRow(&ctx, size, baseY: horizon + h * 0.040, count: 18, height: h * 0.085,
               width: w * 0.070, color: Color(red: 0.07, green: 0.16, blue: 0.12), salt: 33)

        // Трава.
        ctx.fill(Path(CGRect(x: 0, y: horizon + h * 0.020, width: w, height: h - horizon)),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.36, green: 0.52, blue: 0.26),
                                      Color(red: 0.20, green: 0.34, blue: 0.16),
                                      Color(red: 0.13, green: 0.24, blue: 0.12)]),
                    startPoint: CGPoint(x: 0, y: horizon + h * 0.02), endPoint: CGPoint(x: 0, y: h)))

        // Травинки и цветы.
        for i in 0..<150 {
            let x = w * noise(i, 41)
            let y = horizon + h * 0.05 + (h - horizon - h * 0.05) * pow(noise(i, 42), 0.7)
            let len = h * (0.006 + 0.012 * noise(i, 43))
            var blade = Path()
            blade.move(to: CGPoint(x: x, y: y))
            blade.addLine(to: CGPoint(x: x + (noise(i, 44) - 0.5) * len * 0.8, y: y - len))
            ctx.stroke(blade, with: .color(Color(red: 0.30, green: 0.46, blue: 0.22).opacity(0.7)),
                       lineWidth: max(1, h * 0.0018))
        }
        for i in 0..<44 {
            let x = w * noise(i, 51)
            let y = horizon + h * 0.09 + (h - horizon - h * 0.12) * pow(noise(i, 52), 0.6)
            let r = h * (0.0032 + 0.0026 * noise(i, 53))
            let warm = noise(i, 54) > 0.45
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(warm ? Color(red: 0.97, green: 0.90, blue: 0.55)
                                       : Color(red: 0.90, green: 0.72, blue: 0.90)))
        }
    }

    // MARK: - Глава 17. Поле в грозу

    static func field(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, lightning: Double) {
        let w = size.width, h = size.height
        let horizon = h * 0.52

        // Грозовое небо.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.06, green: 0.07, blue: 0.12),
                                      Color(red: 0.14, green: 0.17, blue: 0.24),
                                      Color(red: 0.22, green: 0.26, blue: 0.33)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))

        // Тучи.
        for layer in 0..<3 {
            let y = horizon * (0.16 + 0.26 * CGFloat(layer))
            let drift = CGFloat(t * (0.004 + 0.003 * Double(layer)))
            for i in 0..<7 {
                let x = ((noise(i, 60 + layer) + drift).truncatingRemainder(dividingBy: 1.25) - 0.12) * w
                let rw = w * (0.20 + 0.22 * noise(i, 70 + layer))
                let rh = h * (0.030 + 0.020 * noise(i, 80 + layer))
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: rw, height: rh)),
                         with: .color(Color(red: 0.10, green: 0.12, blue: 0.18).opacity(0.75)))
            }
        }

        // Вспышка молнии.
        if lightning > 0.01 {
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon)),
                     with: .color(Color(red: 0.85, green: 0.90, blue: 1.0).opacity(0.45 * lightning)))
            var bolt = Path()
            var bx = w * 0.24
            var by: CGFloat = 0
            bolt.move(to: CGPoint(x: bx, y: by))
            var seed = 1
            while by < horizon {
                by += h * 0.05
                bx += (noise(seed, 91) - 0.5) * w * 0.06
                bolt.addLine(to: CGPoint(x: bx, y: by))
                seed += 1
            }
            ctx.stroke(bolt, with: .color(Color.white.opacity(0.85 * lightning)),
                       lineWidth: max(2, h * 0.004))
        }

        // Чаща вокруг поля.
        firRow(&ctx, size, baseY: horizon + h * 0.035, count: 28, height: h * 0.155,
               width: w * 0.070, color: Color(red: 0.045, green: 0.085, blue: 0.075), salt: 101)
        firRow(&ctx, size, baseY: horizon + h * 0.055, count: 16, height: h * 0.115,
               width: w * 0.085, color: Color(red: 0.030, green: 0.060, blue: 0.055), salt: 111)

        // Трава.
        ctx.fill(Path(CGRect(x: 0, y: horizon + h * 0.030, width: w, height: h - horizon)),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.14, green: 0.24, blue: 0.14),
                                      Color(red: 0.07, green: 0.13, blue: 0.08)]),
                    startPoint: CGPoint(x: 0, y: horizon + h * 0.03), endPoint: CGPoint(x: 0, y: h)))

        // Земляная площадка.
        let dirt = CGRect(x: w * 0.30, y: horizon + h * 0.085, width: w * 0.52, height: h * 0.20)
        ctx.fill(Path(ellipseIn: dirt), with: .linearGradient(
            Gradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.20),
                              Color(red: 0.22, green: 0.16, blue: 0.12)]),
            startPoint: CGPoint(x: 0, y: dirt.minY), endPoint: CGPoint(x: 0, y: dirt.maxY)))
        // Дорожка от питчера к дому.
        ctx.fill(Path(ellipseIn: CGRect(x: w * 0.46, y: horizon + h * 0.20, width: w * 0.10, height: h * 0.055)),
                 with: .color(Color(red: 0.30, green: 0.22, blue: 0.16)))

        // Дождь.
        precipitation(&ctx, size, t: t, count: 110, speed: 0.30, slant: -0.16,
                      color: Color(red: 0.75, green: 0.85, blue: 1.0), alpha: 0.30, streak: h * 0.030)

        // Тёмная виньетка грозы.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: .radialGradient(
                    Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.45)]),
                    center: CGPoint(x: w * 0.5, y: h * 0.45),
                    startRadius: h * 0.25, endRadius: h * 0.85))
    }

    // MARK: - Глава 19. Балетная студия

    static func studio(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        let floorY = h * Layout.studioFloor

        // Стена.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: floorY)),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.10, green: 0.09, blue: 0.10),
                                      Color(red: 0.18, green: 0.16, blue: 0.17)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: floorY)))

        // Зеркала вдоль стены.
        let mirrorTop = h * 0.10
        let mirrorBottom = floorY - h * 0.030
        for i in 0..<5 {
            let x = w * 0.02 + CGFloat(i) * w * 0.198
            let rect = CGRect(x: x, y: mirrorTop, width: w * 0.176, height: mirrorBottom - mirrorTop)
            ctx.fill(Path(roundedRect: rect, cornerRadius: h * 0.006),
                     with: .linearGradient(
                        Gradient(colors: [Color(red: 0.20, green: 0.22, blue: 0.25),
                                          Color(red: 0.12, green: 0.13, blue: 0.16)]),
                        startPoint: CGPoint(x: rect.minX, y: 0),
                        endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            // Косой блик.
            var gleam = Path()
            gleam.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.maxY))
            gleam.addLine(to: CGPoint(x: rect.minX + rect.width * 0.55, y: rect.minY))
            gleam.addLine(to: CGPoint(x: rect.minX + rect.width * 0.70, y: rect.minY))
            gleam.addLine(to: CGPoint(x: rect.minX + rect.width * 0.30, y: rect.maxY))
            gleam.closeSubpath()
            ctx.fill(gleam, with: .color(Color.white.opacity(0.045)))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: h * 0.006),
                       with: .color(Color.white.opacity(0.10)), lineWidth: max(1, h * 0.002))
        }

        // Балетный станок.
        let barreY = floorY - h * 0.155
        ctx.fill(Path(CGRect(x: 0, y: barreY, width: w, height: h * 0.008)),
                 with: .color(Color(red: 0.42, green: 0.32, blue: 0.24)))
        for i in 0..<7 {
            let x = w * (0.06 + CGFloat(i) * 0.147)
            ctx.fill(Path(CGRect(x: x, y: barreY, width: w * 0.010, height: h * 0.155)),
                     with: .color(Color(red: 0.30, green: 0.24, blue: 0.20)))
        }

        // Окно с лунным светом.
        let win = CGRect(x: w * 0.68, y: h * 0.055, width: w * 0.26, height: h * 0.16)
        ctx.fill(Path(win), with: .color(Color(red: 0.55, green: 0.65, blue: 0.80).opacity(0.55)))
        var mullion = Path()
        mullion.move(to: CGPoint(x: win.midX, y: win.minY)); mullion.addLine(to: CGPoint(x: win.midX, y: win.maxY))
        mullion.move(to: CGPoint(x: win.minX, y: win.midY)); mullion.addLine(to: CGPoint(x: win.maxX, y: win.midY))
        ctx.stroke(mullion, with: .color(Color(red: 0.12, green: 0.11, blue: 0.12)), lineWidth: max(2, h * 0.005))
        ctx.stroke(Path(win), with: .color(Color(red: 0.12, green: 0.11, blue: 0.12)), lineWidth: max(3, h * 0.008))

        // Луч света на полу.
        var shaft = Path()
        shaft.move(to: CGPoint(x: win.minX, y: win.maxY))
        shaft.addLine(to: CGPoint(x: win.minX + w * 0.02, y: floorY))
        shaft.addLine(to: CGPoint(x: win.maxX - w * 0.10, y: h))
        shaft.addLine(to: CGPoint(x: win.maxX, y: win.maxY))
        shaft.closeSubpath()
        ctx.fill(shaft, with: .linearGradient(
            Gradient(colors: [Color(red: 0.70, green: 0.80, blue: 0.95).opacity(0.20),
                              Color(red: 0.70, green: 0.80, blue: 0.95).opacity(0.02)]),
            startPoint: CGPoint(x: 0, y: win.maxY), endPoint: CGPoint(x: 0, y: h)))

        // Деревянный пол.
        ctx.fill(Path(CGRect(x: 0, y: floorY, width: w, height: h - floorY)),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.30, green: 0.21, blue: 0.15),
                                      Color(red: 0.16, green: 0.11, blue: 0.08)]),
                    startPoint: CGPoint(x: 0, y: floorY), endPoint: CGPoint(x: 0, y: h)))
        for i in 0..<13 {
            let y = floorY + (h - floorY) * CGFloat(i) / 13
            ctx.fill(Path(CGRect(x: 0, y: y, width: w, height: max(1, h * 0.0016))),
                     with: .color(Color.black.opacity(0.25)))
        }
        for i in 0..<9 {
            let x = w * CGFloat(i) / 9
            var seam = Path()
            seam.move(to: CGPoint(x: x, y: floorY))
            seam.addLine(to: CGPoint(x: x - w * 0.03, y: h))
            ctx.stroke(seam, with: .color(Color.black.opacity(0.18)), lineWidth: max(1, h * 0.0016))
        }

        // Пыль в лунном свете.
        for i in 0..<46 {
            let phase = (t * 0.06 + Double(noise(i, 131))).truncatingRemainder(dividingBy: 1.0)
            let x = win.minX + (win.maxX - win.minX) * noise(i, 132) + CGFloat(phase) * w * 0.02
            let y = win.maxY + (h - win.maxY) * CGFloat(phase)
            let r = h * (0.0016 + 0.0022 * noise(i, 133))
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                     with: .color(Color.white.opacity(0.22)))
        }

        // Тёмная рамка.
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: .radialGradient(
                    Gradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)]),
                    center: CGPoint(x: w * 0.5, y: h * 0.45),
                    startRadius: h * 0.20, endRadius: h * 0.80))
    }

    // MARK: - Общие детали

    private static func snowBank(_ ctx: inout GraphicsContext, _ size: CGSize,
                                 x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        let rect = CGRect(x: x, y: y, width: w, height: h)
        ctx.fill(Path(roundedRect: rect, cornerRadius: h * 0.5),
                 with: .linearGradient(
                    Gradient(colors: [Color(red: 0.92, green: 0.95, blue: 0.99),
                                      Color(red: 0.70, green: 0.76, blue: 0.84)]),
                    startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
    }

    private static func firRow(_ ctx: inout GraphicsContext, _ size: CGSize, baseY: CGFloat,
                               count: Int, height: CGFloat, width: CGFloat,
                               color: Color, salt: Int) {
        for i in 0..<count {
            let x = size.width * (CGFloat(i) + noise(i, salt) * 0.7) / CGFloat(count)
            let hh = height * (0.72 + 0.55 * noise(i, salt + 1))
            let ww = width * (0.80 + 0.45 * noise(i, salt + 2))
            for level in 0..<4 {
                let scale = 1.0 - CGFloat(level) * 0.20
                let top = baseY - hh + CGFloat(level) * hh * 0.21
                var tri = Path()
                tri.move(to: CGPoint(x: x, y: top))
                tri.addLine(to: CGPoint(x: x - ww * scale * 0.5, y: top + hh * 0.42))
                tri.addLine(to: CGPoint(x: x + ww * scale * 0.5, y: top + hh * 0.42))
                tri.closeSubpath()
                ctx.fill(tri, with: .color(color))
            }
        }
    }

    private static func mountains(_ ctx: inout GraphicsContext, _ size: CGSize,
                                  baseY: CGFloat, height: CGFloat, color: Color, salt: Int) {
        var path = Path()
        path.move(to: CGPoint(x: -size.width * 0.05, y: baseY))
        let steps = 9
        for i in 0...steps {
            let x = size.width * CGFloat(i) / CGFloat(steps) * 1.1 - size.width * 0.05
            let peak = baseY - height * (0.45 + 0.85 * noise(i, salt))
            path.addLine(to: CGPoint(x: x, y: peak))
            path.addLine(to: CGPoint(x: x + size.width * 0.06, y: baseY))
        }
        path.addLine(to: CGPoint(x: size.width * 1.1, y: baseY + height))
        path.addLine(to: CGPoint(x: -size.width * 0.05, y: baseY + height))
        path.closeSubpath()
        ctx.fill(path, with: .color(color))
    }

    private static func clouds(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double, horizon: CGFloat) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: size.height * 0.016))
            for i in 0..<7 {
                let speed = 0.0030 + 0.0040 * Double(noise(i, 141))
                let x = ((noise(i, 142) + t * speed).truncatingRemainder(dividingBy: 1.3) - 0.15) * size.width
                let y = horizon * (0.10 + 0.60 * noise(i, 143))
                let rw = size.width * (0.20 + 0.22 * noise(i, 144))
                let rh = size.height * (0.020 + 0.018 * noise(i, 145))
                // тело облака из нескольких перекрывающихся овалов
                for k in 0..<5 {
                    let kx = x + rw * (CGFloat(k) * 0.20 - 0.05)
                    let ky = y + rh * (noise(i * 7 + k, 146) - 0.5) * 1.1
                    let krw = rw * (0.42 + 0.30 * noise(i * 7 + k, 147))
                    let krh = rh * (0.75 + 0.60 * noise(i * 7 + k, 148))
                    layer.fill(Path(ellipseIn: CGRect(x: kx, y: ky, width: krw, height: krh)),
                               with: .color(Color.white.opacity(0.72)))
                }
            }
        }
    }

    private static func precipitation(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double,
                                      count: Int, speed: Double, slant: Double,
                                      color: Color, alpha: Double, streak: CGFloat = 0) {
        for i in 0..<count {
            let baseX = noise(i, 151)
            let phase = (noise(i, 152) + t * speed * (0.7 + 0.8 * Double(noise(i, 153))))
                .truncatingRemainder(dividingBy: 1.0)
            let x = (baseX + CGFloat(phase) * CGFloat(slant) + 1.0).truncatingRemainder(dividingBy: 1.0) * size.width
            let y = CGFloat(phase) * (size.height * 1.1) - size.height * 0.05
            let r = max(0.8, size.height * (0.0016 + 0.0020 * noise(i, 154)))
            if streak > 0 {
                var line = Path()
                line.move(to: CGPoint(x: x, y: y))
                line.addLine(to: CGPoint(x: x + CGFloat(slant) * streak * 0.6, y: y + streak))
                ctx.stroke(line, with: .color(color.opacity(alpha)), lineWidth: r)
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                         with: .color(color.opacity(alpha)))
            }
        }
    }
}

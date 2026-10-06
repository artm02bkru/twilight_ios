import SwiftUI

// MARK: - Микроскоп (глава 1)

/// Окуляр микроскопа с препаратом и кнопки ответов.
struct BiologyOverlay: View {
    @ObservedObject var engine: GameEngine

    var body: some View {
        let s = engine.biology
        GeometryReader { geo in
            let side = min(geo.size.width * 0.55, geo.size.height * 0.4)
            VStack(spacing: 14) {
                Spacer(minLength: geo.size.height * 0.11)
                Text("Какая фаза у клетки в центре? Сравните с картинками на кнопках")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundColor(Theme.ice)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .allowsHitTesting(false)
                ZStack {
                    MicroscopeSlide(phase: s.current, seed: s.seed, focus: s.focus)
                        .frame(width: side, height: side)
                        .clipShape(Circle())
                    // Таймер по краю окуляра.
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, s.timer / s.timeLimit)))
                        .stroke(s.timer / s.timeLimit < 0.3 ? Theme.bloodLight : Theme.ice,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: side + 14, height: side + 14)
                    Circle()
                        .stroke(Color.black, lineWidth: 10)
                        .frame(width: side + 2, height: side + 2)
                }
                .shadow(color: .black.opacity(0.8), radius: 30)
                .allowsHitTesting(false)

                if s.stage == .feedback && s.lastCorrect == false {
                    Text("Эдвард шепчет: «\(s.current.clue)»")
                        .font(Theme.body(14, weight: .semibold))
                        .italic()
                        .foregroundColor(Theme.amber)
                        .transition(.opacity)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(Array(s.options.enumerated()), id: \.offset) { index, phase in
                        Button {
                            engine.choose(index)
                        } label: {
                            HStack(spacing: 10) {
                                // Мини-схема фазы — сравните с препаратом.
                                MicroscopeSlide(phase: phase, seed: 7, focus: 1, iconOnly: true)
                                    .frame(width: 46, height: 46)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(phase.title.uppercased())
                                        .font(Theme.body(15, weight: .heavy))
                                        .tracking(1)
                                    Text(phase.clue)
                                        .font(Theme.body(11, weight: .medium))
                                        .foregroundColor(.white.opacity(0.75))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill(for: phase, s)))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(s.stage != .showing)
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func fill(for phase: BiologyScene.Phase, _ s: BiologyScene) -> Color {
        guard s.stage == .feedback else { return Color.black.opacity(0.55) }
        if phase == s.current { return Color(red: 0.15, green: 0.55, blue: 0.3).opacity(0.9) }
        if phase == s.chosen { return Theme.blood.opacity(0.85) }
        return Color.black.opacity(0.4)
    }
}

/// Препарат под микроскопом: клетки кончика корня, в центре — клетка в нужной фазе митоза.
struct MicroscopeSlide: View {
    let phase: BiologyScene.Phase
    let seed: Int
    let focus: Double
    /// Только главная клетка крупно — для иконок на кнопках.
    var iconOnly: Bool = false

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: UInt64(seed))
            let w = size.width, h = size.height
            if iconOnly {
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.97, green: 0.86, blue: 0.9)))
                drawPhase(&ctx, in: CGRect(x: w * 0.06, y: h * 0.12, width: w * 0.88, height: h * 0.76), rng: &rng)
                return
            }
            // Окрашенная ткань.
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.98, green: 0.88, blue: 0.9),
                                                             Color(red: 0.86, green: 0.66, blue: 0.78)]),
                                           center: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endRadius: w * 0.7))
            // Сетка клеток, похожая на кирпичную кладку.
            let cellW = w / 4.2, cellH = h / 6.0
            let wall = Color(red: 0.62, green: 0.38, blue: 0.55).opacity(0.75)
            let nucleus = Color(red: 0.42, green: 0.16, blue: 0.42)
            var row: CGFloat = -1
            while row * cellH < h + cellH {
                let offset = Int(row) % 2 == 0 ? 0 : cellW / 2
                var col: CGFloat = -1
                while col * cellW < w + cellW {
                    let x = col * cellW + offset + CGFloat(rng.range(-3, 3))
                    let y = row * cellH + CGFloat(rng.range(-2, 2))
                    let rect = CGRect(x: x, y: y, width: cellW - 2, height: cellH - 2)
                    let isCenter = rect.contains(CGPoint(x: w / 2, y: h / 2))
                    ctx.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(wall), lineWidth: 2)
                    if !isCenter {
                        let r = min(cellW, cellH) * CGFloat(rng.range(0.16, 0.22))
                        let c = CGPoint(x: rect.midX + CGFloat(rng.range(-4, 4)), y: rect.midY + CGFloat(rng.range(-3, 3)))
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                 with: .color(nucleus.opacity(0.75)))
                    }
                    col += 1
                }
                row += 1
            }
            // Главная клетка — крупнее, по центру.
            let main = CGRect(x: w / 2 - cellW * 0.75, y: h / 2 - cellH * 0.8, width: cellW * 1.5, height: cellH * 1.6)
            ctx.fill(Path(roundedRect: main, cornerRadius: 10), with: .color(Color(red: 0.97, green: 0.86, blue: 0.9)))
            ctx.stroke(Path(roundedRect: main, cornerRadius: 10), with: .color(wall), lineWidth: 3)
            drawPhase(&ctx, in: main, rng: &rng)
        }
        .blur(radius: CGFloat((1 - focus) * 6))
        .overlay(
            RadialGradient(colors: [.clear, .clear, Color.black.opacity(iconOnly ? 0 : 0.75)],
                           center: .center, startRadius: 0, endRadius: 260)
        )
    }

    private func drawPhase(_ ctx: inout GraphicsContext, in r: CGRect, rng: inout SeededRandom) {
        let chromo = Color(red: 0.3, green: 0.05, blue: 0.32)
        let c = CGPoint(x: r.midX, y: r.midY)
        let spindle = Color(red: 0.5, green: 0.3, blue: 0.5).opacity(0.35)

        func rod(_ p: CGPoint, angle: Double, length: CGFloat, width: CGFloat = 5) {
            var path = Path()
            path.move(to: CGPoint(x: p.x - CGFloat(cos(angle)) * length / 2, y: p.y - CGFloat(sin(angle)) * length / 2))
            path.addLine(to: CGPoint(x: p.x + CGFloat(cos(angle)) * length / 2, y: p.y + CGFloat(sin(angle)) * length / 2))
            ctx.stroke(path, with: .color(chromo), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        func spindles(from a: CGPoint, to b: CGPoint) {
            for i in 0..<9 {
                let t = CGFloat(i) / 8 - 0.5
                var p = Path()
                p.move(to: a)
                p.addQuadCurve(to: b, control: CGPoint(x: c.x, y: c.y + t * r.height * 0.9))
                ctx.stroke(p, with: .color(spindle), lineWidth: 1)
            }
        }
        let left = CGPoint(x: r.minX + r.width * 0.12, y: c.y)
        let right = CGPoint(x: r.maxX - r.width * 0.12, y: c.y)

        switch phase {
        case .interphase:
            let rad = min(r.width, r.height) * 0.26
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2)),
                     with: .color(Color(red: 0.55, green: 0.3, blue: 0.55)))
            for _ in 0..<40 {
                let a = Double(rng.range(0, 6.28)), d = CGFloat(rng.range(0, 0.9)) * rad
                let p = CGPoint(x: c.x + CGFloat(cos(a)) * d, y: c.y + CGFloat(sin(a)) * d)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)), with: .color(chromo.opacity(0.6)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 8, width: 12, height: 12)), with: .color(chromo))
        case .prophase:
            let rad = min(r.width, r.height) * 0.3
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2)),
                       with: .color(Color(red: 0.55, green: 0.3, blue: 0.55).opacity(0.6)), lineWidth: 2)
            for _ in 0..<8 {
                var p = Path()
                var pt = CGPoint(x: c.x + CGFloat(rng.range(-0.6, 0.6)) * rad, y: c.y + CGFloat(rng.range(-0.6, 0.6)) * rad)
                p.move(to: pt)
                for _ in 0..<4 {
                    let next = CGPoint(x: pt.x + CGFloat(rng.range(-14, 14)), y: pt.y + CGFloat(rng.range(-14, 14)))
                    p.addQuadCurve(to: next, control: CGPoint(x: (pt.x + next.x) / 2 + CGFloat(rng.range(-8, 8)),
                                                             y: (pt.y + next.y) / 2 + CGFloat(rng.range(-8, 8))))
                    pt = next
                }
                ctx.stroke(p, with: .color(chromo), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            }
        case .metaphase:
            spindles(from: left, to: right)
            for i in 0..<7 {
                let y = c.y + (CGFloat(i) - 3) * r.height * 0.09
                rod(CGPoint(x: c.x + CGFloat(rng.range(-3, 3)), y: y), angle: Double(rng.range(-0.3, 0.3)), length: 16, width: 6)
            }
        case .anaphase:
            spindles(from: left, to: right)
            for side in [-1.0, 1.0] {
                for i in 0..<6 {
                    let y = c.y + (CGFloat(i) - 2.5) * r.height * 0.09
                    let x = c.x + CGFloat(side) * r.width * CGFloat(0.22 + Double(rng.range(0, 0.06)))
                    // Хромосомы V-образные, тянутся к полюсу.
                    rod(CGPoint(x: x, y: y - 3), angle: side > 0 ? 0.6 : 2.5, length: 13, width: 4.5)
                    rod(CGPoint(x: x, y: y + 3), angle: side > 0 ? -0.6 : -2.5, length: 13, width: 4.5)
                }
            }
        case .telophase:
            for side in [-1.0, 1.0] {
                let n = CGPoint(x: c.x + CGFloat(side) * r.width * 0.26, y: c.y)
                let rad = min(r.width, r.height) * 0.17
                ctx.fill(Path(ellipseIn: CGRect(x: n.x - rad, y: n.y - rad, width: rad * 2, height: rad * 2)),
                         with: .color(Color(red: 0.5, green: 0.25, blue: 0.5)))
                for _ in 0..<5 {
                    rod(CGPoint(x: n.x + CGFloat(rng.range(-8, 8)), y: n.y + CGFloat(rng.range(-8, 8))),
                        angle: Double(rng.range(0, 3)), length: 10, width: 3.5)
                }
            }
            // Клеточная пластинка посередине.
            var plate = Path()
            plate.move(to: CGPoint(x: c.x, y: r.minY + 6))
            plate.addLine(to: CGPoint(x: c.x, y: r.maxY - 6))
            ctx.stroke(plate, with: .color(Color(red: 0.62, green: 0.38, blue: 0.55)), style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
        }
    }
}

// MARK: - Танец (выпускной)

/// Кольца ритма: касание, когда внешнее кольцо сошлось с кругом.
struct RhythmOverlay: View {
    @ObservedObject var engine: GameEngine

    var body: some View {
        let s = engine.prom
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(Array(s.upcoming.enumerated()), id: \.offset) { _, step in
                    let remaining = step.time - s.time
                    let k = CGFloat(max(0, remaining / DanceScene.approach))
                    let base = unit * 0.11
                    ZStack {
                        Circle()
                            .fill(Theme.gold.opacity(0.18 + 0.2 * (1 - Double(k))))
                            .frame(width: base, height: base)
                        Circle()
                            .stroke(Theme.gold, lineWidth: 3)
                            .frame(width: base, height: base)
                        Circle()
                            .stroke(Color.white.opacity(0.85), lineWidth: 2)
                            .frame(width: base * (1 + k * 2.2), height: base * (1 + k * 2.2))
                        Image(systemName: "music.note")
                            .font(.system(size: base * 0.32, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .opacity(Double(min(1, (1 - k) * 3)))
                    .position(x: step.x * geo.size.width, y: step.y * geo.size.height)
                }

                if s.combo >= 3 {
                    Text("×\(s.combo)")
                        .font(.system(size: unit * 0.06, weight: .black, design: .rounded))
                        .foregroundColor(Theme.gold)
                        .shadow(color: Theme.gold.opacity(0.7), radius: 14)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.84)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Свадьба

/// Пожелание Элис, варианты и кнопка «Готово».
struct WeddingOverlay: View {
    @ObservedObject var engine: GameEngine

    var body: some View {
        let s = engine.wedding
        VStack(spacing: 14) {
            Spacer(minLength: 120)

            // Пожелание Элис.
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(red: 0.35, green: 0.2, blue: 0.4), .black],
                                                 startPoint: .top, endPoint: .bottom))
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.gold)
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ЭЛИС · \(s.category.title)")
                        .font(Theme.body(11, weight: .heavy))
                        .tracking(1.6)
                        .foregroundColor(Theme.gold)
                    Text("«\(s.wish.text)»")
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .italic()
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .frame(maxWidth: 620)
            .padding(.horizontal, 20)

            Spacer()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(s.options.enumerated()), id: \.offset) { index, option in
                        Button {
                            engine.choose(index)
                        } label: {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 44, height: 44)
                                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                                    .shadow(color: option.color.opacity(0.6), radius: 8)
                                Text(option.name)
                                    .font(Theme.body(13, weight: .bold))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(height: 34)
                            }
                            .padding(12)
                            .frame(width: 150)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(s.selection == index ? Theme.gold.opacity(0.35) : Color.black.opacity(0.45))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(s.selection == index ? Theme.gold : Color.white.opacity(0.18),
                                            lineWidth: s.selection == index ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(s.stage != .choosing)
                    }
                }
                .padding(.horizontal, 20)
            }

            HStack(spacing: 14) {
                // Время на раздумья.
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(Theme.gold)
                            .frame(width: g.size.width * CGFloat(max(0, s.timer / s.timeLimit)))
                    }
                }
                .frame(height: 6)
                Button("ГОТОВО") {
                    engine.confirm()
                }
                .buttonStyle(GlassButtonStyle(prominent: true))
                .frame(width: 180)
                .disabled(s.stage != .choosing)
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
        }
    }
}

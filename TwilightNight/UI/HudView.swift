import SwiftUI

/// Верхняя панель и приборы главы.
/// Слой с информацией не перехватывает касания — иначе он мешал бы управлять сценой.
struct HudView: View {

    @ObservedObject var engine: GameEngine

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 10) {
                topBar
                if engine.phase == .playing {
                    chapterMeters
                }
                Spacer()
            }
            .allowsHitTesting(false)

            // Кнопки — единственные интерактивные элементы HUD.
            HStack(spacing: 10) {
                Spacer()
                MusicToggleButton()
                Button {
                    engine.pause()
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Theme.text)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 22)
            .padding(.top, 12)
        }
    }

    // MARK: - Верхняя строка

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(engine.score)")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundColor(Theme.text)
                    .shadow(color: Theme.blood.opacity(0.85), radius: 12, y: 3)

                Text("\(engine.chapter.number) · \(engine.chapter.title.uppercased())")
                    .font(Theme.body(12, weight: .heavy))
                    .tracking(1.5)
                    .foregroundColor(engine.chapter.accent)

                progressBar
                    .frame(width: 148)

                Text(engine.chapterCaption)
                    .font(Theme.body(12, weight: .semibold))
                    .foregroundColor(Theme.textDim)

                hearts
                    .padding(.top, 2)
            }

            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: [engine.chapter.accent, Theme.bloodLight],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, geo.size.width * CGFloat(engine.chapterProgress)))
            }
        }
        .frame(height: 6)
    }

    private var hearts: some View {
        HStack(spacing: 3) {
            ForEach(0..<GameEngine.maxLives, id: \.self) { index in
                Text("❤")
                    .font(.system(size: 19))
                    .foregroundColor(index < engine.lives ? Theme.bloodLight : Color.white.opacity(0.16))
            }
        }
    }

    // MARK: - Приборы главы

    @ViewBuilder
    private var chapterMeters: some View {
        switch engine.chapter {
        case .van, .biology, .wedding:
            EmptyView()

        case .portAngeles, .forest:
            let runner = engine.chapter == .forest ? engine.forest : engine.portAngeles
            dotsMeter(title: engine.chapter == .forest ? "СТОЛКНОВЕНИЯ" : "ПРЕСЛЕДОВАТЕЛИ",
                      filled: runner.hits % 3, total: 3, tint: Theme.bloodLight)

        case .chase:
            meter(title: "ДЖЕЙМС БЛИЗКО", value: engine.chase.danger, tint: Theme.bloodLight,
                  warning: engine.chase.danger > 0.65)

        case .prom:
            dotsMeter(title: "СБИЛАСЬ С РИТМА", filled: engine.prom.misses % 5, total: 5, tint: Theme.bloodLight)

        case .meadow:
            meter(
                title: "СОЛНЦЕ ВЫДАЁТ",
                value: engine.meadow.exposure,
                tint: Theme.amber,
                warning: engine.meadow.exposure > 0.6
            )

        case .baseball:
            VStack(spacing: 8) {
                thunderMeter
                noiseMeter
            }

        case .studio:
            VStack(spacing: 8) {
                meter(title: "ЯД В КРОВИ", value: engine.studio.venom,
                      tint: Theme.venom, warning: false, inverted: true)
                meter(title: "ЖАЖДА", value: engine.studio.thirst,
                      tint: Theme.bloodLight, warning: engine.studio.thirst > 0.7)
            }
        }
    }

    private func meter(title: String, value: Double, tint: Color,
                       warning: Bool, inverted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                    .font(Theme.body(11, weight: .heavy))
                    .tracking(1.4)
                    .foregroundColor(warning ? Theme.bloodLight : Theme.textDim)
                if warning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.bloodLight)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.45))
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.7), tint],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(2, geo.size.width * CGFloat(clamp(value, 0, 1))))
                }
            }
            .frame(height: 9)
            .opacity(inverted ? 0.95 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: 330)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(warning ? Theme.bloodLight.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    /// Ряд точек: сколько ошибок до потери жизни.
    private func dotsMeter(title: String, filled: Int, total: Int, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(Theme.body(11, weight: .heavy))
                .tracking(1.2)
                .foregroundColor(filled > 0 ? tint : Theme.textDim)
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled ? tint : Color.white.opacity(0.18))
                    .frame(width: 11, height: 11)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 330)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.42)))
    }

    /// Гром: насколько громко сейчас, и где «зона идеального удара».
    private var thunderMeter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(engine.baseball.thunder > 0.66 ? Theme.amber : Theme.textDim)
                Text(engine.baseball.thunder > 0.66 ? "ГРОМ! БЕЙ СЕЙЧАС" : "ЖДЁМ ГРОМА")
                    .font(Theme.body(11, weight: .heavy))
                    .tracking(1.2)
                    .foregroundColor(engine.baseball.thunder > 0.66 ? Theme.amber : Theme.textDim)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.45))
                    // Зона, где удар заглушается громом.
                    Capsule()
                        .fill(Theme.amber.opacity(0.22))
                        .frame(width: geo.size.width * 0.34)
                        .offset(x: geo.size.width * 0.66)
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.ice.opacity(0.6), Theme.amber],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(2, geo.size.width * CGFloat(engine.baseball.thunder)))
                }
            }
            .frame(height: 9)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: 330)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(engine.baseball.thunder > 0.66 ? Theme.amber.opacity(0.8)
                                                       : Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    /// Сколько раз лес уже услышал удар — приближение кочевников.
    private var noiseMeter: some View {
        HStack(spacing: 8) {
            Text("КОЧЕВНИКИ")
                .font(Theme.body(11, weight: .heavy))
                .tracking(1.2)
                .foregroundColor(engine.baseball.noise > 0 ? Theme.bloodLight : Theme.textDim)
            ForEach(0..<BaseballScene.noiseLimit, id: \.self) { index in
                Circle()
                    .fill(index < engine.baseball.noise ? Theme.bloodLight : Color.white.opacity(0.18))
                    .frame(width: 11, height: 11)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 330)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(engine.baseball.noiseWarning > 0.05 ? Theme.bloodLight.opacity(0.8)
                                                            : Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

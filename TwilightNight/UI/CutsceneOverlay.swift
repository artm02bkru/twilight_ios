import SwiftUI

/// Кинорежим: чёрные полосы, титр главы, субтитры и кнопка «Пропустить».
/// Тап по экрану (мимо кнопки) листает реплики — его ловит слой жестов под оверлеем.
struct CutsceneOverlay: View {

    @ObservedObject var engine: GameEngine

    var body: some View {
        GeometryReader { geo in
            let bar = geo.size.height * 0.1
            ZStack {
                VStack(spacing: 0) {
                    Color.black.frame(height: bar)
                    Spacer()
                    Color.black.frame(height: bar)
                }
                .allowsHitTesting(false)

                if let playback = engine.cutscene, !playback.isFinished {
                    content(playback, bar: bar, size: geo.size)
                }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func content(_ playback: CutscenePlayback, bar: CGFloat, size: CGSize) -> some View {
        let shot = playback.shot
        let fade = textOpacity(playback)

        ZStack {
            // Подпись главы в левом верхнем углу.
            if let caption = playback.script.caption {
                VStack {
                    HStack {
                        Text(caption)
                            .font(Theme.body(13, weight: .heavy))
                            .tracking(3)
                            .foregroundColor(Theme.amber)
                            .padding(.leading, 24)
                        Spacer()
                    }
                    .frame(height: bar)
                    .padding(.top, 8)
                    Spacer()
                }
                .opacity(playback.index == 0 ? fade : 1)
                .allowsHitTesting(false)
            }

            switch shot.style {
            case .title:
                Text(shot.line)
                    .font(Theme.title(min(96, size.width * 0.14)))
                    .tracking(min(18, size.width * 0.02))
                    .foregroundColor(Theme.text)
                    .shadow(color: Theme.blood.opacity(0.9), radius: 30, y: 4)
                    .scaleEffect(1 + CGFloat(playback.progress) * 0.06)
                    .opacity(fade)
                    .allowsHitTesting(false)

            case .subtitle:
                VStack(spacing: 6) {
                    Spacer()
                    if let speaker = shot.speaker {
                        Text(speaker.uppercased())
                            .font(Theme.body(12, weight: .heavy))
                            .tracking(2.5)
                            .foregroundColor(Theme.amber)
                    }
                    Text(shot.line)
                        .font(.system(size: min(24, size.width * 0.045), weight: .medium, design: .serif))
                        .italic(shot.speaker == nil)
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black, radius: 6, y: 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 720)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, bar + 18)
                .opacity(fade)
                .allowsHitTesting(false)
            }

            // Кнопка пропуска — единственная интерактивная часть.
            VStack {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) { engine.skipCutscene() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("ПРОПУСТИТЬ")
                                .font(Theme.body(12, weight: .heavy))
                                .tracking(1.5)
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(Theme.text.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 20)
                }
                .frame(height: bar)
                .padding(.top, 8)
                Spacer()
                // Подсказка: тап — следующая реплика.
                HStack {
                    Spacer()
                    Text("коснитесь, чтобы продолжить")
                        .font(Theme.body(11, weight: .medium))
                        .foregroundColor(Theme.textDim.opacity(0.7))
                        .padding(.trailing, 24)
                }
                .frame(height: bar)
                .allowsHitTesting(false)
            }
        }
    }

    /// Текст появляется и гаснет на краях кадра.
    private func textOpacity(_ playback: CutscenePlayback) -> Double {
        let t = playback.shotTime
        let d = playback.shot.duration
        return max(0, min(1, min(t / 0.45, (d - t) / 0.35)))
    }
}

/// Всплывающие надписи над сценой («ИДЕАЛЬНО +40», «НЕ УСПЕЛ»).
struct BannerLayer: View {

    @ObservedObject var engine: GameEngine

    var body: some View {
        GeometryReader { geo in
            ForEach(engine.banners) { banner in
                let progress = min(1, max(0, banner.life / banner.total) * 2.3)
                let size = geo.size.height * (banner.big ? 0.032 : 0.025) * CGFloat(1 + (1 - progress) * 0.12)
                Text(banner.text)
                    .font(.system(size: size, weight: .black, design: .rounded))
                    .foregroundColor(banner.color)
                    .shadow(color: .black.opacity(0.9), radius: 6, y: 2)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.35)).blur(radius: 6))
                    .opacity(progress)
                    .position(x: banner.x * geo.size.width, y: banner.y * geo.size.height)
            }
        }
        .allowsHitTesting(false)
    }
}

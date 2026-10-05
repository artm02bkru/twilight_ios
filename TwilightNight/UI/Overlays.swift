import SwiftUI

// MARK: - Общее оформление

struct TwilightPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color(red: 0.05, green: 0.06, blue: 0.11).opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.7), radius: 34, y: 14)
    }
}

struct TwilightButtonStyle: ButtonStyle {
    var filled: Bool = true
    var tint: Color = Theme.blood

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(19, weight: .heavy))
            .foregroundColor(Color.white)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(
                Capsule().fill(
                    filled
                    ? LinearGradient(colors: [tint.opacity(0.85), tint],
                                     startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.06)],
                                     startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(Capsule().stroke(Color.white.opacity(filled ? 0.0 : 0.24), lineWidth: 1))
            .shadow(color: filled ? tint.opacity(0.5) : .clear, radius: 18, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct Scrim<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        ZStack {
            Color.black.opacity(0.38).ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                content
                    .padding(.horizontal, 22)
                    .padding(.vertical, 34)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Карточка главы

struct ChapterCardOverlay: View {

    @ObservedObject var engine: GameEngine

    var body: some View {
        ZStack {
            LinearGradient(colors: [.clear, Color.black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()

            TwilightPanel {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: engine.chapter.symbol)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(engine.chapter.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(engine.chapter.number)
                                .font(Theme.body(12, weight: .heavy))
                                .tracking(2.5)
                                .foregroundColor(engine.chapter.accent)
                            Text(engine.chapter.title.uppercased())
                                .font(Theme.title(34))
                                .foregroundColor(Theme.text)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                        }
                    }

                    Text(engine.chapter.place)
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundColor(Theme.textDim)

                    Text(engine.chapter.line)
                        .font(Theme.body(16, weight: .medium))
                        .foregroundColor(Theme.text.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)

                    Divider().overlay(Color.white.opacity(0.15))

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Theme.ice)
                        Text(engine.chapter.rule)
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundColor(Theme.ice)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("НАЧАТЬ ГЛАВУ") {
                        withAnimation(.easeInOut(duration: 0.2)) { engine.beginChapter() }
                    }
                    .buttonStyle(TwilightButtonStyle(tint: engine.chapter.accent))
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Пауза

struct PauseOverlay: View {

    @ObservedObject var engine: GameEngine

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            TwilightPanel {
                VStack(spacing: 14) {
                    Text("ПАУЗА")
                        .font(Theme.title(38))
                        .foregroundColor(Theme.text)

                    Text("\(engine.chapter.number) · \(engine.chapter.title)   ·   \(engine.score) очков")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundColor(Theme.textDim)
                        .padding(.bottom, 6)

                    Button("ПРОДОЛЖИТЬ") {
                        withAnimation(.easeInOut(duration: 0.2)) { engine.resume() }
                    }
                    .buttonStyle(TwilightButtonStyle())

                    Button("ПЕРЕИГРАТЬ ГЛАВУ") {
                        withAnimation(.easeInOut(duration: 0.2)) { engine.restartChapter() }
                    }
                    .buttonStyle(TwilightButtonStyle(filled: false))

                    Button("В МЕНЮ") {
                        withAnimation(.easeInOut(duration: 0.2)) { engine.goToMenu() }
                    }
                    .buttonStyle(TwilightButtonStyle(filled: false))
                }
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Итог главы

struct ChapterResultOverlay: View {

    @ObservedObject var engine: GameEngine

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()

            TwilightPanel {
                VStack(spacing: 12) {
                    Text(engine.result?.chapter.number ?? "")
                        .font(Theme.body(12, weight: .heavy))
                        .tracking(3)
                        .foregroundColor(engine.chapter.accent)

                    Text(engine.result?.rank ?? "")
                        .font(Theme.title(40))
                        .foregroundColor(Theme.text)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    Text("\(engine.result?.score ?? 0) очков за главу")
                        .font(Theme.body(17, weight: .bold))
                        .foregroundColor(Theme.amber)

                    if let note = engine.result?.note {
                        Text(note)
                            .font(Theme.body(14, weight: .medium))
                            .foregroundColor(Theme.textDim)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 4)
                    }

                    Text("Всего: \(engine.score)   ·   Жизней: \(engine.lives)")
                        .font(Theme.body(13, weight: .semibold))
                        .foregroundColor(Theme.textDim)

                    Button(engine.chapter == .wedding ? "СМОТРЕТЬ СВАДЬБУ" : "СЛЕДУЮЩАЯ ГЛАВА") {
                        withAnimation(.easeInOut(duration: 0.22)) { engine.advanceFromResult() }
                    }
                    .buttonStyle(TwilightButtonStyle(tint: engine.chapter.accent))
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, 24)
        }
    }
}

// MARK: - Конец партии

struct GameOverOverlay: View {

    @ObservedObject var engine: GameEngine

    var body: some View {
        Scrim {
            TwilightPanel {
                VStack(spacing: 12) {
                    Text("ИСТОРИЯ ОБОРВАЛАСЬ")
                        .font(Theme.title(30))
                        .foregroundColor(Theme.text)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)

                    Text("\(engine.chapter.number) · \(engine.chapter.title)")
                        .font(Theme.body(14, weight: .heavy))
                        .tracking(1.5)
                        .foregroundColor(engine.chapter.accent)

                    Text("\(engine.score)")
                        .font(.system(size: 68, weight: .black, design: .rounded))
                        .foregroundColor(Theme.text)
                        .shadow(color: Theme.blood.opacity(0.85), radius: 20, y: 4)

                    Text("Лучший результат: \(engine.best)")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundColor(Theme.textDim)
                        .padding(.bottom, 4)

                    Button("ПЕРЕИГРАТЬ ГЛАВУ") {
                        withAnimation(.easeInOut(duration: 0.2)) { engine.retryChapter() }
                    }
                    .buttonStyle(TwilightButtonStyle())

                    Button("В МЕНЮ") {
                        withAnimation(.easeInOut(duration: 0.2)) { engine.goToMenu() }
                    }
                    .buttonStyle(TwilightButtonStyle(filled: false))
                }
            }
            .frame(maxWidth: 460)
        }
    }
}

// MARK: - Финал

struct FinaleOverlay: View {

    @ObservedObject var engine: GameEngine

    private var rank: String { Ranks.finalRank(forScore: engine.score) }

    var body: some View {
        Scrim {
            TwilightPanel {
                VStack(spacing: 12) {
                    Text("НАВСЕГДА")
                        .font(Theme.title(32))
                        .foregroundColor(Theme.text)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    Text("История Беллы и Эдварда пройдена")
                        .font(Theme.body(15, weight: .medium))
                        .foregroundColor(Theme.textDim)

                    Text("\(engine.score)")
                        .font(.system(size: 76, weight: .black, design: .rounded))
                        .foregroundColor(Theme.text)
                        .shadow(color: Theme.amber.opacity(0.8), radius: 22, y: 4)

                    Text(rank)
                        .font(Theme.body(20, weight: .heavy))
                        .tracking(2)
                        .foregroundColor(Theme.amber)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Theme.amber.opacity(0.16)))
                        .overlay(Capsule().stroke(Theme.amber.opacity(0.5), lineWidth: 1))

                    Text("Лучший результат: \(engine.best)")
                        .font(Theme.body(15, weight: .semibold))
                        .foregroundColor(Theme.textDim)
                        .padding(.top, 2)

                    Button("ПРОЙТИ ЗАНОВО") {
                        withAnimation(.easeInOut(duration: 0.2)) { engine.newRun() }
                    }
                    .buttonStyle(TwilightButtonStyle())

                    Button("В МЕНЮ") {
                        withAnimation(.easeInOut(duration: 0.2)) { engine.goToMenu() }
                    }
                    .buttonStyle(TwilightButtonStyle(filled: false))
                }
            }
            .frame(maxWidth: 480)
        }
    }
}

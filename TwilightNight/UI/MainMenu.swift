import SwiftUI

/// Главное меню поверх 3D-сцены: светящийся логотип, «Продолжить», главы, настройки.
struct MenuOverlay: View {

    @ObservedObject var engine: GameEngine
    @State private var panel: Panel? = nil
    @State private var appeared = false

    private enum Panel { case chapters, settings }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                // Затемнение снизу и по краям — 3D-сцена остаётся главной.
                LinearGradient(colors: [Color.black.opacity(0.55), .clear, .clear, Color.black.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    LogoView()
                        .frame(maxWidth: landscape ? 520 : min(geo.size.width * 0.82, 560))
                        .padding(.top, landscape ? 26 : geo.size.height * 0.07)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : -16)

                    // Подпись разработчика.
                    Text("by @twilight_xbot")
                        .font(Theme.body(14, weight: .medium).italic())
                        .tracking(1.5)
                        .foregroundColor(Theme.ice.opacity(0.8))
                        .shadow(color: .black.opacity(0.6), radius: 4)
                        .padding(.top, 2)
                        .opacity(appeared ? 1 : 0)

                    Text("ИСТОРИЯ БЕЛЛЫ И ЭДВАРДА")
                        .font(Theme.body(13, weight: .semibold))
                        .tracking(6)
                        .foregroundColor(Theme.mist)
                        .padding(.top, 10)
                        .opacity(appeared ? 0.9 : 0)

                    Spacer()

                    HStack {
                        if !landscape { Spacer(minLength: 0) }
                        menuButtons
                            .frame(maxWidth: 400)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 24)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, landscape ? 48 : 24)

                    footer
                        .padding(.top, 16)
                        .padding(.bottom, landscape ? 14 : 28)
                }

                if let panel {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { self.panel = nil } }
                    Group {
                        switch panel {
                        case .chapters: ChapterPicker(engine: engine) { withAnimation { self.panel = nil } }
                        case .settings: SettingsPanel(engine: engine) { withAnimation { self.panel = nil } }
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).delay(0.3)) { appeared = true }
        }
    }

    private var menuButtons: some View {
        VStack(spacing: 12) {
            if let saved = engine.savedChapter {
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { engine.continueRun() }
                } label: {
                    VStack(spacing: 2) {
                        Text("ПРОДОЛЖИТЬ")
                        Text("\(saved.number) · \(saved.title)")
                            .font(Theme.body(12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                    }
                }
                .buttonStyle(GlassButtonStyle(prominent: true))
            }
            Button("НОВАЯ ИСТОРИЯ") {
                withAnimation(.easeInOut(duration: 0.35)) { engine.newRun() }
            }
            .buttonStyle(GlassButtonStyle(prominent: engine.savedChapter == nil))

            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { panel = .chapters }
                } label: {
                    Label("ГЛАВЫ", systemImage: "book.closed.fill")
                }
                .buttonStyle(GlassButtonStyle())
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { panel = .settings }
                } label: {
                    Label("НАСТРОЙКИ", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if engine.best > 0 {
                Text("Лучший результат: \(engine.best)")
                    .font(Theme.body(13, weight: .semibold))
                    .foregroundColor(Theme.textDim)
            }
            Text("Фанатская игра по мотивам книг «Сумерки». Права на франшизу принадлежат их правообладателям.")
                .font(Theme.body(10, weight: .regular))
                .foregroundColor(Theme.textDim.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
    }
}

// MARK: - Логотип

/// Логотип «twilight» с мягким свечением и бегущим бликом.
struct LogoView: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let sweep = CGFloat((t * 0.12).truncatingRemainder(dividingBy: 1)) * 2.4 - 0.7
            ZStack {
                Image("Logo")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(Theme.blood.opacity(0.9))
                    .blur(radius: 18)
                    .opacity(0.55 + 0.15 * sin(t * 0.8))
                Image("Logo")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(Color(red: 0.93, green: 0.95, blue: 1))
                    .shadow(color: Theme.ice.opacity(0.5), radius: 10)
                // Блик скользит по буквам.
                Image("Logo")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(
                        LinearGradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.95), location: 0.5),
                            .init(color: .clear, location: 1)
                        ], startPoint: UnitPoint(x: sweep - 0.15, y: 0), endPoint: UnitPoint(x: sweep + 0.15, y: 1))
                    )
                    .blendMode(.plusLighter)
            }
        }
        .accessibilityLabel("Сумерки")
    }
}

// MARK: - Кнопки

/// Стеклянная кнопка с подсветкой.
struct GlassButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(prominent ? 18 : 15, weight: .heavy))
            .tracking(1.5)
            .foregroundColor(.white)
            .padding(.vertical, prominent ? 16 : 13)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(prominent
                              ? LinearGradient(colors: [Theme.blood.opacity(0.85), Theme.blood.opacity(0.55)],
                                               startPoint: .top, endPoint: .bottom)
                              : LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                                               startPoint: .top, endPoint: .bottom))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.08)],
                                           startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: prominent ? Theme.blood.opacity(0.55) : .black.opacity(0.4), radius: prominent ? 22 : 10, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Выбор главы

struct ChapterPicker: View {
    @ObservedObject var engine: GameEngine
    var close: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("ГЛАВЫ")
                    .font(Theme.title(30))
                    .foregroundColor(Theme.text)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Chapter.allCases) { chapter in
                        ChapterCard(chapter: chapter, locked: chapter.rawValue > engine.unlocked) {
                            withAnimation(.easeInOut(duration: 0.35)) { engine.startFrom(chapter) }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
            }

            Text("Открытые главы можно переиграть отдельно. Очки начнутся с нуля.")
                .font(Theme.body(12, weight: .medium))
                .foregroundColor(Theme.textDim)
        }
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.black.opacity(0.35)))
        )
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .padding(20)
        .frame(maxWidth: 980)
    }
}

private struct ChapterCard: View {
    let chapter: Chapter
    let locked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: locked ? "lock.fill" : chapter.symbol)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(locked ? Theme.textDim : chapter.accent)
                    Spacer()
                    Text(chapter.number)
                        .font(Theme.body(11, weight: .heavy))
                        .tracking(1.5)
                        .foregroundColor(Theme.textDim)
                }
                Spacer()
                Text(chapter.title)
                    .font(Theme.title(22))
                    .foregroundColor(locked ? Theme.textDim : Theme.text)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(locked ? "Пройдите предыдущие главы" : chapter.place)
                    .font(Theme.body(11, weight: .medium))
                    .foregroundColor(Theme.textDim)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(width: 190, height: 230)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [chapter.accent.opacity(locked ? 0.06 : 0.35), Color.black.opacity(0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(chapter.accent.opacity(locked ? 0.15 : 0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }
}

// MARK: - Настройки

struct SettingsPanel: View {
    @ObservedObject var engine: GameEngine
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("НАСТРОЙКИ")
                    .font(Theme.title(28))
                    .foregroundColor(Theme.text)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            Text("СЛОЖНОСТЬ")
                .font(Theme.body(12, weight: .heavy))
                .tracking(2)
                .foregroundColor(Theme.textDim)
            HStack(spacing: 10) {
                ForEach(Difficulty.allCases) { d in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { engine.difficulty = d }
                    } label: {
                        VStack(spacing: 4) {
                            Text(d.title)
                                .font(Theme.body(15, weight: .heavy))
                            Text(d.hint)
                                .font(Theme.body(10, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 74)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(engine.difficulty == d ? Theme.blood.opacity(0.75) : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(engine.difficulty == d ? 0.5 : 0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("ЗВУК")
                .font(Theme.body(12, weight: .heavy))
                .tracking(2)
                .foregroundColor(Theme.textDim)
            MusicToggleRow()
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.black.opacity(0.35)))
        )
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .frame(maxWidth: 560)
        .padding(20)
    }
}

import SwiftUI

/// Корневой экран: 3D-мир + слой касаний + HUD + оверлеи.
struct RootView: View {

    @StateObject private var engine = GameEngine()
    @StateObject private var director = WorldDirector()
    @StateObject private var clock = DisplayLinkDriver()
    @ObservedObject private var music = SoundtrackPlayer.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)

            ZStack {
                Color.black

                WorldView(director: director)
                    .allowsHitTesting(false)

                // Слой касаний: SCNView касаний не принимает, всё ловится здесь.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                engine.dragChanged(CGPoint(x: value.location.x / w,
                                                           y: value.location.y / h))
                            }
                            .onEnded { _ in
                                engine.dragEnded()
                            }
                    )

                // Багровая вспышка при потере жизни.
                Theme.blood
                    .opacity(engine.flash * 0.26)
                    .allowsHitTesting(false)

                if engine.phase == .playing {
                    BannerLayer(engine: engine)
                    miniGameOverlay
                }

                if engine.phase == .playing || engine.phase == .paused {
                    HudView(engine: engine)
                }

                overlay

                if director.isLoading && engine.phase != .menu {
                    LoadingBadge()
                        .transition(.opacity)
                }
            }
            .onAppear {
                music.start()
                engine.setAspect(w / h)
                clock.onTick = { delta in
                    // Пока площадка строится, история не идёт дальше.
                    if director.isReady(engine.stageID) {
                        engine.update(dt: delta)
                    }
                    director.tick(engine, dt: delta)
                }
                clock.start()
            }
            .onChange(of: geo.size) { newSize in
                engine.setAspect(newSize.width / max(1, newSize.height))
            }
        }
        .ignoresSafeArea()
        .onDisappear { clock.stop() }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                music.resumeIfNeeded()
                SoundFX.shared.resume()
            case .inactive, .background:
                // Свернули игру — ставим на паузу, чтобы не потерять жизнь.
                engine.pause()
            @unknown default:
                break
            }
        }
    }

    /// Интерфейс мини-игр поверх сцены.
    @ViewBuilder
    private var miniGameOverlay: some View {
        switch engine.chapter {
        case .biology: BiologyOverlay(engine: engine)
        case .prom:    RhythmOverlay(engine: engine)
        case .wedding: WeddingOverlay(engine: engine)
        default:       EmptyView()
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch engine.phase {
        case .menu:
            MenuOverlay(engine: engine).transition(.opacity)
        case .cutscene:
            CutsceneOverlay(engine: engine).transition(.opacity)
        case .chapterCard:
            ChapterCardOverlay(engine: engine).transition(.opacity)
        case .paused:
            PauseOverlay(engine: engine).transition(.opacity)
        case .chapterResult:
            ChapterResultOverlay(engine: engine).transition(.opacity)
        case .gameOver:
            GameOverOverlay(engine: engine).transition(.opacity)
        case .finale:
            FinaleOverlay(engine: engine).transition(.opacity)
        case .playing:
            EmptyView()
        }
    }
}

/// Индикатор построения сцены.
private struct LoadingBadge: View {
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                ProgressView()
                    .tint(Theme.ice)
                Text("Сцена строится…")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundColor(Theme.textDim)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .padding(.bottom, 40)
        }
        .allowsHitTesting(false)
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .preferredColorScheme(.dark)
    }
}

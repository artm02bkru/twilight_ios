import SwiftUI

/// Корневой экран: сцена + HUD + оверлеи.
struct RootView: View {

    @StateObject private var engine = GameEngine()
    @StateObject private var clock = DisplayLinkDriver()
    @ObservedObject private var music = SoundtrackPlayer.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)

            ZStack {
                Color.black

                SceneCanvas(engine: engine)
                    .offset(x: shakeOffset)
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

                if engine.phase == .playing || engine.phase == .paused {
                    HudView(engine: engine)
                }

                overlay
            }
            .onAppear {
                music.start()
                engine.setAspect(w / h)
                clock.onTick = { delta in engine.update(dt: delta) }
                clock.start()
            }
            .onChange(of: geo.size) { newSize in
                engine.setAspect(newSize.width / max(1, newSize.height))
            }
        }
        .ignoresSafeArea()
        .onDisappear { clock.stop() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { music.resumeIfNeeded() }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch engine.phase {
        case .menu:
            MenuOverlay(engine: engine).transition(.opacity)
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

    private var shakeOffset: CGFloat {
        let amount = engine.shake
        guard amount > 0.01 else { return 0 }
        return sin(engine.time * 54) * 16 * amount
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .preferredColorScheme(.dark)
    }
}

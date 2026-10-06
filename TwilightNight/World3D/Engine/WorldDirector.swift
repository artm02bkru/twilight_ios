import SceneKit
import SpriteKit
import SwiftUI

/// Режиссёр 3D-мира: держит SCNView, собирает площадки в фоне,
/// переключает их с затемнением и каждый кадр передаёт им состояние игры.
final class WorldDirector: ObservableObject {

    let view: SCNView
    /// Нужная площадка ещё строится — игра ждёт, на экране индикатор.
    @Published private(set) var isLoading = false

    private var stages: [StageID: Stage3D] = [:]
    private var building: Set<StageID> = []
    private var current: StageID?
    private var modeKey = ""
    private let buildQueue = DispatchQueue(label: "twilight.stage-build", qos: .userInitiated)

    init() {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true
        view.isPlaying = true
        view.autoenablesDefaultLighting = false
        view.isUserInteractionEnabled = false
        self.view = view

        // Сначала меню, затем пролог и первая глава — остальные по мере сюжета.
        for id in [StageID.menu, .road, .classroom] {
            request(id)
        }
    }

    // MARK: - Площадки

    @discardableResult
    private func request(_ id: StageID) -> Stage3D? {
        if let stage = stages[id] { return stage }
        guard !building.contains(id) else { return nil }
        building.insert(id)
        buildQueue.async { [weak self] in
            let stage = Self.make(id)
            DispatchQueue.main.async {
                guard let self else { return }
                self.stages[id] = stage
                self.building.remove(id)
                // Заранее загрузить геометрию и шейдеры в GPU — без рывка при показе.
                self.view.prepare([stage.scene], completionHandler: nil)
            }
        }
        return nil
    }

    private static func make(_ id: StageID) -> Stage3D {
        switch id {
        case .menu:      return MenuStage()
        case .road:      return RoadStage()
        case .classroom: return ClassroomStage()
        case .van:       return VanStage()
        case .street:    return StreetStage()
        case .meadow:    return MeadowStage()
        case .forestRun: return ForestRunStage()
        case .baseball:  return BaseballStage()
        case .chase:     return ChaseStage()
        case .studio:    return StudioStage()
        case .finale:    return FinaleStage()
        case .wedding:   return WeddingStage()
        }
    }

    /// Какие площадки держать в памяти: текущую, следующую по сюжету и меню.
    private func wanted(for engine: GameEngine) -> Set<StageID> {
        var set: Set<StageID> = [engine.stageID, .menu, engine.chapter.stage]
        if let next = Chapter(rawValue: engine.chapter.rawValue + 1) { set.insert(next.stage) }
        if engine.phase == .menu {
            set.insert(.road)
            set.insert(engine.savedChapter?.stage ?? .classroom)
        }
        if engine.chapter == .wedding || engine.chapter == .prom { set.insert(.wedding) }
        return set
    }

    /// Подгрузить нужное заранее и выгрузить лишнее.
    private func manageMemory(_ engine: GameEngine) {
        let want = wanted(for: engine)
        for id in want where stages[id] == nil { request(id) }
        for id in Array(stages.keys) where !want.contains(id) && id != current {
            stages[id] = nil
        }
    }

    func isReady(_ id: StageID) -> Bool { stages[id] != nil }

    /// В раннерах важнее плавность: рендер в 75% разрешения и сглаживание 2x.
    private func applyQuality(for stage: Stage3D) {
        let native = view.window?.screen.scale ?? 2
        if stage is RunnerStageBase {
            view.contentScaleFactor = native * 0.75
            view.antialiasingMode = .multisampling2X
        } else {
            view.contentScaleFactor = native
            view.antialiasingMode = .multisampling4X
        }
    }

    // MARK: - Кадр

    private var memoryTimer: CGFloat = 0

    func tick(_ engine: GameEngine, dt: CGFloat) {
        memoryTimer -= dt
        if memoryTimer <= 0 {
            memoryTimer = 1
            manageMemory(engine)
        }
        let id = engine.stageID
        // Площадка ещё строится — остаёмся на прежней.
        guard let stage = request(id) else {
            if !isLoading { isLoading = true }
            return
        }
        if isLoading { isLoading = false }

        if current != id {
            current = id
            modeKey = ""
            applyQuality(for: stage)
            SoundFX.shared.ambience(stage.ambience)
            if view.scene == nil {
                view.scene = stage.scene
                view.pointOfView = stage.camera
            } else {
                view.present(stage.scene,
                             with: SKTransition.fade(with: .black, duration: 0.9),
                             incomingPointOfView: stage.camera,
                             completionHandler: nil)
            }
        }

        let fdt = Float(dt)
        stage.time += fdt

        switch engine.phase {
        case .cutscene:
            if let playback = engine.cutscene, !playback.isFinished {
                let key = "cut-\(playback.script.id)-\(playback.index)"
                if key != modeKey {
                    modeKey = key
                    stage.setCinematic(true)
                    stage.beginShot(playback.shot.cue)
                    SoundFX.shared.voice("\(playback.shot.cue)")
                }
                stage.updateShot(playback.shot.cue, progress: Float(playback.progress), dt: fdt)
            }

        case .playing, .paused, .gameOver:
            if modeKey != "game" {
                modeKey = "game"
                SoundFX.shared.stopVoice()
                stage.setCinematic(false)
                stage.enterGameplay()
            }
            stage.updateGameplay(engine, dt: engine.phase == .playing ? fdt : 0)

        case .chapterResult:
            // Остаёмся в последнем кадре развязки — только живой фон.
            if modeKey.isEmpty {
                modeKey = "idle"
                stage.enterIdle()
            }
            if modeKey == "idle" { stage.updateIdle(dt: fdt) }

        case .menu, .chapterCard, .finale:
            if modeKey != "idle" {
                modeKey = "idle"
                stage.setCinematic(false)
                stage.enterIdle()
            }
            stage.updateIdle(dt: fdt)
        }

        stage.shake = max(stage.shake, Float(engine.shake) * 0.6)
        stage.updateAmbient(dt: fdt)
        stage.commitCamera(dt: fdt)
    }
}

/// SwiftUI-обёртка над SCNView. Касания принимает слой поверх неё.
struct WorldView: UIViewRepresentable {
    let director: WorldDirector

    func makeUIView(context: Context) -> SCNView { director.view }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

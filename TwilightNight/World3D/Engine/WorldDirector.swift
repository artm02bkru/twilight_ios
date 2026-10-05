import SceneKit
import SpriteKit
import SwiftUI

/// Режиссёр 3D-мира: держит SCNView, собирает площадки в фоне,
/// переключает их с затемнением и каждый кадр передаёт им состояние игры.
final class WorldDirector: ObservableObject {

    let view: SCNView

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

        // Сначала дорога (её видно в меню), остальные площадки — следом, в фоне.
        for id in [StageID.road, .van, .meadow, .baseball, .studio, .finale] {
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
        case .road:     return RoadStage()
        case .van:      return VanStage()
        case .meadow:   return MeadowStage()
        case .baseball: return BaseballStage()
        case .studio:   return StudioStage()
        case .finale:   return FinaleStage()
        }
    }

    // MARK: - Кадр

    func tick(_ engine: GameEngine, dt: CGFloat) {
        let id = engine.stageID
        // Площадка ещё строится — остаёмся на прежней.
        guard let stage = request(id) else { return }

        if current != id {
            current = id
            modeKey = ""
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
                }
                stage.updateShot(playback.shot.cue, progress: Float(playback.progress), dt: fdt)
            }

        case .playing, .paused, .gameOver:
            if modeKey != "game" {
                modeKey = "game"
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

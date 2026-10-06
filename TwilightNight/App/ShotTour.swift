import SceneKit
import UIKit

/// Фототур для CI: при запуске с аргументом `-shotTour` игра сама проходит по сценам
/// и сохраняет кадры в Documents/shots — так сборочный сервер показывает, как выглядит игра.
final class ShotTour {

    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-shotTour") }

    private struct Item {
        let name: String
        let apply: (GameEngine) -> Void
        /// Сколько секунд дать сцене поиграть перед снимком.
        var settle: Double = 1.6
    }

    private let engine: GameEngine
    private let director: WorldDirector
    private var items: [Item] = []
    private let folder: URL

    init(engine: GameEngine, director: WorldDirector) {
        self.engine = engine
        self.director = director
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        folder = docs.appendingPathComponent("shots", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        items = Self.plan()
    }

    private static func plan() -> [Item] {
        func cut(_ name: String, _ c: Chapter, _ id: CutsceneID, _ shot: Int) -> Item {
            Item(name: name, apply: { $0.tourShow(c, cutscene: id, shot: shot) })
        }
        func play(_ name: String, _ c: Chapter, settle: Double = 3) -> Item {
            Item(name: name, apply: { $0.tourShow(c, cutscene: nil, play: true) }, settle: settle)
        }
        func card(_ name: String, _ c: Chapter) -> Item {
            Item(name: name, apply: { $0.tourShow(c, cutscene: nil) })
        }
        return [
            Item(name: "00_menu", apply: { $0.goToMenu() }, settle: 2.5),
            cut("01_prologue_truck", .biology, .prologue, 1),
            cut("02_class_establish", .biology, .intro(.biology), 0),
            cut("03_class_bella_enters", .biology, .intro(.biology), 1),
            cut("04_class_edward_stare", .biology, .intro(.biology), 2),
            cut("05_class_microscope", .biology, .intro(.biology), 3),
            card("06_class_card", .biology),
            play("07_class_play", .biology),
            cut("08_van_skid", .van, .intro(.van), 3),
            play("09_van_play", .van),
            cut("10_van_dent", .van, .outro(.van), 0),
            play("11_street_run", .portAngeles, settle: 4),
            cut("12_street_getin", .portAngeles, .outro(.portAngeles), 1),
            cut("13_meadow_reveal", .meadow, .intro(.meadow), 1),
            play("14_meadow_play", .meadow),
            cut("15_meadow_lying", .meadow, .outro(.meadow), 0),
            cut("16_meadow_lying_close", .meadow, .outro(.meadow), 1),
            cut("17_forest_back", .forest, .intro(.forest), 0),
            play("18_forest_run", .forest, settle: 4),
            cut("19_baseball_pitch", .baseball, .intro(.baseball), 2),
            play("20_baseball_play", .baseball),
            cut("21_chase_depart", .chase, .intro(.chase), 0),
            play("22_chase_run", .chase, settle: 4),
            cut("23_studio", .studio, .intro(.studio), 1),
            play("24_prom", .prom),
            play("25_wedding", .wedding),
            cut("26_finale_aisle", .wedding, .finale, 0)
        ]
    }

    func run() {
        Task { @MainActor in
            // Игра альбомная: поворачиваем окно.
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
            }
            // Дать меню построиться.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            for item in items {
                item.apply(engine)
                // Ждём, пока площадка построится и затемнение пройдёт.
                var waited = 0.0
                while (!director.isReady(engine.stageID) || director.isLoading) && waited < 60 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    waited += 0.2
                }
                try? await Task.sleep(nanoseconds: UInt64((1.2 + item.settle) * 1_000_000_000))
                save(director.view.snapshot(), name: item.name)
                if let window = director.view.window {
                    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
                    let full = renderer.image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    save(full, name: item.name + "_ui")
                }
            }
            try? "done".write(to: folder.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
        }
    }

    private func save(_ image: UIImage, name: String) {
        // Уменьшаем до 1280 по ширине — хватит, чтобы рассмотреть сцену.
        let scale = min(1, 1280 / max(1, image.size.width * image.scale))
        let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        if let data = small.jpegData(compressionQuality: 0.82) {
            try? data.write(to: folder.appendingPathComponent(name + ".jpg"))
        }
    }
}

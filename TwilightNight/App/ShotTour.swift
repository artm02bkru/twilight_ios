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
        WorldDirector.lowQuality = true
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
        // Сгруппировано по площадкам: каждая строится один раз (на CI это минуты).
        return [
            Item(name: "00_menu", apply: { $0.goToMenu() }, settle: 2.5),
            play("01_class_play", .biology),
            cut("02_class_bella_enters", .biology, .intro(.biology), 1),
            cut("03_class_microscope", .biology, .intro(.biology), 3),
            card("04_class_card", .biology),
            play("05_street_run", .portAngeles, settle: 4),
            cut("06_street_getin", .portAngeles, .outro(.portAngeles), 1),
            play("07_forest_run", .forest, settle: 4),
            cut("08_forest_back", .forest, .intro(.forest), 0),
            cut("09_meadow_lying", .meadow, .outro(.meadow), 0),
            play("10_baseball_play", .baseball),
            play("11_chase_run", .chase, settle: 4),
            play("12_prom", .prom),
            play("13_wedding", .wedding),
            cut("14_van_dent", .van, .outro(.van), 0)
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
                try? item.name.write(to: folder.appendingPathComponent("progress.txt"), atomically: true, encoding: .utf8)
                item.apply(engine)
                // Ждём, пока площадка построится и затемнение пройдёт.
                var waited = 0.0
                while (!director.isReady(engine.stageID) || director.isLoading) && waited < 300 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    waited += 0.2
                }
                try? await Task.sleep(nanoseconds: UInt64((1.2 + item.settle) * 1_000_000_000))
                // Программный рендер иногда отдаёт пустой кадр — пробуем ещё пару раз.
                var shot = director.view.snapshot()
                for _ in 0..<3 where Self.isBlack(shot) {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    shot = director.view.snapshot()
                }
                save(shot, name: item.name)
                let cam = director.currentCamera?.simdWorldPosition ?? .zero
                let line = "\(item.name): want=\(engine.stageID) shown=\(director.currentStage.map { "\($0)" } ?? "nil") waited=\(Int(waited))s cam=(\(cam.x), \(cam.y), \(cam.z)) phase=\(engine.phase)\n"
                if let h = try? FileHandle(forWritingTo: folder.appendingPathComponent("info.txt")) {
                    h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
                } else {
                    try? line.write(to: folder.appendingPathComponent("info.txt"), atomically: true, encoding: .utf8)
                }
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

    private static func isBlack(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return true }
        let w = 32, h = 32
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0
        for i in stride(from: 0, to: px.count, by: 4) { sum += Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2]) }
        return sum / (w * h * 3) < 2
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

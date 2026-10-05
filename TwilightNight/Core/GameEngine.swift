import SwiftUI
import UIKit

/// Дирижёр всей книги: ведёт главы, считает очки, жизни и рекорд,
/// а ввод передаёт активной сцене.
final class GameEngine: ObservableObject {

    // MARK: - Публичное состояние

    /// Растёт каждый кадр — заставляет Canvas перерисоваться.
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var phase: GamePhase = .menu
    @Published private(set) var chapter: Chapter = .van
    @Published private(set) var score: Int = 0
    @Published private(set) var lives: Int = 3
    @Published private(set) var chapterScore: Int = 0
    @Published private(set) var result: ChapterResult? = nil
    @Published private(set) var best: Int
    /// Текущая кат-сцена (только в фазе `.cutscene`).
    @Published private(set) var cutscene: CutscenePlayback? = nil

    static let startLives = 3
    static let maxLives = 5

    // MARK: - Состояние сцен (читается рендером напрямую)

    private(set) var van = VanScene()
    private(set) var meadow = MeadowScene()
    private(set) var baseball = BaseballScene()
    private(set) var studio = StudioScene()

    // MARK: - Общие эффекты

    private(set) var banners: [Banner] = []
    private(set) var flash: Double = 0
    private(set) var shake: CGFloat = 0
    private(set) var time: Double = 0
    private(set) var sceneTime: Double = 0

    // MARK: - Ввод

    private var touching = false
    private var dragActive = false
    private var touchX: CGFloat = 0.5
    private var pendingTap: CGPoint? = nil
    private var aspect: CGFloat = 0.75

    private enum Keys {
        static let best = "twilight.book.best"
    }

    private var lightHaptics = UIImpactFeedbackGenerator(style: .light)
    private var heavyHaptics = UIImpactFeedbackGenerator(style: .heavy)

    init() {
        best = UserDefaults.standard.integer(forKey: Keys.best)
    }

    // MARK: - Управление потоком

    func setAspect(_ value: CGFloat) {
        guard value.isFinite, value > 0.2, value < 4 else { return }
        aspect = value
    }

    /// Новая партия: начинаем с первой главы.
    func newRun() {
        score = 0
        lives = Self.startLives
        chapter = .van
        banners = []
        result = nil
        touching = false
        pendingTap = nil
        lightHaptics.prepare()
        heavyHaptics.prepare()
        playCutscene(.prologue)
    }

    /// Игрок нажал «начать главу» на карточке.
    func beginChapter() {
        sceneTime = 0
        chapterScore = 0
        banners = []
        touching = false
        pendingTap = nil

        switch chapter {
        case .van:      van.start()
        case .meadow:   meadow.start()
        case .baseball: baseball.start()
        case .studio:   studio.start()
        }

        phase = .playing
    }

    /// Игрок закрыл экран итогов главы.
    func advanceFromResult() {
        if let next = Chapter(rawValue: chapter.rawValue + 1) {
            chapter = next
            result = nil
            playCutscene(.intro(next))
        } else {
            saveBest(score)
            playCutscene(.finale)
        }
    }

    // MARK: - Кат-сцены

    private func playCutscene(_ id: CutsceneID) {
        banners = []
        touching = false
        pendingTap = nil
        cutscene = CutscenePlayback(script: CutsceneLibrary.script(id))
        phase = .cutscene
    }

    /// Тап по экрану в кат-сцене — следующий кадр.
    func skipShot() {
        guard phase == .cutscene, var playback = cutscene else { return }
        // Защита от случайного двойного тапа на стыке кадров.
        guard playback.shotTime > 0.35 else { return }
        playback.index += 1
        playback.shotTime = 0
        if playback.isFinished {
            finishCutscene()
        } else {
            cutscene = playback
        }
    }

    /// Кнопка «Пропустить» — вся кат-сцена целиком.
    func skipCutscene() {
        guard phase == .cutscene else { return }
        finishCutscene()
    }

    private func advanceCutscene(_ dt: Double) {
        guard var playback = cutscene else {
            phase = .chapterCard
            return
        }
        playback.shotTime += dt
        if playback.shotTime >= playback.shot.duration {
            playback.index += 1
            playback.shotTime = 0
        }
        if playback.isFinished {
            finishCutscene()
        } else {
            cutscene = playback
        }
    }

    private func finishCutscene() {
        guard let id = cutscene?.script.id else {
            phase = .chapterCard
            return
        }
        cutscene = nil
        switch id {
        case .prologue:
            playCutscene(.intro(.van))
        case .intro:
            phase = .chapterCard
        case .outro:
            phase = .chapterResult
        case .finale:
            phase = .finale
        }
    }

    /// Какую 3D-площадку сейчас показывать.
    var stageID: StageID {
        switch phase {
        case .menu:
            return .road
        case .cutscene:
            return cutscene?.script.id.stage ?? chapter.stage
        case .finale:
            return .finale
        default:
            return chapter.stage
        }
    }

    func pause() {
        guard phase == .playing else { return }
        touching = false
        pendingTap = nil
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .playing
    }

    /// Переиграть текущую главу с начала.
    func restartChapter() {
        guard phase == .paused else { return }
        beginChapter()
    }

    func goToMenu() {
        cutscene = nil
        phase = .menu
        touching = false
        dragActive = false
        pendingTap = nil
    }

    // MARK: - Ввод от вида

    /// Жест: первый вызов в серии считается «нажатием», дальше — перемещением.
    func dragChanged(_ normalized: CGPoint) {
        if dragActive {
            touchMoved(normalized)
        } else {
            dragActive = true
            touchBegan(normalized)
        }
    }

    func dragEnded() {
        dragActive = false
        touchEnded()
    }

    func touchBegan(_ normalized: CGPoint) {
        if phase == .cutscene {
            skipShot()
            return
        }
        guard phase == .playing else { return }
        touching = true
        touchX = clamp(normalized.x, 0, 1)
        pendingTap = CGPoint(x: clamp(normalized.x, 0, 1), y: clamp(normalized.y, 0, 1))
    }

    func touchMoved(_ normalized: CGPoint) {
        guard phase == .playing else { return }
        touchX = clamp(normalized.x, 0, 1)
    }

    func touchEnded() {
        touching = false
    }

    /// Палец на экране — для 3D-сцены (Эдвард склоняется к ране, пока игрок держит).
    var isHolding: Bool { touching }

    // MARK: - Игровой цикл

    func update(dt: CGFloat) {
        revision &+= 1
        time += Double(dt)

        flash = max(0, flash - Double(dt) * 2.6)
        if shake > 0 { shake = max(0, shake - dt * 3.0) }

        for index in banners.indices {
            banners[index].life -= Double(dt)
            banners[index].y -= CGFloat(dt) * 0.10
        }
        banners.removeAll { $0.life <= 0 }

        if phase == .cutscene {
            pendingTap = nil
            advanceCutscene(Double(dt))
            return
        }

        guard phase == .playing else {
            pendingTap = nil
            return
        }

        sceneTime += Double(dt)

        let ctx = SceneContext(
            dt: dt,
            time: sceneTime,
            aspect: aspect,
            touchX: touchX,
            touching: touching,
            tap: pendingTap
        )
        pendingTap = nil

        var outcome = SceneOutcome.none
        switch chapter {
        case .van:      outcome = van.update(ctx)
        case .meadow:   outcome = meadow.update(ctx)
        case .baseball: outcome = baseball.update(ctx)
        case .studio:   outcome = studio.update(ctx)
        }

        if outcome.score != 0 {
            score += outcome.score
            chapterScore += outcome.score
        }
        if let banner = outcome.banner {
            banners.append(banner)
        }
        if outcome.lifeDelta < 0 {
            lives = max(0, lives + outcome.lifeDelta)
            shake = 1
            flash = 1
            heavyHaptics.impactOccurred()
        } else if outcome.score > 0 {
            lightHaptics.impactOccurred(intensity: 0.5)
        }

        if lives <= 0 {
            saveBest(score)
            phase = .gameOver
        } else if outcome.chapterDone {
            finishChapter()
        }
    }

    // MARK: - Внутреннее

    private func finishChapter() {
        let rank = Ranks.rank(forScore: chapterScore, chapter: chapter)
        result = ChapterResult(
            chapter: chapter,
            score: chapterScore,
            livesLeft: lives,
            rank: rank,
            note: Self.note(for: chapter)
        )
        // Сначала развязка главы, потом экран итогов.
        playCutscene(.outro(chapter))
    }

    private static func note(for chapter: Chapter) -> String {
        switch chapter {
        case .van:
            return "Вмятину на дверце фургона он объяснить не смог."
        case .meadow:
            return "«Это просто свет», — сказал он. Ты не поверила."
        case .baseball:
            return "Гроза кончилась. Игру пришлось закончить."
        case .studio:
            return "Он успел. На этот раз — успел."
        }
    }

    private func saveBest(_ value: Int) {
        guard value > best else { return }
        best = value
        UserDefaults.standard.set(value, forKey: Keys.best)
    }

    // MARK: - Для HUD

    /// Прогресс текущей главы, 0...1.
    var chapterProgress: Double {
        switch chapter {
        case .van:
            return min(1, Double(van.beat) / Double(VanScene.beats))
        case .meadow:
            return min(1, sceneTime / MeadowScene.duration)
        case .baseball:
            return min(1, Double(baseball.beat) / Double(BaseballScene.beats))
        case .studio:
            return 1 - studio.venom
        }
    }

    var chapterCaption: String {
        switch chapter {
        case .van:
            return "ФУРГОН \(min(van.beat + 1, VanScene.beats)) / \(VanScene.beats)"
        case .meadow:
            return "ПРОДЕРЖИСЬ \(max(0, Int(ceil(MeadowScene.duration - sceneTime)))) С"
        case .baseball:
            return "БРОСОК \(min(baseball.beat + 1, BaseballScene.beats)) / \(BaseballScene.beats)"
        case .studio:
            return "ЯД \(Int(studio.venom * 100))%"
        }
    }
}

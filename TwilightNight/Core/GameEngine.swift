import SwiftUI
import UIKit

/// Дирижёр всей книги: ведёт главы и кат-сцены, считает очки, жизни и рекорд,
/// хранит прогресс и настройки, а ввод передаёт активной сцене.
final class GameEngine: ObservableObject {

    // MARK: - Публичное состояние

    /// Растёт каждый кадр — заставляет HUD обновиться.
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var phase: GamePhase = .menu
    @Published private(set) var chapter: Chapter = .biology
    @Published private(set) var score: Int = 0
    @Published private(set) var lives: Int = 3
    @Published private(set) var chapterScore: Int = 0
    @Published private(set) var result: ChapterResult? = nil
    @Published private(set) var best: Int
    /// Текущая кат-сцена (только в фазе `.cutscene`).
    @Published private(set) var cutscene: CutscenePlayback? = nil

    /// Сложность (запоминается между запусками).
    @Published var difficulty: Difficulty {
        didSet { UserDefaults.standard.set(difficulty.rawValue, forKey: Keys.difficulty) }
    }
    /// До какой главы игрок уже дошёл (открыта для выбора).
    @Published private(set) var unlocked: Int
    /// Сохранённая точка для «Продолжить».
    @Published private(set) var savedChapter: Chapter?

    static let startLives = 3
    static let maxLives = 5

    // MARK: - Состояние сцен (читается рендером напрямую)

    private(set) var biology = BiologyScene()
    private(set) var van = VanScene()
    private(set) var portAngeles = RunnerScene(kind: .street)
    private(set) var meadow = MeadowScene()
    private(set) var forest = RunnerScene(kind: .forest)
    private(set) var baseball = BaseballScene()
    private(set) var chase = RunnerScene(kind: .chase)
    private(set) var studio = StudioScene()
    private(set) var prom = DanceScene()
    private(set) var wedding = WeddingScene()

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
    private var pendingChoice: Int? = nil
    private var pendingConfirm = false
    private var pendingSwipe: RunnerScene.Swipe? = nil
    /// Откуда начался жест и сработал ли уже свайп в нём.
    private var swipeOrigin: CGPoint = .zero
    private var swipeUsed = false
    private var aspect: CGFloat = 0.75
    private var chapterStartScore = 0

    private enum Keys {
        static let best = "twilight.book.best"
        static let difficulty = "twilight.difficulty"
        static let unlocked = "twilight.unlocked"
        static let savedChapter = "twilight.save.chapter"
        static let savedScore = "twilight.save.score"
        static let savedLives = "twilight.save.lives"
    }

    private var lightHaptics = UIImpactFeedbackGenerator(style: .light)
    private var heavyHaptics = UIImpactFeedbackGenerator(style: .heavy)

    init() {
        let defaults = UserDefaults.standard
        best = defaults.integer(forKey: Keys.best)
        difficulty = Difficulty(rawValue: defaults.integer(forKey: Keys.difficulty)) ?? .normal
        if defaults.object(forKey: Keys.difficulty) == nil { difficulty = .normal }
        unlocked = defaults.integer(forKey: Keys.unlocked)
        if defaults.object(forKey: Keys.savedChapter) != nil {
            savedChapter = Chapter(rawValue: defaults.integer(forKey: Keys.savedChapter))
        } else {
            savedChapter = nil
        }
    }

    // MARK: - Управление потоком

    func setAspect(_ value: CGFloat) {
        guard value.isFinite, value > 0.2, value < 4 else { return }
        aspect = value
    }

    /// Новая партия: пролог и первая глава.
    func newRun() {
        resetRun(score: 0, lives: Self.startLives)
        chapter = .biology
        playCutscene(.prologue)
    }

    /// Продолжить с сохранённой главы.
    func continueRun() {
        let defaults = UserDefaults.standard
        guard let saved = savedChapter else { newRun(); return }
        resetRun(score: defaults.integer(forKey: Keys.savedScore),
                 lives: max(1, defaults.integer(forKey: Keys.savedLives)))
        chapter = saved
        playCutscene(.intro(saved))
    }

    /// Начать с любой открытой главы (очки с нуля).
    func startFrom(_ target: Chapter) {
        guard target.rawValue <= unlocked else { return }
        resetRun(score: 0, lives: Self.startLives)
        chapter = target
        playCutscene(.intro(target))
    }

    private func resetRun(score: Int, lives: Int) {
        self.score = score
        self.lives = lives
        banners = []
        result = nil
        touching = false
        pendingTap = nil
        pendingChoice = nil
        lightHaptics.prepare()
        heavyHaptics.prepare()
    }

    /// Игрок нажал «начать главу» на карточке.
    func beginChapter() {
        sceneTime = 0
        chapterScore = 0
        chapterStartScore = score
        banners = []
        touching = false
        pendingTap = nil
        pendingChoice = nil

        let d = difficulty.factor
        switch chapter {
        case .biology:     biology.start(difficulty: d)
        case .van:         van.start(difficulty: d)
        case .portAngeles: portAngeles.start(difficulty: d)
        case .meadow:      meadow.start(difficulty: d)
        case .forest:      forest.start(difficulty: d)
        case .baseball:    baseball.start(difficulty: d)
        case .chase:       chase.start(difficulty: d)
        case .studio:      studio.start(difficulty: d)
        case .prom:        prom.start(difficulty: d)
        case .wedding:     wedding.start(difficulty: d)
        }

        phase = .playing
    }

    /// Игрок закрыл экран итогов главы.
    func advanceFromResult() {
        if let next = Chapter(rawValue: chapter.rawValue + 1) {
            chapter = next
            result = nil
            // Новая глава — немного сил: одна жизнь возвращается.
            lives = min(Self.maxLives, lives + 1)
            save(next)
            playCutscene(.intro(next))
        } else {
            saveBest(score)
            clearSave()
            playCutscene(.finale)
        }
    }

    /// После поражения — переиграть главу с теми очками, что были на её начале.
    func retryChapter() {
        guard phase == .gameOver else { return }
        score = chapterStartScore
        lives = Self.startLives
        phase = .chapterCard
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
            playCutscene(.intro(.biology))
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
            return .menu
        case .cutscene:
            return cutscene?.script.id.stage ?? chapter.stage
        case .finale:
            return .wedding
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
        score = chapterStartScore
        beginChapter()
    }

    func goToMenu() {
        cutscene = nil
        phase = .menu
        touching = false
        dragActive = false
        pendingTap = nil
    }

    // MARK: - Сохранение

    private func save(_ next: Chapter) {
        let defaults = UserDefaults.standard
        defaults.set(next.rawValue, forKey: Keys.savedChapter)
        defaults.set(score, forKey: Keys.savedScore)
        defaults.set(lives, forKey: Keys.savedLives)
        savedChapter = next
        if next.rawValue > unlocked {
            unlocked = next.rawValue
            defaults.set(unlocked, forKey: Keys.unlocked)
        }
    }

    private func clearSave() {
        UserDefaults.standard.removeObject(forKey: Keys.savedChapter)
        savedChapter = nil
        unlocked = Chapter.allCases.count - 1
        UserDefaults.standard.set(unlocked, forKey: Keys.unlocked)
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
        swipeOrigin = normalized
        swipeUsed = false
    }

    func touchMoved(_ normalized: CGPoint) {
        guard phase == .playing else { return }
        touchX = clamp(normalized.x, 0, 1)
        // Свайп: достаточно сдвинуть палец на ~5% экрана в одну сторону.
        guard !swipeUsed else { return }
        let dx = (normalized.x - swipeOrigin.x) * aspect
        let dy = normalized.y - swipeOrigin.y
        let threshold: CGFloat = 0.05
        if max(abs(dx), abs(dy)) > threshold {
            swipeUsed = true
            if abs(dx) > abs(dy) {
                pendingSwipe = dx < 0 ? .left : .right
            } else {
                pendingSwipe = dy < 0 ? .up : .down
            }
        }
    }

    func touchEnded() {
        touching = false
    }

    /// Палец на экране — для 3D-сцены (Эдвард склоняется к ране, пока игрок держит).
    var isHolding: Bool { touching }

    /// Ответ в викторине или выбор варианта на свадьбе.
    func choose(_ index: Int) {
        guard phase == .playing else { return }
        pendingChoice = index
        // Свадебный выбор виден сразу, не дожидаясь кадра.
        if chapter == .wedding { wedding.select(index) }
    }

    /// Кнопка «Готово» в свадебном раунде.
    func confirm() {
        guard phase == .playing else { return }
        pendingConfirm = true
    }

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
            pendingChoice = nil
            return
        }

        sceneTime += Double(dt)

        let ctx = SceneContext(
            dt: dt,
            time: sceneTime,
            aspect: aspect,
            touchX: touchX,
            touching: touching,
            tap: pendingTap,
            choice: pendingChoice,
            confirm: pendingConfirm,
            swipe: pendingSwipe,
            difficulty: difficulty.factor
        )
        pendingSwipe = nil
        pendingTap = nil
        pendingChoice = nil
        pendingConfirm = false

        var outcome = SceneOutcome.none
        switch chapter {
        case .biology:     outcome = biology.update(ctx)
        case .van:         outcome = van.update(ctx)
        case .portAngeles: outcome = portAngeles.update(ctx)
        case .meadow:      outcome = meadow.update(ctx)
        case .forest:      outcome = forest.update(ctx)
        case .baseball:    outcome = baseball.update(ctx)
        case .chase:       outcome = chase.update(ctx)
        case .studio:      outcome = studio.update(ctx)
        case .prom:        outcome = prom.update(ctx)
        case .wedding:     outcome = wedding.update(ctx)
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
        saveBest(score)
        // Сначала развязка главы, потом экран итогов.
        playCutscene(.outro(chapter))
    }

    private static func note(for chapter: Chapter) -> String {
        switch chapter {
        case .biology:     return "«Мы же партнёры по лабораторной», — сказал он. И впервые улыбнулся."
        case .van:         return "Вмятину на дверце фургона он объяснить не смог."
        case .portAngeles: return "Он нашёл её в чужом городе. Как — так и не сказал."
        case .meadow:      return "«Это просто свет», — сказал он. Ты не поверила."
        case .forest:      return "Голова кружилась. Не от скорости."
        case .baseball:    return "Гроза кончилась. Игру пришлось закончить."
        case .chase:       return "Фары исчезли из зеркала. Но ненадолго."
        case .studio:      return "Он успел. На этот раз — успел."
        case .prom:        return "Она танцевала на его ногах. И не упала ни разу."
        case .wedding:     return "«Ты превзошла саму себя», — сказала Элис. Почти без зависти."
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
        case .biology:     return min(1, Double(biology.slide) / Double(BiologyScene.slides))
        case .van:         return min(1, Double(van.beat) / Double(VanScene.beats))
        case .portAngeles: return portAngeles.progress
        case .meadow:      return min(1, sceneTime / MeadowScene.duration)
        case .forest:      return forest.progress
        case .baseball:    return min(1, Double(baseball.beat) / Double(BaseballScene.beats))
        case .chase:       return chase.progress
        case .studio:      return 1 - studio.venom
        case .prom:        return prom.progress
        case .wedding:     return min(1, Double(wedding.round) / Double(WeddingScene.Category.allCases.count))
        }
    }

    var chapterCaption: String {
        switch chapter {
        case .biology:
            return "ПРЕПАРАТ \(min(biology.slide + 1, BiologyScene.slides)) / \(BiologyScene.slides)"
        case .van:
            return "ФУРГОН \(min(van.beat + 1, VanScene.beats)) / \(VanScene.beats)"
        case .portAngeles:
            return "ДО СВЕТА \(max(0, Int(ceil(portAngeles.duration - portAngeles.time)))) С"
        case .meadow:
            return "ПРОДЕРЖИСЬ \(max(0, Int(ceil(MeadowScene.duration - sceneTime)))) С"
        case .forest:
            return "\(Int(forest.speed * 3.6)) КМ/Ч"
        case .baseball:
            return "БРОСОК \(min(baseball.beat + 1, BaseballScene.beats)) / \(BaseballScene.beats)"
        case .chase:
            return "\(Int(chase.speed * 3.6)) КМ/Ч · \(max(0, Int(ceil(chase.duration - chase.time)))) С"
        case .studio:
            return "ЯД \(Int(studio.venom * 100))%"
        case .prom:
            return "СЕРИЯ \(prom.combo)"
        case .wedding:
            return "\(wedding.category.title) · \(max(0, Int(ceil(wedding.timer)))) С"
        }
    }
}

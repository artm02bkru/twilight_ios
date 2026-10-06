import SwiftUI

/// Финал. Подготовка к свадьбе: Элис даёт пожелание, игрок выбирает наряд или оформление.
/// Каждое совпадение с задумкой Элис приносит очки; выбор сразу виден в 3D-сцене,
/// а финальная кат-сцена показывает свадьбу именно такой, какой её собрал игрок.
struct WeddingScene {

    enum Category: Int, CaseIterable {
        case dress, veil, bouquet, suit, arch, lights, aisle, ribbons

        var title: String {
            switch self {
            case .dress:   return "ПЛАТЬЕ БЕЛЛЫ"
            case .veil:    return "ФАТА"
            case .bouquet: return "БУКЕТ"
            case .suit:    return "КОСТЮМ ЭДВАРДА"
            case .arch:    return "АРКА"
            case .lights:  return "СВЕТ"
            case .aisle:   return "ДОРОЖКА К АЛТАРЮ"
            case .ribbons: return "ЛЕНТЫ НА СТУЛЬЯХ"
            }
        }

        var symbol: String {
            switch self {
            case .dress:   return "figure.stand.dress"
            case .veil:    return "sparkles"
            case .bouquet: return "camera.macro"
            case .suit:    return "tshirt.fill"
            case .arch:    return "rainbow"
            case .lights:  return "lightbulb.fill"
            case .aisle:   return "road.lanes"
            case .ribbons: return "gift.fill"
            }
        }
    }

    enum Tag: CaseIterable {
        case vintage, lace, modest, modern, silk, elegant, classic, grand, simple, bold
        case nature, white, romantic, fragrant, mystic, warm
    }

    struct Option {
        let name: String
        let color: Color
        let tags: Set<Tag>
    }

    struct Wish {
        let text: String
        let tags: Set<Tag>
    }

    static let options: [Category: [Option]] = [
        .dress: [
            Option(name: "Винтажное кружево", color: Color(red: 0.97, green: 0.94, blue: 0.86), tags: [.vintage, .lace, .modest]),
            Option(name: "Шёлк, открытая спина", color: Color(red: 0.98, green: 0.96, blue: 0.92), tags: [.modern, .silk, .elegant]),
            Option(name: "Пышное, как у принцессы", color: .white, tags: [.classic, .grand]),
            Option(name: "Простое атласное", color: Color(red: 0.95, green: 0.88, blue: 0.78), tags: [.simple, .modest]),
            Option(name: "Голубое, как на выпускном", color: Color(red: 0.42, green: 0.6, blue: 0.82), tags: [.bold, .simple])
        ],
        .veil: [
            Option(name: "Длинная фата", color: .white, tags: [.classic, .grand]),
            Option(name: "Короткая вуаль", color: Color(red: 0.96, green: 0.93, blue: 0.86), tags: [.vintage, .modest]),
            Option(name: "Цветы в волосах", color: Color(red: 0.9, green: 0.85, blue: 0.95), tags: [.simple, .nature])
        ],
        .bouquet: [
            Option(name: "Белые фрезии", color: .white, tags: [.classic, .white, .fragrant]),
            Option(name: "Полевые цветы", color: Color(red: 0.95, green: 0.8, blue: 0.4), tags: [.nature, .simple]),
            Option(name: "Красные розы", color: Color(red: 0.75, green: 0.08, blue: 0.14), tags: [.bold, .romantic]),
            Option(name: "Синие ирисы", color: Color(red: 0.3, green: 0.35, blue: 0.85), tags: [.bold, .nature])
        ],
        .suit: [
            Option(name: "Чёрный смокинг", color: Color(white: 0.06), tags: [.classic, .grand]),
            Option(name: "Серый костюм", color: Color(white: 0.45), tags: [.modern, .simple]),
            Option(name: "Кремовый пиджак", color: Color(red: 0.9, green: 0.85, blue: 0.74), tags: [.vintage, .elegant]),
            Option(name: "Тёмно-синий", color: Color(red: 0.1, green: 0.14, blue: 0.3), tags: [.modern, .bold])
        ],
        .arch: [
            Option(name: "Белые цветы и плющ", color: .white, tags: [.classic, .white, .nature]),
            Option(name: "Ветви и свечи", color: Color(red: 0.55, green: 0.45, blue: 0.35), tags: [.vintage, .mystic]),
            Option(name: "Ткань и кристаллы", color: Color(red: 0.85, green: 0.9, blue: 1), tags: [.grand, .modern]),
            Option(name: "Еловые лапы", color: Color(red: 0.15, green: 0.35, blue: 0.2), tags: [.nature, .simple])
        ],
        .lights: [
            Option(name: "Тёплые гирлянды", color: Color(red: 1, green: 0.8, blue: 0.45), tags: [.warm, .romantic]),
            Option(name: "Свечи в фонарях", color: Color(red: 1, green: 0.65, blue: 0.3), tags: [.vintage, .mystic]),
            Option(name: "Холодный лунный свет", color: Color(red: 0.65, green: 0.78, blue: 1), tags: [.mystic, .modern])
        ],
        .aisle: [
            Option(name: "Белые лепестки", color: .white, tags: [.classic, .romantic, .white]),
            Option(name: "Мох и папоротник", color: Color(red: 0.25, green: 0.45, blue: 0.2), tags: [.nature, .simple]),
            Option(name: "Ковровая дорожка", color: Color(red: 0.6, green: 0.1, blue: 0.15), tags: [.grand, .classic])
        ],
        .ribbons: [
            Option(name: "Белые ленты", color: .white, tags: [.white, .classic]),
            Option(name: "Лиловые ленты", color: Color(red: 0.6, green: 0.45, blue: 0.8), tags: [.romantic, .bold]),
            Option(name: "Без лент", color: Color(red: 0.5, green: 0.38, blue: 0.28), tags: [.simple, .modern])
        ]
    ]

    static let wishes: [Category: [Wish]] = [
        .dress: [
            Wish(text: "Белла не любит пафос. Что-то скромное, но с историей.", tags: [.modest, .vintage]),
            Wish(text: "Пусть все ахнут, когда она выйдет!", tags: [.grand, .classic]),
            Wish(text: "Современно и очень элегантно.", tags: [.modern, .elegant]),
            Wish(text: "Просто и честно — как она сама.", tags: [.simple, .modest])
        ],
        .veil: [
            Wish(text: "Классика. Длинная, до самой земли.", tags: [.classic, .grand]),
            Wish(text: "Что-нибудь живое — она выросла среди леса.", tags: [.nature, .simple]),
            Wish(text: "В тон к старинному кружеву.", tags: [.vintage, .modest])
        ],
        .bouquet: [
            Wish(text: "Её любимый запах — белые фрезии.", tags: [.fragrant, .white]),
            Wish(text: "Ярко! Чтобы было видно с другого конца сада.", tags: [.bold, .romantic]),
            Wish(text: "Цветы, которые растут на нашем лугу.", tags: [.nature, .simple])
        ],
        .suit: [
            Wish(text: "Эдвард родился в 1901-м. Пусть будет немного старины.", tags: [.vintage, .elegant]),
            Wish(text: "Строго, торжественно, безупречно.", tags: [.classic, .grand]),
            Wish(text: "Он и так слишком идеален. Попроще.", tags: [.simple, .modern])
        ],
        .arch: [
            Wish(text: "Белое и зелёное — как свадьбы в старых фильмах.", tags: [.white, .nature]),
            Wish(text: "Немного магии. Пусть горят свечи.", tags: [.mystic, .vintage]),
            Wish(text: "Роскошно. Хрусталь и шёлк.", tags: [.grand, .modern])
        ],
        .lights: [
            Wish(text: "Тепло и уютно, как в сказке.", tags: [.warm, .romantic]),
            Wish(text: "Таинственно — мы же всё-таки вампиры.", tags: [.mystic]),
            Wish(text: "Живой огонь, как сто лет назад.", tags: [.vintage, .mystic])
        ],
        .aisle: [
            Wish(text: "Лепестки под ногами — это обязательно.", tags: [.romantic, .white]),
            Wish(text: "Пусть дорожка будет частью леса.", tags: [.nature, .simple]),
            Wish(text: "Торжественно, как во дворце.", tags: [.grand, .classic])
        ],
        .ribbons: [
            Wish(text: "Всё в белом. Это же свадьба!", tags: [.white, .classic]),
            Wish(text: "Добавь цвета, а то как в больнице.", tags: [.bold, .romantic]),
            Wish(text: "Ничего лишнего.", tags: [.simple])
        ]
    ]

    enum Stage { case choosing, feedback }

    var round = 0
    var category: Category = .dress
    var wish = Wish(text: "", tags: [])
    /// Текущий (ещё не подтверждённый) выбор — сразу виден в 3D.
    var selection: Int = 0
    /// Окончательный выбор по каждой категории (индекс варианта).
    var picked: [Int] = Array(repeating: 0, count: Category.allCases.count)
    var stage: Stage = .choosing
    var timer: Double = 0
    var timeLimit: Double = 22
    var feedbackTimer: Double = 0
    var lastMatches = 0
    var finished = false
    private var difficulty: CGFloat = 1

    var options: [Option] { Self.options[category] ?? [] }

    mutating func start(difficulty: CGFloat = 1) {
        self = WeddingScene()
        self.difficulty = difficulty
        beginRound()
    }

    private mutating func beginRound() {
        category = Category(rawValue: round) ?? .dress
        wish = Self.wishes[category]?.randomElement() ?? Wish(text: "", tags: [])
        selection = picked[category.rawValue]
        timeLimit = 22 / Double(difficulty)
        timer = timeLimit
        stage = .choosing
    }

    /// Выбор варианта (кнопка) — меняет превью сразу.
    mutating func select(_ index: Int) {
        guard stage == .choosing, index >= 0, index < options.count else { return }
        selection = index
        picked[category.rawValue] = index
    }

    mutating func update(_ ctx: SceneContext) -> SceneOutcome {
        var outcome = SceneOutcome.none
        switch stage {
        case .choosing:
            if let index = ctx.choice { select(index) }
            timer -= Double(ctx.dt)
            if ctx.confirm || timer <= 0 {
                confirm(&outcome)
            }
        case .feedback:
            feedbackTimer -= Double(ctx.dt)
            if feedbackTimer <= 0 {
                round += 1
                if round >= Category.allCases.count {
                    finished = true
                    outcome.chapterDone = true
                } else {
                    beginRound()
                }
            }
        }
        return outcome
    }

    private mutating func confirm(_ outcome: inout SceneOutcome) {
        picked[category.rawValue] = selection
        let chosen = options[selection]
        let matches = chosen.tags.intersection(wish.tags).count
        lastMatches = matches
        let timeBonus = Int(max(0, timer) / timeLimit * 15)
        let gained = matches * 25 + timeBonus
        outcome.score = gained
        switch matches {
        case 2...:
            outcome.banner = Banner(text: "ЭЛИС В ВОСТОРГЕ  +\(gained)", color: Theme.gold,
                                    x: 0.5, y: 0.22, life: 1.4, total: 1.4, big: true)
        case 1:
            outcome.banner = Banner(text: "НЕПЛОХО  +\(gained)", color: Theme.ice,
                                    x: 0.5, y: 0.22, life: 1.2, total: 1.2)
        default:
            outcome.banner = Banner(text: "ЭЛИС ВЗДЫХАЕТ  +\(gained)", color: Theme.mist,
                                    x: 0.5, y: 0.22, life: 1.2, total: 1.2)
        }
        stage = .feedback
        feedbackTimer = 1.4
    }
}

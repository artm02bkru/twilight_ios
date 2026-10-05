import Foundation

/// Сценарии всех кат-сцен. Реплики — пересказ сцен книги своими словами.
enum CutsceneLibrary {

    static func script(_ id: CutsceneID) -> Cutscene {
        switch id {
        case .prologue:            return prologue
        case .intro(let chapter):  return intro(chapter)
        case .outro(let chapter):  return outro(chapter)
        case .finale:              return finale
        }
    }

    // MARK: - Пролог

    private static let prologue = Cutscene(
        id: .prologue,
        caption: nil,
        shots: [
            CutsceneShot(cue: .roadAerial, duration: 6.0, speaker: nil,
                         line: "Форкс, штат Вашингтон. Самое дождливое место в Америке."),
            CutsceneShot(cue: .roadTruckFollow, duration: 6.0, speaker: "Белла",
                         line: "Я переехала к отцу — в город, где солнце бывает реже, чем праздники."),
            CutsceneShot(cue: .roadTruckSide, duration: 5.5, speaker: "Белла",
                         line: "Я и представить не могла, что здесь живут те, кому солнце запрещено."),
            CutsceneShot(cue: .roadTitle, duration: 4.5, speaker: nil,
                         line: "СУМЕРКИ", style: .title)
        ]
    )

    // MARK: - Вступления глав

    private static func intro(_ chapter: Chapter) -> Cutscene {
        let caption = "\(chapter.number) · \(chapter.title.uppercased())"
        switch chapter {
        case .van:
            return Cutscene(id: .intro(chapter), caption: caption, shots: [
                CutsceneShot(cue: .lotEstablish, duration: 5.5, speaker: nil,
                             line: "Утро после первого снега. Парковку школы затянуло льдом."),
                CutsceneShot(cue: .lotBella, duration: 5.0, speaker: "Белла",
                             line: "Я разглядывала цепи на колёсах — Чарли поставил их ещё до рассвета."),
                CutsceneShot(cue: .lotEdward, duration: 4.5, speaker: nil,
                             line: "Через четыре машины стоял Эдвард Каллен. И смотрел на неё с ужасом."),
                CutsceneShot(cue: .lotVanSkid, duration: 4.0, speaker: nil,
                             line: "Визг шин. Фургон Тайлера развернуло на льду."),
                CutsceneShot(cue: .lotVanClose, duration: 3.5, speaker: "Белла",
                             line: "Времени не осталось даже на то, чтобы закрыть глаза.")
            ])

        case .meadow:
            return Cutscene(id: .intro(chapter), caption: caption, shots: [
                CutsceneShot(cue: .forestHike, duration: 5.0, speaker: nil,
                             line: "Он вёл её через лес — туда, где кончалась тропа."),
                CutsceneShot(cue: .meadowReveal, duration: 5.0, speaker: "Белла",
                             line: "Луг. Почти идеально круглый, весь в диких цветах."),
                CutsceneShot(cue: .edwardHesitates, duration: 4.5, speaker: "Эдвард",
                             line: "Ты должна увидеть, почему я прячусь от солнца."),
                CutsceneShot(cue: .edwardSteps, duration: 5.5, speaker: nil,
                             line: "Его кожа вспыхнула, будто в неё вросли тысячи алмазов."),
                CutsceneShot(cue: .cloudsMove, duration: 4.5, speaker: nil,
                             line: "Но облака расходятся. Если кто-то забредёт сюда — тайна раскрыта.")
            ])

        case .baseball:
            return Cutscene(id: .intro(chapter), caption: caption, shots: [
                CutsceneShot(cue: .stormSky, duration: 4.5, speaker: "Элис",
                             line: "Гроза будет через минуту. Можно начинать."),
                CutsceneShot(cue: .cullensField, duration: 5.0, speaker: nil,
                             line: "Каллены играют только в грозу: гром прячет звук удара."),
                CutsceneShot(cue: .alicePitch, duration: 4.0, speaker: nil,
                             line: "Элис на питчерской горке. Эдвард у базы."),
                CutsceneShot(cue: .nomadsTree, duration: 4.5, speaker: "Элис",
                             line: "Будьте тише. Где-то в лесу есть те, кто может услышать.")
            ])

        case .studio:
            return Cutscene(id: .intro(chapter), caption: caption, shots: [
                CutsceneShot(cue: .studioEstablish, duration: 5.0, speaker: nil,
                             line: "Балетная студия в Фениксе. Все зеркала разбиты."),
                CutsceneShot(cue: .studioBite, duration: 4.5, speaker: nil,
                             line: "Джеймс успел укусить её. Яд уже жжёт кровь."),
                CutsceneShot(cue: .studioCarlisle, duration: 5.0, speaker: "Карлайл",
                             line: "Ты можешь вытянуть яд, Эдвард. Труднее всего — вовремя остановиться."),
                CutsceneShot(cue: .studioEdward, duration: 3.5, speaker: "Эдвард",
                             line: "Я смогу.")
            ])
        }
    }

    // MARK: - Развязки глав

    private static func outro(_ chapter: Chapter) -> Cutscene {
        switch chapter {
        case .van:
            return Cutscene(id: .outro(chapter), caption: nil, shots: [
                CutsceneShot(cue: .lotDent, duration: 4.5, speaker: nil,
                             line: "На борту фургона осталась вмятина — точно по форме ладони."),
                CutsceneShot(cue: .lotFacesBella, duration: 4.0, speaker: "Белла",
                             line: "Ты стоял у своей машины. Я видела."),
                CutsceneShot(cue: .lotFacesEdward, duration: 4.0, speaker: "Эдвард",
                             line: "Ты ударилась головой, Белла. Я всё время был рядом.")
            ])

        case .meadow:
            return Cutscene(id: .outro(chapter), caption: nil, shots: [
                CutsceneShot(cue: .meadowLying, duration: 4.5, speaker: "Эдвард",
                             line: "Ты совсем меня не боишься?"),
                CutsceneShot(cue: .meadowLyingClose, duration: 4.5, speaker: "Белла",
                             line: "Я боюсь только одного — что ты исчезнешь."),
                CutsceneShot(cue: .meadowSunset, duration: 4.5, speaker: nil,
                             line: "Солнце ушло за деревья. Тайна осталась на лугу.")
            ])

        case .baseball:
            return Cutscene(id: .outro(chapter), caption: nil, shots: [
                CutsceneShot(cue: .nomadsArrive, duration: 4.5, speaker: nil,
                             line: "Из тумана вышли трое кочевников."),
                CutsceneShot(cue: .jamesSniffs, duration: 4.0, speaker: "Джеймс",
                             line: "Вы привели с собой человека?"),
                CutsceneShot(cue: .edwardShields, duration: 4.5, speaker: nil,
                             line: "С этой минуты охота началась.")
            ])

        case .studio:
            return Cutscene(id: .outro(chapter), caption: nil, shots: [
                CutsceneShot(cue: .studioCalm, duration: 4.0, speaker: "Белла",
                             line: "Огонь уходит..."),
                CutsceneShot(cue: .studioEmbrace, duration: 4.5, speaker: "Эдвард",
                             line: "Я здесь. И больше никуда не уйду.")
            ])
        }
    }

    // MARK: - Финал

    private static let finale = Cutscene(
        id: .finale,
        caption: "ЭПИЛОГ · ВЫПУСКНОЙ",
        shots: [
            CutsceneShot(cue: .finaleDance, duration: 5.5, speaker: nil,
                         line: "Выпускной бал. Сумерки — самое безопасное время для них."),
            CutsceneShot(cue: .finaleClose, duration: 4.5, speaker: "Белла",
                         line: "Я хочу остаться с тобой. Навсегда."),
            CutsceneShot(cue: .finaleCrane, duration: 4.5, speaker: nil,
                         line: "СУМЕРКИ", style: .title)
        ]
    )
}

import AVFoundation

/// Звуки игры. Если в папке Audio лежит файл с нужным именем — играет он:
/// фоны `amb_<имя>`, эффекты `sfx_<имя>`, реплики кат-сцен `vo_<кадр>` (m4a, mp3, wav, aac, caf).
/// Фоновые петли без файла молчат (синтезированный шум убран); эффекты без файла —
/// синтезированные. Список имён — Audio/README.txt.
final class SoundFX {

    static let shared = SoundFX()

    enum Effect: CaseIterable {
        case thunder, thunderNear, skid, impact, batCrack, whiff, heartbeat, chime, whoosh, chirp, sparkle
    }

    enum Ambience: CaseIterable {
        case rain, heavyRain, wind, forest, crickets, hum, engine
    }

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var oneShots: [AVAudioPlayerNode] = []
    private var nextShot = 0
    private var loops: [Ambience: AVAudioPlayerNode] = [:]
    private var effectBuffers: [Effect: AVAudioPCMBuffer] = [:]
    private var running = false
    private let queue = DispatchQueue(label: "twilight.sfx")
    /// Фоны и эффекты из файлов.
    private var ambiencePlayers: [Ambience: AVAudioPlayer] = [:]
    private var effectFiles: [Effect: URL] = [:]
    private var voiceNode: (player: AVAudioPlayerNode, eq: AVAudioUnitEQ)?
    private var lastVoice = ""

    /// Усиление файлов (дБ): AVAudioPlayer не умеет громче 100 %, поэтому — через движок с EQ.
    private static let effectGain: Float = 5
    private static let thunderGain: Float = 8
    private static let edwardVoiceGain: Float = 9
    private static let voiceGain: Float = 3

    /// Проиграть файл через движок с усилением; узлы сами отключаются по окончании.
    @discardableResult
    private func playFile(_ url: URL, gain: Float, volume: Float) -> (player: AVAudioPlayerNode, eq: AVAudioUnitEQ)? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        if !engine.isRunning { try? engine.start() }
        let node = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 0)
        eq.globalGain = gain
        engine.attach(node)
        engine.attach(eq)
        engine.connect(node, to: eq, format: file.processingFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: file.processingFormat)
        node.volume = volume
        node.scheduleFile(file, at: nil) { [weak self] in
            self?.queue.asyncAfter(deadline: .now() + 0.3) {
                guard let self else { return }
                node.stop()
                self.engine.detach(node)
                self.engine.detach(eq)
            }
        }
        node.play()
        return (node, eq)
    }

    /// Файл из папки Audio по имени без расширения.
    static func audioURL(_ name: String) -> URL? {
        let bundle = Bundle.main
        for ext in ["m4a", "mp3", "wav", "aac", "caf"] {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Audio")
                ?? bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }

    private init() {
        // Звуки синтезируются в фоне — запуск игры не задерживается.
        queue.async { [weak self] in self?.build() }
    }

    // MARK: - Публичное

    func play(_ effect: Effect, volume: Float = 1, delay: TimeInterval = 0) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            if let url = self.effectFiles[effect] {
                let loud = effect == .thunder || effect == .thunderNear
                self.playFile(url, gain: loud ? Self.thunderGain : Self.effectGain, volume: volume)
                return
            }
            guard self.running, let buffer = self.effectBuffers[effect] else { return }
            let player = self.oneShots[self.nextShot]
            self.nextShot = (self.nextShot + 1) % self.oneShots.count
            player.stop()
            player.volume = volume
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            player.play()
        }
    }

    /// Громкость фонового слоя (0 — тишина). Меняется плавно на стороне вызывающего.
    func setAmbience(_ ambience: Ambience, volume: Float) {
        queue.async { [weak self] in
            guard let p = self?.ambiencePlayers[ambience] else { return }
            p.setVolume(volume, fadeDuration: 0.6)
            if volume > 0 && !p.isPlaying { p.play() }
        }
    }

    /// Выключить все фоновые слои, кроме перечисленных.
    func ambience(_ levels: [Ambience: Float]) {
        queue.async { [weak self] in
            guard let self else { return }
            for (kind, p) in self.ambiencePlayers {
                let v = levels[kind] ?? 0
                p.setVolume(v, fadeDuration: 1.2)
                if v > 0 && !p.isPlaying { p.play() }
            }
        }
    }

    /// Реплика кадра кат-сцены: файл `vo_<name>`; музыка на время приглушается.
    /// Голос Эдварда записан тише — ему отдельное усиление.
    func voice(_ name: String, speaker: String? = nil) {
        queue.async { [weak self] in
            guard let self, name != self.lastVoice else { return }
            self.lastVoice = name
            self.stopVoiceNode()
            guard let url = Self.audioURL("vo_" + name) else { return }
            let gain = speaker == "Эдвард" ? Self.edwardVoiceGain : Self.voiceGain
            self.voiceNode = self.playFile(url, gain: gain, volume: 1)
            let length = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 2
            DispatchQueue.main.async {
                SoundtrackPlayer.shared.duck(to: 0.14, over: 0.3)
                DispatchQueue.main.asyncAfter(deadline: .now() + length + 0.2) {
                    SoundtrackPlayer.shared.unduck()
                }
            }
        }
    }

    private func stopVoiceNode() {
        guard let v = voiceNode else { return }
        v.player.stop()
        voiceNode = nil
    }

    func stopVoice() {
        queue.async { [weak self] in
            guard let self, self.voiceNode != nil || !self.lastVoice.isEmpty else { return }
            self.stopVoiceNode()
            self.lastVoice = ""
            DispatchQueue.main.async { SoundtrackPlayer.shared.unduck() }
        }
    }

    /// Вернуться из фона — аудиодвижок мог остановиться.
    func resume() {
        queue.async { [weak self] in
            guard let self, !self.engine.isRunning, !self.oneShots.isEmpty else { return }
            try? self.engine.start()
            for p in self.ambiencePlayers.values where p.volume > 0 { p.play() }
        }
    }

    // MARK: - Сборка

    private func build() {
        for effect in Effect.allCases { effectBuffers[effect] = makeEffect(effect) }

        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            oneShots.append(p)
        }
        // Фоны — только из файлов: синтезированный шум шипел.
        for kind in Ambience.allCases {
            guard let url = Self.audioURL("amb_\(kind)"), let p = try? AVAudioPlayer(contentsOf: url) else { continue }
            p.numberOfLoops = -1
            p.volume = 0
            p.prepareToPlay()
            ambiencePlayers[kind] = p
        }
        for effect in Effect.allCases {
            if let url = Self.audioURL("sfx_\(effect)") {
                effectFiles[effect] = url
            }
        }
        engine.mainMixerNode.outputVolume = 0.9
        do {
            try engine.start()
        } catch {
            NSLog("SoundFX: аудиодвижок не запустился: \(error)")
            return
        }
        running = true
    }

    private var sampleRate: Float { Float(format.sampleRate) }

    private func buffer(seconds: Float, _ sample: (Int, Float) -> Float) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let channel = buf.floatChannelData![0]
        for i in 0..<Int(frames) {
            channel[i] = max(-1, min(1, sample(i, Float(i) / sampleRate)))
        }
        return buf
    }

    // MARK: Шумы

    /// Простой генератор белого шума с фильтрами.
    private struct Noise {
        var state: UInt32 = 22_222
        var low: Float = 0
        var brown: Float = 0
        var pinkB: (Float, Float, Float) = (0, 0, 0)

        mutating func white() -> Float {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Float(state >> 8) / Float(1 << 24) * 2 - 1
        }

        mutating func lowpass(_ k: Float) -> Float {
            low += (white() - low) * k
            return low
        }

        mutating func brownian() -> Float {
            brown = (brown + white() * 0.02) * 0.998
            return brown * 3.5
        }

        mutating func pink() -> Float {
            let w = white()
            pinkB.0 = 0.99765 * pinkB.0 + w * 0.0990460
            pinkB.1 = 0.96300 * pinkB.1 + w * 0.2965164
            pinkB.2 = 0.57000 * pinkB.2 + w * 1.0526913
            return (pinkB.0 + pinkB.1 + pinkB.2 + w * 0.1848) * 0.11
        }
    }

    // MARK: Фоновые слои

    private func makeLoop(_ kind: Ambience) -> AVAudioPCMBuffer {
        var n = Noise(state: UInt32(17 + kind.hashValue & 0xFFFF))
        let length: Float = 6
        let fade = { (t: Float) -> Float in
            // Мягкие края, чтобы шов петли не щёлкал.
            min(1, t / 0.05, (length - t) / 0.05)
        }
        switch kind {
        case .rain, .heavyRain:
            let heavy = kind == .heavyRain
            return buffer(seconds: length) { _, t in
                var s = n.pink() * (heavy ? 0.55 : 0.35)
                // Отдельные капли — короткие щелчки.
                if n.white() > (heavy ? 0.9965 : 0.998) { s += n.white() * 0.5 }
                return s * fade(t)
            }
        case .wind:
            return buffer(seconds: length) { _, t in
                let gust = 0.55 + 0.45 * sin(t * 0.9) * sin(t * 0.37 + 1)
                return n.lowpass(0.02) * 2.2 * gust * fade(t)
            }
        case .forest:
            // Листва и далёкие птицы.
            return buffer(seconds: length) { _, t in
                var s = n.lowpass(0.05) * 0.6
                let birdPhase = t.truncatingRemainder(dividingBy: 2.3)
                if birdPhase < 0.18 {
                    let f = 2600 + 900 * sin(birdPhase * 60)
                    s += sin(t * f * 2 * Float.pi) * 0.06 * sin(birdPhase / 0.18 * Float.pi)
                }
                return s * fade(t)
            }
        case .crickets:
            return buffer(seconds: length) { _, t in
                let chirp = (t * 3.1).truncatingRemainder(dividingBy: 1) < 0.25 ? 1 : 0
                let trill = sin(t * 4600 * 2 * Float.pi) * (0.5 + 0.5 * sin(t * 90 * 2 * Float.pi))
                return trill * 0.05 * Float(chirp) * fade(t) + n.lowpass(0.02) * 0.2 * fade(t)
            }
        case .hum:
            // Гул ламп дневного света.
            return buffer(seconds: length) { _, t in
                let s = sin(t * 100 * 2 * Float.pi) * 0.12 + sin(t * 200 * 2 * Float.pi) * 0.05
                return (s + n.white() * 0.01) * fade(t)
            }
        case .engine:
            // Мотор старого пикапа.
            return buffer(seconds: length) { _, t in
                let rpm: Float = 38 + 3 * sin(t * 0.7)
                let s = sin(t * rpm * 2 * Float.pi) * 0.25 + sin(t * rpm * 4 * Float.pi) * 0.12
                return (s + n.lowpass(0.08) * 0.4) * 0.6 * fade(t)
            }
        }
    }

    // MARK: Разовые эффекты

    private func makeEffect(_ effect: Effect) -> AVAudioPCMBuffer {
        var n = Noise(state: 91 &+ UInt32(Effect.allCases.firstIndex(of: effect) ?? 0) &* 7919)
        switch effect {
        case .thunder, .thunderNear:
            let near = effect == .thunderNear
            return buffer(seconds: near ? 4.5 : 5.5) { _, t in
                let crack = near ? n.white() * exp(-t * 18) * 0.9 : 0
                let rumble = n.brownian() * (1 - exp(-t * 6)) * exp(-t * (near ? 0.9 : 0.7))
                let roll = 0.7 + 0.3 * sin(t * 5.3) * sin(t * 2.1)
                return (crack + rumble * roll * (near ? 1.4 : 1.0))
            }
        case .skid:
            return buffer(seconds: 1.6) { _, t in
                let env = min(1, t / 0.08) * exp(-max(0, t - 1.0) * 6)
                let squeal = sin(t * (1150 + 120 * sin(t * 23)) * 2 * Float.pi) * 0.35
                return (squeal + n.white() * 0.25) * env * 0.8
            }
        case .impact:
            return buffer(seconds: 1.0) { _, t in
                let thud = sin(t * 58 * 2 * Float.pi) * exp(-t * 7)
                let ring1: Float = sin(t * 310 * 2 * Float.pi) * exp(-t * 9) * 0.4
                let ring2: Float = sin(t * 523 * 2 * Float.pi) * exp(-t * 12) * 0.25
                let metal: Float = ring1 + ring2
                return (thud + metal + n.white() * exp(-t * 30) * 0.6) * 0.9
            }
        case .batCrack:
            return buffer(seconds: 0.35) { _, t in
                let click = n.white() * exp(-t * 60)
                let tone = sin(t * 1900 * 2 * Float.pi) * exp(-t * 35) * 0.5
                return (click + tone) * 0.95
            }
        case .whiff:
            return buffer(seconds: 0.4) { _, t in
                n.lowpass(0.2) * sin(min(1, t / 0.4) * Float.pi) * 1.2
            }
        case .heartbeat:
            return buffer(seconds: 0.9) { _, t in
                func beat(_ t0: Float) -> Float {
                    let x = t - t0
                    guard x > 0 else { return 0 }
                    return sin(x * 52 * 2 * Float.pi) * exp(-x * 14)
                }
                return (beat(0) + beat(0.28) * 0.7) * 0.9
            }
        case .chime:
            return buffer(seconds: 1.2) { _, t in
                let notes: [Float] = [1568, 2093, 2637]
                var s: Float = 0
                for (k, f) in notes.enumerated() {
                    let x = t - Float(k) * 0.07
                    if x > 0 { s += sin(x * f * 2 * Float.pi) * exp(-x * 4) * 0.12 }
                }
                return s
            }
        case .sparkle:
            // Тихий хрустальный перелив — кожа Эдварда на солнце (не путать со школьным звонком).
            return buffer(seconds: 1.6) { _, t in
                let notes: [Float] = [3136, 3951, 4699, 5274, 3520]
                var s: Float = 0
                for (k, f) in notes.enumerated() {
                    let x = t - Float(k) * 0.11
                    if x > 0 { s += sin(x * f * 2 * Float.pi) * exp(-x * 5) * 0.05 }
                }
                return s
            }
        case .whoosh:
            return buffer(seconds: 0.5) { _, t in
                n.lowpass(0.05 + t * 0.3) * 2.5 * sin(t / 0.5 * Float.pi)
            }
        case .chirp:
            return buffer(seconds: 0.3) { _, t in
                sin(t * (3200 - t * 3000) * 2 * Float.pi) * sin(t / 0.3 * Float.pi) * 0.15
            }
        }
    }
}

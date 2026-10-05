import AVFoundation

/// Процедурные звуки: дождь, ветер, гром, визг шин, удары, сердцебиение, сверчки.
/// Всё синтезируется при запуске — аудиофайлы не нужны. Играет поверх музыки.
final class SoundFX {

    static let shared = SoundFX()

    enum Effect: CaseIterable {
        case thunder, thunderNear, skid, impact, batCrack, whiff, heartbeat, chime, whoosh, chirp
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

    private init() {
        // Звуки синтезируются в фоне — запуск игры не задерживается.
        queue.async { [weak self] in self?.build() }
    }

    // MARK: - Публичное

    func play(_ effect: Effect, volume: Float = 1, delay: TimeInterval = 0) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.running, let buffer = self.effectBuffers[effect] else { return }
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
            self?.loops[ambience]?.volume = volume
        }
    }

    /// Выключить все фоновые слои, кроме перечисленных.
    func ambience(_ levels: [Ambience: Float]) {
        queue.async { [weak self] in
            guard let self else { return }
            for (kind, player) in self.loops {
                player.volume = levels[kind] ?? 0
            }
        }
    }

    /// Вернуться из фона — аудиодвижок мог остановиться.
    func resume() {
        queue.async { [weak self] in
            guard let self, !self.engine.isRunning, !self.oneShots.isEmpty else { return }
            try? self.engine.start()
            for player in self.loops.values { player.play() }
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
        var loopBuffers: [Ambience: AVAudioPCMBuffer] = [:]
        for kind in Ambience.allCases {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            p.volume = 0
            loops[kind] = p
            loopBuffers[kind] = makeLoop(kind)
        }
        engine.mainMixerNode.outputVolume = 0.9
        do {
            try engine.start()
        } catch {
            NSLog("SoundFX: аудиодвижок не запустился: \(error)")
            return
        }
        for (kind, p) in loops {
            if let buffer = loopBuffers[kind] {
                p.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
                p.play()
            }
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
                let metal = sin(t * 310 * 2 * Float.pi) * exp(-t * 9) * 0.4 + sin(t * 523 * 2 * Float.pi) * exp(-t * 12) * 0.25
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

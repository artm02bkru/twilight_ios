import AVFoundation
import SwiftUI

/// Фоновая музыка игры: один трек по кругу, с плавным появлением и отключением.
///
/// Если файла нет в сборке — игра просто работает без музыки, без падения.
final class SoundtrackPlayer: ObservableObject {

    static let shared = SoundtrackPlayer()

    /// Выключен ли звук. Настройка запоминается между запусками.
    @Published private(set) var isMuted: Bool

    private var player: AVAudioPlayer?
    private var fadeTimer: Timer?

    private static let resourceName = "EyesOnFire"
    private static let resourceExtension = "mp3"
    private static let muteKey = "twilight.music.muted"
    private static let normalVolume: Float = 0.55

    private init() {
        isMuted = UserDefaults.standard.bool(forKey: Self.muteKey)
        configureAudioSession()
    }

    // MARK: - Управление

    /// Запускает музыку. Вызывать один раз при появлении корневого экрана.
    func start() {
        if let player {
            if !isMuted {
                player.play()
                fade(to: Self.normalVolume, over: 1.6)
            }
            return
        }

        guard let url = trackURL ?? Self.findTrack(),
              let player = try? AVAudioPlayer(contentsOf: url) else {
            // Трека нет в сборке — просто играем без музыки, без падения.
            NSLog("SoundtrackPlayer: \(Self.resourceName).\(Self.resourceExtension) не найден в бандле")
            return
        }

        player.numberOfLoops = -1          // играет по кругу всю партию
        player.volume = 0
        player.prepareToPlay()
        self.player = player
        trackURL = url

        guard !isMuted else { return }
        player.play()
        fade(to: Self.normalVolume, over: 1.8)
    }

    /// Вернуться к игре из фона.
    func resumeIfNeeded() {
        guard let player, !isMuted, !player.isPlaying else { return }
        player.play()
    }

    func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        isMuted = muted
        UserDefaults.standard.set(muted, forKey: Self.muteKey)

        guard let player else { return }
        if muted {
            fade(to: 0, over: 0.45) { [weak self] in
                if self?.isMuted == true { self?.player?.pause() }
            }
        } else {
            player.play()
            fade(to: Self.normalVolume, over: 0.7)
        }
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    /// Приглушить музыку на время (например, на экране итогов) и вернуть обратно.
    func duck(to volume: Float, over duration: TimeInterval) {
        guard !isMuted else { return }
        fade(to: volume, over: duration)
    }

    /// Вернуть обычную громкость после приглушения.
    func unduck() {
        guard !isMuted, player != nil else { return }
        fade(to: Self.normalVolume, over: 0.8)
    }

    // MARK: - Музыка по главам

    private var trackKey = ""
    private var trackURL: URL?

    /// Выбрать музыку для места игры: файл `music_<key>` в папке Audio
    /// (menu, prologue, biology, van, portAngeles, meadow, forest, baseball, chase, studio, prom, wedding, finale).
    /// Если такого файла нет — играет общий трек.
    func select(_ key: String) {
        guard key != trackKey else { return }
        trackKey = key
        let url = SoundFX.audioURL("music_" + key) ?? Self.findTrack()
        guard let url, url != trackURL else { return }
        if player == nil {
            trackURL = url
            return
        }
        switchTo(url)
    }

    private func switchTo(_ url: URL) {
        trackURL = url
        let start = { [weak self] in
            guard let self, self.trackURL == url, let next = try? AVAudioPlayer(contentsOf: url) else { return }
            self.player?.stop()
            next.numberOfLoops = -1
            next.volume = 0
            next.prepareToPlay()
            self.player = next
            guard !self.isMuted else { return }
            next.play()
            self.fade(to: Self.normalVolume, over: 1.4)
        }
        if isMuted { start() } else { fade(to: 0, over: 0.7, completion: start) }
    }

    // MARK: - Внутреннее

    /// Ищет трек: сначала по имени, потом любой mp3/m4a в папке Audio.
    private static func findTrack() -> URL? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: "Audio")
            ?? bundle.url(forResource: resourceName, withExtension: resourceExtension) {
            return url
        }
        if let url = SoundFX.audioURL("music_default") { return url }
        // Любой трек, кроме звуков с приставками (фоны, эффекты, реплики, музыка глав).
        let prefixes = ["amb_", "sfx_", "vo_", "music_"]
        for ext in ["mp3", "m4a", "aac", "wav"] {
            let urls = bundle.urls(forResourcesWithExtension: ext, subdirectory: "Audio") ?? []
            if let url = urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                .first(where: { u in !prefixes.contains { u.lastPathComponent.hasPrefix($0) } }) {
                return url
            }
        }
        return nil
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // .ambient: игра не перебивает чужую музыку и уважает переключатель «без звука».
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func fade(to target: Float, over duration: TimeInterval, completion: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        guard let player else { completion?(); return }

        let steps = max(1, Int(duration * 30))
        let start = player.volume
        let delta = (target - start) / Float(steps)
        var remaining = steps

        fadeTimer = Timer.scheduledTimer(withTimeInterval: duration / Double(steps), repeats: true) { timer in
            remaining -= 1
            player.volume = min(1, max(0, player.volume + delta))
            if remaining <= 0 {
                timer.invalidate()
                player.volume = target
                completion?()
            }
        }
    }
}

/// Круглая кнопка «звук вкл/выкл».
struct MusicToggleButton: View {

    @ObservedObject private var music = SoundtrackPlayer.shared
    var size: CGFloat = 44

    var body: some View {
        Button {
            music.toggleMute()
        } label: {
            Image(systemName: music.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundColor(music.isMuted ? Theme.textDim : Theme.text)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(music.isMuted ? "Включить музыку" : "Выключить музыку")
    }
}

/// Строка «музыка» для меню.
struct MusicToggleRow: View {

    @ObservedObject private var music = SoundtrackPlayer.shared

    var body: some View {
        Button {
            music.toggleMute()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: music.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(music.isMuted ? Theme.textDim : Theme.ice)
                Text(music.isMuted ? "МУЗЫКА ВЫКЛЮЧЕНА" : "МУЗЫКА ВКЛЮЧЕНА")
                    .font(Theme.body(13, weight: .heavy))
                    .tracking(1.5)
                    .foregroundColor(music.isMuted ? Theme.textDim : Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

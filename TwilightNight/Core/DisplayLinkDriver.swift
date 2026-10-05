import UIKit

/// Тикающий «сердечный ритм» игры на базе CADisplayLink.
/// Даёт честный delta-time и не грузит систему выше 60 к/с.
final class DisplayLinkDriver: NSObject, ObservableObject {

    /// Вызывается на главном потоке: (deltaTime в секундах).
    var onTick: ((CGFloat) -> Void)?

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    func start() {
        guard link == nil else { return }
        lastTimestamp = 0
        let displayLink = CADisplayLink(target: self, selector: #selector(handleTick(_:)))
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = 0
    }

    @objc private func handleTick(_ displayLink: CADisplayLink) {
        guard lastTimestamp != 0 else {
            lastTimestamp = displayLink.timestamp
            return
        }
        // Ограничиваем шаг, чтобы после сворачивания игры предметы не телепортировались.
        let delta = min(max(displayLink.timestamp - lastTimestamp, 0), 1.0 / 20.0)
        lastTimestamp = displayLink.timestamp
        onTick?(CGFloat(delta))
    }

    deinit {
        link?.invalidate()
    }
}

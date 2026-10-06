import SceneKit
import UIKit
import simd

/// Основа для площадок-раннеров (Порт-Анджелес, лес, шоссе).
///
/// Декорации собраны из нескольких сегментов, которые «перешагивают» вперёд,
/// когда остаются за камерой, — путь бесконечный, а геометрии немного.
/// Препятствия из игровой логики раскладываются по пулам готовых узлов.
class RunnerStageBase: Stage3D {

    /// Метров мира на единицу горизонтали игры (−1...1).
    let xScale: Float
    let segmentLength: Float
    private var segments: [SCNNode] = []
    private var pools: [Int: [SCNNode]] = [:]
    private var pickups: [SCNNode] = []
    /// Пулы уже созданы — новых узлов во время игры не строим.
    private var isWarm = false
    /// Положение игрока по Z (вперёд — минус).
    var playerZ: Float = 0
    var playerX: Float = 0

    init(xScale: Float, segmentLength: Float) {
        self.xScale = xScale
        self.segmentLength = segmentLength
        super.init()
    }

    // MARK: - Переопределяется

    /// Сегмент декораций от z = 0 до z = −segmentLength.
    func makeSegment(_ index: Int) -> SCNNode { SCNNode() }
    /// Узел препятствия заданного варианта.
    func makeObstacle(_ variant: Int) -> SCNNode { SCNNode() }
    /// Как анимировать препятствие (огни, повороты) каждый кадр.
    func animateObstacle(_ node: SCNNode, variant: Int, relativeZ: Float) {}

    /// Огонёк-бонус.
    func makePickup() -> SCNNode {
        let n = SCNNode()
        let core = SCNNode(SCNSphere(radius: 0.12),
                           Materials.glow(UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1), intensity: 3, doubleSided: false))
        n.addChildNode(core)
        let halo = SCNNode(SCNPlane(width: 1.1, height: 1.1),
                           Materials.glowImage(Textures.softDot, color: UIColor(red: 1, green: 0.75, blue: 0.4, alpha: 1),
                                               intensity: 1.2))
        halo.constraints = [SCNBillboardConstraint()]
        n.addChildNode(halo)
        n.castsShadow = false
        return n
    }

    // MARK: - Сборка

    /// Построить сегменты (вызывать в init наследника после настройки сцены).
    func installSegments(count: Int = 4) {
        for i in 0..<count {
            let seg = makeSegment(i)
            seg.simdPosition = V3(0, 0, -Float(i) * segmentLength)
            scene.rootNode.addChildNode(seg)
            segments.append(seg)
        }
    }

    /// Заранее создать узлы препятствий и огоньков, чтобы во время бега ничего не строилось.
    func prewarm(variants: [Int], count: Int, pickups pickupCount: Int = 8) {
        for v in variants {
            for i in 0..<count { _ = node(variant: v, index: i) }
        }
        for i in 0..<pickupCount { _ = pickup(index: i) }
        hideObstacles()
        isWarm = true
    }

    /// Облегчённая графика для быстрых сцен: без SSAO и размытия в движении,
    /// тени попроще. На скорости разница не видна, а кадры — видны.
    func useRunnerQuality(key: SCNNode) {
        cameraSettings.screenSpaceAmbientOcclusionIntensity = 0
        cameraSettings.motionBlurIntensity = 0
        cameraSettings.wantsDepthOfField = false
        key.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.light?.shadowSampleCount = 4
    }

    /// Камера «как в Subway Surfers»: строго сзади и сверху, по центру трассы,
    /// лишь слегка следует за полосой игрока.
    func runnerCamera(dt: Float, height: Float = 3.6, back: Float = 7.2) {
        let x = playerX * 0.35
        followCamera(eye: V3(x, height, playerZ + back), target: V3(x, 0.9, playerZ - 12),
                     fov: 62, rate: 10, dt: max(dt, 0.016))
    }

    /// Сбросить сегменты к началу пути.
    func resetSegments() {
        for (i, seg) in segments.enumerated() {
            seg.simdPosition = V3(0, 0, -Float(i) * segmentLength)
        }
    }

    /// Переставить сегменты, оставшиеся позади камеры, вперёд.
    func updateTreadmill() {
        let cameraZ = camera.simdPosition.z
        let total = Float(segments.count) * segmentLength
        for seg in segments {
            // Сегмент целиком позади камеры — переносим вперёд.
            while seg.simdPosition.z - segmentLength > cameraZ + 6 {
                seg.simdPosition.z -= total
            }
            // И наоборот — если камера ушла назад (новый заход).
            while seg.simdPosition.z < cameraZ - total + 6 {
                seg.simdPosition.z += total
            }
        }
    }

    // MARK: - Препятствия

    private func node(variant: Int, index: Int) -> SCNNode {
        var list = pools[variant] ?? []
        // Во время игры пул не растёт: если узлов не хватает — повторно используем последний.
        if index >= list.count && isWarm, let last = list.last { return last }
        while list.count <= index {
            let n = makeObstacle(variant)
            n.isHidden = true
            scene.rootNode.addChildNode(n)
            list.append(n)
        }
        pools[variant] = list
        return list[index]
    }

    private func pickup(index: Int) -> SCNNode {
        if index >= pickups.count && isWarm, let last = pickups.last { return last }
        while pickups.count <= index {
            let n = makePickup()
            n.isHidden = true
            scene.rootNode.addChildNode(n)
            pickups.append(n)
        }
        return pickups[index]
    }

    /// Разложить препятствия игры по сцене.
    func layoutObstacles(_ runner: RunnerScene) {
        var used: [Int: Int] = [:]
        var usedPickups = 0
        for o in runner.obstacles {
            let rel = Float(o.at - runner.distance)
            guard rel > -10, rel < Float(RunnerScene.viewAhead) + 5 else { continue }
            let z = -Float(o.at)
            let x = Float(o.x) * xScale
            if o.pickup {
                guard !o.consumed else { continue }
                let n = pickup(index: usedPickups)
                usedPickups += 1
                n.isHidden = false
                n.simdPosition = V3(x, 1.0 + sin(time * 3 + Float(o.at)) * 0.12, z)
            } else {
                let i = used[o.variant] ?? 0
                used[o.variant] = i + 1
                let n = node(variant: o.variant, index: i)
                n.isHidden = false
                n.simdPosition = V3(x, 0, z)
                animateObstacle(n, variant: o.variant, relativeZ: rel)
            }
        }
        for (variant, list) in pools {
            let start = used[variant] ?? 0
            if start < list.count {
                for i in start..<list.count { list[i].isHidden = true }
            }
        }
        if usedPickups < pickups.count {
            for i in usedPickups..<pickups.count { pickups[i].isHidden = true }
        }
    }

    func hideObstacles() {
        for list in pools.values { for n in list { n.isHidden = true } }
        for n in pickups { n.isHidden = true }
    }
}

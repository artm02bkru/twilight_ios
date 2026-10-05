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
            for i in start..<list.count { list[i].isHidden = true }
        }
        for i in usedPickups..<pickups.count { pickups[i].isHidden = true }
    }

    func hideObstacles() {
        for list in pools.values { for n in list { n.isHidden = true } }
        for n in pickups { n.isHidden = true }
    }
}

import SceneKit
import UIKit

/// Готовые PBR-материалы: асфальт, трава, дерево, ткань, краска машин, кожа.
extension Materials {

    /// Общий конструктор PBR-материала.
    static func pbr(_ diffuse: Any,
                    roughness: Any = 0.6,
                    metalness: Any = 0.0,
                    normal: Any? = nil,
                    normalIntensity: CGFloat = 1,
                    tile: Float = 1) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = diffuse
        m.roughness.contents = roughness
        m.metalness.contents = metalness
        if let normal {
            m.normal.contents = normal
            m.normal.intensity = normalIntensity
        }
        if tile != 1 { m.setTiling(tile) }
        return m
    }

    static func asphalt(tile: Float) -> SCNMaterial {
        let m = pbr(Textures.asphalt,
                    roughness: Textures.asphaltRoughness,
                    normal: Textures.asphaltNormal,
                    normalIntensity: 0.6,
                    tile: tile)
        m.metalness.contents = 0.05
        return m
    }

    static func grass(tile: Float) -> SCNMaterial {
        pbr(Textures.grassGround, roughness: 0.92, normal: Textures.groundNormal,
            normalIntensity: 0.8, tile: tile)
    }

    static func dirt(tile: Float) -> SCNMaterial {
        pbr(Textures.dirt, roughness: 0.95, normal: Textures.groundNormal,
            normalIntensity: 1.0, tile: tile)
    }

    static func snow(tile: Float) -> SCNMaterial {
        let m = pbr(Textures.snow, roughness: 0.55, normal: Textures.groundNormal,
                    normalIntensity: 0.5, tile: tile)
        return m
    }

    static func wood(tile: Float, roughness: CGFloat = 0.38) -> SCNMaterial {
        let m = pbr(Textures.woodPlanks, roughness: roughness, normal: Textures.woodNormal,
                    normalIntensity: 0.7, tile: tile)
        m.clearCoat.contents = 0.5
        m.clearCoatRoughness.contents = 0.15
        return m
    }

    static func brick(tile: Float) -> SCNMaterial {
        pbr(Textures.brick, roughness: 0.9, tile: tile)
    }

    static func bark() -> SCNMaterial {
        pbr(Textures.bark, roughness: 0.95)
    }

    /// Ткань одежды.
    static func cloth(_ color: UIColor, roughness: CGFloat = 0.82, sheen: Bool = false) -> SCNMaterial {
        let m = pbr(color, roughness: roughness, normal: Textures.fabricNormal,
                    normalIntensity: 0.55, tile: 6)
        if sheen {
            m.clearCoat.contents = 0.25
            m.clearCoatRoughness.contents = 0.4
        }
        return m
    }

    /// Автомобильная краска с лаком.
    static func carPaint(_ color: UIColor, metallic: CGFloat = 0.45) -> SCNMaterial {
        let m = pbr(color, roughness: 0.28, metalness: metallic)
        m.clearCoat.contents = 1.0
        m.clearCoatRoughness.contents = 0.06
        return m
    }

    static func chrome() -> SCNMaterial {
        pbr(UIColor(white: 0.9, alpha: 1), roughness: 0.08, metalness: 1.0)
    }

    static func rubber() -> SCNMaterial {
        pbr(UIColor(white: 0.06, alpha: 1), roughness: 0.85)
    }

    static func tintedGlass(_ tint: UIColor = UIColor(hex: 0x0E151C)) -> SCNMaterial {
        let m = pbr(tint, roughness: 0.04, metalness: 0.0)
        m.transparency = 0.78
        m.transparencyMode = .dualLayer
        m.clearCoat.contents = 1.0
        return m
    }

    /// Зеркало: металл без шероховатости отражает окружение сцены.
    static func mirror() -> SCNMaterial {
        pbr(UIColor(white: 0.92, alpha: 1), roughness: 0.02, metalness: 1.0)
    }

    /// Светящийся аддитивный материал — лучи, зоны, огоньки.
    static func glow(_ color: UIColor, intensity: CGFloat = 1, doubleSided: Bool = true) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = color
        m.emission.intensity = intensity
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = doubleSided
        return m
    }

    /// Светящийся аддитивный материал с картинкой-маской.
    static func glowImage(_ image: UIImage, color: UIColor, intensity: CGFloat = 1) -> SCNMaterial {
        let m = glow(color, intensity: intensity)
        m.diffuse.contents = image
        m.multiply.contents = color
        m.emission.contents = image
        return m
    }

    /// Ветер для травы и хвои: вершины качаются тем сильнее, чем выше над землёй.
    /// strength — смещение на метр высоты (трава ~0.06, деревья ~0.006).
    static func windModifier(strength: Float) -> String {
        let s = String(format: "%.4f", strength)
        return """
        float windH = max(_geometry.position.y, 0.0);
        float windW = sin(scn_frame.time * 1.6 + _geometry.position.x * 0.31 + _geometry.position.z * 0.23)
                    + 0.5 * sin(scn_frame.time * 2.9 + _geometry.position.x * 0.9);
        _geometry.position.x += windW * windH * \(s);
        _geometry.position.z += windW * windH * \(s) * 0.4;
        """
    }
}

extension SCNMaterial {
    /// Повторить все карты материала плиткой.
    func setTiling(_ tile: Float) {
        let t = SCNMatrix4MakeScale(tile, tile, 1)
        for property in [diffuse, roughness, metalness, normal, emission, ambientOcclusion] {
            property.contentsTransform = t
            property.wrapS = .repeat
            property.wrapT = .repeat
        }
    }
}

extension SCNNode {
    /// Узел с геометрией и одним материалом.
    convenience init(_ geometry: SCNGeometry, _ material: SCNMaterial) {
        self.init(geometry: geometry)
        geometry.materials = [material]
    }

    @discardableResult
    func add(_ child: SCNNode) -> SCNNode {
        addChildNode(child)
        return child
    }

    func at(_ x: Float, _ y: Float, _ z: Float) -> SCNNode {
        simdPosition = V3(x, y, z)
        return self
    }

    /// Включить или выключить отбрасывание теней для всего поддерева.
    func setCastsShadow(_ value: Bool) {
        castsShadow = value
        enumerateChildNodes { node, _ in node.castsShadow = value }
    }
}

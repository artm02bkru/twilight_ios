import SceneKit
import UIKit
import simd

/// Готовое тело персонажа (модель из FBX со скелетом) поверх процедурного скелета `Humanoid`.
///
/// Позы, походки и кат-сцены по-прежнему задаются суставами `Humanoid`; каждый кадр
/// их повороты переносятся на кости модели (ретаргетинг): поворот кости =
/// поворот сустава × (поворот сустава в эталонной T-позе)⁻¹ × поворот кости в T-позе привязки.
/// Кости без пары (ключицы, пальцы, скручивание предплечья) держат позу привязки
/// относительно родителя.
final class AvatarBody {

    /// Корень скелета модели: масштаб подгоняет её рост к внутреннему росту `Humanoid` (1.79).
    let root = SCNNode()
    private var bones: [SCNNode] = []
    private let parents: [Int]
    private let bindWorld: [simd_quatf]
    private let bindLocal: [simd_quatf]
    private let bindPosition: [V3]
    private let fit: Float

    private struct Link {
        let bone: Int
        let joint: SCNNode
        var referenceInverse = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    }
    private var links: [Link] = []
    private var linkOfBone: [Int: Int] = [:]
    private var hipsBone = 0
    private var hipsJoint: SCNNode?
    private var hipsReference = V3.zero
    private var rotations: [simd_quatf] = []

    /// Материалы кожи — для алмазного блеска Эдварда на солнце.
    private(set) var skinMaterials: [SCNMaterial] = []
    private var eyeMaterials: [SCNMaterial] = []
    private var outfitMaterials: [SCNMaterial] = []

    /// Соответствие костей модели (стандартные имена Mixamo/Avaturn) суставам `Humanoid`.
    static let boneMap: [String: String] = [
        "Hips": "hips", "Spine": "spine", "Spine1": "chest", "Neck": "neck", "Head": "head",
        "LeftArm": "shoulderL", "LeftForeArm": "elbowL", "LeftHand": "handL",
        "RightArm": "shoulderR", "RightForeArm": "elbowR", "RightHand": "handR",
        "LeftUpLeg": "hipL", "LeftLeg": "kneeL", "LeftFoot": "ankleL",
        "RightUpLeg": "hipR", "RightLeg": "kneeR", "RightFoot": "ankleR"
    ]

    /// Эталонная поза `Humanoid`, совпадающая с T-позой привязки модели.
    static var referencePose: Pose {
        var p = Pose()
        p.shoulderL = V3(0, 0, Float.pi / 2)
        p.shoulderR = V3(0, 0, -Float.pi / 2)
        p.elbowL = 0
        p.elbowR = 0
        return p
    }

    init?(model: ModelAsset, vampire: Bool) {
        let skeleton = model.skeleton
        guard !skeleton.isEmpty, let part = model.parts["body"],
              let boneIndices = part.boneIndices, let boneWeights = part.boneWeights else { return nil }

        parents = skeleton.map(\.parent)
        bindWorld = skeleton.map(\.bindRotation)
        bindPosition = skeleton.map(\.bindPosition)
        bindLocal = skeleton.indices.map { i in
            let p = skeleton[i].parent
            return p >= 0 ? skeleton[p].bindRotation.inverse * skeleton[i].bindRotation : skeleton[i].bindRotation
        }
        fit = 1.79 / max(1.0, part.boundsMax.y)
        root.name = "avatar"
        root.simdScale = V3(repeating: fit)
        rotations = bindWorld

        // Кости: локальные смещения и повороты позы привязки.
        for (i, b) in skeleton.enumerated() {
            let n = SCNNode()
            n.name = b.name
            let p = b.parent
            if p >= 0 {
                n.simdPosition = skeleton[p].bindRotation.inverse.act(b.bindPosition - skeleton[p].bindPosition)
                n.simdOrientation = bindLocal[i]
                bones[p].addChildNode(n)
            } else {
                n.simdPosition = b.bindPosition
                n.simdOrientation = b.bindRotation
                root.addChildNode(n)
            }
            bones.append(n)
            if b.name == "Hips" { hipsBone = i }
        }

        // Сетка со скиннингом.
        let geometry = (part.geometry.copy() as? SCNGeometry) ?? part.geometry
        var built: [Int: SCNMaterial] = [:]
        var skins: [SCNMaterial] = []
        var eyes: [SCNMaterial] = []
        var outfits: [SCNMaterial] = []
        geometry.materials = part.materialIndices.map { index in
            if let m = built[index] { return m }
            let d = model.materials[index]
            let m = Self.material(d, vampire: vampire)
            if d.name == "AvatarHead" || d.name == "AvatarBody" { skins.append(m) }
            if d.name.hasSuffix("Eyeball") { eyes.append(m) }
            if d.name == "outfit" { outfits.append(m) }
            built[index] = m
            return m
        }
        skinMaterials = skins
        eyeMaterials = eyes
        outfitMaterials = outfits
        let mesh = SCNNode(geometry: geometry)
        mesh.name = "avatar-skin"
        mesh.castsShadow = true
        root.addChildNode(mesh)
        let inverseBind = skeleton.map { b -> NSValue in
            let m = simd_float4x4(translation: b.bindPosition) * simd_float4x4(b.bindRotation)
            return NSValue(scnMatrix4: SCNMatrix4(simd_inverse(m)))
        }
        let skinner = SCNSkinner(baseGeometry: geometry, bones: bones, boneInverseBindTransforms: inverseBind,
                                 boneWeights: boneWeights, boneIndices: boneIndices)
        skinner.skeleton = root
        mesh.skinner = skinner
    }

    /// Запомнить положение суставов в эталонной позе (её уже применили к `Humanoid`).
    func calibrate(owner: SCNNode, joints: [String: SCNNode]) {
        links = []
        linkOfBone = [:]
        for (i, bone) in bones.enumerated() {
            guard let key = bone.name.flatMap({ Self.boneMap[$0] }), let joint = joints[key] else { continue }
            var link = Link(bone: i, joint: joint)
            link.referenceInverse = Self.rotation(of: joint, in: owner).inverse
            linkOfBone[i] = links.count
            links.append(link)
        }
        hipsJoint = joints["hips"]
        if let hipsJoint { hipsReference = owner.simdConvertPosition(.zero, from: hipsJoint) }
    }

    /// Перенести текущую позу суставов на кости модели.
    func sync(owner: SCNNode) {
        for i in bones.indices {
            let p = parents[i]
            let world: simd_quatf
            if let l = linkOfBone[i] {
                let link = links[l]
                world = Self.rotation(of: link.joint, in: owner) * link.referenceInverse * bindWorld[i]
            } else {
                world = p >= 0 ? rotations[p] * bindLocal[i] : bindWorld[i]
            }
            rotations[i] = world
            bones[i].simdOrientation = p >= 0 ? (rotations[p].inverse * world).normalized : world
        }
        if let hipsJoint {
            let now = owner.simdConvertPosition(.zero, from: hipsJoint)
            bones[hipsBone].simdPosition = bindPosition[hipsBone] + (now - hipsReference) / fit
        }
    }

    private static func rotation(of joint: SCNNode, in owner: SCNNode) -> simd_quatf {
        let m = owner.simdConvertTransform(matrix_identity_float4x4, from: joint)
        let r = simd_float3x3(simd_normalize(V3(m.columns.0.x, m.columns.0.y, m.columns.0.z)),
                              simd_normalize(V3(m.columns.1.x, m.columns.1.y, m.columns.1.z)),
                              simd_normalize(V3(m.columns.2.x, m.columns.2.y, m.columns.2.z)))
        return simd_quatf(r)
    }

    // MARK: - Внешность

    /// Цвет радужки (топаз, чёрный голод, алый) и её свечение.
    func setEyes(_ color: UIColor, glow: CGFloat) {
        let c = color.rgba4
        let tint = NSValue(scnVector3: SCNVector3(c.x, c.y, c.z))
        for m in eyeMaterials {
            m.setValue(tint, forKey: "irisTint")
            m.setValue(NSNumber(value: Float(glow)), forKey: "irisGlow")
        }
    }

    /// Перекрасить одежду модели (нарядная рубашка, тёмный костюм). nil — исходные цвета.
    func tintOutfit(_ color: UIColor?) {
        for m in outfitMaterials {
            m.multiply.contents = color ?? UIColor.white
            m.roughness.contents = color == nil ? 0.88 : 0.7
        }
    }

    /// Алмазный блеск кожи на солнце (0...1).
    func setSparkle(_ value: Float) {
        for m in skinMaterials {
            m.emission.intensity = CGFloat(value * 3.5)
        }
    }

    private static func material(_ d: ModelAsset.Material, vampire: Bool) -> SCNMaterial {
        let m = ModelAsset.defaultMaterial(d)
        // В FBX у всех материалов металличность 1.0 — кожа и ткань блестели как хром.
        m.metalness.contents = 0.0
        m.roughness.contents = 0.6
        switch d.name {
        case "AvatarHead", "AvatarBody":
            m.roughness.contents = vampire ? 0.5 : 0.58
            m.normal.intensity = 0.6
            if vampire {
                // Бледнее и холоднее, искры в эмиссии погашены до выхода на солнце.
                m.multiply.contents = UIColor(red: 0.97, green: 0.97, blue: 1.0, alpha: 1)
                m.emission.contents = Textures.sparkle
                m.emission.intensity = 0
                m.emission.contentsTransform = SCNMatrix4MakeScale(18, 18, 1)
                m.emission.wrapS = .repeat
                m.emission.wrapT = .repeat
                m.clearCoat.contents = 0.08
                m.clearCoatRoughness.contents = 0.4
            }
            let rim = vampire ? "float3(0.55, 0.62, 0.75)" : "float3(0.75, 0.28, 0.18)"
            m.shaderModifiers = [.surface: """
            float skinRim = 1.0 - max(dot(_surface.normal, _surface.view), 0.0);
            _surface.emission.rgb += \(rim) * pow(skinRim, 3.0) * 0.06;
            """]
        case "AvatarLeftEyeball", "AvatarRightEyeball":
            m.roughness.contents = 0.15
            m.clearCoat.contents = 0.5
            // Радужка темнее белка: по яркости находим её и перекрашиваем.
            m.shaderModifiers = [.surface: """
            #pragma arguments
            float3 irisTint;
            float irisGlow;
            #pragma body
            float lum = dot(_surface.diffuse.rgb, float3(0.3, 0.59, 0.11));
            float irisMask = smoothstep(0.5, 0.3, lum) * step(0.0001, dot(irisTint, float3(1.0)));
            _surface.diffuse.rgb = mix(_surface.diffuse.rgb, irisTint * (0.35 + lum * 1.6), irisMask * 0.85);
            _surface.emission.rgb += irisTint * irisMask * irisGlow;
            """]
            m.setValue(NSValue(scnVector3: SCNVector3(0, 0, 0)), forKey: "irisTint")
            m.setValue(NSNumber(value: Float(0)), forKey: "irisGlow")
        case "haircut":
            m.roughness.contents = 0.62
            m.normal.intensity = 0.6
            ModelAsset.makeCutout(m)
        case "AvatarEyelashes":
            m.diffuse.contents = UIColor(white: 0.04, alpha: 1)
            m.roughness.contents = 0.6
        case "outfit":
            m.roughness.contents = 0.88
        case "AvatarTeethUpper", "AvatarTeethLower":
            m.roughness.contents = 0.45
        default:
            break
        }
        return m
    }
}

private extension simd_float4x4 {
    init(translation t: V3) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(t.x, t.y, t.z, 1)
    }
}

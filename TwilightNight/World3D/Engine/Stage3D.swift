import SceneKit
import UIKit
import simd

/// Общая основа 3D-площадки: сцена, кинокамера, небо, свет и туман.
///
/// Площадка живёт в трёх режимах:
/// * кат-сцена — `beginShot` / `updateShot` по меткам из сценария;
/// * игра — `enterGameplay` / `updateGameplay`, состояние берётся из `GameEngine`;
/// * фон — `enterIdle` / `updateIdle` для меню, карточек и экранов итогов.
class Stage3D {

    let scene = SCNScene()
    let camera = SCNNode()

    /// Собственные часы площадки (идут и в паузе — для ветра, дождя, дыхания).
    var time: Float = 0

    // Состояние камеры: куда стоит и куда смотрит.
    private(set) var eye = V3(0, 2, 10)
    private(set) var target = V3(0, 1, 0)
    private(set) var fov: Float = 60
    /// 0...1 — тряска (удар, гром, потеря контроля).
    var shake: Float = 0
    /// Лёгкое «дыхание» ручной камеры в кат-сценах.
    private var handheld: Float = 0

    // MARK: - Сборка

    init() {
        let cam = SCNCamera()
        cam.zNear = 0.05
        cam.zFar = 2500
        cam.projectionDirection = .horizontal
        cam.fieldOfView = 60
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = 0
        cam.minimumExposure = -4
        cam.maximumExposure = 4
        cam.bloomIntensity = 0.6
        cam.bloomThreshold = 0.9
        cam.bloomBlurRadius = 14
        cam.vignettingIntensity = 0.6
        cam.vignettingPower = 0.85
        cam.colorFringeStrength = 0.5
        cam.colorFringeIntensity = 0.3
        cam.saturation = 0.95
        cam.contrast = 0.1
        cam.screenSpaceAmbientOcclusionIntensity = 0.85
        cam.screenSpaceAmbientOcclusionRadius = 0.3
        cam.screenSpaceAmbientOcclusionBias = 0.03
        cam.screenSpaceAmbientOcclusionDepthThreshold = 0.2
        cam.grainIntensity = 0.05
        cam.grainScale = 1
        cam.focalBlurSampleCount = 8
        cam.fStop = 2.8
        cam.apertureBladeCount = 6
        cam.wantsDepthOfField = false
        camera.camera = cam
        camera.name = "camera"
        scene.rootNode.addChildNode(camera)
    }

    var cameraSettings: SCNCamera { camera.camera! }

    // MARK: - Атмосфера

    /// Небо-панорама: и фон, и отражения в мокром асфальте, лаке и глазах.
    func setSky(_ style: Textures.SkyStyle, lighting: CGFloat = 1.0) {
        let image = Textures.sky(style)
        scene.background.contents = image
        scene.lightingEnvironment.contents = image
        scene.lightingEnvironment.intensity = lighting
    }

    func setFog(color: UIColor, start: CGFloat, end: CGFloat, exponent: CGFloat = 1.4) {
        scene.fogColor = color
        scene.fogStartDistance = start
        scene.fogEndDistance = end
        scene.fogDensityExponent = exponent
    }

    /// Основной направленный свет с мягкими тенями.
    @discardableResult
    func addKeyLight(color: UIColor, intensity: CGFloat, azimuth: Float, elevation: Float,
                     shadowExtent: CGFloat = 40, softness: CGFloat = 6) -> SCNNode {
        let light = SCNLight()
        light.type = .directional
        light.color = color
        light.intensity = intensity
        light.castsShadow = true
        light.shadowMode = .deferred
        light.shadowSampleCount = 16
        light.shadowRadius = softness
        light.shadowMapSize = CGSize(width: 2048, height: 2048)
        light.shadowColor = UIColor(white: 0, alpha: 0.75)
        light.automaticallyAdjustsShadowProjection = false
        light.orthographicScale = shadowExtent
        light.zNear = 1
        light.zFar = 400
        light.shadowBias = 0.04
        let node = SCNNode()
        node.light = light
        let dir = V3(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))
        node.simdPosition = dir * 120
        node.simdLook(at: V3(0, 0, 0))
        scene.rootNode.addChildNode(node)
        return node
    }

    @discardableResult
    func addAmbient(color: UIColor, intensity: CGFloat) -> SCNNode {
        let light = SCNLight()
        light.type = .ambient
        light.color = color
        light.intensity = intensity
        let node = SCNNode()
        node.light = light
        scene.rootNode.addChildNode(node)
        return node
    }

    /// Точечный свет (фонарь, лампа, огонёк) без теней.
    @discardableResult
    func addOmni(at p: V3, color: UIColor, intensity: CGFloat, range: CGFloat,
                 parent: SCNNode? = nil) -> SCNNode {
        let light = SCNLight()
        light.type = .omni
        light.color = color
        light.intensity = intensity
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = range
        light.attenuationFalloffExponent = 2
        let node = SCNNode()
        node.light = light
        node.simdPosition = p
        (parent ?? scene.rootNode).addChildNode(node)
        return node
    }

    /// Прожектор: светит по −Z узла.
    static func spotLight(color: UIColor, intensity: CGFloat, angle: CGFloat,
                          range: CGFloat, shadows: Bool = false) -> SCNNode {
        let light = SCNLight()
        light.type = .spot
        light.color = color
        light.intensity = intensity
        light.spotInnerAngle = angle * 0.5
        light.spotOuterAngle = angle
        light.attenuationStartDistance = 0
        light.attenuationEndDistance = range
        light.attenuationFalloffExponent = 2
        light.castsShadow = shadows
        if shadows {
            light.shadowMode = .deferred
            light.shadowSampleCount = 8
            light.shadowRadius = 4
            light.shadowMapSize = CGSize(width: 1024, height: 1024)
        }
        let node = SCNNode()
        node.light = light
        return node
    }

    // MARK: - Камера

    /// Поставить камеру сразу (для кат-сцен, где путь задан явно).
    func placeCamera(eye: V3, target: V3, fov: Float? = nil) {
        self.eye = eye
        self.target = target
        if let fov { self.fov = fov }
    }

    /// Плавно вести камеру к цели (для игры).
    func followCamera(eye: V3, target: V3, fov: Float? = nil, rate: Float, dt: Float) {
        self.eye = dampv(self.eye, eye, rate, dt)
        self.target = dampv(self.target, target, rate, dt)
        if let fov { self.fov = damp(self.fov, fov, rate, dt) }
    }

    /// Проезд камеры: позиция и взгляд интерполируются с плавным разгоном.
    func dolly(_ p: Float, eye: (V3, V3), look: (V3, V3), fov: (Float, Float) = (55, 55)) {
        let t = easeSoft(p)
        placeCamera(eye: mixv(eye.0, eye.1, t),
                    target: mixv(look.0, look.1, t),
                    fov: lerpf(fov.0, fov.1, t))
    }

    /// Кинорежим: глубина резкости по цели.
    func setCinematic(_ on: Bool, fStop: CGFloat = 2.2) {
        cameraSettings.wantsDepthOfField = on
        cameraSettings.fStop = fStop
        handheld = on ? 1 : 0
    }

    /// Записать состояние камеры в узел. Вызывается директором в конце кадра.
    func commitCamera(dt: Float) {
        shake = max(0, shake - dt * 2.2)
        var e = eye
        if shake > 0.001 {
            let a = shake * shake * 0.12
            e += V3(sin(time * 61) * a, sin(time * 47 + 1.3) * a, sin(time * 53 + 2.1) * a * 0.5)
        }
        // Оператор с камерой на плече: медленный дрейф в пару сантиметров.
        var t = target
        if handheld > 0 {
            let d = simd_length(target - eye)
            e += V3(sin(time * 0.71) * 0.012, sin(time * 0.53 + 0.8) * 0.009, 0) * handheld
            t += V3(sin(time * 0.43 + 2.1), sin(time * 0.61 + 0.3), 0) * (0.0025 * d * handheld)
        }
        camera.simdPosition = e
        camera.simdLook(at: t)
        cameraSettings.fieldOfView = CGFloat(fov)
        cameraSettings.focusDistance = CGFloat(simd_length(target - eye))
    }

    // MARK: - Переопределяется площадками

    /// Фоновые звуки площадки и их громкость.
    var ambience: [SoundFX.Ambience: Float] { [:] }

    func beginShot(_ cue: Cue) {}
    func updateShot(_ cue: Cue, progress: Float, dt: Float) {}

    func enterGameplay() {}
    func updateGameplay(_ engine: GameEngine, dt: Float) {}

    func enterIdle() { enterGameplay() }
    func updateIdle(dt: Float) {
        // По умолчанию — медленный облёт текущей точки.
        let a = time * 0.05
        placeCamera(eye: target + rotateY(V3(0, 2.5, 9), a), target: target)
    }

    /// Каждый кадр, в любом режиме: погода, дыхание персонажей, огоньки.
    func updateAmbient(dt: Float) {}
}

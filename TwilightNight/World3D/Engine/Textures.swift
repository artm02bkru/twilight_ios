import UIKit
import simd

// MARK: - Бесшовный шум для текстур

/// Value-noise, который повторяется с заданным периодом, — текстуры кладутся плиткой без швов.
struct TileNoise {
    let seed: Int

    private func hash(_ xi: Int, _ yi: Int) -> Float {
        var h = UInt64(truncatingIfNeeded: xi) &* 0x9E37_79B9_7F4A_7C15
        h ^= UInt64(truncatingIfNeeded: yi) &* 0xBF58_476D_1CE4_E5B9
        h ^= UInt64(truncatingIfNeeded: seed) &* 0x94D0_49BB_1331_11EB
        h ^= h >> 29
        h = h &* 0xBF58_476D_1CE4_E5B9
        h ^= h >> 32
        return Float(h & 0xFFFF_FF) / Float(0xFFFF_FF)
    }

    /// Случайное число для целочисленной клетки — для крапинок и звёзд.
    func cell(_ x: Int, _ y: Int) -> Float { hash(x, y) }

    func value(_ x: Float, _ y: Float, period: Int) -> Float {
        let fx = floor(x), fy = floor(y)
        let p = max(1, period)
        let xi = ((Int(fx) % p) + p) % p
        let yi = ((Int(fy) % p) + p) % p
        let xj = (xi + 1) % p
        let yj = (yi + 1) % p
        let xf = x - fx, yf = y - fy
        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)
        let a = hash(xi, yi), b = hash(xj, yi)
        let c = hash(xi, yj), d = hash(xj, yj)
        return (a + (b - a) * u) * (1 - v) + (c + (d - c) * u) * v
    }

    /// u, v — 0...1 по картинке. basePeriod — сколько «клеток» шума на всю текстуру.
    func fbm(_ u: Float, _ v: Float, basePeriod: Int, octaves: Int = 4) -> Float {
        var sum: Float = 0, amp: Float = 1, norm: Float = 0
        var period = basePeriod
        for _ in 0..<octaves {
            sum += value(u * Float(period), v * Float(period), period: period) * amp
            norm += amp
            amp *= 0.5
            period *= 2
        }
        return sum / norm
    }
}

// MARK: - Процедурные текстуры

/// Все текстуры рисуются кодом при первом обращении и кешируются.
/// Никаких файлов-картинок проекту не нужно.
enum Textures {

    // MARK: Генератор картинок

    /// RGBA-картинка из функции пикселя (компоненты 0...1).
    static func image(width: Int, height: Int, _ pixel: (Int, Int) -> SIMD4<Float>) -> UIImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let p = pixel(x, y)
                let a = clampf(p.w, 0, 1)
                let i = (y * width + x) * 4
                // Альфа предумножена — так требует CoreGraphics.
                data[i]     = UInt8(clampf(p.x, 0, 1) * a * 255)
                data[i + 1] = UInt8(clampf(p.y, 0, 1) * a * 255)
                data[i + 2] = UInt8(clampf(p.z, 0, 1) * a * 255)
                data[i + 3] = UInt8(a * 255)
            }
        }
        let provider = CGDataProvider(data: Data(data) as CFData)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider,
              let cg = CGImage(width: width, height: height,
                               bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: info,
                               provider: provider,
                               decode: nil,
                               shouldInterpolate: true,
                               intent: .defaultIntent) else {
            return UIImage()
        }
        return UIImage(cgImage: cg)
    }

    /// Карта нормалей из поля высот (высоты 0...1, бесшовные).
    static func normalMap(size: Int, strength: Float, height: (Int, Int) -> Float) -> UIImage {
        var h = [Float](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                h[y * size + x] = height(x, y)
            }
        }
        func at(_ x: Int, _ y: Int) -> Float {
            h[((y + size) % size) * size + ((x + size) % size)]
        }
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let dx = (at(x + 1, y) - at(x - 1, y)) * strength
            let dy = (at(x, y + 1) - at(x, y - 1)) * strength
            let n = simd_normalize(SIMD3<Float>(-dx, -dy, 1))
            return SIMD4(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1)
        }
    }

    private static func rgb(_ hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
    }

    // MARK: Асфальт

    static let asphalt: UIImage = {
        let n = TileNoise(seed: 11)
        let size = 256
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let u = Float(x) / Float(size), v = Float(y) / Float(size)
            let large = n.fbm(u, v, basePeriod: 4, octaves: 4)
            let grain = n.cell(x, y)
            var c = SIMD3<Float>(repeating: 0.16 + large * 0.10)
            c += SIMD3(repeating: (grain - 0.5) * 0.08)
            // Редкие светлые камешки в смеси.
            if grain > 0.965 { c += SIMD3(repeating: 0.12) }
            c *= SIMD3(1.0, 1.0, 1.04)
            return SIMD4(c, 1)
        }
    }()

    /// Шероховатость: лужи и наледь почти зеркальные.
    static let asphaltRoughness: UIImage = {
        let n = TileNoise(seed: 12)
        let size = 256
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let u = Float(x) / Float(size), v = Float(y) / Float(size)
            let f = n.fbm(u, v, basePeriod: 3, octaves: 4)
            let wet = smoothstepf(0.48, 0.62, f)
            let r = lerpf(0.72, 0.06, wet)
            return SIMD4(r, r, r, 1)
        }
    }()

    static let asphaltNormal: UIImage = {
        let n = TileNoise(seed: 13)
        let size = 256
        return normalMap(size: size, strength: 2.2) { (x: Int, y: Int) -> Float in
            n.cell(x, y) * 0.35 + n.fbm(Float(x) / Float(size), Float(y) / Float(size), basePeriod: 16, octaves: 3)
        }
    }()

    // MARK: Земля и трава

    static let grassGround: UIImage = {
        let n = TileNoise(seed: 21)
        let size = 256
        let dark = rgb(0x2B4220), light = rgb(0x4F6B2F), dry = rgb(0x6B6A3A)
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let u = Float(x) / Float(size), v = Float(y) / Float(size)
            let a = n.fbm(u, v, basePeriod: 4, octaves: 4)
            let b = n.fbm(u + 0.37, v + 0.11, basePeriod: 8, octaves: 3)
            var c = simd_mix(dark, light, SIMD3(repeating: a))
            c = simd_mix(c, dry, SIMD3(repeating: smoothstepf(0.55, 0.8, b) * 0.6))
            c *= 0.85 + n.cell(x, y) * 0.3
            return SIMD4(c, 1)
        }
    }()

    static let dirt: UIImage = {
        let n = TileNoise(seed: 31)
        let size = 256
        let base = rgb(0x6A4B32), wet = rgb(0x3F2B1E)
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let u = Float(x) / Float(size), v = Float(y) / Float(size)
            let a = n.fbm(u, v, basePeriod: 4, octaves: 5)
            var c = simd_mix(wet, base, SIMD3(repeating: a))
            c *= 0.82 + n.cell(x, y) * 0.36
            return SIMD4(c, 1)
        }
    }()

    static let groundNormal: UIImage = {
        let n = TileNoise(seed: 32)
        let size = 256
        return normalMap(size: size, strength: 3.0) { (x: Int, y: Int) -> Float in
            n.fbm(Float(x) / Float(size), Float(y) / Float(size), basePeriod: 12, octaves: 4) + n.cell(x, y) * 0.15
        }
    }()

    static let snow: UIImage = {
        let n = TileNoise(seed: 41)
        let size = 256
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let u = Float(x) / Float(size), v = Float(y) / Float(size)
            let a = n.fbm(u, v, basePeriod: 6, octaves: 4)
            let c = SIMD3<Float>(0.86, 0.89, 0.94) * (0.88 + a * 0.14)
            return SIMD4(c, 1)
        }
    }()

    // MARK: Дерево

    /// Паркет из досок: оттенок каждой доски свой, волокна, тёмные стыки.
    static let woodPlanks: UIImage = {
        let n = TileNoise(seed: 51)
        let size = 512
        let rows = 8
        let plankH = size / rows
        let light = rgb(0x9C6B3F), dark = rgb(0x5B3A20)
        let plankLen: Int = size / 2
        let fsize: Float = Float(size)
        let grainFreq: Float = Float(rows) * 9
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let row: Int = y / plankH
            let inRow: Int = y % plankH
            // Стыки досок вразбежку.
            let offset: Int = Int(n.cell(row, 7) * fsize)
            let along: Int = (x + offset) % size
            let plank: Int = (x + offset) / plankLen
            let tint: Float = n.cell(row, plank + 31)
            let u: Float = Float(along) / fsize
            let v: Float = Float(y) / fsize
            let warp: Float = n.fbm(u, v, basePeriod: 4, octaves: 3)
            let phase: Float = (v * grainFreq + warp * 6) * 2 * Float.pi
            let grain: Float = 0.5 + 0.5 * sin(phase)
            let mixAmount: Float = 0.35 + tint * 0.5
            var c: SIMD3<Float> = simd_mix(dark, light, SIMD3<Float>(repeating: mixAmount))
            let shade: Float = 0.86 + grain * 0.18
            c *= shade
            if inRow < 2 || along % plankLen < 2 { c *= Float(0.35) }
            return SIMD4<Float>(c, 1)
        }
    }()

    static let woodNormal: UIImage = {
        let size = 512
        let rows = 8
        let plankH = size / rows
        let n = TileNoise(seed: 52)
        return normalMap(size: size, strength: 1.6) { (x: Int, y: Int) -> Float in
            let inRow = y % plankH
            let groove: Float = inRow < 2 ? 0 : 1
            return groove * 0.6 + n.fbm(Float(x) / Float(size), Float(y) / Float(size), basePeriod: 32, octaves: 2) * 0.1
        }
    }()

    static let bark: UIImage = {
        let n = TileNoise(seed: 53)
        let size = 128
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let u = Float(x) / Float(size), v = Float(y) / Float(size)
            let a = n.fbm(u * 1, v * 0.25, basePeriod: 8, octaves: 4)
            let c = rgb(0x3B2A1F) * (0.6 + a * 0.7)
            return SIMD4(c, 1)
        }
    }()

    // MARK: Кирпич

    static let brick: UIImage = {
        let n = TileNoise(seed: 61)
        let size = 256
        let bw = 64, bh = 24
        let base = rgb(0x7A3B2A), mortar = rgb(0x8E877C)
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let row = y / bh
            let shift = row % 2 == 0 ? 0 : bw / 2
            let bx = (x + shift) % bw
            let by = y % bh
            if bx < 3 || by < 3 {
                let k: Float = 0.8 + n.cell(x, y) * 0.2
                return SIMD4<Float>(mortar * k, 1)
            }
            let id: Float = n.cell((x + shift) / bw, row)
            let u: Float = Float(x) / Float(size)
            let v: Float = Float(y) / Float(size)
            let tint: Float = 0.75 + id * 0.4
            let grain: Float = 0.85 + n.fbm(u, v, basePeriod: 16, octaves: 2) * 0.3
            let c: SIMD3<Float> = base * (tint * grain)
            return SIMD4<Float>(c, 1)
        }
    }()

    // MARK: Ткань

    /// Переплетение нитей — даёт одежде фактуру при боковом свете.
    static let fabricNormal: UIImage = {
        let size = 128
        let n = TileNoise(seed: 71)
        return normalMap(size: size, strength: 1.2) { (x: Int, y: Int) -> Float in
            let k: Float = Float.pi * 64 / Float(size)
            let wx: Float = sin(Float(x) * k)
            let wy: Float = sin(Float(y) * k)
            return (wx * wy) * 0.25 + 0.5 + n.cell(x, y) * 0.08
        }
    }()

    /// Поры и лёгкая неровность кожи.
    static let skinNormal: UIImage = {
        let size = 128
        let n = TileNoise(seed: 72)
        return normalMap(size: size, strength: 0.9) { (x: Int, y: Int) -> Float in
            n.fbm(Float(x) / Float(size), Float(y) / Float(size), basePeriod: 16, octaves: 3) * 0.6 + n.cell(x, y) * 0.1
        }
    }()

    /// Волосы: тонкие пряди вдоль одной оси.
    static let hairStrands: UIImage = {
        let size = 128
        let n = TileNoise(seed: 73)
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let streak = n.value(Float(x) * 0.5, Float(y) * 0.02, period: 64)
            let v = 0.55 + streak * 0.6
            return SIMD4(v, v, v, 1)
        }
    }()

    // MARK: Вампирская кожа

    /// Россыпь искр: эмиссия кожи на солнце. Чёрное — не светится.
    static let sparkle: UIImage = {
        let n = TileNoise(seed: 81)
        let size = 256
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let r = n.cell(x, y)
            if r > 0.992 {
                return SIMD4(1, 1, 1, 1)
            } else if r > 0.975 {
                let k = (r - 0.975) / 0.017
                return SIMD4(0.7 * k, 0.85 * k, 1.0 * k, 1)
            }
            return SIMD4(0, 0, 0, 1)
        }
    }()

    // MARK: Частицы

    /// Мягкая круглая точка — снег, туман, пыль, огоньки.
    static let softDot: UIImage = {
        let size = 64
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let dx = (Float(x) + 0.5) / Float(size) * 2 - 1
            let dy = (Float(y) + 0.5) / Float(size) * 2 - 1
            let d = min(1, sqrt(dx * dx + dy * dy))
            let a: Float = pow(1 - d, Float(2.2))
            return SIMD4(1, 1, 1, a)
        }
    }()

    /// Четырёхлучевая искра — блеск алмазной кожи.
    static let star: UIImage = {
        let size = 64
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let fs: Float = Float(size)
            let dx: Float = abs((Float(x) + 0.5) / fs * 2 - 1)
            let dy: Float = abs((Float(y) + 0.5) / fs * 2 - 1)
            let radius: Float = (dx * dx + dy * dy).squareRoot()
            let core: Float = max(0, 1 - radius * 3)
            let rayH: Float = max(0, 1 - dx * 14) * max(0, 1 - dy)
            let rayV: Float = max(0, 1 - dy * 14) * max(0, 1 - dx)
            let a: Float = min(1, core + (rayH + rayV) * 0.9)
            return SIMD4<Float>(1, 1, 1, a)
        }
    }()

    /// Широкий мягкий клуб — туман и пар.
    static let smoke: UIImage = {
        let size = 64
        let n = TileNoise(seed: 91)
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let u = (Float(x) + 0.5) / Float(size), v = (Float(y) + 0.5) / Float(size)
            let dx = u * 2 - 1, dy = v * 2 - 1
            let d = min(1, sqrt(dx * dx + dy * dy))
            let noise: Float = n.fbm(u, v, basePeriod: 4, octaves: 3)
            let a: Float = pow(1 - d, Float(1.6)) * (0.6 + noise * 0.6)
            return SIMD4(1, 1, 1, a)
        }
    }()

    // MARK: Шины и номера

    /// Протектор шины: поперечные канавки и продольные рёбра.
    static let tireTread: UIImage = {
        let size = 128
        return normalMap(size: size, strength: 2.5) { (x: Int, y: Int) -> Float in
            let fx: Float = Float(x) / Float(size)
            let fy: Float = Float(y) / Float(size)
            let block: Float = sin(fx * Float.pi * 2 * 12) > 0.2 ? 1 : 0
            let rib: Float = abs(fy - 0.5) < 0.04 ? 0 : 1
            return block * rib
        }
    }()

    /// Номерной знак с надписью.
    static func plate(_ text: String) -> UIImage {
        let size = CGSize(width: 256, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.93, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 0.1, green: 0.2, blue: 0.5, alpha: 1).setStroke()
            let border = UIBezierPath(roundedRect: CGRect(x: 6, y: 6, width: size.width - 12, height: size.height - 12),
                                      cornerRadius: 10)
            border.lineWidth = 6
            border.stroke()
            let header = NSAttributedString(string: "WASHINGTON", attributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor(red: 0.1, green: 0.2, blue: 0.5, alpha: 1)
            ])
            header.draw(at: CGPoint(x: (size.width - header.size().width) / 2, y: 12))
            let main = NSAttributedString(string: text, attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 52, weight: .heavy),
                .foregroundColor: UIColor(white: 0.08, alpha: 1)
            ])
            main.draw(at: CGPoint(x: (size.width - main.size().width) / 2, y: 40))
        }
    }

    // MARK: Окна

    /// Сетка окон: часть горит тёплым светом. Для эмиссии фасадов.
    static let windowsLit: UIImage = {
        let n = TileNoise(seed: 101)
        let size = 256
        let cols = 4, rows = 2
        let cw = size / cols, ch = size / rows
        return image(width: size, height: size) { (x: Int, y: Int) -> SIMD4<Float> in
            let cx = x / cw, cy = y / ch
            let lx = x % cw, ly = y % ch
            let inside = lx > cw / 6 && lx < cw * 5 / 6 && ly > ch / 5 && ly < ch * 4 / 5
            guard inside else { return SIMD4(0, 0, 0, 1) }
            let lit = n.cell(cx, cy + 9) > 0.35
            if !lit { return SIMD4(0.02, 0.025, 0.03, 1) }
            let k: Float = 0.7 + n.cell(cx, cy) * 0.3
            let warm: SIMD3<Float> = SIMD3<Float>(1.0, 0.78, 0.48) * k
            // Переплёт рамы.
            if abs(lx - cw / 2) < 2 { return SIMD4(0.05, 0.04, 0.03, 1) }
            return SIMD4(warm, 1)
        }
    }()

    // MARK: Небо

    struct SkyStyle {
        var zenith: SIMD3<Float>
        var horizon: SIMD3<Float>
        var ground: SIMD3<Float>
        /// 0 — ясно, 1 — сплошная облачность.
        var cloudCover: Float = 0.5
        var cloudLight: SIMD3<Float> = SIMD3(0.6, 0.62, 0.66)
        var cloudDark: SIMD3<Float> = SIMD3(0.18, 0.2, 0.24)
        /// Направление на солнце или луну: азимут и высота в радианах.
        var sunAzimuth: Float = 0.6
        var sunElevation: Float = 0.3
        var sunColor: SIMD3<Float> = SIMD3(1, 0.9, 0.75)
        var sunGlow: Float = 0.6
        var sunDisc: Bool = true
        var stars: Bool = false
        var seed: Int = 5
    }

    /// Равнопромежуточная панорама 2:1 — и фон, и источник отражений для PBR.
    static func sky(_ style: SkyStyle, width: Int = 512) -> UIImage {
        let height = width / 2
        let n = TileNoise(seed: style.seed)
        let sunDir = SIMD3<Float>(
            cos(style.sunElevation) * sin(style.sunAzimuth),
            sin(style.sunElevation),
            cos(style.sunElevation) * cos(style.sunAzimuth)
        )
        let fw: Float = Float(width), fh: Float = Float(height)
        let halfPi: Float = Float.pi / 2
        return image(width: width, height: height) { (x: Int, y: Int) -> SIMD4<Float> in
            let u: Float = (Float(x) + 0.5) / fw
            let v: Float = (Float(y) + 0.5) / fh
            let az: Float = u * 2 * Float.pi - Float.pi
            let el: Float = (0.5 - v) * Float.pi
            let cosEl: Float = cos(el)
            let dir = SIMD3<Float>(cosEl * sin(az), sin(el), cosEl * cos(az))

            var c: SIMD3<Float>
            if el >= 0 {
                let up: Float = min(1, el / halfPi)
                let t: Float = pow(up, Float(0.45))
                c = simd_mix(style.horizon, style.zenith, SIMD3<Float>(repeating: t))
            } else {
                let t: Float = min(1, -el / 0.35)
                let below: SIMD3<Float> = style.horizon * Float(0.8)
                c = simd_mix(below, style.ground, SIMD3<Float>(repeating: t))
            }

            // Сияние вокруг солнца.
            let sd: Float = max(0, simd_dot(dir, sunDir))
            let glowWide: Float = pow(sd, Float(8)) * style.sunGlow
            let glowCore: Float = pow(sd, Float(64)) * style.sunGlow * 1.5
            c += style.sunColor * (glowWide + glowCore)
            if style.sunDisc && sd > 0.9992 { c = style.sunColor * Float(4) }

            // Облака — только над горизонтом, у горизонта сплющены.
            if el > -0.02 {
                let sinEl: Float = sin(max(Float(0.02), el))
                let squash: Float = 1 / max(Float(0.12), sinEl + 0.15)
                let cu: Float = u
                let cv: Float = min(0.999, v * 0.6 + squash * 0.02)
                let f: Float = n.fbm(cu, cv, basePeriod: 6, octaves: 5)
                let threshold: Float = 1 - style.cloudCover
                let density: Float = smoothstepf(threshold - 0.1, threshold + 0.25, f)
                if density > 0 {
                    let shade: Float = n.fbm(cu + 0.13, cv + 0.07, basePeriod: 12, octaves: 3)
                    var cloud: SIMD3<Float> = simd_mix(style.cloudDark, style.cloudLight, SIMD3<Float>(repeating: shade))
                    let rim: Float = pow(sd, Float(6)) * 0.5
                    cloud += style.sunColor * rim
                    let fade: Float = min(1, (el + 0.02) / 0.1)
                    c = simd_mix(c, cloud, SIMD3<Float>(repeating: density * fade))
                }
            }

            if style.stars && el > 0.1 {
                let r: Float = n.cell(x, y)
                if r > 0.996 {
                    let star: Float = (r - 0.996) * 220 * (1 - style.cloudCover)
                    c += SIMD3<Float>(repeating: star)
                }
            }
            return SIMD4(c, 1)
        }
    }
}

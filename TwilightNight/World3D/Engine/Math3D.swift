import Foundation
import simd

typealias V3 = SIMD3<Float>

@inline(__always) func v3(_ x: Float, _ y: Float, _ z: Float) -> V3 { V3(x, y, z) }

@inline(__always) func lerpf(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

@inline(__always) func clampf(_ v: Float, _ lo: Float, _ hi: Float) -> Float { min(hi, max(lo, v)) }

@inline(__always) func mixv(_ a: V3, _ b: V3, _ t: Float) -> V3 { a + (b - a) * t }

/// Плавный вход и выход — для движения камеры.
@inline(__always) func ease(_ t: Float) -> Float {
    let x = clampf(t, 0, 1)
    return x * x * (3 - 2 * x)
}

/// Мягче, чем `ease`: долгий разгон и торможение.
@inline(__always) func easeSoft(_ t: Float) -> Float {
    let x = clampf(t, 0, 1)
    return x * x * x * (x * (x * 6 - 15) + 10)
}

/// Экспоненциальное приближение к цели, не зависящее от частоты кадров.
@inline(__always) func damp(_ current: Float, _ target: Float, _ rate: Float, _ dt: Float) -> Float {
    current + (target - current) * (1 - exp(-rate * dt))
}

@inline(__always) func dampv(_ current: V3, _ target: V3, _ rate: Float, _ dt: Float) -> V3 {
    current + (target - current) * (1 - exp(-rate * dt))
}

/// Поворот вектора вокруг вертикали.
@inline(__always) func rotateY(_ v: V3, _ angle: Float) -> V3 {
    let c = cos(angle), s = sin(angle)
    return V3(v.x * c + v.z * s, v.y, -v.x * s + v.z * c)
}

/// Угол поворота вокруг Y, чтобы «вперёд» (+Z) смотрело на точку.
@inline(__always) func yawToward(from a: V3, to b: V3) -> Float {
    atan2(b.x - a.x, b.z - a.z)
}

/// Детерминированный «случайный» генератор — одинаковая расстановка при каждом запуске.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0...1
    mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    mutating func range(_ lo: Float, _ hi: Float) -> Float {
        lo + (hi - lo) * unit()
    }
}

@inline(__always) func smoothstepf(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = clampf((x - e0) / max(0.00001, e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)
}

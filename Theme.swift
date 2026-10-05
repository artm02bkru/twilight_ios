import SwiftUI

/// Единая палитра: холодный форкский сумрак, вампирский багровый, янтарь глаз.
enum Theme {

    static let skyTop = Color(red: 0.02, green: 0.03, blue: 0.07)
    static let skyMid = Color(red: 0.05, green: 0.08, blue: 0.14)
    static let skyBottom = Color(red: 0.06, green: 0.13, blue: 0.13)

    static let blood = Color(red: 0.72, green: 0.09, blue: 0.14)
    static let bloodLight = Color(red: 0.95, green: 0.28, blue: 0.32)
    static let venom = Color(red: 0.55, green: 0.24, blue: 0.62)
    static let amber = Color(red: 0.95, green: 0.72, blue: 0.32)
    static let gold = Color(red: 0.85, green: 0.66, blue: 0.22)
    static let ice = Color(red: 0.72, green: 0.86, blue: 0.96)
    static let mist = Color(red: 0.58, green: 0.65, blue: 0.78)
    static let forest = Color(red: 0.04, green: 0.09, blue: 0.09)

    static let text = Color.white
    static let textDim = Color.white.opacity(0.62)

    static func title(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .serif)
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

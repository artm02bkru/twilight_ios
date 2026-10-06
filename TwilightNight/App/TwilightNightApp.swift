import SwiftUI

@main
struct TwilightNightApp: App {
    @StateObject private var license = LicenseManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                // Пока игра не активирована ключом — экран активации (если проверка включена).
                if license.isRequired && !license.isActivated {
                    ActivationView(license: license)
                } else {
                    RootView()
                }
            }
            .preferredColorScheme(.dark)
            .statusBarHidden(true)
        }
    }
}

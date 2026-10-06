import SwiftUI

/// Экран ввода ключа: 1 ключ — 1 устройство. Показывается до меню, пока игра не активирована.
struct ActivationView: View {

    @ObservedObject var license: LicenseManager
    @State private var key = ""
    @State private var busy = false
    @State private var error: String?
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.skyTop, Theme.skyMid, Theme.skyBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                LogoView()
                    .frame(maxWidth: 420)
                Text("by @twilight_xbot")
                    .font(Theme.body(14, weight: .medium).italic())
                    .foregroundColor(Theme.ice.opacity(0.8))

                VStack(alignment: .leading, spacing: 12) {
                    Text("АКТИВАЦИЯ ИГРЫ")
                        .font(Theme.body(13, weight: .heavy))
                        .tracking(4)
                        .foregroundColor(Theme.mist)
                    Text("Введите ключ. Один ключ работает на одном устройстве.")
                        .font(Theme.body(15, weight: .regular))
                        .foregroundColor(Theme.text)

                    TextField("TW-XXXX-XXXX-XXXX", text: $key)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ice.opacity(0.35), lineWidth: 1))
                        .submitLabel(.go)
                        .onSubmit(activate)

                    if let error {
                        Text(error)
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundColor(Theme.bloodLight)
                    }

                    Button(action: activate) {
                        HStack(spacing: 10) {
                            if busy { ProgressView().tint(.white) }
                            Text(busy ? "ПРОВЕРЯЕМ…" : "АКТИВИРОВАТЬ")
                        }
                    }
                    .buttonStyle(GlassButtonStyle(prominent: true))
                    .disabled(busy)

                    Button {
                        openURL(LicenseConfig.botURL)
                    } label: {
                        Text("Нет ключа? Получить в Telegram: @twilight_xbot")
                            .font(Theme.body(14, weight: .semibold))
                            .foregroundColor(Theme.ice)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(24)
                .frame(maxWidth: 520)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.black.opacity(0.45)))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .padding(24)
        }
    }

    private func activate() {
        guard !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            let result = await license.activate(key: key)
            busy = false
            error = result?.message
        }
    }
}

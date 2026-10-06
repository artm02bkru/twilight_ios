import CryptoKit
import Foundation
import Security
import UIKit

/// Настройки лицензии. Публичный ключ и адрес выдаёт ваш бот (см. Server/README.md).
/// Пока publicKeyBase64 пустой, проверка выключена — игра запускается без ключа.
enum LicenseConfig {
    /// Адрес активации на сервере бота: POST {"key": "...", "device": "..."}.
    static let activationURL = URL(string: "https://YOUR-BOT-HOST.example.com/activate")!
    /// Публичный Ed25519-ключ сервера (base64, 32 байта) — из Server/keygen.py.
    static let publicKeyBase64 = ""
    /// Где получить ключ.
    static let botURL = URL(string: "https://t.me/twilight_xbot")!
}

/// Лицензия «1 ключ — 1 устройство».
///
/// Устройство определяется случайным ID, который хранится в Keychain только на этом
/// устройстве (не переносится через iCloud и переживает переустановку игры).
/// Сервер привязывает ключ к ID и возвращает подписанную лицензию; дальше игра
/// проверяет подпись встроенным публичным ключом и работает без интернета.
final class LicenseManager: ObservableObject {

    static let shared = LicenseManager()

    @Published private(set) var isActivated = false

    /// Нужна ли проверка: ключ сервера задан и это не фототур на CI.
    var isRequired: Bool {
        !LicenseConfig.publicKeyBase64.isEmpty && !ShotTour.isRequested
    }

    let deviceID: String

    enum ActivationError: Error {
        case emptyKey, network, notFound, usedElsewhere, revoked, badResponse

        var message: String {
            switch self {
            case .emptyKey:      return "Введите ключ."
            case .network:       return "Нет связи с сервером. Проверьте интернет и попробуйте ещё раз."
            case .notFound:      return "Такого ключа нет. Проверьте, что он введён без ошибок."
            case .usedElsewhere: return "Этот ключ уже активирован на другом устройстве."
            case .revoked:       return "Ключ отозван. Напишите в @twilight_xbot."
            case .badResponse:   return "Сервер ответил непонятно. Попробуйте позже."
            }
        }
    }

    private struct Stored: Codable {
        let license: String
        let signature: String
    }

    private struct Payload: Codable {
        let key: String
        let device: String
        let issued: Int?
    }

    private init() {
        if let id = Keychain.read("device-id") {
            deviceID = id
        } else {
            let id = UUID().uuidString
            Keychain.write("device-id", id)
            deviceID = id
        }
        if let raw = Keychain.read("license"),
           let data = raw.data(using: .utf8),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            isActivated = verify(stored)
        }
    }

    /// Отправить ключ на сервер и сохранить подписанную лицензию.
    @MainActor
    func activate(key raw: String) async -> ActivationError? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else { return .emptyKey }
        var request = URLRequest(url: LicenseConfig.activationURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "key": key,
            "device": deviceID,
            "model": UIDevice.current.model,
            "system": UIDevice.current.systemVersion
        ])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .network }
        switch http.statusCode {
        case 200:
            guard let stored = try? JSONDecoder().decode(Stored.self, from: data), verify(stored),
                  let text = String(data: data, encoding: .utf8) else { return .badResponse }
            Keychain.write("license", text)
            isActivated = true
            return nil
        case 404: return .notFound
        case 409: return .usedElsewhere
        case 403: return .revoked
        default:  return .badResponse
        }
    }

    /// Подпись верна, и лицензия выдана именно этому устройству.
    private func verify(_ stored: Stored) -> Bool {
        guard let keyData = Data(base64Encoded: LicenseConfig.publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let licenseData = Data(base64Encoded: stored.license),
              let signature = Data(base64Encoded: stored.signature),
              publicKey.isValidSignature(signature, for: licenseData),
              let payload = try? JSONDecoder().decode(Payload.self, from: licenseData) else { return false }
        return payload.device == deviceID
    }
}

/// Минимальная обёртка над Keychain: строки только на этом устройстве.
private enum Keychain {
    private static let service = "twilight.license"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

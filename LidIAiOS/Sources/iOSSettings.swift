import Foundation
import Security
import SwiftUI

@MainActor
@Observable
final class iOSSettings {
    var displayName: String = "" {
        didSet { UserDefaults.standard.set(displayName, forKey: "displayName") }
    }

    var openaiAPIKey: String = "" {
        didSet { saveToKeychain(key: "lidia.openai.apiKey", value: openaiAPIKey) }
    }

    var ttsVoiceID: String = "alloy" {
        didSet { UserDefaults.standard.set(ttsVoiceID, forKey: "ttsVoiceID") }
    }

    var personalityMode: PersonalityMode = .professional {
        didSet { UserDefaults.standard.set(personalityMode.rawValue, forKey: "personalityMode") }
    }

    var syncEnabled: Bool = false {
        didSet { UserDefaults.standard.set(syncEnabled, forKey: "syncEnabled") }
    }
    var syncServerURL: String = "" {
        didSet { UserDefaults.standard.set(syncServerURL, forKey: "syncServerURL") }
    }
    var syncAuthToken: String = "" {
        didSet { saveToKeychain(key: "lidia.sync.authToken", value: syncAuthToken) }
    }

    enum PersonalityMode: String, CaseIterable {
        case professional = "Professional"
        case friendly = "Friendly"
        case witty = "Witty"

        var promptFragment: String {
            switch self {
            case .professional: "Be direct and efficient. No small talk."
            case .friendly: "Be warm, encouraging, and supportive. Use a casual tone."
            case .witty: "Be clever and humorous. Add light humor where appropriate, but stay helpful."
            }
        }
    }

    var hasAPIKey: Bool { !openaiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    init() {
        let defaults = UserDefaults.standard
        displayName = defaults.string(forKey: "displayName") ?? ""
        openaiAPIKey = loadFromKeychain(key: "lidia.openai.apiKey") ?? ""
        ttsVoiceID = defaults.string(forKey: "ttsVoiceID") ?? ""
        personalityMode = PersonalityMode(rawValue: defaults.string(forKey: "personalityMode") ?? "") ?? .professional
        syncEnabled = defaults.bool(forKey: "syncEnabled")
        syncServerURL = defaults.string(forKey: "syncServerURL") ?? ""
        syncAuthToken = loadFromKeychain(key: "lidia.sync.authToken") ?? ""
    }

    // MARK: - Keychain

    private func saveToKeychain(key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.lidia.ios",
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        if !value.isEmpty {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "io.lidia.ios",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

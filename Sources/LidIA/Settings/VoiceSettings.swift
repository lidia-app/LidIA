import Foundation
import Observation

@MainActor
@Observable
final class VoiceSettings {
    private var isLoading = false

    // STT
    var sttEngine: AppSettings.STTEngineType = .parakeet {
        didSet { saveDefault(sttEngine.rawValue, forKey: "sttEngine") }
    }
    var whisperKitModel: String = "" {
        didSet { saveDefault(whisperKitModel, forKey: "whisperKitModel") }
    }
    var enableDiarization: Bool = true {
        didSet { saveDefault(enableDiarization, forKey: "enableDiarization") }
    }

    /// IANA locale identifier for STT (e.g., "en-US", "es-ES", "fr-FR", "de-DE", "pt-BR", "ja-JP")
    /// Empty string means "system default" (Locale.current)
    var sttLanguage: String = "" {
        didSet { saveDefault(sttLanguage, forKey: "sttLanguage") }
    }

    // Voice Assistant
    var voiceEnabled: Bool = false {
        didSet { saveDefault(voiceEnabled, forKey: "voiceEnabled") }
    }
    var voiceHotkey: String = "option+space" {
        didSet { saveDefault(voiceHotkey, forKey: "voiceHotkey") }
    }
    var ttsProvider: AppSettings.TTSProvider = .automatic {
        didSet { saveDefault(ttsProvider.rawValue, forKey: "ttsProvider") }
    }
    var ttsVoiceID: String = "" {
        didSet { saveDefault(ttsVoiceID, forKey: "ttsVoiceID") }
    }
    var selectedTTSModelID: String = "" {
        didSet { saveDefault(selectedTTSModelID, forKey: "selectedTTSModelID") }
    }
    var voiceReadResponses: Bool = true {
        didSet { saveDefault(voiceReadResponses, forKey: "voiceReadResponses") }
    }
    var voiceSilenceTimeout: Double = 1.5 {
        didSet { saveDefault(voiceSilenceTimeout, forKey: "voiceSilenceTimeout") }
    }

    // Assistant Personality
    var assistantPersonality: AppSettings.AssistantPersonality = .professional {
        didSet { saveDefault(assistantPersonality.rawValue, forKey: "assistantPersonality") }
    }

    // Custom Vocabulary
    var customVocabulary: [AppSettings.VocabularyEntry] = [] {
        didSet { saveVocabulary() }
    }

    // MARK: - Init

    init() {
        loadFromDefaults()
    }

    func loadFromDefaults() {
        isLoading = true
        defer { isLoading = false }
        let defaults = UserDefaults.standard
        sttEngine = AppSettings.STTEngineType(rawValue: defaults.string(forKey: "sttEngine") ?? "") ?? .parakeet
        whisperKitModel = defaults.string(forKey: "whisperKitModel") ?? ""
        if let diar = defaults.object(forKey: "enableDiarization") as? Bool {
            enableDiarization = diar
        }
        sttLanguage = defaults.string(forKey: "sttLanguage") ?? ""
        voiceEnabled = defaults.bool(forKey: "voiceEnabled")
        voiceHotkey = defaults.string(forKey: "voiceHotkey") ?? "option+space"
        ttsProvider = AppSettings.TTSProvider(rawValue: defaults.string(forKey: "ttsProvider") ?? "") ?? .automatic
        ttsVoiceID = defaults.string(forKey: "ttsVoiceID") ?? ""
        selectedTTSModelID = defaults.string(forKey: "selectedTTSModelID") ?? ""
        voiceReadResponses = defaults.object(forKey: "voiceReadResponses") as? Bool ?? true
        voiceSilenceTimeout = defaults.object(forKey: "voiceSilenceTimeout") as? Double ?? 1.5
        assistantPersonality = AppSettings.AssistantPersonality(rawValue: defaults.string(forKey: "assistantPersonality") ?? "") ?? .professional
        loadVocabulary()
    }

    // MARK: - Vocabulary Persistence

    private func saveVocabulary() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(customVocabulary) {
            UserDefaults.standard.set(data, forKey: "customVocabulary")
        }
    }

    private func loadVocabulary() {
        guard let data = UserDefaults.standard.data(forKey: "customVocabulary"),
              let saved = try? JSONDecoder().decode([AppSettings.VocabularyEntry].self, from: data) else {
            return
        }
        customVocabulary = saved
    }

    /// Applies custom vocabulary replacements to a word.
    func applyVocabulary(to word: String) -> String {
        var result = word
        for entry in customVocabulary {
            let heard = entry.heardAs
            if entry.caseSensitive {
                if result == heard { result = entry.replaceTo }
            } else {
                if result.caseInsensitiveCompare(heard) == .orderedSame { result = entry.replaceTo }
            }
        }
        return result
    }

    // MARK: - Persistence Helpers

    private func saveDefault(_ value: some Any, forKey key: String) {
        guard !isLoading else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
}

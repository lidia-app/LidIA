import Foundation

@MainActor
struct TranscriptionService {
    func makeEngine(settings: AppSettings) -> any STTEngine {
        let languageID = settings.sttLanguage
        switch settings.sttEngine {
        case .parakeet:
            return ParakeetEngine()
        case .graniteSpeech:
            return GraniteSpeechEngine()
        case .whisperKit:
            return WhisperKitEngine(
                modelName: settings.whisperKitModel,
                language: languageID.isEmpty ? nil : languageID
            )
        case .appleSpeech:
            let locale = languageID.isEmpty ? Locale.current : Locale(identifier: languageID)
            return AppleSpeechEngine(locale: locale)
        }
    }
}

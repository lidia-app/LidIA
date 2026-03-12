import Testing
import Foundation
@testable import LidIA

@Suite("AppSettings")
struct AppSettingsTests {

    // MARK: - Default Values
    //
    // These tests clear relevant UserDefaults keys before checking defaults,
    // because tests in the same process share UserDefaults.standard.

    @MainActor
    @Test("LLM provider defaults to Ollama")
    func defaultLLMProvider() {
        UserDefaults.standard.removeObject(forKey: "llmProvider")
        let settings = LLMSettings()
        settings.loadFromDefaults()
        #expect(settings.llmProvider == .ollama)
    }

    @MainActor
    @Test("Ollama URL has a sensible default")
    func defaultOllamaURL() {
        UserDefaults.standard.removeObject(forKey: "ollamaURL")
        let settings = LLMSettings()
        settings.loadFromDefaults()
        #expect(settings.ollamaURL == "http://localhost:11434")
    }

    @MainActor
    @Test("OpenAI base URL defaults to api.openai.com")
    func defaultOpenAIBaseURL() {
        UserDefaults.standard.removeObject(forKey: "openaiBaseURL")
        let settings = LLMSettings()
        settings.loadFromDefaults()
        #expect(settings.openaiBaseURL == "https://api.openai.com")
    }

    @MainActor
    @Test("Anthropic model has a default")
    func defaultAnthropicModel() {
        UserDefaults.standard.removeObject(forKey: "anthropicModel")
        let settings = LLMSettings()
        settings.loadFromDefaults()
        #expect(!settings.anthropicModel.isEmpty)
        #expect(settings.anthropicModel.contains("claude"))
    }

    @MainActor
    @Test("Appearance mode defaults to system")
    func defaultAppearanceMode() {
        UserDefaults.standard.removeObject(forKey: "appearanceMode")
        let settings = AppSettings()
        #expect(settings.appearanceMode == .system)
    }

    @MainActor
    @Test("Auto-stop on silence defaults to off")
    func defaultAutoStopOnSilence() {
        UserDefaults.standard.removeObject(forKey: "autoStopOnSilence")
        let settings = RecordingSettings()
        settings.loadFromDefaults()
        #expect(settings.autoStopOnSilence == false)
    }

    @MainActor
    @Test("Silence timeout has a positive default")
    func defaultSilenceTimeout() {
        UserDefaults.standard.removeObject(forKey: "silenceTimeoutSeconds")
        let settings = RecordingSettings()
        settings.loadFromDefaults()
        #expect(settings.silenceTimeoutSeconds > 0)
    }

    // MARK: - Forwarding Properties

    @MainActor
    @Test("llmProvider forwards to llm domain object")
    func llmProviderForwarding() {
        let settings = AppSettings()
        settings.llm.llmProvider = .anthropic
        #expect(settings.llmProvider == .anthropic)

        settings.llmProvider = .openai
        #expect(settings.llm.llmProvider == .openai)
    }

    @MainActor
    @Test("ollamaURL forwards to llm domain object")
    func ollamaURLForwarding() {
        let settings = AppSettings()
        let testURL = "http://custom:9999"
        settings.ollamaURL = testURL
        #expect(settings.llm.ollamaURL == testURL)
    }

    @MainActor
    @Test("sttEngine forwards to voice domain object")
    func sttEngineForwarding() {
        let settings = AppSettings()
        settings.sttEngine = .appleSpeech
        #expect(settings.voice.sttEngine == .appleSpeech)

        settings.voice.sttEngine = .whisperKit
        #expect(settings.sttEngine == .whisperKit)
    }

    @MainActor
    @Test("calendarEnabled forwards to calendar domain object")
    func calendarEnabledForwarding() {
        let settings = AppSettings()
        settings.calendarEnabled = true
        #expect(settings.calendar.calendarEnabled == true)
    }

    @MainActor
    @Test("n8nEnabled forwards to integration domain object")
    func n8nEnabledForwarding() {
        let settings = AppSettings()
        settings.n8nEnabled = true
        #expect(settings.integration.n8nEnabled == true)

        settings.integration.n8nEnabled = false
        #expect(settings.n8nEnabled == false)
    }

    @MainActor
    @Test("audioCaptureMode forwards to recording domain object")
    func audioCaptureModeForwarding() {
        let settings = AppSettings()
        settings.recording.audioCaptureMode = .micOnly
        #expect(settings.audioCaptureMode == .micOnly)
    }

    // MARK: - AppearanceMode

    @MainActor
    @Test("AppearanceMode system returns nil colorScheme")
    func appearanceModeSystem() {
        #expect(AppSettings.AppearanceMode.system.colorScheme == nil)
    }

    @MainActor
    @Test("AppearanceMode light returns .light colorScheme")
    func appearanceModeLight() {
        #expect(AppSettings.AppearanceMode.light.colorScheme == .light)
    }

    @MainActor
    @Test("AppearanceMode dark returns .dark colorScheme")
    func appearanceModeDark() {
        #expect(AppSettings.AppearanceMode.dark.colorScheme == .dark)
    }

    // MARK: - AssistantPersonality

    @MainActor
    @Test("Each personality has a non-empty prompt fragment")
    func personalityPrompts() {
        for personality in AppSettings.AssistantPersonality.allCases {
            #expect(!personality.promptFragment.isEmpty, "Empty prompt for \(personality)")
        }
    }

    // MARK: - LLMProvider

    @MainActor
    @Test("All LLM providers have non-empty raw values")
    func llmProviderRawValues() {
        for provider in AppSettings.LLMProvider.allCases {
            #expect(!provider.rawValue.isEmpty)
        }
    }

    @MainActor
    @Test("LLMProvider round-trips through rawValue")
    func llmProviderRoundTrip() {
        for provider in AppSettings.LLMProvider.allCases {
            let decoded = AppSettings.LLMProvider(rawValue: provider.rawValue)
            #expect(decoded == provider)
        }
    }
}

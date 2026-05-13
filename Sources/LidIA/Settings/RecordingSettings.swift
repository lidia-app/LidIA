import Foundation
import Observation

@MainActor
@Observable
final class RecordingSettings {
    private var isLoading = false

    var audioCaptureMode: AudioCaptureMode = .micAndSystem {
        didSet { saveDefault(audioCaptureMode.rawValue, forKey: "audioCaptureMode") }
    }
    var autoStopOnSilence: Bool = false {
        didSet { saveDefault(autoStopOnSilence, forKey: "autoStopOnSilence") }
    }
    var silenceTimeoutSeconds: Double = 30 {
        didSet { saveDefault(silenceTimeoutSeconds, forKey: "silenceTimeoutSeconds") }
    }
    var displayName: String = "" {
        didSet { saveDefault(displayName, forKey: "displayName") }
    }
    var noiseReductionEnabled: Bool = false {
        didSet { saveDefault(noiseReductionEnabled, forKey: "noiseReductionEnabled") }
    }
    var useVADPreFilter: Bool = true {
        didSet { saveDefault(useVADPreFilter, forKey: "useVADPreFilter") }
    }
    var useSpeechEnhancement: Bool = false {
        didSet { saveDefault(useSpeechEnhancement, forKey: "useSpeechEnhancement") }
    }

    // MARK: - Init

    init() {
        loadFromDefaults()
    }

    func loadFromDefaults() {
        isLoading = true
        defer { isLoading = false }
        let defaults = UserDefaults.standard
        audioCaptureMode = AudioCaptureMode(rawValue: defaults.string(forKey: "audioCaptureMode") ?? "") ?? .micAndSystem
        autoStopOnSilence = defaults.bool(forKey: "autoStopOnSilence")
        if let timeout = defaults.object(forKey: "silenceTimeoutSeconds") as? Double {
            silenceTimeoutSeconds = timeout
        }
        if let name = defaults.string(forKey: "displayName") {
            displayName = name
        }
        noiseReductionEnabled = defaults.bool(forKey: "noiseReductionEnabled")
        if defaults.object(forKey: "useVADPreFilter") != nil {
            useVADPreFilter = defaults.bool(forKey: "useVADPreFilter")
        }
        if defaults.object(forKey: "useSpeechEnhancement") != nil {
            useSpeechEnhancement = defaults.bool(forKey: "useSpeechEnhancement")
        }
    }

    // MARK: - Persistence Helpers

    private func saveDefault(_ value: some Any, forKey key: String) {
        guard !isLoading else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
}

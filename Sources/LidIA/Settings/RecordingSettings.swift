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
    }

    // MARK: - Persistence Helpers

    private func saveDefault(_ value: some Any, forKey key: String) {
        guard !isLoading else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
}

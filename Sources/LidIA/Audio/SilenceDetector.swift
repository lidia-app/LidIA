import Foundation
import Observation

/// Monitors audio RMS levels and detects sustained silence.
@MainActor
@Observable
final class SilenceDetector {
    private(set) var isSilent = false
    private(set) var silenceDuration: TimeInterval = 0

    private var silenceStart: Date?
    private let threshold: Float = 0.01

    /// Feed an audio chunk's RMS value. Returns `true` when silence has
    /// exceeded the given timeout.
    func update(rms: Float, timeout: TimeInterval) -> Bool {
        // RMS near zero means the audio stream is dead or no input — don't
        // count that as silence (real room silence still has RMS ~0.002-0.005).
        guard rms >= 0.001 else {
            reset()
            return false
        }

        if rms < threshold {
            if silenceStart == nil {
                silenceStart = Date()
            }
            silenceDuration = Date().timeIntervalSince(silenceStart!)
            isSilent = silenceDuration >= timeout
            return isSilent
        } else {
            silenceStart = nil
            silenceDuration = 0
            isSilent = false
            return false
        }
    }

    func reset() {
        silenceStart = nil
        silenceDuration = 0
        isSilent = false
    }
}

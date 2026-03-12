import Foundation

struct AudioSourceEvent: Sendable {
    let source: AudioSource
    let timestamp: TimeInterval
    let rms: Float
}

@MainActor
@Observable
final class CaptureService {
    enum AudioQualityState {
        case good
        case lowInput
        case clipping
        case noInput
    }

    private let audioManager = AudioCaptureManager()

    var elapsedTime: TimeInterval {
        audioManager.elapsedTime
    }

    var currentRMS: Float {
        audioManager.currentRMS
    }

    /// Returns recent per-source (mic/system) RMS values from the last few seconds.
    /// Used by extended silence detection to check both channels independently.
    struct PerSourceRMS: Sendable {
        var mic: Float = 0
        var system: Float = 0
    }

    func recentPerSourceRMS() -> PerSourceRMS {
        audioManager.recentPerSourceRMS()
    }

    var activeCaptureMode: AudioCaptureMode {
        audioManager.activeCaptureMode
    }

    var captureStatus: AudioCaptureManager.CaptureStatus {
        audioManager.captureStatus
    }

    var audioQualityState: AudioQualityState {
        let rms = audioManager.currentRMS
        if rms < 0.003 { return .noInput }
        if rms > 0.65 { return .clipping }
        if rms < 0.015 { return .lowInput }
        return .good
    }

    var audioStream: AsyncStream<AudioChunk> {
        audioManager.audioStream
    }

    func startCapture(mode: AudioCaptureMode) async throws {
        try await audioManager.startCapture(mode: mode)
    }

    func stopCaptureAndDrainSamples() -> (mic: [Float], system: [Float], sourceEvents: [AudioSourceEvent]) {
        let mic = audioManager.drainAccumulatedMicSamples()
        let system = audioManager.drainAccumulatedSystemSamples()
        let events = audioManager.drainSourceEvents()
        audioManager.stopCapture()
        return (mic, system, events)
    }

    func drainSourceEvents() -> [AudioSourceEvent] {
        audioManager.drainSourceEvents()
    }

    func pauseCapture() {
        audioManager.pauseCapture()
    }

    func resumeCapture() {
        audioManager.resumeCapture()
    }
}

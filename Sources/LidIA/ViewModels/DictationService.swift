import Foundation
import os

private let logger = Logger(subsystem: "io.lidia.app", category: "DictationService")

@MainActor
@Observable
final class DictationService {

    // MARK: - Public State

    var isDictating = false

    /// Called when dictation completes with transcribed text.
    var onTranscription: ((String) -> Void)?

    // MARK: - Private State

    private var dictationSession: AudioCaptureSession?
    private var dictationTask: Task<Void, Never>?
    /// Shared engine — loaded once, reused across dictation calls to avoid repeated model loading.
    private var sharedParakeetEngine: ParakeetEngine?
    /// Max samples to accumulate (~30 seconds at 44.1kHz) to prevent unbounded memory growth.
    private static let maxDictationSamples = 44100 * 30

    // MARK: - Public API

    func toggleDictation() {
        if isDictating {
            finishDictationManually()
        } else {
            startDictation()
        }
    }

    // MARK: - Private

    private func startDictation() {
        let session = AudioCaptureSession()
        session.setSilenceDuration(1.5)
        do {
            try session.start()
        } catch {
            logger.error("Failed to start dictation audio capture: \(error)")
            return
        }
        dictationSession = session
        isDictating = true

        dictationTask = Task { [weak self] in
            var allSamples: [Float] = []

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, self.isDictating else { break }

                let (samples, _) = session.drain()
                if !samples.isEmpty {
                    let remaining = Self.maxDictationSamples - allSamples.count
                    if remaining > 0 {
                        allSamples.append(contentsOf: samples.prefix(remaining))
                    }
                }

                if session.isSilenceDetected() && !allSamples.isEmpty {
                    await self.transcribeDictation(samples: allSamples)
                    return
                }

                if allSamples.count >= Self.maxDictationSamples {
                    await self.transcribeDictation(samples: allSamples)
                    return
                }
            }
        }
    }

    private func finishDictationManually() {
        guard isDictating, let session = dictationSession else {
            stopDictation()
            return
        }
        dictationTask?.cancel()
        let (remaining, _) = session.drain()
        stopDictation()

        guard !remaining.isEmpty else { return }
        dictationTask = Task { [weak self] in
            await self?.transcribeDictation(samples: remaining)
        }
    }

    private func transcribeDictation(samples: [Float]) async {
        stopDictation()
        guard !samples.isEmpty else { return }

        if sharedParakeetEngine == nil {
            sharedParakeetEngine = ParakeetEngine()
        }
        let engine = sharedParakeetEngine!

        let chunk = AudioChunk(samples: samples, sampleRate: 44100, timestamp: 0, source: .mic)
        let audioStream = AsyncStream<AudioChunk> { continuation in
            continuation.yield(chunk)
            continuation.finish()
        }

        var words: [String] = []
        for await word in engine.transcribe(audioStream: audioStream) {
            words.append(word.word)
        }

        let transcript = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !transcript.isEmpty {
            onTranscription?(transcript)
        }
    }

    private func stopDictation() {
        dictationSession?.stop()
        dictationSession = nil
        isDictating = false
    }
}

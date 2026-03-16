import Foundation
import MLX
import MLXAudioSTT
import os

/// Batch STT engine using IBM Granite Speech 4.0 via mlx-audio-swift.
/// Collects all audio from the stream, then transcribes in one pass.
/// Supports English, French, German, Spanish, Portuguese, and Japanese.
final class GraniteSpeechEngine: STTEngine, Sendable {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "GraniteSpeechEngine")
    private let modelID: String

    init(modelID: String = "mlx-community/granite-4.0-1b-speech-5bit") {
        self.modelID = modelID
    }

    func preload() async throws {
        let _ = try await GraniteSpeechModel.fromPretrained(modelID)
    }

    func transcribe(audioStream: AsyncStream<AudioChunk>) -> AsyncStream<TranscriptWord> {
        let modelID = self.modelID
        return AsyncStream { continuation in
            Task {
                // Collect all audio samples from the stream
                var allSamples: [Float] = []
                for await chunk in audioStream {
                    allSamples.append(contentsOf: chunk.samples)
                }

                guard !allSamples.isEmpty else {
                    continuation.finish()
                    return
                }

                do {
                    Self.logger.info("Loading Granite Speech model: \(modelID)")
                    let model = try await GraniteSpeechModel.fromPretrained(modelID)

                    // Audio must be 16kHz mono — check sample count implies duration
                    let duration = Double(allSamples.count) / 16000.0
                    Self.logger.info("Transcribing \(allSamples.count) samples (\(String(format: "%.1f", duration))s)")

                    let audio = MLXArray(allSamples)
                    let params = model.defaultGenerationParameters
                    let output = model.generate(audio: audio, generationParameters: params)

                    Self.logger.info("Granite output: \(output.text.prefix(200))")

                    // Parse output text into words with estimated timing
                    let text = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let words = text.split(separator: " ")
                    let wordDuration = words.isEmpty ? 0 : duration / Double(words.count)

                    for (i, word) in words.enumerated() {
                        let start = Double(i) * wordDuration
                        let end = start + wordDuration
                        continuation.yield(TranscriptWord(
                            word: String(word),
                            start: start,
                            end: end,
                            confidence: 1.0
                        ))
                    }
                    Self.logger.info("Granite transcription complete: \(words.count) words")
                } catch {
                    Self.logger.error("Granite transcription failed: \(error)")
                }

                continuation.finish()
            }
        }
    }
}

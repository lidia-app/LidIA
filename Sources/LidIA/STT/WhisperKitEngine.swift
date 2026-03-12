import Foundation
import WhisperKit
import os

/// STT engine using WhisperKit — CoreML-optimized Whisper for Apple Silicon.
/// Handles long-form audio by processing in chunks with a single model instance.
final class WhisperKitEngine: STTEngine {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "WhisperKitEngine")
    private let modelName: String
    private let language: String?

    /// - Parameter modelName: WhisperKit model name (e.g. "large-v3", "base", "small").
    ///   If empty, WhisperKit auto-selects the best model for the device.
    /// - Parameter language: Optional language code (e.g. "en", "es", "fr").
    ///   If nil, WhisperKit auto-detects the language.
    init(modelName: String = "", language: String? = nil) {
        self.modelName = modelName
        // WhisperKit uses short language codes (e.g. "en", "es"), not full IANA locales.
        // Strip the region suffix if present.
        if let lang = language {
            self.language = String(lang.prefix(2))
        } else {
            self.language = nil
        }
    }

    func transcribe(audioStream: AsyncStream<AudioChunk>) -> AsyncStream<TranscriptWord> {
        let modelName = self.modelName
        let language = self.language

        return AsyncStream { continuation in
            let task = Task { @Sendable in
                // 1. Initialize WhisperKit (downloads model if needed on first use)
                Self.logger.info("Initializing with model: \(modelName.isEmpty ? "auto" : modelName)...")
                let config: WhisperKitConfig
                if modelName.isEmpty {
                    config = WhisperKitConfig()
                } else {
                    config = WhisperKitConfig(model: modelName)
                }

                let whisperKit: WhisperKit
                do {
                    try Task.checkCancellation()
                    whisperKit = try await WhisperKit(config)
                    Self.logger.info("Model loaded successfully")
                } catch is CancellationError {
                    Self.logger.info("Transcription cancelled during model init")
                    continuation.finish()
                    return
                } catch {
                    Self.logger.error("Failed to initialize: \(error)")
                    continuation.finish()
                    return
                }

                // 2. Accumulate audio and process in ~30-second chunks
                var allSamples: [Float] = []
                var baseTimestamp: TimeInterval = 0
                var isFirst = true
                let chunkDurationSamples = 16000 * 30 // 30 seconds at 16kHz

                for await chunk in audioStream {
                    if Task.isCancelled {
                        Self.logger.info("Transcription cancelled during audio processing")
                        break
                    }

                    if isFirst {
                        baseTimestamp = chunk.timestamp
                        isFirst = false
                    }

                    // Resample to 16kHz if needed
                    let samples: [Float]
                    if chunk.sampleRate != 16000 {
                        samples = AudioResampler.resample(chunk.samples, from: chunk.sampleRate, to: 16000)
                    } else {
                        samples = chunk.samples
                    }
                    allSamples.append(contentsOf: samples)

                    // Process when we have enough audio
                    if allSamples.count >= chunkDurationSamples {
                        if Task.isCancelled { break }

                        let chunkToProcess = Array(allSamples.prefix(chunkDurationSamples))
                        allSamples = Array(allSamples.dropFirst(chunkDurationSamples))

                        let words = await Self.processChunk(
                            whisperKit: whisperKit,
                            samples: chunkToProcess,
                            baseTimestamp: baseTimestamp,
                            language: language
                        )
                        for word in words {
                            continuation.yield(word)
                        }
                        baseTimestamp += Double(chunkDurationSamples) / 16000.0
                    }
                }

                // 3. Process remaining audio (skip if cancelled)
                if !Task.isCancelled && !allSamples.isEmpty {
                    let words = await Self.processChunk(
                        whisperKit: whisperKit,
                        samples: allSamples,
                        baseTimestamp: baseTimestamp,
                        language: language
                    )
                    for word in words {
                        continuation.yield(word)
                    }
                }

                Self.logger.info("Transcription \(Task.isCancelled ? "cancelled" : "complete")")
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func processChunk(
        whisperKit: WhisperKit,
        samples: [Float],
        baseTimestamp: TimeInterval,
        language: String? = nil
    ) async -> [TranscriptWord] {
        do {
            let options = DecodingOptions(
                language: language,
                wordTimestamps: true
            )

            let results = await whisperKit.transcribe(
                audioArrays: [samples],
                decodeOptions: options
            )

            var words: [TranscriptWord] = []

            for resultArray in results {
                guard let transcriptions = resultArray else { continue }
                for result in transcriptions {
                    // Extract words from segments
                    for segment in result.segments {
                        if let wordTimings = segment.words {
                            // Use word-level timestamps
                            for timing in wordTimings {
                                let cleaned = timing.word.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !cleaned.isEmpty else { continue }
                                let word = TranscriptWord(
                                    word: cleaned,
                                    start: baseTimestamp + Double(timing.start),
                                    end: baseTimestamp + Double(timing.end),
                                    confidence: Double(timing.probability),
                                    speaker: nil
                                )
                                words.append(word)
                            }
                        } else {
                            // Fallback: split segment text into words with estimated timestamps
                            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                            let textWords = text.split(separator: " ")
                            let segDuration = Double(segment.end - segment.start)
                            let wordDuration = segDuration / Double(max(textWords.count, 1))

                            for (i, w) in textWords.enumerated() {
                                let word = TranscriptWord(
                                    word: String(w),
                                    start: baseTimestamp + Double(segment.start) + wordDuration * Double(i),
                                    end: baseTimestamp + Double(segment.start) + wordDuration * Double(i + 1),
                                    confidence: 0.9,
                                    speaker: nil
                                )
                                words.append(word)
                            }
                        }
                    }
                }
            }

            let wordCount = words.count
            let duration = String(format: "%.1f", Double(samples.count) / 16000.0)
            Self.logger.debug("Processed \(duration)s chunk → \(wordCount) words")
            return words
        }
    }

}

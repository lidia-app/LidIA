import AVFoundation
import FluidAudio
import os
import Synchronization

/// Streaming STT engine using FluidAudio's Parakeet EOU model.
/// Uses StreamingEouAsrManager for real-time transcription during recording.
///
/// Words are emitted progressively via the partial callback (fires on every decoded chunk),
/// then reset on EOU (end-of-utterance silence). The batch processor replaces this
/// streaming transcript with a higher-quality version after recording stops.
/// Thread-safe via Mutex for the pre-loaded manager state.
/// StreamingEouAsrManager is not Sendable, so we use @unchecked Sendable
/// with Mutex-based synchronization for the only shared mutable state.
final class ParakeetEngine: @unchecked Sendable, STTEngine {

    private static let logger = Logger(subsystem: "io.lidia.app", category: "ParakeetEngine")

    /// Pre-loaded manager from `preload()`, reused by `transcribe()` to skip model loading.
    /// Access synchronized via Mutex. StreamingEouAsrManager is not Sendable itself.
    private let preloadedManagerMutex = Mutex<StreamingEouAsrManager?>(nil)

    /// Pre-load the streaming ASR model so the first `transcribe()` call is fast.
    func preload() async throws {
        let manager = StreamingEouAsrManager(chunkSize: .ms320, eouDebounceMs: 800)
        let modelsDir = Self.streamingModelsDirectory()
        try await Self.downloadStreamingModelsIfNeeded(to: modelsDir)
        try await manager.loadModels(modelDir: modelsDir)
        Self.logger.info("Streaming ASR models pre-loaded")
        preloadedManagerMutex.withLock { $0 = manager }
    }

    /// Take the pre-loaded manager (if any), clearing it so it's only used once.
    private func takePreloadedManager() -> StreamingEouAsrManager? {
        preloadedManagerMutex.withLock { manager in
            let taken = manager
            manager = nil
            return taken
        }
    }

    func transcribe(audioStream: AsyncStream<AudioChunk>) -> AsyncStream<TranscriptWord> {
        return AsyncStream { continuation in
            Task { @Sendable [weak self] in
                let manager: StreamingEouAsrManager
                if let preloaded = self?.takePreloadedManager() {
                    manager = preloaded
                    ParakeetEngine.logger.info("Reusing pre-loaded ASR manager")
                } else {
                    manager = StreamingEouAsrManager(chunkSize: .ms320, eouDebounceMs: 800)
                    do {
                        let modelsDir = Self.streamingModelsDirectory()
                        try await Self.downloadStreamingModelsIfNeeded(to: modelsDir)
                        try await manager.loadModels(modelDir: modelsDir)
                        ParakeetEngine.logger.info("Streaming ASR models loaded")
                    } catch {
                        ParakeetEngine.logger.error("Failed to load streaming models: \(error)")
                        continuation.finish()
                        return
                    }
                }

                // Track emitted words so we only yield NEW words from each partial update.
                // partialCallback fires on every chunk with decoded tokens, giving the
                // full accumulated text so far. We diff against what we already emitted.
                let state = PartialState()

                await manager.setPartialCallback { partial in
                    let words = partial.split(separator: " ")
                    guard !words.isEmpty else { return }

                    let emitted = state.emittedWordCount
                    // confirmedCount = all words except the last (which may be incomplete)
                    let confirmedCount = words.count - 1

                    if confirmedCount > emitted {
                        // Emit the previously held-back word (now confirmed by new words after it)
                        if let held = state.heldBackWord {
                            continuation.yield(TranscriptWord(
                                word: held, start: 0, end: 0, confidence: 0.90, speaker: nil
                            ))
                        }
                        // Emit all newly confirmed words (skip the held-back index if it was already emitted above)
                        let startIdx = state.heldBackWord != nil ? emitted + 1 : emitted
                        for i in startIdx..<confirmedCount {
                            let cleaned = String(words[i]).trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !cleaned.isEmpty else { continue }
                            continuation.yield(TranscriptWord(
                                word: cleaned, start: 0, end: 0, confidence: 0.90, speaker: nil
                            ))
                        }
                        state.emittedWordCount = confirmedCount
                    }

                    // Always hold back the last word (potentially incomplete)
                    state.heldBackWord = String(words.last!).trimmingCharacters(in: .whitespacesAndNewlines)
                }

                // Process audio chunks from the capture stream
                for await chunk in audioStream {
                    let samples16k: [Float]
                    if chunk.sampleRate != 16000 {
                        samples16k = AudioResampler.resample(chunk.samples, from: chunk.sampleRate, to: 16000)
                    } else {
                        samples16k = chunk.samples
                    }

                    guard let buffer = Self.makePCMBuffer(from: samples16k, sampleRate: 16000) else {
                        continue
                    }

                    do {
                        // process() drives the model — partialCallback fires inside here
                        // when new tokens are decoded. process() itself returns "".
                        _ = try await manager.process(audioBuffer: buffer)

                        // On end-of-utterance (silence detected), finalize and reset
                        if await manager.eouDetected {
                            // Flush the held-back word before resetting
                            if let held = state.heldBackWord, !held.isEmpty {
                                continuation.yield(TranscriptWord(
                                    word: held, start: 0, end: 0, confidence: 0.90, speaker: nil
                                ))
                                state.heldBackWord = nil
                            }
                            _ = try await manager.finish()
                            await manager.reset()
                            state.emittedWordCount = 0
                        }
                    } catch {
                        ParakeetEngine.logger.error("Processing error: \(error)")
                    }
                }

                // Flush any held-back word before finalizing
                if let held = state.heldBackWord, !held.isEmpty {
                    continuation.yield(TranscriptWord(
                        word: held, start: 0, end: 0, confidence: 0.90, speaker: nil
                    ))
                    state.heldBackWord = nil
                }

                // Finalize remaining audio when recording stops
                do {
                    let remaining = try await manager.finish()
                    if !remaining.isEmpty {
                        // Emit any words not yet sent via partial callback
                        let words = remaining.split(separator: " ")
                        let emitted = state.emittedWordCount
                        if words.count > emitted {
                            let now = Date().timeIntervalSince1970
                            for i in emitted..<words.count {
                                let cleaned = String(words[i]).trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !cleaned.isEmpty else { continue }
                                continuation.yield(TranscriptWord(
                                    word: cleaned,
                                    start: now,
                                    end: now,
                                    confidence: 0.90,
                                    speaker: nil
                                ))
                            }
                        }
                    }
                } catch {
                    ParakeetEngine.logger.error("Finish error: \(error)")
                }

                ParakeetEngine.logger.info("Streaming transcription complete")
                continuation.finish()
            }
        }
    }

    // MARK: - Model Management

    static func streamingModelsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("parakeet-eou-streaming/320ms", isDirectory: true)
    }

    static func downloadStreamingModelsIfNeeded(to destination: URL) async throws {
        let encoderPath = destination.appendingPathComponent("streaming_encoder.mlmodelc")
        if FileManager.default.fileExists(atPath: encoderPath.path) {
            return
        }

        Self.logger.info("Downloading streaming EOU models...")
        let fluidAudioDir = destination
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try await DownloadUtils.downloadRepo(.parakeetEou320, to: fluidAudioDir)
        Self.logger.info("Streaming models downloaded")
    }

    // MARK: - Helpers

    private static func makePCMBuffer(from samples: [Float], sampleRate: Int) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { src in
                channelData[0].update(from: src.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }
}

/// Mutable state shared between the partial callback and the main processing loop.
/// Thread-safe via Mutex — the partial callback is @Sendable and may fire from
/// a different isolation context than the main processing loop.
private struct PartialStateValue: Sendable {
    /// Number of words confirmed and emitted (not counting the held-back word).
    var emittedWordCount = 0
    /// The last word from the previous partial — held back because it may be incomplete.
    /// Emitted only when the next partial confirms it by showing a new word after it.
    var heldBackWord: String?
}

/// Wrapper providing the same API as the old PartialState class, backed by a Mutex.
private final class PartialState: Sendable {
    private let storage = Mutex(PartialStateValue())

    var emittedWordCount: Int {
        get { storage.withLock { $0.emittedWordCount } }
        set { storage.withLock { $0.emittedWordCount = newValue } }
    }
    var heldBackWord: String? {
        get { storage.withLock { $0.heldBackWord } }
        set { storage.withLock { $0.heldBackWord = newValue } }
    }
}

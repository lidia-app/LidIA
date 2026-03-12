import Foundation
import SwiftData
import Synchronization
import os

/// Local voice pipeline: Parakeet STT → LLM → TTS.
/// Tool execution, context enrichment, and TTS fallback included.
/// @unchecked Sendable is safe: all `let` properties are Sendable protocols,
/// and `currentTask` is protected by a Mutex.
final class LocalVoicePipeline: VoicePipeline, @unchecked Sendable {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "LocalVoicePipeline")

    private let sttEngine: any STTEngine
    private let llmClient: any LLMClient
    private let llmModel: String
    private let ttsEngine: any TTSEngine
    private let fallbackTTS: any TTSEngine
    private let toolExecutor: VoiceToolExecutor.Configuration
    private let currentTaskMutex = Mutex<Task<Void, Never>?>(nil)

    init(
        stt: any STTEngine,
        llm: any LLMClient,
        model: String,
        tts: any TTSEngine,
        fallbackTTS: any TTSEngine,
        toolConfig: VoiceToolExecutor.Configuration
    ) {
        self.sttEngine = stt
        self.llmClient = llm
        self.llmModel = model
        self.ttsEngine = tts
        self.fallbackTTS = fallbackTTS
        self.toolExecutor = toolConfig
    }

    func process(turn: VoiceTurnInput) -> AsyncStream<VoicePipelineEvent> {
        AsyncStream { continuation in
            let task = Task { [sttEngine, llmClient, llmModel, ttsEngine, fallbackTTS, toolExecutor] in
                do {
                    // 1. Resample audio 48kHz → 16kHz
                    let samples16k = AudioResampler.resample(turn.audioSamples, from: turn.sampleRate, to: 16000)
                    guard !samples16k.isEmpty else {
                        continuation.yield(.finished)
                        continuation.finish()
                        return
                    }

                    try Task.checkCancellation()

                    // 2. Transcribe with STT engine, speculatively pre-fetching context
                    let (transcript, speculativeContext) = await Self.transcribeWithPrefetch(
                        samples: samples16k,
                        engine: sttEngine,
                        contextProvider: turn.contextProvider,
                        continuation: continuation
                    )
                    guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        continuation.yield(.finished)
                        continuation.finish()
                        return
                    }
                    continuation.yield(.transcribed(transcript))

                    try Task.checkCancellation()

                    // 3. Use speculative context if available, else fetch fresh
                    let enrichedPrompt: String
                    if let speculative = speculativeContext {
                        // Check if speculative result is still valid for the full transcript
                        enrichedPrompt = speculative
                        Self.logger.debug("Using speculative context from partial transcript")
                    } else {
                        enrichedPrompt = await turn.contextProvider(transcript)
                    }
                    let systemPrompt = enrichedPrompt.isEmpty ? turn.baseSystemPrompt : enrichedPrompt

                    // 4. Build messages
                    var messages = turn.conversationHistory
                    if !messages.isEmpty, messages[0].role == "system" {
                        messages[0] = LLMChatMessage(role: "system", content: systemPrompt)
                    }
                    messages.append(LLMChatMessage(role: "user", content: transcript))

                    try Task.checkCancellation()

                    // 5. Stream LLM response with sentence-level TTS
                    var fullResponse = ""
                    var sentenceBuffer = ""
                    let stream = await llmClient.chatStream(messages: messages, model: llmModel)

                    do {
                        for try await chunk in stream {
                            try Task.checkCancellation()
                            fullResponse += chunk
                            sentenceBuffer += chunk
                            continuation.yield(.responseChunk(chunk))

                            // Check for sentence boundaries and synthesize each sentence
                            while let range = sentenceBuffer.rangeOfSentenceBoundary() {
                                let sentence = String(sentenceBuffer[sentenceBuffer.startIndex..<range.upperBound])
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                sentenceBuffer = String(sentenceBuffer[range.upperBound...])

                                // Strip tool markers before TTS so <tool>...</tool> blocks aren't spoken
                                let cleaned = VoiceToolExecutor.stripToolMarkers(sentence)
                                if !cleaned.isEmpty {
                                    do {
                                        let audio = try await ttsEngine.synthesize(cleaned)
                                        if !audio.isEmpty {
                                            continuation.yield(.audioReady(audio))
                                        }
                                    } catch {
                                        Self.logger.warning("Primary TTS failed for sentence, trying fallback: \(error)")
                                        if let audio = try? await fallbackTTS.synthesize(cleaned), !audio.isEmpty {
                                            continuation.yield(.audioReady(audio))
                                        }
                                    }
                                }
                            }
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        Self.logger.error("LLM stream failed: \(error)")
                        fullResponse = "Sorry, I had trouble with that."
                        sentenceBuffer = fullResponse
                    }

                    // Flush remaining text in buffer
                    let remaining = sentenceBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !remaining.isEmpty {
                        let cleaned = VoiceToolExecutor.stripToolMarkers(remaining)
                        if !cleaned.isEmpty {
                            do {
                                let audio = try await ttsEngine.synthesize(cleaned)
                                if !audio.isEmpty {
                                    continuation.yield(.audioReady(audio))
                                }
                            } catch {
                                Self.logger.warning("Primary TTS failed for remaining text, trying fallback: \(error)")
                                if let audio = try? await fallbackTTS.synthesize(cleaned), !audio.isEmpty {
                                    continuation.yield(.audioReady(audio))
                                }
                            }
                        }
                    }

                    try Task.checkCancellation()

                    // 6. Tool execution (on full response)
                    let toolResult: VoiceToolExecutor.Result
                    if let context = toolExecutor.modelContext {
                        toolResult = await MainActor.run {
                            VoiceToolExecutor.process(response: fullResponse, modelContext: context)
                        }
                    } else {
                        toolResult = VoiceToolExecutor.Result(spokenResponse: fullResponse, executedActions: [])
                    }

                    continuation.yield(.responseComplete(toolResult.spokenResponse))

                    if !toolResult.executedActions.isEmpty {
                        let summary = toolResult.executedActions.joined(separator: ", ")
                        continuation.yield(.toolResult(summary))
                        Self.logger.info("Voice tools executed: \(summary)")
                    }

                    continuation.yield(.finished)
                } catch is CancellationError {
                    Self.logger.debug("Local pipeline cancelled")
                    continuation.yield(.finished)
                } catch {
                    Self.logger.error("Local pipeline error: \(error.localizedDescription)")
                    continuation.yield(.error(error.localizedDescription))
                    continuation.yield(.finished)
                }
                continuation.finish()
            }
            self.currentTaskMutex.withLock { $0 = task }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func warmup() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [sttEngine] in
                do {
                    try await sttEngine.preload()
                } catch {
                    Self.logger.warning("STT preload failed (will attempt lazy init): \(error)")
                }
            }
            group.addTask { [ttsEngine] in await ttsEngine.warmup() }
        }
    }

    func cancel() {
        currentTaskMutex.withLock { task in
            task?.cancel()
            task = nil
        }
        ttsEngine.stop()
    }

    /// Unload heavy models (TTS, STT) to free memory after session ends.
    func unloadModels() async {
        await ttsEngine.unloadModel()
        Self.logger.info("Voice pipeline models unloaded")
    }

    /// Transcribe audio, starting a speculative context pre-fetch once enough words are recognized.
    /// Returns (finalTranscript, speculativeContextResult).
    private static func transcribeWithPrefetch(
        samples: [Float],
        engine: any STTEngine,
        contextProvider: @Sendable @escaping (String) async -> String,
        continuation: AsyncStream<VoicePipelineEvent>.Continuation
    ) async -> (String, String?) {
        let chunk = AudioChunk(samples: samples, sampleRate: 16000, timestamp: 0)
        let stream = engine.transcribe(audioStream: AsyncStream { c in
            c.yield(chunk)
            c.finish()
        })

        var words: [String] = []
        var lastPartial = ""
        var prefetchTask: Task<String, Never>?
        var prefetchPartial = ""
        let prefetchThreshold = 3 // Start prefetch after N words

        for await word in stream {
            words.append(word.word)
            let partial = words.joined(separator: " ")
            if partial != lastPartial {
                continuation.yield(.partialTranscript(partial))
                lastPartial = partial
            }

            // Kick off speculative context fetch once we have enough words
            if words.count == prefetchThreshold && prefetchTask == nil {
                let partialText = partial
                prefetchPartial = partialText
                prefetchTask = Task {
                    await contextProvider(partialText)
                }
            }
        }

        let finalTranscript = words.joined(separator: " ")

        // Determine if speculative result is usable
        guard let task = prefetchTask else {
            return (finalTranscript, nil)
        }

        // If final transcript is very different from what we prefetched with, discard
        let finalTokens = Set(finalTranscript.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })
        let prefetchTokens = Set(prefetchPartial.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 })

        // If partial tokens are a subset of (or mostly overlap with) final tokens, the prefetch is valid
        let overlap = prefetchTokens.intersection(finalTokens).count
        let isValid = !prefetchTokens.isEmpty && overlap >= prefetchTokens.count / 2

        if isValid {
            let result = await task.value
            return (finalTranscript, result.isEmpty ? nil : result)
        } else {
            task.cancel()
            logger.debug("Speculative context discarded — transcript diverged from partial")
            return (finalTranscript, nil)
        }
    }
}

// MARK: - VoiceToolExecutor Configuration

extension VoiceToolExecutor {
    struct Configuration: @unchecked Sendable {
        let modelContext: ModelContext?
    }
}

// MARK: - Sentence Boundary Detection

private extension String {
    /// Find the first sentence boundary (. ! ? followed by space/newline/end).
    func rangeOfSentenceBoundary() -> Range<String.Index>? {
        for i in indices {
            let char = self[i]
            guard char == "." || char == "!" || char == "?" else { continue }

            // Don't split on abbreviations like "Dr.", "Mr.", "e.g.", numbers like "3.5"
            // Simple heuristic: require at least 15 chars before the split point
            let distance = self.distance(from: startIndex, to: i)
            guard distance >= 15 else { continue }

            let nextIndex = index(after: i)
            if nextIndex == endIndex {
                // Punctuation at end of string — this is a boundary
                return i..<nextIndex
            }
            if nextIndex < endIndex {
                let next = self[nextIndex]
                if next == " " || next == "\n" {
                    return i..<index(after: nextIndex) // Include the space/newline
                }
            }
        }
        return nil
    }
}

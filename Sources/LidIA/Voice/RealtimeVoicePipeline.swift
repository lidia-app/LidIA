import Foundation
import Synchronization
import os

/// VoicePipeline using OpenAI Realtime WebSocket API (audio-in → audio-out).
/// No tool execution — text and audio arrive together from the WebSocket (D2).
/// @unchecked Sendable is safe: `client` and `voice` are immutable,
/// `currentTask` is protected by a Mutex.
final class RealtimeVoicePipeline: VoicePipeline, @unchecked Sendable {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "RealtimeVoicePipeline")

    private let client: RealtimeVoiceClient
    private let voice: String
    private let currentTaskMutex = Mutex<Task<Void, Never>?>(nil)

    init(apiKey: String, voice: String = "nova") {
        self.client = RealtimeVoiceClient(apiKey: apiKey)
        self.voice = voice
    }

    func process(turn: VoiceTurnInput) -> AsyncStream<VoicePipelineEvent> {
        AsyncStream { continuation in
            let task = Task { [client, voice] in
                do {
                    // 1. Send audio and get transcript
                    let transcript = try await client.completeTurn(
                        samples: turn.audioSamples,
                        sourceSampleRate: turn.sampleRate,
                        voice: voice,
                        instructions: turn.baseSystemPrompt
                    )
                    continuation.yield(.transcribed(transcript))

                    try Task.checkCancellation()

                    // 2. Generate response (text + audio together)
                    let result = try await client.generateResponse(
                        for: transcript,
                        voice: voice,
                        instructions: turn.baseSystemPrompt
                    )

                    // 3. Yield response text (no tool stripping — D2)
                    continuation.yield(.responseComplete(result.text))

                    // 4. Yield audio if available
                    if let wavData = result.wavAudioData {
                        continuation.yield(.audioReady(wavData))
                    }

                    continuation.yield(.finished)
                } catch is CancellationError {
                    Self.logger.debug("Realtime pipeline cancelled")
                    continuation.yield(.finished)
                } catch {
                    Self.logger.error("Realtime pipeline error: \(error.localizedDescription)")
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
        // No-op: OpenAI Realtime doesn't need local model pre-loading.
    }

    func cancel() {
        currentTaskMutex.withLock { task in
            task?.cancel()
            task = nil
        }
        Task { await client.disconnect() }
    }
}

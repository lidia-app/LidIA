import Foundation
import LidIAKit

/// Contract for voice processing pipelines (local STT→LLM→TTS or cloud realtime).
protocol VoicePipeline: Sendable {
    /// Process a single voice turn, yielding events as processing progresses.
    func process(turn: VoiceTurnInput) -> AsyncStream<VoicePipelineEvent>
    /// Cooperatively cancel the current turn.
    func cancel()
    /// Pre-warm models (STT, TTS) so the first turn is fast.
    func warmup() async
}

/// Input for a single voice turn.
struct VoiceTurnInput: Sendable {
    /// Raw audio samples captured from the microphone.
    let audioSamples: [Float]
    /// Sample rate of the audio (typically 48000 Hz).
    let sampleRate: Int
    /// Conversation history for multi-turn dialogue.
    let conversationHistory: [LLMChatMessage]
    /// Base system prompt (personalization, SOUL.md, etc).
    let baseSystemPrompt: String
    /// Called from a non-main-actor context (pipeline background task).
    /// Takes the transcript text, returns enriched system prompt with meeting context.
    /// Implementation should use `await MainActor.run { ... }` internally.
    let contextProvider: @Sendable (String) async -> String
}

/// Events emitted by a voice pipeline during turn processing.
enum VoicePipelineEvent: Sendable {
    /// Unconfirmed partial transcript token (show grayed/italic in floating transcript).
    case partialTranscript(String)
    /// Confirmed transcription of user's speech.
    case transcribed(String)
    /// Streaming LLM response token.
    case responseChunk(String)
    /// Complete response text after tool processing.
    case responseComplete(String)
    /// Synthesized audio data (WAV format) ready for playback.
    case audioReady(Data)
    /// Tool execution result description.
    case toolResult(String)
    /// Error during processing.
    case error(String)
    /// Turn processing is complete.
    case finished
}

import Foundation

protocol STTEngine: Sendable {
    func transcribe(audioStream: AsyncStream<AudioChunk>) -> AsyncStream<TranscriptWord>
    /// Pre-load models so the first transcription call is fast. Default: no-op.
    func preload() async throws
}

extension STTEngine {
    func preload() async throws {}
}

#if DEBUG
/// Mock STT engine for testing. Thread-safe: mockWords is immutable after init.
final class MockSTTEngine: STTEngine, Sendable {
    let mockWords: [TranscriptWord]

    init(mockWords: [TranscriptWord] = []) {
        self.mockWords = mockWords
    }

    func transcribe(audioStream: AsyncStream<AudioChunk>) -> AsyncStream<TranscriptWord> {
        let words = mockWords
        return AsyncStream { continuation in
            for word in words {
                continuation.yield(word)
            }
            continuation.finish()
        }
    }
}
#endif

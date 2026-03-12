import Testing
@testable import LidIA

@Test func mockSTTEngineWorks() async throws {
    let words = [
        TranscriptWord(word: "hello", start: 0, end: 0.5, confidence: 0.9, speaker: nil),
        TranscriptWord(word: "world", start: 0.5, end: 1.0, confidence: 0.85, speaker: nil),
    ]
    let engine = MockSTTEngine(mockWords: words)

    var received: [TranscriptWord] = []
    let stream = engine.transcribe(audioStream: AsyncStream { $0.finish() })
    for await word in stream {
        received.append(word)
    }
    #expect(received.count == 2)
    #expect(received[0].word == "hello")
}

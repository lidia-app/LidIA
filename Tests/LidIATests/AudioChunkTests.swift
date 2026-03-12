import Testing
@testable import LidIA

@Test func audioChunkCreation() async throws {
    let samples: [Float] = [0.1, 0.2, 0.3, -0.1, -0.2]
    let chunk = AudioChunk(samples: samples, sampleRate: 16000, timestamp: 1.0)
    #expect(chunk.samples.count == 5)
    #expect(chunk.sampleRate == 16000)
    #expect(chunk.timestamp == 1.0)
}

@Test func audioChunkDuration() async throws {
    let samples = [Float](repeating: 0.0, count: 16000)
    let chunk = AudioChunk(samples: samples, sampleRate: 16000, timestamp: 0)
    #expect(chunk.duration == 1.0)
}

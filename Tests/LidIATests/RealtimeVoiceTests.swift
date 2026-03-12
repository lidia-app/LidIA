import Foundation
import Testing
@testable import LidIA

@Test func voiceBackendSelectionPrefersRealtimeWhenOpenAIIsConfigured() {
    #expect(VoiceAssistantBackend.resolve(ttsProvider: .openai, openAIAPIKey: "sk-test") == .openAIRealtime)
    #expect(VoiceAssistantBackend.resolve(ttsProvider: .openai, openAIAPIKey: "") == .localPipeline)
    #expect(VoiceAssistantBackend.resolve(ttsProvider: .system, openAIAPIKey: "sk-test") == .localPipeline)
}

@Test func realtimeVoiceClientBuildsPCM16InputPayload() throws {
    let samples: [Float] = [-1.2, -0.5, 0, 0.5, 1.2]
    let payload = try #require(RealtimeVoiceClient.inputAudioAppendEvent(samples: samples, sourceSampleRate: 24_000)["audio"] as? String)
    let data = try #require(Data(base64Encoded: payload))
    let pcm = data.withUnsafeBytes { buffer in
        stride(from: 0, to: buffer.count, by: 2).map { offset -> Int16 in
            buffer.load(fromByteOffset: offset, as: Int16.self)
        }
    }

    #expect(pcm.count > 0)
    #expect(pcm.first == Int16.min)
    #expect(pcm.last == Int16.max)
}

@Test func realtimeVoiceClientParsesCoreServerEvents() throws {
    let audioEvent = try #require(RealtimeVoiceClient.parseServerEvent(from: Data("{\"type\":\"response.audio.delta\",\"delta\":\"QUJD\"}".utf8)))
    #expect(audioEvent == .audioDelta(Data("ABC".utf8)))

    let textEvent = try #require(RealtimeVoiceClient.parseServerEvent(from: Data("{\"type\":\"response.text.delta\",\"delta\":\"Hi\"}".utf8)))
    #expect(textEvent == .textDelta("Hi"))

    let transcriptEvent = try #require(RealtimeVoiceClient.parseServerEvent(from: Data("{\"type\":\"conversation.item.input_audio_transcription.completed\",\"transcript\":\"hello there\"}".utf8)))
    #expect(transcriptEvent == .inputTranscript("hello there"))
}

import Foundation
import LidIAKit
import Testing
@testable import LidIA

@Test func voiceTurnInputStoresLidIAKitHistoryAndPipelineEventsPreservePayloads() async {
    let history: [LidIA.LLMChatMessage] = [
        LidIA.LLMChatMessage(role: "user", content: "What changed?"),
        LidIA.LLMChatMessage(role: "assistant", content: "Budget moved."),
    ]

    let input = VoiceTurnInput(
        audioSamples: [0.1, -0.1, 0.25],
        sampleRate: 24_000,
        conversationHistory: history,
        baseSystemPrompt: "Keep answers short.",
        contextProvider: { query in
            "Context for \(query)"
        }
    )

    #expect(input.audioSamples == [0.1, -0.1, 0.25])
    #expect(input.sampleRate == 24_000)
    #expect(input.conversationHistory.map { $0.role } == ["user", "assistant"])
    #expect(input.conversationHistory.map { $0.content } == ["What changed?", "Budget moved."])
    #expect(input.baseSystemPrompt == "Keep answers short.")
    #expect(await input.contextProvider("budget") == "Context for budget")

    #expect({
        if case .partialTranscript("par") = VoicePipelineEvent.partialTranscript("par") { true } else { false }
    }())
    #expect({
        if case .transcribed("full") = VoicePipelineEvent.transcribed("full") { true } else { false }
    }())
    #expect({
        if case .responseChunk("chunk") = VoicePipelineEvent.responseChunk("chunk") { true } else { false }
    }())
    #expect({
        if case .responseComplete("done") = VoicePipelineEvent.responseComplete("done") { true } else { false }
    }())
    #expect({
        if case .audioReady(Data([1, 2, 3])) = VoicePipelineEvent.audioReady(Data([1, 2, 3])) { true } else { false }
    }())
    #expect({
        if case .toolResult("created note") = VoicePipelineEvent.toolResult("created note") { true } else { false }
    }())
    #expect({
        if case .error("failed") = VoicePipelineEvent.error("failed") { true } else { false }
    }())
    #expect({
        if case .finished = VoicePipelineEvent.finished { true } else { false }
    }())
}

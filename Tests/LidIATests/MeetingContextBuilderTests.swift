import Testing
@testable import LidIA

// MARK: - Grounding & Source Derivation Tests

/// Tests for MeetingContextBuilder's pure logic: source title derivation and grounding confidence.
/// These avoid SwiftData by testing only the non-fetch methods.
@Suite("MeetingContextBuilder")
struct MeetingContextBuilderTests {

    // MARK: - deriveSourceTitles

    @MainActor
    @Test("Returns explicit matches when answer mentions candidate titles")
    func deriveSourceTitlesExplicitMatch() {
        let builder = MeetingContextBuilder()
        let answer = "In the Sprint Planning meeting, we discussed the roadmap."
        let candidates = ["Sprint Planning", "Design Review", "1:1 Check-in"]

        let result = builder.deriveSourceTitles(answer: answer, candidateTitles: candidates)
        #expect(result == ["Sprint Planning"])
    }

    @MainActor
    @Test("Returns multiple explicit matches when answer mentions several titles")
    func deriveSourceTitlesMultipleMatches() {
        let builder = MeetingContextBuilder()
        let answer = "Both the Sprint Planning and Design Review meetings covered that topic."
        let candidates = ["Sprint Planning", "Design Review", "1:1 Check-in"]

        let result = builder.deriveSourceTitles(answer: answer, candidateTitles: candidates)
        #expect(result.contains("Sprint Planning"))
        #expect(result.contains("Design Review"))
        #expect(result.count == 2)
    }

    @MainActor
    @Test("Falls back to first 3 candidates when no explicit match found")
    func deriveSourceTitlesFallback() {
        let builder = MeetingContextBuilder()
        let answer = "The team agreed to prioritize latency improvements."
        let candidates = ["Meeting A", "Meeting B", "Meeting C", "Meeting D"]

        let result = builder.deriveSourceTitles(answer: answer, candidateTitles: candidates)
        #expect(result == ["Meeting A", "Meeting B", "Meeting C"])
    }

    @MainActor
    @Test("Returns empty array when no candidates provided")
    func deriveSourceTitlesEmpty() {
        let builder = MeetingContextBuilder()
        let result = builder.deriveSourceTitles(answer: "Some answer", candidateTitles: [])
        #expect(result.isEmpty)
    }

    @MainActor
    @Test("Case-insensitive matching for source titles")
    func deriveSourceTitlesCaseInsensitive() {
        let builder = MeetingContextBuilder()
        let answer = "In the sprint planning session, we agreed on priorities."
        let candidates = ["Sprint Planning"]

        let result = builder.deriveSourceTitles(answer: answer, candidateTitles: candidates)
        #expect(result == ["Sprint Planning"])
    }

    @MainActor
    @Test("Caps explicit matches at 4")
    func deriveSourceTitlesCapsAt4() {
        let builder = MeetingContextBuilder()
        let candidates = ["A", "B", "C", "D", "E"]
        let answer = "Discussed in A, B, C, D, and E meetings."

        let result = builder.deriveSourceTitles(answer: answer, candidateTitles: candidates)
        #expect(result.count == 4)
    }

    // MARK: - deriveGroundingConfidence

    @MainActor
    @Test("High confidence with 2+ sources")
    func groundingConfidenceHigh() {
        let builder = MeetingContextBuilder()
        let confidence = builder.deriveGroundingConfidence(answer: "The team agreed.", sourceCount: 3)
        #expect(confidence == .high)
    }

    @MainActor
    @Test("Medium confidence with exactly 1 source")
    func groundingConfidenceMedium() {
        let builder = MeetingContextBuilder()
        let confidence = builder.deriveGroundingConfidence(answer: "Based on the meeting.", sourceCount: 1)
        #expect(confidence == .medium)
    }

    @MainActor
    @Test("Low confidence with 0 sources")
    func groundingConfidenceLow() {
        let builder = MeetingContextBuilder()
        let confidence = builder.deriveGroundingConfidence(answer: "I'm not sure.", sourceCount: 0)
        #expect(confidence == .low)
    }

    @MainActor
    @Test("Low confidence when answer contains error marker")
    func groundingConfidenceLowOnError() {
        let builder = MeetingContextBuilder()
        let confidence = builder.deriveGroundingConfidence(answer: "[error: something failed]", sourceCount: 5)
        #expect(confidence == .low)
    }

    @MainActor
    @Test("Low confidence when answer indicates insufficient evidence")
    func groundingConfidenceLowOnInsufficientEvidence() {
        let builder = MeetingContextBuilder()

        let phrases = [
            "There is insufficient evidence to answer.",
            "I don't have enough information to determine that.",
            "There is not enough information available.",
            "I cannot determine the answer from the context.",
        ]

        for phrase in phrases {
            let confidence = builder.deriveGroundingConfidence(answer: phrase, sourceCount: 3)
            #expect(confidence == .low, "Expected .low for: \(phrase)")
        }
    }

    // MARK: - buildContextBundle edge cases (no modelContext configured)

    @MainActor
    @Test("Returns no-evidence bundle for selectedMeeting scope when no meeting selected")
    func buildContextBundleNoSelectedMeeting() {
        let builder = MeetingContextBuilder()
        let bundle = builder.buildContextBundle(for: "test query", scope: .selectedMeeting)
        #expect(!bundle.hasEvidence)
        #expect(bundle.candidateSourceTitles.isEmpty)
        #expect(bundle.contextText.contains("No selected meeting"))
    }

    @MainActor
    @Test("Returns no-evidence bundle for allMeetings scope when no modelContext")
    func buildContextBundleNoModelContext() {
        let builder = MeetingContextBuilder()
        let bundle = builder.buildContextBundle(for: "test query", scope: .allMeetings)
        #expect(!bundle.hasEvidence)
        #expect(bundle.candidateSourceTitles.isEmpty)
    }

    @MainActor
    @Test("Returns no-evidence bundle for myNotes scope when no modelContext")
    func buildContextBundleNoModelContextNotes() {
        let builder = MeetingContextBuilder()
        let bundle = builder.buildContextBundle(for: "test query", scope: .myNotes)
        #expect(!bundle.hasEvidence)
    }
}

import SwiftUI

struct LiveTranscriptView: View {
    let words: [TranscriptWord]
    var localSpeakerName: String = "Me"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(utterances.enumerated()), id: \.offset) { index, utterance in
                        utteranceBubble(utterance)
                            .id("utterance-\(index)")
                    }
                }
                .id("transcript-bottom")
            }
            .onChange(of: words.count) {
                withAnimation {
                    proxy.scrollTo("transcript-bottom", anchor: .bottom)
                }
            }
        }
    }

    private struct Utterance {
        let text: String
        let isLocal: Bool?
        let speakerName: String
    }

    private var utterances: [Utterance] {
        guard !words.isEmpty else { return [] }

        var result: [Utterance] = []
        var currentWords: [String] = []
        var currentIsLocal: Bool? = words[0].isLocalSpeaker
        var lastTimestamp: TimeInterval = words[0].end

        for word in words {
            let speakerChanged = word.isLocalSpeaker != currentIsLocal
            let gapTooLong = word.start - lastTimestamp > 2.0
            let tooManyWords = currentWords.count >= 50

            if (speakerChanged || gapTooLong || tooManyWords) && !currentWords.isEmpty {
                result.append(Utterance(
                    text: currentWords.joined(separator: " "),
                    isLocal: currentIsLocal,
                    speakerName: currentIsLocal == true ? localSpeakerName : "Others"
                ))
                currentWords.removeAll(keepingCapacity: true)
                currentIsLocal = word.isLocalSpeaker
            }

            currentWords.append(word.word)
            lastTimestamp = word.end
        }

        if !currentWords.isEmpty {
            result.append(Utterance(
                text: currentWords.joined(separator: " "),
                isLocal: currentIsLocal,
                speakerName: currentIsLocal == true ? localSpeakerName : "Others"
            ))
        }

        return result
    }

    private func utteranceBubble(_ utterance: Utterance) -> some View {
        let isLocal = utterance.isLocal == true
        let color: Color = isLocal ? .blue : .secondary

        return VStack(alignment: isLocal ? .trailing : .leading, spacing: 2) {
            Text(utterance.speakerName)
                .font(.caption2.bold())
                .foregroundStyle(color.opacity(0.7))

            Text(utterance.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: isLocal ? .trailing : .leading)
    }
}

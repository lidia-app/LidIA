import SwiftUI

struct LiveTranscriptView: View {
    let words: [TranscriptWord]
    var localSpeakerName: String = "Me"

    @State private var pinnedToBottom = true
    @State private var showJumpButton = false

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(utterances.enumerated()), id: \.offset) { index, utterance in
                            utteranceBubble(utterance)
                                .id("utterance-\(index)")
                        }
                    }
                    .id("transcript-bottom")
                }
                .onScrollGeometryChange(for: Bool.self) { geo in
                    let maxOffset = max(0, geo.contentSize.height - geo.containerSize.height)
                    return (maxOffset - geo.contentOffset.y) < 40
                } action: { _, isPinned in
                    pinnedToBottom = isPinned
                    if isPinned { showJumpButton = false }
                }
                .onChange(of: words.count) {
                    guard pinnedToBottom else {
                        if !words.isEmpty { showJumpButton = true }
                        return
                    }
                    withAnimation {
                        proxy.scrollTo("transcript-bottom", anchor: .bottom)
                    }
                }

                if showJumpButton {
                    Button {
                        withAnimation {
                            proxy.scrollTo("transcript-bottom", anchor: .bottom)
                        }
                        showJumpButton = false
                    } label: {
                        Label("Jump to latest", systemImage: "arrow.down.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.glassProminent)
                    .padding(12)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: showJumpButton)
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
            let gap = word.start - lastTimestamp
            // Only split on speaker change if there's a meaningful gap (>1.5s)
            // to avoid splitting on every interleaved mic/system word in dual-stream
            let speakerChanged = word.isLocalSpeaker != currentIsLocal && gap > 1.5
            let gapTooLong = gap > 2.0
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

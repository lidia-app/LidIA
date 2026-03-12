import SwiftUI
import AppKit

/// The SwiftUI content displayed inside the floating transcript panel.
/// Shows a live-scrolling transcript, elapsed time with waveform animation,
/// and close / copy-transcript buttons.
///
/// Accepts the `RecordingSession` directly so the view observes live updates
/// via the `@Observable` conformance on the session.
struct FloatingTranscriptView: View {
    var session: RecordingSession
    let onClose: () -> Void

    /// Only the last N words are rendered for performance.
    private let tailCount = 50

    private var tailWords: [TranscriptWord] {
        let words = session.transcriptWords
        if words.count <= tailCount {
            return words
        }
        return Array(words.suffix(tailCount))
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(formatTime(session.elapsedTime))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: true)
                    .foregroundStyle(.red)
                    .font(.caption)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Hide panel (recording continues)")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()

            // MARK: - Transcript
            ScrollViewReader { proxy in
                ScrollView {
                    Text(buildAttributedText())
                        .font(.system(.callout))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .id("floating-transcript-bottom")
                }
                .onChange(of: session.transcriptWords.count) {
                    withAnimation {
                        proxy.scrollTo("floating-transcript-bottom", anchor: .bottom)
                    }
                }
            }

            Divider()

            // MARK: - Footer
            HStack {
                Spacer()
                Button {
                    copyTranscript()
                } label: {
                    Label("Copy Transcript", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy full transcript to clipboard")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 360, height: 280)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Helpers

    private func buildAttributedText() -> AttributedString {
        var result = AttributedString()
        for (index, word) in tailWords.enumerated() {
            var wordStr = AttributedString(word.word)
            if word.confidence < 0.5 {
                wordStr.foregroundColor = .secondary
            }
            result.append(wordStr)
            if index < tailWords.count - 1 {
                result.append(AttributedString(" "))
            }
        }
        return result
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func copyTranscript() {
        let text = session.transcriptWords.map(\.word).joined(separator: " ")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

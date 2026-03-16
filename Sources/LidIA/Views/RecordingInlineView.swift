import SwiftUI

struct RecordingInlineView: View {
    @Environment(RecordingSession.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 16) {
            // Elapsed time
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(formatTime(session.elapsedTime))
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(.primary)
            }

            // Live waveform
            LiveWaveformView(isActive: session.isRecording && !session.isPaused)
                .frame(height: 60)
                .padding(.horizontal, 20)

            // Word count
            Text("\(session.transcriptWords.count) words captured")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Controls
            HStack(spacing: 24) {
                // Pause / Resume
                Button {
                    if session.isPaused {
                        session.resumeRecording()
                    } else {
                        session.pauseRecording()
                    }
                } label: {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .help(session.isPaused ? "Resume recording" : "Pause recording")

                // Stop
                Button {
                    session.stopRecording(
                        modelContext: modelContext,
                        settings: settings
                    )
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.glass)
                .help("Stop recording")
            }

            // Status
            if session.isPaused {
                Text("Paused")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

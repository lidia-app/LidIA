import SwiftUI

struct RecordingControlsView: View {
    let isRecording: Bool
    @Namespace private var controlsNamespace
    let onStart: () -> Void
    let onStop: () -> Void
    let elapsedTime: TimeInterval

    var body: some View {
        GlassEffectContainer(spacing: 20) {
            if !isRecording {
                Button {
                    withAnimation(.bouncy) {
                        onStart()
                    }
                } label: {
                    Label("Start Recording", systemImage: "mic.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .glassEffectID("record", in: controlsNamespace)
            } else {
                HStack(spacing: 12) {
                    Text(formatTime(elapsedTime))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: isRecording)
                        .foregroundStyle(.red)

                    Button {
                        withAnimation(.bouncy) {
                            onStop()
                        }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .glassEffectID("stop", in: controlsNamespace)
                }
                .glassEffectID("record", in: controlsNamespace)
            }
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

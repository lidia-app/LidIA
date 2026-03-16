import SwiftUI

struct RecordingSettingsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Section("Recording") {
            Picker("Audio Capture", selection: $settings.audioCaptureMode) {
                ForEach(AudioCaptureMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            if settings.audioCaptureMode == .micAndSystem {
                Text("Captures both your microphone and the other participants' audio from meeting apps. Requires Screen Recording permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Only captures your microphone. Other participants won't be transcribed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Auto-stop on silence", isOn: $settings.autoStopOnSilence)

            if settings.autoStopOnSilence {
                HStack {
                    Text("Timeout")
                    Slider(
                        value: $settings.silenceTimeoutSeconds,
                        in: 5...120,
                        step: 5
                    )
                    Text("\(Int(settings.silenceTimeoutSeconds))s")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }

            TextField("Your Name", text: $settings.displayName)
                .textFieldStyle(.roundedBorder)
            Text("Shown as your speaker label in transcripts. Leave blank for \"Me\".")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Audio Enhancement") {
            Toggle("Noise Reduction", isOn: $settings.noiseReductionEnabled)
            Text("Reduces background noise before transcription using DeepFilterNet. May add processing time.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if settings.noiseReductionEnabled {
                Label("Available after next dependency update", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}

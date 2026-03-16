import SwiftUI
import SwiftData
import Speech
import AVFoundation
import LidIAKit

struct VoiceNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isRecording = false
    @State private var transcribedText = ""
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var audioEngine: AVAudioEngine?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var permissionGranted = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Timer
                Text(formatTime(elapsedTime))
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundStyle(isRecording ? .primary : .secondary)

                // Waveform indicator
                if isRecording {
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(.red)
                                .frame(width: 4, height: CGFloat.random(in: 8...24))
                                .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true).delay(Double(i) * 0.1), value: isRecording)
                        }
                    }
                    .frame(height: 30)
                }

                // Transcribed text preview
                if !transcribedText.isEmpty {
                    ScrollView {
                        Text(transcribedText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                    .padding(.horizontal)
                }

                Spacer()

                // Controls
                HStack(spacing: 40) {
                    // Cancel
                    Button {
                        stopRecording()
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.subheadline)
                    }
                    .buttonStyle(.glass)

                    // Record / Stop
                    Button {
                        if isRecording {
                            stopRecording()
                        } else {
                            startRecording()
                        }
                    } label: {
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.title)
                            .frame(width: 64, height: 64)
                            .foregroundStyle(isRecording ? .red : .white)
                    }
                    .buttonStyle(.glassProminent)

                    // Save
                    Button {
                        saveNote()
                        dismiss()
                    } label: {
                        Text("Save")
                            .font(.subheadline)
                    }
                    .buttonStyle(.glass)
                    .disabled(transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding()
            .navigationTitle("Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                requestPermissions()
            }
            .onDisappear {
                stopRecording()
            }
        }
    }

    // MARK: - Permissions

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                permissionGranted = status == .authorized
                if status != .authorized {
                    errorMessage = "Speech recognition permission required."
                }
            }
        }
    }

    // MARK: - Recording

    private func startRecording() {
        guard permissionGranted else {
            errorMessage = "Speech recognition not authorized."
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            errorMessage = "Speech recognizer not available."
            return
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            errorMessage = "Audio engine failed: \(error.localizedDescription)"
            return
        }

        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                Task { @MainActor in
                    transcribedText = result.bestTranscription.formattedString
                }
            }
            if error != nil {
                Task { @MainActor in
                    stopRecording()
                }
            }
        }

        self.audioEngine = engine
        self.recognitionRequest = request
        self.recognitionTask = task
        isRecording = true
        elapsedTime = 0

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                elapsedTime += 1
            }
        }
    }

    private func stopRecording() {
        timer?.invalidate()
        timer = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
    }

    // MARK: - Save

    private func saveNote() {
        let text = transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let meeting = Meeting(
            title: "Voice Note",
            date: .now,
            duration: elapsedTime,
            summary: text,
            status: .complete
        )
        meeting.notes = text
        modelContext.insert(meeting)
        try? modelContext.save()
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let mins = Int(interval) / 60
        let secs = Int(interval) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

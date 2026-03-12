import SwiftUI
import SwiftData
import AVFoundation
import LidIAKit

/// Thread-safe buffer for audio samples. The audio tap writes here from the
/// render thread; MainActor reads when the user taps to send.
private final class AudioSampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var _samples: [Float] = []
    private var _rms: Float = 0

    var rms: Float {
        lock.lock()
        defer { lock.unlock() }
        return _rms
    }

    func append(samples: [Float], rms: Float) {
        lock.lock()
        _samples.append(contentsOf: samples)
        _rms = rms
        lock.unlock()
    }

    func drainSamples() -> [Float] {
        lock.lock()
        let result = _samples
        _samples = []
        lock.unlock()
        return result
    }

    func reset() {
        lock.lock()
        _samples = []
        _rms = 0
        lock.unlock()
    }
}

struct VoiceModeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(iOSSettings.self) private var settings

    enum VoiceState {
        case idle        // Waiting for tap
        case listening   // Recording audio
        case thinking    // Processing with OpenAI
        case responding  // Playing response
    }

    @State private var voiceState: VoiceState = .idle
    @State private var transcript = ""
    @State private var responseText = ""
    @State private var errorMessage: String?
    @State private var audioEngine: AVAudioEngine?
    @State private var realtimeClient: RealtimeVoiceClient?
    @State private var audioLevel: Float = 0
    @State private var levelTimer: Timer?

    private let sampleBuffer = AudioSampleBuffer()

    // Colors
    private let magenta = Color(red: 1.0, green: 0.31, blue: 0.64)
    private let coral = Color(red: 1.0, green: 0.37, blue: 0.48)
    private let cyan = Color(red: 0.50, green: 0.91, blue: 1.0)
    private let deepPurple = Color(red: 0.16, green: 0.05, blue: 0.43)
    private let blue = Color(red: 0.06, green: 0.30, blue: 0.81)

    var body: some View {
        ZStack {
            deepPurple.opacity(0.95).ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        cleanup()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
                .padding(.trailing, 20)
                .padding(.top, 12)

                Spacer()

                // Response
                if !responseText.isEmpty {
                    ScrollView {
                        Text(responseText)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }
                    .frame(maxHeight: 200)
                    .padding(.bottom, 20)
                }

                // Orb — tap to start/stop
                orbView
                    .padding(.bottom, 16)

                // Status
                Text(statusText)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))

                // Transcript
                if !transcript.isEmpty {
                    Text(transcript)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .lineLimit(3)
                        .padding(.top, 6)
                }

                // Error
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }

                Spacer()
            }
        }
        .onDisappear { cleanup() }
    }

    // MARK: - Orb

    private var orbView: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let baseRadius = min(size.width, size.height) / 2 - 16
                let time = timeline.date.timeIntervalSinceReferenceDate
                drawOrb(context: context, center: center, baseRadius: baseRadius, time: time)
            }
            .frame(width: 220, height: 220)
        }
        .contentShape(Circle())
        .onTapGesture { orbTapped() }
    }

    private var statusText: String {
        switch voiceState {
        case .idle:      return "Tap to speak"
        case .listening: return "Listening — tap to send"
        case .thinking:  return "Thinking..."
        case .responding: return "Speaking..."
        }
    }

    // MARK: - Tap Handler

    private func orbTapped() {
        switch voiceState {
        case .idle:
            startListening()
        case .listening:
            stopAndProcess()
        case .thinking, .responding:
            break // ignore taps while processing
        }
    }

    // MARK: - Start Listening

    private func startListening() {
        guard settings.hasAPIKey else {
            errorMessage = "Add your OpenAI API key in Settings first."
            return
        }

        let permission = AVAudioSession.sharedInstance().recordPermission
        switch permission {
        case .granted:
            beginRecording()
        case .undetermined:
            Task { @MainActor in
                let granted = await AVAudioApplication.requestRecordPermission()
                if granted {
                    beginRecording()
                } else {
                    errorMessage = "Microphone access is needed. Enable in iOS Settings."
                }
            }
        case .denied:
            errorMessage = "Microphone denied. Enable in iOS Settings > LidIA."
        @unknown default:
            errorMessage = "Unable to access microphone."
        }
    }

    private func beginRecording() {
        errorMessage = nil
        transcript = ""
        responseText = ""
        sampleBuffer.reset()
        audioLevel = 0

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            errorMessage = "Audio setup failed: \(error.localizedDescription)"
            return
        }

        let engine = AVAudioEngine()
        self.audioEngine = engine
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let buffer = sampleBuffer
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { pcmBuffer, _ in
            let count = Int(pcmBuffer.frameLength)
            guard let data = pcmBuffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: data, count: count))
            var sum: Float = 0
            for s in samples { sum += s * s }
            let rms = sqrt(sum / max(Float(count), 1))
            buffer.append(samples: samples, rms: rms)
        }

        do {
            try engine.start()
            voiceState = .listening

            // Poll audio level for orb animation
            let buf = sampleBuffer
            levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
                Task { @MainActor in
                    self.audioLevel = min(buf.rms * 4, 1.0)
                }
            }
        } catch {
            errorMessage = "Mic failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Stop & Process

    private func stopAndProcess() {
        guard voiceState == .listening else { return }

        // Stop recording
        levelTimer?.invalidate()
        levelTimer = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioLevel = 0

        let samples = sampleBuffer.drainSamples()
        guard !samples.isEmpty else {
            errorMessage = "No audio captured. Try again."
            voiceState = .idle
            return
        }

        voiceState = .thinking

        // Capture values before async
        let container = modelContext.container
        let apiKey = settings.openaiAPIKey
        let voiceID = settings.ttsVoiceID.isEmpty ? "alloy" : settings.ttsVoiceID
        let instructions = buildInstructions()
        let sampleRate = Int(AVAudioSession.sharedInstance().sampleRate)

        Task { @MainActor in
            do {
                let client = ensureClient(apiKey: apiKey)

                let userTranscript = try await client.completeTurn(
                    samples: samples,
                    sourceSampleRate: sampleRate,
                    voice: voiceID,
                    instructions: instructions
                )
                transcript = userTranscript

                let response = try await client.generateResponse(
                    for: userTranscript,
                    voice: voiceID,
                    instructions: instructions
                )

                let result = VoiceToolExecutor.process(
                    response: response.text,
                    modelContainer: container
                )
                responseText = result.spokenResponse

                // Play audio
                if let wavData = response.wavAudioData {
                    voiceState = .responding
                    await playWAV(wavData)
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            voiceState = .idle
        }
    }

    // MARK: - Audio Playback (on MainActor)

    @MainActor
    private func playWAV(_ data: Data) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            guard let player = try? AVAudioPlayer(data: data) else {
                cont.resume()
                return
            }
            let delegate = PlaybackDelegate { cont.resume() }
            player.delegate = delegate
            objc_setAssociatedObject(player, "d", delegate, .OBJC_ASSOCIATION_RETAIN)
            // Prevent player from being deallocated
            objc_setAssociatedObject(self, "p", player, .OBJC_ASSOCIATION_RETAIN)
            player.prepareToPlay()
            player.play()
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        sampleBuffer.reset()
        if let client = realtimeClient {
            realtimeClient = nil
            Task { await client.disconnect() }
        }
        voiceState = .idle
    }

    private func ensureClient(apiKey: String) -> RealtimeVoiceClient {
        if let existing = realtimeClient { return existing }
        let client = RealtimeVoiceClient(apiKey: apiKey)
        realtimeClient = client
        return client
    }

    // MARK: - Instructions

    private func buildInstructions() -> String {
        var parts = [
            "You are LidIA, a helpful meeting assistant on iOS.",
            "Be concise — the user is on mobile.",
        ]

        let personalization = VoiceToolExecutor.personalizationPrompt(
            displayName: settings.displayName,
            personalityFragment: settings.personalityMode.promptFragment
        )
        if !personalization.isEmpty {
            parts.append(personalization)
        }

        let context = buildMeetingContext()
        if !context.isEmpty {
            parts.append("Meeting context:\n\(context)")
        }

        parts.append(VoiceToolExecutor.toolPrompt)
        return parts.joined(separator: "\n\n")
    }

    private func buildMeetingContext() -> String {
        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let meetings = try? modelContext.fetch(descriptor) else { return "" }
        let completed = meetings.filter { $0.status == .complete }
        guard !completed.isEmpty else { return "" }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return Array(completed.prefix(5)).map { meeting in
            var entry = "## \(meeting.title.isEmpty ? "Untitled" : meeting.title)"
            entry += "\nDate: \(formatter.string(from: meeting.date))"
            let summary = MeetingContextRetrievalService.effectiveSummary(for: meeting)
            if !summary.isEmpty { entry += "\nSummary: \(String(summary.prefix(300)))" }
            if !meeting.actionItems.isEmpty {
                let items = meeting.actionItems.prefix(5).map { "- [\($0.isCompleted ? "x" : " ")] \($0.title)" }
                entry += "\nAction Items:\n\(items.joined(separator: "\n"))"
            }
            return entry
        }.joined(separator: "\n\n")
    }

    // MARK: - Orb Drawing

    private func drawOrb(context: GraphicsContext, center: CGPoint, baseRadius: Double, time: Double) {
        let level = Double(audioLevel)
        let distortion: Double
        let glowRadius: Double
        let gradient: Gradient

        switch voiceState {
        case .idle:
            let breath = sin(time * 2.0) * 0.02 + 1.0
            distortion = 0
            glowRadius = baseRadius * breath
            gradient = Gradient(colors: [magenta.opacity(0.6), cyan.opacity(0.4)])

        case .listening:
            distortion = level * 20
            glowRadius = baseRadius * (1.0 + level * 0.3)
            gradient = Gradient(colors: [magenta, coral, cyan.opacity(0.6)])

        case .thinking:
            let rotate = time.truncatingRemainder(dividingBy: 2.0) / 2.0
            distortion = sin(rotate * .pi * 2) * 8
            glowRadius = baseRadius * (0.9 + sin(time * 3) * 0.05)
            gradient = Gradient(colors: [blue, cyan, magenta.opacity(0.3)])

        case .responding:
            let pulse = sin(time * 4) * 0.05 + 1.0
            distortion = sin(time * 6) * 6
            glowRadius = baseRadius * pulse
            gradient = Gradient(colors: [cyan, magenta.opacity(0.6), coral.opacity(0.4)])
        }

        // Outer glow
        let glowRect = CGRect(
            x: center.x - glowRadius - 10,
            y: center.y - glowRadius - 10,
            width: (glowRadius + 10) * 2,
            height: (glowRadius + 10) * 2
        )
        context.fill(
            Circle().path(in: glowRect),
            with: .radialGradient(
                Gradient(colors: [magenta.opacity(0.3), .clear]),
                center: center,
                startRadius: glowRadius * 0.5,
                endRadius: glowRadius + 20
            )
        )

        // Main orb
        let orbPath = Path { path in
            let segments = 64
            for i in 0...segments {
                let angle = Double(i) / Double(segments) * .pi * 2
                let noise = sin(angle * 3 + time * 4) * distortion
                let r = glowRadius + noise
                let pt = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.closeSubpath()
        }

        context.fill(orbPath, with: .radialGradient(
            gradient, center: center, startRadius: 0, endRadius: glowRadius
        ))
    }
}

private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish() }
}

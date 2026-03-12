import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class VoiceOrbPanelController {
    private var panel: NSPanel?
    private var thinkingPlayer: AVAudioPlayer?
    /// Cached WAV data — generated once, reused on every playThinkingSound() call.
    private static let cachedThinkingToneData: Data? = createThinkingTone()

    private static let positionXKey = "voiceOrb.position.x"
    private static let positionYKey = "voiceOrb.position.y"

    func show(service: VoiceAssistantService) {
        if let panel {
            panel.orderFront(nil)
            return
        }

        let orbView = VoiceOrbContainerView(service: service)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 300),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Restore saved position, or center on screen
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.positionXKey) != nil {
            let x = defaults.double(forKey: Self.positionXKey)
            let y = defaults.double(forKey: Self.positionYKey)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let x = (screen.visibleFrame.width - 240) / 2 + screen.visibleFrame.origin.x
            let y = (screen.visibleFrame.height - 300) / 2 + screen.visibleFrame.origin.y
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.contentView = NSHostingView(rootView: orbView)
        panel.orderFront(nil)
        self.panel = panel
    }

    func close() {
        stopThinkingSound()
        // Save position before closing
        if let panel {
            let origin = panel.frame.origin
            UserDefaults.standard.set(origin.x, forKey: Self.positionXKey)
            UserDefaults.standard.set(origin.y, forKey: Self.positionYKey)
        }
        panel?.close()
        panel = nil
    }

    var isVisible: Bool { panel != nil }

    // MARK: - Thinking Sound

    func playThinkingSound() {
        guard thinkingPlayer == nil, let data = Self.cachedThinkingToneData else { return }
        thinkingPlayer = try? AVAudioPlayer(data: data)
        thinkingPlayer?.numberOfLoops = -1
        thinkingPlayer?.volume = 0.08
        thinkingPlayer?.play()
    }

    func stopThinkingSound() {
        thinkingPlayer?.stop()
        thinkingPlayer = nil
    }

    /// Create a warm ambient pad — harmonic, pleasant, non-intrusive thinking sound.
    /// Returns WAV data (cached as static let, reused by playThinkingSound).
    private static func createThinkingTone() -> Data? {
        let sampleRate: Double = 44100
        let duration: Double = 4.0  // longer loop = smoother feel
        let frameCount = Int(sampleRate * duration)

        var audioData = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate

            // Warm C major 7th pad — low register, pure intervals
            // Using low frequencies so it feels warm, not piercing
            let c3  = sin(2.0 * .pi * 130.81 * t) * 0.18  // C3 — root, warm bass
            let e3  = sin(2.0 * .pi * 164.81 * t) * 0.10  // E3 — major third
            let g3  = sin(2.0 * .pi * 196.00 * t) * 0.08  // G3 — fifth
            let b3  = sin(2.0 * .pi * 246.94 * t) * 0.05  // B3 — major seventh (dreamy)

            // Slow tremolo (amplitude modulation) — gentle breathing feel
            let tremolo = 0.85 + 0.15 * sin(2.0 * .pi * 0.4 * t)

            // Smooth crossfade envelope for seamless looping
            let fadeLen = 0.8
            let envelope: Double
            if t < fadeLen {
                // Sine-shaped fade in (smoother than linear)
                envelope = sin((.pi / 2.0) * (t / fadeLen))
            } else if t > duration - fadeLen {
                envelope = sin((.pi / 2.0) * ((duration - t) / fadeLen))
            } else {
                envelope = 1.0
            }

            audioData[i] = Float((c3 + e3 + g3 + b3) * envelope * tremolo)
        }

        // Build a WAV in memory
        let bytesPerSample = 2  // 16-bit
        let dataSize = frameCount * bytesPerSample
        var wav = Data()

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        var chunkSize = UInt32(36 + dataSize).littleEndian
        wav.append(Data(bytes: &chunkSize, count: 4))
        wav.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        var fmtSize = UInt32(16).littleEndian
        wav.append(Data(bytes: &fmtSize, count: 4))
        var audioFormat = UInt16(1).littleEndian  // PCM
        wav.append(Data(bytes: &audioFormat, count: 2))
        var channels = UInt16(1).littleEndian
        wav.append(Data(bytes: &channels, count: 2))
        var sr = UInt32(44100).littleEndian
        wav.append(Data(bytes: &sr, count: 4))
        var byteRate = UInt32(44100 * 2).littleEndian
        wav.append(Data(bytes: &byteRate, count: 4))
        var blockAlign = UInt16(2).littleEndian
        wav.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample = UInt16(16).littleEndian
        wav.append(Data(bytes: &bitsPerSample, count: 2))

        // data chunk
        wav.append(contentsOf: "data".utf8)
        var ds = UInt32(dataSize).littleEndian
        wav.append(Data(bytes: &ds, count: 4))

        for sample in audioData {
            let clamped = max(-1.0, min(1.0, sample))
            var int16 = Int16(clamped * 32767).littleEndian
            wav.append(Data(bytes: &int16, count: 2))
        }

        return wav
    }
}

// MARK: - Container View

private struct VoiceOrbContainerView: View {
    @Bindable var service: VoiceAssistantService

    var body: some View {
        VStack(spacing: 0) {
            VoiceOrbView(
                state: service.inputController.state,
                audioLevel: service.inputController.audioLevel,
                isMuted: service.inputController.isMuted,
                onTap: {
                    if service.inputController.state == .listening {
                        service.submitCurrentInput()
                    }
                },
                onClose: {
                    service.endSession()
                },
                onMute: {
                    service.inputController.toggleMute()
                }
            )

            if !service.partialText.isEmpty {
                Text(service.partialText)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: service.partialText)
            }
        }
    }
}

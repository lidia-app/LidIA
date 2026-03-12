import AVFoundation

// MARK: - TTSVoice

struct TTSVoice: Identifiable, Sendable {
    let id: String
    let name: String
    let locale: String
}

// MARK: - TTSEngine Protocol

protocol TTSEngine: Sendable {
    /// Synthesize speech and return raw audio data (WAV format).
    func synthesize(_ text: String) async throws -> Data
    /// Synthesize and play. Default implementation calls synthesize() then plays via AVAudioPlayer.
    func speak(_ text: String) async throws
    func stop()
    var availableVoices: [TTSVoice] { get }
    /// Pre-load models so the first synthesis call is fast. Default: no-op.
    func warmup() async
    /// Unload model from memory. Default: no-op (only relevant for MLX).
    func unloadModel() async
}

extension TTSEngine {
    func warmup() async {}
    func unloadModel() async {}
}

// MARK: - SystemTTSEngine

/// Uses AVSpeechSynthesizer which must be called from the main thread.
/// @unchecked Sendable is safe because @MainActor provides isolation for all
/// mutable state; NSObject base class prevents compiler-synthesized conformance.
@MainActor
final class SystemTTSEngine: NSObject, TTSEngine, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private let voiceIdentifier: String?
    private var delegate: SystemTTSDelegate?

    init(voiceIdentifier: String? = nil) {
        self.voiceIdentifier = voiceIdentifier
        super.init()
        let delegate = SystemTTSDelegate { [weak self] in
            MainActor.assumeIsolated {
                self?.continuation?.resume()
                self?.continuation = nil
            }
        }
        self.delegate = delegate
        synthesizer.delegate = delegate
    }

    nonisolated var availableVoices: [TTSVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.quality.rawValue >= AVSpeechSynthesisVoiceQuality.enhanced.rawValue }
            .map { TTSVoice(id: $0.identifier, name: $0.name, locale: $0.language) }
    }

    func synthesize(_ text: String) async throws -> Data {
        let utterance = AVSpeechUtterance(string: text)
        if let id = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0

        // AVSpeechSynthesizer.write() delivers callbacks on arbitrary queues.
        // Buffer objects may be recycled after the callback returns, so we must
        // copy float samples immediately. Use a lock-protected collector since
        // callbacks can fire concurrently and ResumeOnce for the continuation.
        let collector = AudioSampleCollector()
        let guard_ = ResumeOnce()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            synthesizer.write(utterance) { buffer in
                if let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 {
                    let frameCount = Int(pcm.frameLength)
                    let channelCount = Int(pcm.format.channelCount)
                    // Copy samples from channel 0 immediately
                    if channelCount > 0, let channelData = pcm.floatChannelData {
                        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
                        collector.append(samples: samples, sampleRate: pcm.format.sampleRate, channelCount: channelCount)
                    }
                } else if guard_.tryResume() {
                    cont.resume()
                }
            }
        }

        let result = collector.finalize()
        guard !result.samples.isEmpty else { return Data() }

        // Build WAV in memory
        return buildWAV(samples: result.samples, sampleRate: Int(result.sampleRate), channelCount: 1)
    }

    private func buildWAV(samples: [Float], sampleRate: Int, channelCount: Int) -> Data {
        let bitsPerSample: UInt16 = 16
        let blockAlign = UInt16(channelCount) * (bitsPerSample / 8)
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)

        var pcmData = Data(count: samples.count * 2)
        pcmData.withUnsafeMutableBytes { raw in
            let buffer = raw.bindMemory(to: Int16.self)
            for i in samples.indices {
                let clamped = max(-1.0, min(1.0, samples[i]))
                buffer[i] = Int16(clamped * Float(Int16.max)).littleEndian
            }
        }

        let dataSize = UInt32(pcmData.count)
        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        var chunkSize = (36 + dataSize).littleEndian
        wav.append(Data(bytes: &chunkSize, count: 4))
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        var fmtSize = UInt32(16).littleEndian
        wav.append(Data(bytes: &fmtSize, count: 4))
        var audioFormat = UInt16(1).littleEndian // PCM
        wav.append(Data(bytes: &audioFormat, count: 2))
        var ch = UInt16(channelCount).littleEndian
        wav.append(Data(bytes: &ch, count: 2))
        var sr = UInt32(sampleRate).littleEndian
        wav.append(Data(bytes: &sr, count: 4))
        var br = byteRate.littleEndian
        wav.append(Data(bytes: &br, count: 4))
        var ba = blockAlign.littleEndian
        wav.append(Data(bytes: &ba, count: 2))
        var bps = bitsPerSample.littleEndian
        wav.append(Data(bytes: &bps, count: 2))
        wav.append("data".data(using: .ascii)!)
        var ds = dataSize.littleEndian
        wav.append(Data(bytes: &ds, count: 4))
        wav.append(pcmData)
        return wav
    }

    func speak(_ text: String) async throws {
        let data = try await synthesize(text)
        guard !data.isEmpty else { return }
        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()
        await withCheckedContinuation { cont in
            self.continuation = cont
            player.play()
        }
    }

    nonisolated func stop() {
        Task { @MainActor in
            synthesizer.stopSpeaking(at: .immediate)
            continuation?.resume()
            continuation = nil
        }
    }
}

/// Thread-safe collector for float audio samples from callbacks on arbitrary queues.
/// @unchecked Sendable is safe: all mutable state protected by NSLock.
private final class AudioSampleCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 22050

    func append(samples newSamples: [Float], sampleRate: Double, channelCount: Int) {
        lock.lock()
        self.sampleRate = sampleRate
        samples.append(contentsOf: newSamples)
        lock.unlock()
    }

    func finalize() -> (samples: [Float], sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (samples, sampleRate)
    }
}

/// Thread-safe one-shot flag for resuming a continuation exactly once.
/// @unchecked Sendable is safe: all mutable state protected by NSLock.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    /// Returns `true` exactly once; all subsequent calls return `false`.
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }
}

/// Separate delegate class to avoid NSObject/MainActor issues.
/// @unchecked Sendable is safe: only stored property is an immutable `let` closure.
/// NSObject base class prevents compiler-synthesized Sendable conformance.
private final class SystemTTSDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            onFinish()
        }
    }
}

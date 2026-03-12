#if os(macOS)
import AVFoundation
import Foundation
import MLX
import MLXAudioCore
import MLXAudioTTS
import MLXLMCommon
import os

/// Local TTS engine using mlx-audio-swift (Kokoro-82M default, Qwen3-TTS optional).
actor MLXTTSEngine: TTSEngine {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "MLXTTSEngine")

    /// Default voice description for VoiceDesign models — produces a consistent voice.
    private static let defaultVoiceDescription =
        "A clear, warm, and friendly female voice with a moderate pace. Natural and conversational tone."

    /// Default speaker name for Base models (not VoiceDesign).
    private static let defaultBaseSpeaker = "Chelsie"

    private var model: SpeechGenerationModel?
    private let modelRepo: String
    private let voiceParam: String
    private var generationTask: Task<Void, Never>?

    /// Cached reference audio from the first sentence — used to anchor subsequent
    /// sentences to the same voice characteristics within a multi-sentence response.
    private var referenceAudio: MLXArray?
    private var referenceText: String?
    private var lastSynthesisTime: Date?
    /// Max seconds before reference expires (voice context window).
    private static let referenceExpirySeconds: TimeInterval = 60

    /// Whether this model repo is a VoiceDesign model (accepts text descriptions)
    /// vs a Base model (accepts speaker name strings like "Chelsie").
    private var isVoiceDesign: Bool {
        modelRepo.lowercased().contains("voicedesign")
    }

    init(
        modelRepo: String = "mlx-community/Kokoro-82M-8bit",
        voiceDescription: String? = nil
    ) {
        self.modelRepo = modelRepo
        // VoiceDesign models take a text description; Base models take a speaker name.
        if modelRepo.lowercased().contains("voicedesign") {
            self.voiceParam = voiceDescription ?? Self.defaultVoiceDescription
        } else {
            self.voiceParam = voiceDescription ?? Self.defaultBaseSpeaker
        }
    }

    nonisolated var availableVoices: [TTSVoice] {
        [TTSVoice(id: "default", name: "Default", locale: "en")]
    }

    func synthesize(_ text: String) async throws -> Data {
        let model = try await ensureLoaded()
        let sampleRate = model.sampleRate

        // Expire stale reference audio (e.g., from a previous conversation turn)
        if let lastTime = lastSynthesisTime,
           Date().timeIntervalSince(lastTime) > Self.referenceExpirySeconds {
            referenceAudio = nil
            referenceText = nil
        }

        let hasRef = referenceAudio != nil
        Self.logger.info("MLX TTS synthesizing: '\(text.prefix(60))' at \(sampleRate) Hz, voice: '\(self.voiceParam.prefix(40))' (\(self.isVoiceDesign ? "VoiceDesign" : "Base")), ref: \(hasRef)")

        var allSamples: [Float] = []
        var allAudioChunks: [MLXArray] = []
        // Cap tokens based on text length — voice responses are short.
        // At 12.5 codes/sec, 100 tokens ≈ 8 seconds of audio.
        let estimatedTokens = max(75, text.count * 3)
        let parameters = GenerateParameters(
            maxTokens: min(estimatedTokens, 2048),
            temperature: 0.1,
            topP: 0.6,
            repetitionPenalty: 1.3,
            repetitionContextSize: 20
        )

        for try await event in model.generateStream(
            text: text,
            voice: voiceParam,
            refAudio: referenceAudio,
            refText: referenceText,
            language: "en",
            generationParameters: parameters
        ) {
            try Task.checkCancellation()

            switch event {
            case .audio(let audioData):
                let samples = audioData.asArray(Float.self)
                allSamples.append(contentsOf: samples)
                allAudioChunks.append(audioData)
            case .token, .info:
                break
            }
        }

        Memory.clearCache()

        Self.logger.info("MLX TTS generated \(allSamples.count) samples, duration: \(Double(allSamples.count) / Double(sampleRate))s")

        guard !allSamples.isEmpty else {
            throw TTSError.apiError(statusCode: 0, body: "MLX TTS generated no audio")
        }

        // Cache this sentence's audio as reference for subsequent sentences.
        // Use the first ~3 seconds (keeps reference short and representative).
        if referenceAudio == nil, !allAudioChunks.isEmpty {
            let combined = MLX.concatenated(allAudioChunks)
            let maxRefSamples = sampleRate * 3  // 3 seconds
            referenceAudio = combined.count > maxRefSamples
                ? combined[0..<maxRefSamples]
                : combined
            referenceText = text
            Self.logger.info("Cached reference audio: \(self.referenceAudio!.count) samples")
        }
        lastSynthesisTime = Date()

        return pcmToWAV(samples: allSamples, sampleRate: sampleRate)
    }

    func speak(_ text: String) async throws {
        let data = try await synthesize(text)
        guard !data.isEmpty else { return }

        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let delegate = MLXAudioDelegate { cont.resume() }
            objc_setAssociatedObject(player, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            player.delegate = delegate
            player.play()
        }
    }

    nonisolated func stop() {
        Task { await cancelGeneration() }
    }

    /// Clear cached reference audio — call between conversation turns
    /// so the next turn starts fresh (avoids anchoring to stale context).
    func clearReference() {
        referenceAudio = nil
        referenceText = nil
    }

    private func cancelGeneration() {
        generationTask?.cancel()
        generationTask = nil
        clearReference()
    }

    func warmup() async {
        _ = try? await ensureLoaded()
    }

    /// Unload the TTS model from memory to free RAM/VRAM.
    /// Call after voice session ends.
    func unloadModel() {
        model = nil
        clearReference()
        Memory.clearCache()
        Self.logger.info("TTS model unloaded from memory")
    }

    private func ensureLoaded() async throws -> SpeechGenerationModel {
        if let model { return model }
        Self.logger.info("Loading TTS model: \(self.modelRepo)")
        let loaded = try await TTS.loadModel(modelRepo: modelRepo)
        self.model = loaded
        Self.logger.info("TTS model loaded")
        return loaded
    }

    /// Convert Float32 PCM samples to WAV data.
    private func pcmToWAV(samples: [Float], sampleRate: Int) -> Data {
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channelCount) * UInt32(bitsPerSample / 8)
        let blockAlign = channelCount * (bitsPerSample / 8)

        // Convert Float32 → Int16 (bulk)
        var pcm16Data = Data(count: samples.count * 2)
        pcm16Data.withUnsafeMutableBytes { raw in
            let buffer = raw.bindMemory(to: Int16.self)
            for i in samples.indices {
                let clamped = max(-1.0, min(1.0, samples[i]))
                buffer[i] = Int16(clamped * Float(Int16.max)).littleEndian
            }
        }

        let chunkSize = 36 + UInt32(pcm16Data.count)

        var wav = Data()
        wav.append("RIFF".data(using: .ascii)!)
        wav.append(littleEndian(chunkSize))
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        wav.append(littleEndian(UInt32(16)))           // fmt chunk size
        wav.append(littleEndian(UInt16(1)))             // PCM
        wav.append(littleEndian(channelCount))
        wav.append(littleEndian(UInt32(sampleRate)))
        wav.append(littleEndian(byteRate))
        wav.append(littleEndian(blockAlign))
        wav.append(littleEndian(bitsPerSample))
        wav.append("data".data(using: .ascii)!)
        wav.append(littleEndian(UInt32(pcm16Data.count)))
        wav.append(pcm16Data)
        return wav
    }

    private func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        var le = value.littleEndian
        return Data(bytes: &le, count: MemoryLayout<T>.size)
    }
}

/// AVAudioPlayerDelegate bridge. @unchecked Sendable is safe because:
/// - All stored properties are immutable (`let`)
/// - NSObject base class prevents compiler-synthesized Sendable conformance
private final class MLXAudioDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let onFinish: @Sendable () -> Void
    init(onFinish: @escaping @Sendable () -> Void) { self.onFinish = onFinish }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { onFinish() }
}
#endif

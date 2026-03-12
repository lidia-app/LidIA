import AVFoundation
import Foundation
import os

enum VoiceAssistantBackend: Equatable, Sendable {
    case localPipeline
    case openAIRealtime

    static func resolve(ttsProvider: AppSettings.TTSProvider, openAIAPIKey: String) -> Self {
        let hasOpenAIKey = !openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Only use OpenAI Realtime when explicitly selected with a valid key
        if ttsProvider == .openai, hasOpenAIKey {
            return .openAIRealtime
        }
        return .localPipeline
    }
}

enum RealtimeVoiceError: LocalizedError, Sendable {
    case missingSocket
    case apiError(String)
    case invalidAudioPayload

    var errorDescription: String? {
        switch self {
        case .missingSocket:
            return "Realtime voice socket is not connected."
        case .apiError(let message):
            return "OpenAI Realtime error: \(message)"
        case .invalidAudioPayload:
            return "OpenAI Realtime returned invalid audio data."
        }
    }
}

actor RealtimeVoiceClient {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "RealtimeVoice")

    static let defaultModel = "gpt-4o-realtime-preview"
    static let audioSampleRate = 24_000

    enum ServerEvent: Equatable, Sendable {
        case audioDelta(Data)
        case textDelta(String)
        case audioTranscriptDelta(String)
        case inputTranscript(String)
        case responseDone
        case sessionUpdated
        case other(String)
        case error(String)
    }

    struct Response: Sendable {
        let transcript: String
        let text: String
        let audioPCM16: Data

        var wavAudioData: Data? {
            guard !audioPCM16.isEmpty else { return nil }
            return Self.wrapPCM16AsWAV(audioPCM16, sampleRate: RealtimeVoiceClient.audioSampleRate)
        }

        private static func wrapPCM16AsWAV(_ pcm16: Data, sampleRate: Int) -> Data {
            let channelCount: UInt16 = 1
            let bitsPerSample: UInt16 = 16
            let byteRate = UInt32(sampleRate) * UInt32(channelCount) * UInt32(bitsPerSample / 8)
            let blockAlign = channelCount * (bitsPerSample / 8)
            let chunkSize = 36 + UInt32(pcm16.count)
            let subchunkSize = UInt32(pcm16.count)

            var data = Data()
            data.append("RIFF".data(using: .ascii)!)
            data.append(Self.littleEndianBytes(chunkSize))
            data.append("WAVE".data(using: .ascii)!)
            data.append("fmt ".data(using: .ascii)!)
            data.append(Self.littleEndianBytes(UInt32(16)))
            data.append(Self.littleEndianBytes(UInt16(1)))
            data.append(Self.littleEndianBytes(channelCount))
            data.append(Self.littleEndianBytes(UInt32(sampleRate)))
            data.append(Self.littleEndianBytes(byteRate))
            data.append(Self.littleEndianBytes(blockAlign))
            data.append(Self.littleEndianBytes(bitsPerSample))
            data.append("data".data(using: .ascii)!)
            data.append(Self.littleEndianBytes(subchunkSize))
            data.append(pcm16)
            return data
        }

        private static func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> Data {
            var littleEndian = value.littleEndian
            return Data(bytes: &littleEndian, count: MemoryLayout<T>.size)
        }
    }

    private let apiKey: String
    private let model: String
    private let urlSession: URLSession
    private var webSocketTask: URLSessionWebSocketTask?

    init(apiKey: String, model: String = RealtimeVoiceClient.defaultModel, urlSession: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.urlSession = urlSession
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
    }

    func completeTurn(
        samples: [Float],
        sourceSampleRate: Int,
        voice: String,
        instructions: String
    ) async throws -> String {
        try connectIfNeeded()
        try await updateSession(instructions: instructions, voice: voice)
        try await sendInputAudio(samples: samples, sourceSampleRate: sourceSampleRate)
        try await sendEvent(["type": "input_audio_buffer.commit"])
        return try await awaitInputTranscript()
    }

    func generateResponse(
        for transcript: String,
        voice: String,
        instructions: String
    ) async throws -> Response {
        try connectIfNeeded()
        try await updateSession(instructions: instructions, voice: voice)
        try await createResponse()
        return try await awaitResponse(transcript: transcript)
    }

    private func connectIfNeeded() throws {
        guard webSocketTask == nil else { return }
        let url = URL(string: "wss://api.openai.com/v1/realtime?model=\(model)")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let task = urlSession.webSocketTask(with: request)
        task.resume()
        webSocketTask = task
    }

    private func updateSession(instructions: String, voice: String) async throws {
        let event: [String: Any] = [
            "type": "session.update",
            "session": [
                "instructions": instructions,
                "voice": voice,
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "input_audio_transcription": ["model": "gpt-4o-mini-transcribe"],
                "turn_detection": NSNull(),
            ]
        ]
        try await sendEvent(event)
    }

    private func createResponse() async throws {
        let event: [String: Any] = [
            "type": "response.create",
            "response": [
                "modalities": ["text", "audio"]
            ]
        ]
        try await sendEvent(event)
    }

    private func sendInputAudio(samples: [Float], sourceSampleRate: Int) async throws {
        let bytesPerChunk = 4_096 * MemoryLayout<Int16>.size
        let event = Self.inputAudioAppendEvent(samples: samples, sourceSampleRate: sourceSampleRate)
        guard let payload = event["audio"] as? String,
              let data = Data(base64Encoded: payload)
        else {
            throw RealtimeVoiceError.invalidAudioPayload
        }

        if data.isEmpty {
            try await sendEvent(event)
            return
        }

        for start in stride(from: 0, to: data.count, by: bytesPerChunk) {
            let end = min(start + bytesPerChunk, data.count)
            let chunk = data.subdata(in: start..<end)
            try await sendEvent([
                "type": "input_audio_buffer.append",
                "audio": chunk.base64EncodedString()
            ])
        }
    }

    private func awaitInputTranscript() async throws -> String {
        while true {
            switch try await receiveEvent() {
            case .inputTranscript(let transcript):
                return transcript
            case .error(let message):
                throw RealtimeVoiceError.apiError(message)
            default:
                continue
            }
        }
    }

    private func awaitResponse(transcript: String) async throws -> Response {
        var text = ""
        var audio = Data()
        var sawTextDelta = false

        while true {
            switch try await receiveEvent() {
            case .textDelta(let delta):
                sawTextDelta = true
                text += delta
            case .audioTranscriptDelta(let delta):
                guard !sawTextDelta else { continue }
                text += delta
            case .audioDelta(let delta):
                audio.append(delta)
            case .responseDone:
                return Response(transcript: transcript, text: text, audioPCM16: audio)
            case .error(let message):
                throw RealtimeVoiceError.apiError(message)
            default:
                continue
            }
        }
    }

    private func sendEvent(_ event: [String: Any]) async throws {
        guard let webSocketTask else { throw RealtimeVoiceError.missingSocket }
        let data = try JSONSerialization.data(withJSONObject: event)
        let text = String(decoding: data, as: UTF8.self)
        try await webSocketTask.send(.string(text))
    }

    private func receiveEvent() async throws -> ServerEvent {
        guard let webSocketTask else { throw RealtimeVoiceError.missingSocket }

        while true {
            let message = try await webSocketTask.receive()
            let data: Data
            switch message {
            case .data(let payload):
                data = payload
            case .string(let payload):
                data = Data(payload.utf8)
            @unknown default:
                continue
            }

            if let event = Self.parseServerEvent(from: data) {
                switch event {
                case .other(let type):
                    Self.logger.debug("Ignoring Realtime event: \(type, privacy: .public)")
                    continue
                default:
                    return event
                }
            }
        }
    }

    nonisolated static func inputAudioAppendEvent(samples: [Float], sourceSampleRate: Int) -> [String: Any] {
        let normalizedSamples: [Float]
        if sourceSampleRate == audioSampleRate {
            normalizedSamples = samples
        } else {
            normalizedSamples = AudioResampler.resample(samples, from: sourceSampleRate, to: audioSampleRate)
        }

        let pcm16 = pcm16Data(from: normalizedSamples)
        return [
            "type": "input_audio_buffer.append",
            "audio": pcm16.base64EncodedString()
        ]
    }

    nonisolated static func parseServerEvent(from data: Data) -> ServerEvent? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String
        else {
            return nil
        }

        switch type {
        case "response.audio.delta":
            guard let delta = json["delta"] as? String,
                  let decoded = Data(base64Encoded: delta)
            else { return nil }
            return .audioDelta(decoded)
        case "response.text.delta":
            guard let delta = json["delta"] as? String else { return nil }
            return .textDelta(delta)
        case "response.audio_transcript.delta":
            guard let delta = json["delta"] as? String else { return nil }
            return .audioTranscriptDelta(delta)
        case "conversation.item.input_audio_transcription.completed":
            if let transcript = json["transcript"] as? String {
                return .inputTranscript(transcript)
            }
            if let item = json["item"] as? [String: Any],
               let transcript = item["transcript"] as? String {
                return .inputTranscript(transcript)
            }
            return nil
        case "response.done", "response.completed":
            return .responseDone
        case "session.updated":
            return .sessionUpdated
        case "error":
            let message: String
            if let error = json["error"] as? [String: Any] {
                message = error["message"] as? String ?? "Unknown error"
            } else {
                message = json["message"] as? String ?? "Unknown error"
            }
            return .error(message)
        default:
            return .other(type)
        }
    }

    private nonisolated static func pcm16Data(from samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let scaled = clamped == -1
                ? Int16.min
                : Int16((clamped * Float(Int16.max)).rounded())
            var littleEndian = scaled.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }
}

actor RealtimeAudioPlayer {
    private var audioPlayer: AVAudioPlayer?
    private var continuation: CheckedContinuation<Void, Never>?

    func play(wavData: Data) async throws {
        let player = try AVAudioPlayer(data: wavData)
        audioPlayer = player
        player.prepareToPlay()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
            let delegate = AudioPlayerDelegate {
                continuation.resume()
            }
            player.delegate = delegate
            objc_setAssociatedObject(player, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            player.play()
        }

        continuation = nil
        audioPlayer = nil
    }

    nonisolated func stop() {
        Task { await stopInternal() }
    }

    private func stopInternal() {
        audioPlayer?.stop()
        continuation?.resume()
        continuation = nil
        audioPlayer = nil
    }
}

/// AVAudioPlayerDelegate bridge. @unchecked Sendable is safe because:
/// - Only stored property is an immutable `let` closure
/// - NSObject base class prevents compiler-synthesized Sendable conformance
private final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

import AVFoundation
import os

actor OpenAITTSEngine: TTSEngine {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "OpenAITTS")

    private let apiKey: String
    private let baseURL: URL
    private let voice: String
    private var audioPlayer: AVAudioPlayer?

    init(apiKey: String, baseURL: URL = URL(string: "https://api.openai.com")!, voice: String = "nova") {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.voice = voice
    }

    nonisolated var availableVoices: [TTSVoice] {
        [
            TTSVoice(id: "alloy", name: "Alloy", locale: "en"),
            TTSVoice(id: "echo", name: "Echo", locale: "en"),
            TTSVoice(id: "fable", name: "Fable", locale: "en"),
            TTSVoice(id: "nova", name: "Nova", locale: "en"),
            TTSVoice(id: "onyx", name: "Onyx", locale: "en"),
            TTSVoice(id: "shimmer", name: "Shimmer", locale: "en"),
        ]
    }

    func synthesize(_ text: String) async throws -> Data {
        let url = baseURL.appendingPathComponent("v1/audio/speech")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "tts-1",
            "input": text,
            "voice": voice,
            "response_format": "wav"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw TTSError.apiError(statusCode: statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        return data
    }

    func speak(_ text: String) async throws {
        let data = try await synthesize(text)

        let player = try AVAudioPlayer(data: data)
        self.audioPlayer = player
        player.prepareToPlay()

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let delegate = AudioPlayerDelegate {
                cont.resume()
            }
            player.delegate = delegate
            objc_setAssociatedObject(player, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            player.play()
        }
        self.audioPlayer = nil
    }

    nonisolated func stop() {
        Task { await _stop() }
    }

    private func _stop() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}

// MARK: - TTSError

enum TTSError: LocalizedError {
    case apiError(statusCode: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .apiError(let code, let body):
            return "TTS API error (\(code)): \(body)"
        }
    }
}

// MARK: - AudioPlayerDelegate

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

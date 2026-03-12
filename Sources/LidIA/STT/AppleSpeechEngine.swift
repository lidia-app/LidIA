import AVFoundation
import Foundation
import os
import Speech
import Synchronization

final class AppleSpeechEngine: STTEngine {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "AppleSpeechEngine")
    private let locale: Locale

    init(locale: Locale = .current) {
        self.locale = locale
    }

    func transcribe(audioStream: AsyncStream<AudioChunk>) -> AsyncStream<TranscriptWord> {
        AsyncStream { continuation in
            Task { @Sendable in
                // Request speech recognition authorization
                let authStatus = await withCheckedContinuation { cont in
                    SFSpeechRecognizer.requestAuthorization { status in
                        cont.resume(returning: status)
                    }
                }
                guard authStatus == .authorized else {
                    Self.logger.error("Speech recognition not authorized: \(authStatus.rawValue)")
                    continuation.finish()
                    return
                }

                guard let recognizer = SFSpeechRecognizer(locale: self.locale),
                      recognizer.isAvailable else {
                    Self.logger.error("SFSpeechRecognizer unavailable for locale: \(self.locale)")
                    continuation.finish()
                    return
                }

                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                request.addsPunctuation = true

                let lastWordCount = Mutex(0)
                var chunkCount = 0
                var cachedFormat: AVAudioFormat?

                let task = recognizer.recognitionTask(with: request) { result, error in
                    guard let result else {
                        if let error {
                            AppleSpeechEngine.logger.error("Recognition error: \(error.localizedDescription)")
                        }
                        return
                    }

                    let segments = result.bestTranscription.segments
                    let currentCount = lastWordCount.withLock { value in
                        let prev = value
                        value = segments.count
                        return prev
                    }
                    let newSegments = segments.dropFirst(currentCount)

                    for segment in newSegments {
                        let word = TranscriptWord(
                            word: segment.substring,
                            start: segment.timestamp,
                            end: segment.timestamp + segment.duration,
                            confidence: Double(segment.confidence),
                            speaker: nil
                        )
                        continuation.yield(word)
                    }

                    if result.isFinal {
                        continuation.finish()
                    }
                }

                for await chunk in audioStream {
                    // Create or reuse format matching the chunk's sample rate
                    if cachedFormat == nil || Int(cachedFormat!.sampleRate) != chunk.sampleRate {
                        cachedFormat = AVAudioFormat(
                            commonFormat: .pcmFormatFloat32,
                            sampleRate: Double(chunk.sampleRate),
                            channels: 1,
                            interleaved: false
                        )
                        Self.logger.info("Audio format: \(chunk.sampleRate)Hz, mono, Float32")
                    }

                    guard let format = cachedFormat else { continue }

                    guard let buffer = AVAudioPCMBuffer(
                        pcmFormat: format,
                        frameCapacity: AVAudioFrameCount(chunk.samples.count)
                    ) else { continue }

                    buffer.frameLength = AVAudioFrameCount(chunk.samples.count)
                    chunk.samples.withUnsafeBufferPointer { src in
                        buffer.floatChannelData![0]
                            .update(from: src.baseAddress!, count: src.count)
                    }

                    // Log audio level periodically
                    chunkCount += 1
                    if chunkCount % 50 == 1 {
                        let rms = sqrt(
                            chunk.samples.reduce(0.0) { $0 + $1 * $1 }
                                / max(Float(chunk.samples.count), 1)
                        )
                        Self.logger.debug("Chunk #\(chunkCount): \(chunk.samples.count) samples, RMS=\(String(format: "%.4f", rms))")
                    }

                    request.append(buffer)
                }

                Self.logger.info("Audio stream ended, finalizing recognition...")
                request.endAudio()
                try? await Task.sleep(for: .seconds(3))
                task.cancel()
                continuation.finish()
            }
        }
    }
}

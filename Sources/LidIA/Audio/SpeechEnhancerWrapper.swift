import SpeechEnhancement
import os

actor SpeechEnhancerWrapper {
    static let shared = SpeechEnhancerWrapper()
    private var enhancer: SpeechEnhancer?
    private static let logger = Logger(subsystem: "io.lidia.app", category: "SpeechEnhancer")

    func enhance(samples: [Float], sampleRate: Int) async throws -> [Float] {
        if enhancer == nil {
            Self.logger.info("Loading DeepFilterNet3 model...")
            enhancer = try await SpeechEnhancer.fromPretrained { progress, status in
                Self.logger.info("DeepFilterNet3: \(status) (\(Int(progress * 100))%)")
            }
            Self.logger.info("DeepFilterNet3 model loaded")
        }
        let enhanced = try enhancer!.enhance(audio: samples, sampleRate: sampleRate)
        // DeepFilterNet outputs at 48kHz — resample back to original rate for STT
        return resampleIfNeeded(enhanced, from: SpeechEnhancer.sampleRate, to: sampleRate)
    }

    private func resampleIfNeeded(_ samples: [Float], from sourceSR: Int, to targetSR: Int) -> [Float] {
        guard sourceSR != targetSR else { return samples }
        let ratio = Double(targetSR) / Double(sourceSR)
        let outputCount = Int(Double(samples.count) * ratio)
        return (0..<outputCount).map { i in
            samples[min(Int(Double(i) / ratio), samples.count - 1)]
        }
    }
}

import Foundation
import SpeechVAD
import os

private let ssLogger = Logger(subsystem: "io.lidia.app", category: "SpeechSwiftDiarizer")

/// Adapter wrapping speech-swift's PyannoteDiarizationPipeline for use in ParakeetBatchProcessor.
/// Downloads models on first use, then caches locally. Falls back gracefully on failure.
actor SpeechSwiftDiarizer {

    /// A speaker segment compatible with what ParakeetBatchProcessor expects.
    struct SpeakerSegment: Sendable {
        let speakerId: Int
        let startTime: Float
        let endTime: Float
    }

    /// Shared singleton instance.
    static let shared = SpeechSwiftDiarizer()

    /// Cached pipeline instance (expensive to load — reuse across calls).
    private var pipeline: PyannoteDiarizationPipeline?

    /// Load the diarization pipeline, downloading models on first call.
    func loadPipeline() async throws -> PyannoteDiarizationPipeline {
        if let existing = pipeline { return existing }

        ssLogger.info("Loading speech-swift diarization pipeline (first use downloads models)...")

        let loaded = try await PyannoteDiarizationPipeline.fromPretrained(
            useVADFilter: true,
            progressHandler: { progress, status in
                ssLogger.info("Diarization model: \(status) (\(Int(progress * 100))%)")
            }
        )

        pipeline = loaded
        ssLogger.info("speech-swift diarization pipeline ready")
        return loaded
    }

    /// Run speaker diarization on 16kHz mono audio samples.
    ///
    /// - Parameter samples: PCM Float32 samples at 16kHz
    /// - Returns: Speaker segments with 0-based speaker IDs and timestamps in seconds
    func diarize(samples: [Float]) async throws -> [SpeakerSegment] {
        let pipe = try await loadPipeline()

        let result = pipe.diarize(audio: samples, sampleRate: 16000, config: .default)

        ssLogger.info("speech-swift diarization: \(result.numSpeakers) speakers, \(result.segments.count) segments")

        return result.segments.map { seg in
            SpeakerSegment(
                speakerId: seg.speakerId,
                startTime: seg.startTime,
                endTime: seg.endTime
            )
        }
    }
}

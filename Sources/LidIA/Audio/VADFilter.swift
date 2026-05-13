import Foundation
import SpeechVAD
import os

/// Filters audio samples to speech-only regions using Pyannote VAD.
///
/// Used in the batch post-processing path to strip silence before STT inference,
/// improving both speed (less audio to process) and accuracy (less noise/silence
/// confused as speech).
actor VADFilter {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "VADFilter")

    /// Shared singleton — the underlying model is expensive to load.
    static let shared = VADFilter()

    private var model: PyannoteVADModel?

    /// Load the VAD model if not already loaded. Downloads on first use.
    func loadIfNeeded() async throws {
        guard model == nil else { return }

        Self.logger.info("Loading Pyannote VAD model (first use downloads from HuggingFace)...")
        let loaded = try await PyannoteVADModel.fromPretrained(
            progressHandler: { progress, status in
                Self.logger.info("VAD model: \(status) (\(Int(progress * 100))%)")
            }
        )
        model = loaded
        Self.logger.info("Pyannote VAD model ready")
    }

    /// Filter audio samples to only include speech regions.
    ///
    /// Runs VAD to detect speech segments, then extracts and concatenates
    /// only the speech portions of the audio. Returns the original samples
    /// if VAD finds no speech (safety fallback).
    ///
    /// - Parameters:
    ///   - samples: PCM Float32 audio samples
    ///   - sampleRate: Sample rate in Hz (auto-resampled to 16kHz internally)
    /// - Returns: Filtered samples containing only speech regions
    func filterSpeech(samples: [Float], sampleRate: Int) async throws -> [Float] {
        try await loadIfNeeded()

        guard let model else {
            Self.logger.warning("VAD model not loaded, returning unfiltered audio")
            return samples
        }

        let segments = model.detectSpeech(audio: samples, sampleRate: sampleRate)

        guard !segments.isEmpty else {
            Self.logger.info("VAD found no speech segments, returning original audio")
            return samples
        }

        let totalDuration = Float(samples.count) / Float(sampleRate)
        let speechDuration = segments.reduce(Float(0)) { $0 + $1.duration }

        Self.logger.info("""
            VAD pre-filter: \(segments.count) speech segments, \
            \(String(format: "%.1f", speechDuration))s speech / \
            \(String(format: "%.1f", totalDuration))s total \
            (\(String(format: "%.0f", (1 - speechDuration / totalDuration) * 100))% silence removed)
            """)

        // Extract and concatenate speech-only regions
        var filtered: [Float] = []
        filtered.reserveCapacity(Int(speechDuration * Float(sampleRate)))

        for segment in segments {
            let startSample = max(0, Int(segment.startTime * Float(sampleRate)))
            let endSample = min(samples.count, Int(segment.endTime * Float(sampleRate)))
            guard startSample < endSample else { continue }
            filtered.append(contentsOf: samples[startSample..<endSample])
        }

        // Safety: if filtering produced nothing, return original
        if filtered.isEmpty {
            Self.logger.warning("VAD filtering produced empty result, returning original audio")
            return samples
        }

        return filtered
    }
}

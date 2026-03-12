import FluidAudio
import Foundation
import os

private let batchLogger = Logger(subsystem: "io.lidia.app", category: "ParakeetBatchProcessor")

/// Post-recording batch processor: high-quality ASR + optional speaker diarization.
/// Uses AsrManager for transcription and OfflineDiarizerManager for speaker labels.
actor ParakeetBatchProcessor {

    /// Process accumulated 16kHz mono samples into a diarized transcript.
    func process(samples: [Float], systemSamples: [Float], enableDiarization: Bool) async throws -> [TranscriptWord] {
        guard !samples.isEmpty else { return [] }

        let duration = Double(samples.count) / 16000.0
        batchLogger.info("Processing \(String(format: "%.1f", duration))s of audio (diarization: \(enableDiarization))")

        // Step A: Batch ASR with word timings
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        let asrManager = AsrManager(config: .default)
        try await asrManager.initialize(models: models)

        let result = try await asrManager.transcribe(samples, source: .microphone)
        asrManager.cleanup()

        // Merge sub-word tokens into whole words.
        // tokenTimings contains SentencePiece tokens where "▁" is replaced with " ".
        // A token starting with " " (space) marks a new word boundary.
        // Consecutive tokens without leading space are continuations of the current word.
        var words: [TranscriptWord] = []
        var currentWord = ""
        var wordStart: TimeInterval = 0
        var wordEnd: TimeInterval = 0

        for timing in result.tokenTimings ?? [] {
            let token = timing.token
            let isWordBoundary = token.hasPrefix(" ")

            if isWordBoundary && !currentWord.isEmpty {
                // Save the completed word
                words.append(TranscriptWord(
                    word: currentWord,
                    start: wordStart,
                    end: wordEnd,
                    confidence: Double(result.confidence),
                    speaker: nil
                ))
                currentWord = ""
            }

            // Append token text (strip leading space from boundary tokens)
            let stripped = isWordBoundary ? String(token.dropFirst()) : token
            if currentWord.isEmpty {
                wordStart = timing.startTime
            }
            currentWord += stripped
            wordEnd = timing.endTime
        }

        // Don't forget the last word
        if !currentWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            words.append(TranscriptWord(
                word: currentWord.trimmingCharacters(in: .whitespacesAndNewlines),
                start: wordStart,
                end: wordEnd,
                confidence: Double(result.confidence),
                speaker: nil
            ))
        }

        batchLogger.info("ASR produced \(words.count) words from \((result.tokenTimings ?? []).count) tokens")

        // Step B: Speaker diarization (if enabled)
        guard enableDiarization, !words.isEmpty else { return words }

        do {
            let config = OfflineDiarizerConfig(
                segmentationMinDurationOn: 1.0,  // Require at least 1s of speech per segment
                segmentationMinDurationOff: 0.5   // Require at least 0.5s gap between speakers
            )
            let diarizer = OfflineDiarizerManager(config: config)
            try await diarizer.prepareModels()

            let diarResult = try await diarizer.process(audio: systemSamples.isEmpty ? samples : systemSamples)
            let rawSegments = diarResult.segments

            batchLogger.info("Diarization found \(Set(rawSegments.map(\.speakerId)).count) speakers across \(rawSegments.count) raw segments")

            // Step C: Smooth segments — merge short spurious segments into neighbors
            let segments = Self.smoothSegments(rawSegments)

            batchLogger.info("After smoothing: \(Set(segments.map(\.speakerId)).count) speakers across \(segments.count) segments")

            // Step D: Assign speaker ID to each word based on timestamp overlap
            let uniqueSpeakers = Array(Set(segments.map(\.speakerId))).sorted()
            let speakerIndex: [String: Int] = Dictionary(uniqueKeysWithValues: uniqueSpeakers.enumerated().map { ($1, $0) })

            for i in words.indices {
                let wordMid = (words[i].start + words[i].end) / 2.0
                if let segment = segments.first(where: { wordMid >= Double($0.startTimeSeconds) && wordMid <= Double($0.endTimeSeconds) }) {
                    let idx = speakerIndex[segment.speakerId] ?? 0
                    words[i].speaker = idx
                    words[i].speakerName = "Speaker \(idx + 1)"
                    words[i].isLocalSpeaker = false
                }
            }
        } catch {
            batchLogger.error("Diarization failed (transcript preserved without speakers): \(error)")
        }

        return words
    }

    // MARK: - Segment Smoothing

    /// Merge short spurious diarization segments into their neighbors.
    /// 1. Absorb segments shorter than `minDuration` into the nearest neighbor.
    /// 2. Consolidate consecutive segments with the same speaker ID.
    private static func smoothSegments(
        _ segments: [TimedSpeakerSegment],
        minDuration: Float = 0.5
    ) -> [TimedSpeakerSegment] {
        guard segments.count > 1 else { return segments }

        // Sort by start time
        let sorted = segments.sorted { $0.startTimeSeconds < $1.startTimeSeconds }

        // Step 1: Absorb short segments into their longer neighbor
        var filtered: [TimedSpeakerSegment] = []
        for segment in sorted {
            let duration = segment.endTimeSeconds - segment.startTimeSeconds
            if duration < minDuration, let last = filtered.last {
                // Short segment — absorb into previous (extend its end time)
                let extended = TimedSpeakerSegment(
                    speakerId: last.speakerId,
                    embedding: last.embedding,
                    startTimeSeconds: last.startTimeSeconds,
                    endTimeSeconds: max(last.endTimeSeconds, segment.endTimeSeconds),
                    qualityScore: last.qualityScore
                )
                filtered[filtered.count - 1] = extended
            } else {
                filtered.append(segment)
            }
        }

        // Step 2: Merge consecutive segments with the same speaker
        var merged: [TimedSpeakerSegment] = []
        for segment in filtered {
            if let last = merged.last, last.speakerId == segment.speakerId {
                let combined = TimedSpeakerSegment(
                    speakerId: last.speakerId,
                    embedding: last.embedding,
                    startTimeSeconds: last.startTimeSeconds,
                    endTimeSeconds: max(last.endTimeSeconds, segment.endTimeSeconds),
                    qualityScore: max(last.qualityScore, segment.qualityScore)
                )
                merged[merged.count - 1] = combined
            } else {
                merged.append(segment)
            }
        }

        return merged
    }
}

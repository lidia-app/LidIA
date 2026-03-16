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

        // TODO: DeepFilterNet noise reduction
        // When speech-swift SpeechEnhancement module is integrated:
        // if noiseReductionEnabled {
        //     let enhancer = DeepFilterNet3()
        //     samples = try await enhancer.enhance(samples)
        // }

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

        let diarizationAudio = systemSamples.isEmpty ? samples : systemSamples

        // Try speech-swift (pyannote + WeSpeaker — better accuracy) with FluidAudio fallback
        do {
            let ssSegments = try await SpeechSwiftDiarizer.shared.diarize(samples: diarizationAudio)

            batchLogger.info("speech-swift diarization: \(Set(ssSegments.map(\.speakerId)).count) speakers, \(ssSegments.count) segments")

            // Assign speaker ID to each word based on timestamp overlap
            for i in words.indices {
                let wordMid = Float((words[i].start + words[i].end) / 2.0)
                if let segment = ssSegments.first(where: { wordMid >= $0.startTime && wordMid <= $0.endTime }) {
                    words[i].speaker = segment.speakerId
                }
            }

            Self.assignLocalSpeaker(&words)
        } catch {
            batchLogger.warning("speech-swift diarization failed, falling back to FluidAudio: \(error)")

            // Fallback: FluidAudio OfflineDiarizerManager
            do {
                let config = OfflineDiarizerConfig(
                    segmentationMinDurationOn: 1.0,
                    segmentationMinDurationOff: 0.5
                )
                let diarizer = OfflineDiarizerManager(config: config)
                try await diarizer.prepareModels()

                let diarResult = try await diarizer.process(audio: diarizationAudio)
                let rawSegments = diarResult.segments

                batchLogger.info("FluidAudio diarization found \(Set(rawSegments.map(\.speakerId)).count) speakers across \(rawSegments.count) raw segments")

                let segments = Self.smoothSegments(rawSegments)

                batchLogger.info("After smoothing: \(Set(segments.map(\.speakerId)).count) speakers across \(segments.count) segments")

                let uniqueSpeakers = Array(Set(segments.map(\.speakerId))).sorted()
                let speakerIndex: [String: Int] = Dictionary(uniqueKeysWithValues: uniqueSpeakers.enumerated().map { ($1, $0) })

                for i in words.indices {
                    let wordMid = (words[i].start + words[i].end) / 2.0
                    if let segment = segments.first(where: { wordMid >= Double($0.startTimeSeconds) && wordMid <= Double($0.endTimeSeconds) }) {
                        let idx = speakerIndex[segment.speakerId] ?? 0
                        words[i].speaker = idx
                    }
                }

                Self.assignLocalSpeaker(&words)
            } catch {
                batchLogger.error("Diarization failed (transcript preserved without speakers): \(error)")
            }
        }

        return words
    }

    // MARK: - Local Speaker Assignment

    /// Determine which speaker ID is "me" by majority vote on isLocalSpeaker flags,
    /// then set isLocalSpeaker based on speaker ID mapping.
    private static func assignLocalSpeaker(_ words: inout [TranscriptWord]) {
        var localVotes: [Int: Int] = [:]
        var totalVotes: [Int: Int] = [:]
        for word in words where word.speaker != nil {
            let sp = word.speaker!
            totalVotes[sp, default: 0] += 1
            if word.isLocalSpeaker == true {
                localVotes[sp, default: 0] += 1
            }
        }

        let localSpeakerID = localVotes.max(by: { a, b in
            let ratioA = Double(a.value) / Double(totalVotes[a.key] ?? 1)
            let ratioB = Double(b.value) / Double(totalVotes[b.key] ?? 1)
            return ratioA < ratioB
        })?.key

        for i in words.indices where words[i].speaker != nil {
            words[i].isLocalSpeaker = words[i].speaker == localSpeakerID
        }
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

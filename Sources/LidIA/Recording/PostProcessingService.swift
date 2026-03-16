import Foundation
import SwiftData
import os

@MainActor
final class PostProcessingService {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "PostProcessingService")

    private let maxQueueAttempts = 8
    private var queueDrainTask: Task<Void, Never>?

    func processAfterCapture(
        meeting: Meeting,
        micSamples: [Float],
        systemSamples: [Float],
        sourceEvents: [AudioSourceEvent],
        modelContext: ModelContext,
        settings: AppSettings,
        eventKitManager: EventKitManager?,
        modelManager: ModelManager? = nil
    ) async {
        let combinedSamples = micSamples + systemSamples
        let useParakeetBatch = settings.sttEngine == .parakeet && !combinedSamples.isEmpty
        let useGraniteBatch = settings.sttEngine == .graniteSpeech && !combinedSamples.isEmpty
        let enableDiarization = settings.enableDiarization

        do {
            if useParakeetBatch {
                Self.logger.info("Running batch re-transcription with \(combinedSamples.count) samples")
                let processor = ParakeetBatchProcessor()
                let batchWords = try await processor.process(
                    samples: combinedSamples,
                    systemSamples: systemSamples,
                    enableDiarization: enableDiarization
                )
                if !batchWords.isEmpty {
                    var tagged = batchWords
                    let startTime = sourceEvents.first?.timestamp ?? 0
                    for i in tagged.indices {
                        tagged[i].isLocalSpeaker = Self.resolveLocalSpeaker(
                            wordStart: startTime + tagged[i].start,
                            wordEnd: startTime + tagged[i].end,
                            sourceEvents: sourceEvents
                        )
                    }
                    meeting.rawTranscript = tagged
                    Self.logger.info("Batch transcription replaced stream output with \(tagged.count) words")
                }
            } else if useGraniteBatch {
                Self.logger.info("Running Granite Speech batch transcription with \(combinedSamples.count) samples")
                let engine = GraniteSpeechEngine()
                let audioStream = AsyncStream<AudioChunk> { continuation in
                    // Feed all samples as one chunk
                    continuation.yield(AudioChunk(samples: combinedSamples, sampleRate: 16000, timestamp: 0, source: .mic))
                    continuation.finish()
                }
                var batchWords: [TranscriptWord] = []
                for await word in engine.transcribe(audioStream: audioStream) {
                    batchWords.append(word)
                }
                if !batchWords.isEmpty {
                    // Tag with local speaker info from RMS events
                    let startTime = sourceEvents.first?.timestamp ?? 0
                    for i in batchWords.indices {
                        batchWords[i].isLocalSpeaker = Self.resolveLocalSpeaker(
                            wordStart: startTime + batchWords[i].start,
                            wordEnd: startTime + batchWords[i].end,
                            sourceEvents: sourceEvents
                        )
                    }
                    meeting.rawTranscript = batchWords
                    Self.logger.info("Granite batch transcription produced \(batchWords.count) words")
                }
            }

            try await runPipelineAndAutomation(
                meeting: meeting,
                modelContext: modelContext,
                settings: settings,
                eventKitManager: eventKitManager,
                modelManager: modelManager,
                preserveUserEdits: true
            )
            meeting.processingRetryCount = 0
            try? modelContext.save()
            NotificationCenter.default.post(name: .meetingDidFinishProcessing, object: meeting)
            await DeferredMeetingProcessingQueue.shared.remove(meeting.id)
        } catch {
            if shouldQueue(error), meeting.processingRetryCount < maxQueueAttempts {
                meeting.processingRetryCount += 1
                meeting.status = .queued
                meeting.processingError = "Processing queued (attempt \(meeting.processingRetryCount)/\(maxQueueAttempts)): \(error.localizedDescription)"
                try? modelContext.save()
                await DeferredMeetingProcessingQueue.shared.enqueue(meeting.id)
                Self.logger.warning("Meeting queued for deferred processing: \(meeting.id.uuidString)")
            } else {
                meeting.status = .failed
                meeting.processingError = error.localizedDescription
                try? modelContext.save()
                await DeferredMeetingProcessingQueue.shared.remove(meeting.id)
                Self.logger.error("Meeting processing failed permanently: \(error.localizedDescription)")
            }
        }

        // Unload MLX model after processing to free RAM
        if settings.llmProvider == .mlx {
            modelManager?.unloadModel()
        }
    }

    func startQueueDrainLoop(
        contextProvider: @escaping @MainActor () -> (modelContext: ModelContext, settings: AppSettings, eventKitManager: EventKitManager?, modelManager: ModelManager?)?
    ) {
        guard queueDrainTask == nil else { return }

        queueDrainTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if let env = contextProvider() {
                    await self.drainQueuedMeetings(
                        modelContext: env.modelContext,
                        settings: env.settings,
                        eventKitManager: env.eventKitManager,
                        modelManager: env.modelManager
                    )
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stopQueueDrainLoop() {
        queueDrainTask?.cancel()
        queueDrainTask = nil
    }

    private static func resolveLocalSpeaker(
        wordStart: TimeInterval,
        wordEnd: TimeInterval,
        sourceEvents: [AudioSourceEvent]
    ) -> Bool? {
        var micRMS: Float = 0, systemRMS: Float = 0
        var micCount = 0, systemCount = 0

        for event in sourceEvents {
            guard event.timestamp >= wordStart - 0.1,
                  event.timestamp <= wordEnd + 0.1 else { continue }
            switch event.source {
            case .mic: micRMS += event.rms; micCount += 1
            case .system: systemRMS += event.rms; systemCount += 1
            case .unknown: break
            }
        }

        let avgMic = micCount > 0 ? micRMS / Float(micCount) : 0
        let avgSystem = systemCount > 0 ? systemRMS / Float(systemCount) : 0
        let threshold: Float = 0.005

        if avgMic > threshold && avgMic > avgSystem * 1.5 { return true }
        if avgSystem > threshold && avgSystem > avgMic * 1.5 { return false }
        return nil
    }

    func drainQueuedMeetings(modelContext: ModelContext, settings: AppSettings, eventKitManager: EventKitManager?, modelManager: ModelManager? = nil) async {
        let queuedIDs = await DeferredMeetingProcessingQueue.shared.all()
        guard !queuedIDs.isEmpty else { return }

        let descriptor = FetchDescriptor<Meeting>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let allMeetings = try? modelContext.fetch(descriptor) else { return }

        for id in queuedIDs {
            guard let meeting = allMeetings.first(where: { $0.id == id }) else {
                await DeferredMeetingProcessingQueue.shared.remove(id)
                continue
            }

            guard meeting.status == .queued else {
                await DeferredMeetingProcessingQueue.shared.remove(id)
                continue
            }

            if meeting.processingRetryCount >= maxQueueAttempts {
                meeting.status = .failed
                meeting.processingError = "Exceeded max queued processing attempts (\(maxQueueAttempts))."
                try? modelContext.save()
                await DeferredMeetingProcessingQueue.shared.remove(id)
                continue
            }

            meeting.status = .processing
            meeting.processingError = nil
            try? modelContext.save()

            await processAfterCapture(
                meeting: meeting,
                micSamples: [],
                systemSamples: [],
                sourceEvents: [],
                modelContext: modelContext,
                settings: settings,
                eventKitManager: eventKitManager,
                modelManager: modelManager
            )
        }
    }

    private func runPipelineAndAutomation(
        meeting: Meeting,
        modelContext: ModelContext,
        settings: AppSettings,
        eventKitManager: EventKitManager?,
        modelManager: ModelManager? = nil,
        preserveUserEdits: Bool
    ) async throws {
        let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .summarization)
        let pipeline = MeetingPipeline(
            llmClient: client,
            modelContext: modelContext
        )
        let model = effectiveModel(for: .summary, settings: settings, taskType: .summarization)
        let transcript = MeetingPipeline.buildRawText(from: meeting.rawTranscript)
        let template = await settings.resolveTemplateAsync(
            for: meeting,
            transcript: transcript,
            llmClient: client,
            model: model
        )
        meeting.templateAutoDetected = true
        settings.rememberTemplateChoice(for: meeting, templateID: template.id)
        try await pipeline.process(
            meeting: meeting,
            model: model,
            template: template,
            vocabulary: settings.customVocabulary,
            preserveUserEdits: preserveUserEdits
        )

        await PostMeetingAutomation.run(
            meeting: meeting,
            modelContext: modelContext,
            settings: settings,
            eventKitManager: eventKitManager,
            modelManager: modelManager
        )
    }

    private func shouldQueue(_ error: Error) -> Bool {
        if isConfigurationError(error) {
            return false
        }
        return RetryClassifier.isRetryable(error)
    }

    private func isConfigurationError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("api key")
            || message.contains("not configured")
            || message.contains("no model selected")
            || message.contains("no model")
    }
}

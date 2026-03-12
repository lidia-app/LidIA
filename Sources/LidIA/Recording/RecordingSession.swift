import SwiftUI
import SwiftData
import AppKit
import os
import UserNotifications

@MainActor
@Observable
final class RecordingSession {
    typealias AudioQualityState = CaptureService.AudioQualityState

    private static let logger = Logger(subsystem: "io.lidia.app", category: "RecordingSession")

    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var currentMeeting: Meeting?
    private(set) var transcriptWords: [TranscriptWord] = []

    /// Non-nil when an auto-stop is pending confirmation. Shows countdown in the pill.
    private(set) var autoStopCountdown: Int?
    /// Reason for the pending auto-stop (shown in UI).
    private(set) var autoStopReason: String?
    private var autoStopCountdownTask: Task<Void, Never>?

    var elapsedTime: TimeInterval {
        captureService.elapsedTime
    }

    /// Minutes past the calendar event's scheduled end time. Nil if no calendar event or not yet past end.
    var calendarOverrunMinutes: Int? {
        guard let endTime = calendarEndTime, isRecording else { return nil }
        let overrun = Date().timeIntervalSince(endTime)
        guard overrun > 0 else { return nil }
        return Int(overrun / 60)
    }

    var activeCaptureMode: AudioCaptureMode {
        captureService.activeCaptureMode
    }

    var captureStatusMessage: String? {
        switch captureService.captureStatus {
        case .healthy:
            return nil
        case .warning(let message), .fallbackToMic(let message), .failed(let message):
            return message
        }
    }

    var audioQualityState: AudioQualityState {
        guard isRecording else { return .good }
        return captureService.audioQualityState
    }

    private let captureService = CaptureService()
    private let transcriptionService = TranscriptionService()
    private let postProcessingService = PostProcessingService()
    private let silenceDetector = SilenceDetector()
    private var sourceEvents: [AudioSourceEvent] = []
    private var recordingStartTime: TimeInterval = 0

    private var recordingTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var liveSummaryTask: Task<Void, Never>?
    private var autoFinishTask: Task<Void, Never>?
    private var calendarEndTime: Date?

    private var storedModelContext: ModelContext?
    private var storedSettings: AppSettings?
    private var storedEventKitManager: EventKitManager?
    private var storedModelManager: ModelManager?
    private var storedMeetingDetector: MeetingDetector?

    /// Separate silence detector for extended (meeting-ended) silence check.
    /// Triggers after 2 minutes of both mic AND system audio being silent.
    private let extendedSilenceDetector = SilenceDetector()
    private var extendedSilenceTask: Task<Void, Never>?
    /// How long both channels must be silent before triggering auto-stop (seconds).
    private let extendedSilenceTimeout: TimeInterval = 60

    private let liveSummaryMaxContextWords = 3_000

    private let panelController = FloatingPanelController()
    private let pillController = RecordingPillController()

    @discardableResult
    func startRecording(modelContext: ModelContext, settings: AppSettings, modelManager: ModelManager? = nil, meetingDetector: MeetingDetector? = nil) -> Meeting {
        let meeting = Meeting(date: .now)
        modelContext.insert(meeting)
        currentMeeting = meeting
        transcriptWords = []
        isRecording = true
        storedModelContext = modelContext
        storedSettings = settings
        storedModelManager = modelManager
        storedMeetingDetector = meetingDetector
        silenceDetector.reset()
        extendedSilenceDetector.reset()
        // Cancel any in-flight tasks from a previous recording to prevent leaks
        recordingTask?.cancel()
        recordingTask = nil
        silenceTask?.cancel()
        silenceTask = nil
        autoFinishTask?.cancel()
        autoFinishTask = nil
        extendedSilenceTask?.cancel()
        extendedSilenceTask = nil
        autoStopCountdownTask?.cancel()
        autoStopCountdownTask = nil
        liveSummaryTask?.cancel()
        liveSummaryTask = nil

        // Preload MLX model if using local provider
        if settings.llmProvider == .mlx, let modelManager = storedModelManager {
            Task {
                guard !modelManager.isModelLoaded,
                      !settings.selectedMLXModelID.isEmpty else { return }
                try? await modelManager.loadModel(settings.selectedMLXModelID)
            }
        }

        recordingTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.captureService.startCapture(mode: settings.audioCaptureMode)
                Self.logger.info("Audio capture started (requested: \(settings.audioCaptureMode.rawValue), active: \(self.captureService.activeCaptureMode.rawValue))")
                self.recordingStartTime = Date().timeIntervalSince1970
            } catch {
                Self.logger.error("Audio capture failed: \(error.localizedDescription)")
                meeting.status = .failed
                meeting.processingError = error.localizedDescription
                self.isRecording = false
                return
            }

                self.pillController.show(session: self, onStop: { [weak self] in
                    guard let self,
                          let ctx = self.storedModelContext,
                          let settings = self.storedSettings else { return }
                    self.stopRecording(modelContext: ctx, settings: settings, eventKitManager: self.storedEventKitManager)
                })
                self.startSilenceMonitoring()

                // Always enable auto-finish for all recordings (not just calendar-linked ones).
                // For manual recordings this relies on meeting-app-closed and extended silence signals.
                if let detector = self.storedMeetingDetector, self.autoFinishTask == nil {
                    self.enableAutoFinish(calendarEndTime: nil, meetingDetector: detector)
                }

                let engine = self.transcriptionService.makeEngine(settings: settings)
                let wordStream = engine.transcribe(audioStream: self.captureService.audioStream)
                for await var word in wordStream {
                    word.word = settings.applyVocabulary(to: word.word)
                    self.tagWordWithSource(&word)
                    self.transcriptWords.append(word)
                    self.currentMeeting?.rawTranscript = self.transcriptWords
                }

            Self.logger.info("STT stream ended with \(self.transcriptWords.count) words")
        }

        return meeting
    }

    /// Start recording and populate meeting metadata from an Apple Calendar event.
    @discardableResult
    func startRecordingFromEvent(
        _ event: EventKitManager.CalendarEvent,
        modelContext: ModelContext,
        settings: AppSettings,
        modelManager: ModelManager? = nil,
        meetingDetector: MeetingDetector? = nil
    ) -> Meeting {
        let meeting = startRecording(modelContext: modelContext, settings: settings, modelManager: modelManager, meetingDetector: meetingDetector)
        meeting.title = event.title
        meeting.calendarEventID = event.id
        meeting.calendarAttendees = event.attendees
        if let detector = meetingDetector {
            enableAutoFinish(calendarEndTime: event.end, meetingDetector: detector)
        }
        return meeting
    }

    /// Start recording and populate meeting metadata from a Google Calendar event.
    @discardableResult
    func startRecordingFromGoogleEvent(
        _ event: GoogleCalendarClient.CalendarEvent,
        notes: String = "",
        modelContext: ModelContext,
        settings: AppSettings,
        modelManager: ModelManager? = nil,
        meetingDetector: MeetingDetector? = nil
    ) -> Meeting {
        let meeting = startRecording(modelContext: modelContext, settings: settings, modelManager: modelManager, meetingDetector: meetingDetector)
        meeting.title = event.title
        meeting.calendarEventID = event.id
        meeting.calendarAttendees = event.attendees
        if !notes.isEmpty {
            meeting.notes = notes
        }
        if let detector = meetingDetector {
            enableAutoFinish(calendarEndTime: event.end, meetingDetector: detector)
        }
        return meeting
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        isPaused = true
        captureService.pauseCapture()
        Self.logger.info("Recording paused")
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        captureService.resumeCapture()
        Self.logger.info("Recording resumed")
    }

    func enableAutoFinish(calendarEndTime: Date?, meetingDetector: MeetingDetector) {
        self.calendarEndTime = calendarEndTime
        self.storedMeetingDetector = meetingDetector
        autoFinishTask?.cancel()

        // Start window/process-based active monitoring on MeetingDetector.
        // This supplements the CoreAudio listener which is masked by LidIA's own recording.
        meetingDetector.startActiveMonitoring()

        // Watch for meeting app going inactive via polling
        autoFinishTask = Task { [weak self] in
            guard let self else { return }

            // Poll MeetingDetector every 5 seconds for inactive signal
            while !Task.isCancelled && self.isRecording {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, self.isRecording else { return }

                if meetingDetector.meetingAppBecameInactive {
                    meetingDetector.meetingAppBecameInactive = false
                    Self.logger.info("Meeting app became inactive, starting 15s grace period")

                    // Grace period
                    try? await Task.sleep(for: .seconds(15))
                    guard !Task.isCancelled, self.isRecording else { return }

                    // Check if still inactive
                    if meetingDetector.detectedApp == nil {
                        Self.logger.info("Auto-stop requested: meeting app inactive for 15s")
                        self.requestAutoStop(reason: "Meeting app closed")
                        return
                    } else {
                        Self.logger.info("Meeting app reactivated, cancelling auto-finish")
                    }
                }
            }
        }

        // Start extended silence monitoring (2+ min of both mic AND system silence)
        startExtendedSilenceMonitoring()
    }

    /// Start a 30-second countdown before auto-stopping. The user can cancel via `cancelAutoStop()`.
    /// Audio-alive suppression: if either channel has audio above threshold, the auto-stop is suppressed.
    /// During countdown, audio is re-checked each second — countdown cancels if audio resumes.
    private func requestAutoStop(reason: String) {
        guard autoStopCountdown == nil else { return } // Already pending

        // Audio-alive suppression: if either channel has audio, don't auto-stop
        let perSource = captureService.recentPerSourceRMS()
        let aliveThreshold: Float = 0.01
        if perSource.mic > aliveThreshold || perSource.system > aliveThreshold {
            Self.logger.info("Auto-stop suppressed: audio still active (mic=\(perSource.mic), system=\(perSource.system))")
            return
        }

        Self.logger.info("Auto-stop requested: \(reason) — starting 30s countdown")
        autoStopReason = reason
        autoStopCountdown = 30

        autoStopCountdownTask?.cancel()
        autoStopCountdownTask = Task { [weak self] in
            for remaining in stride(from: 29, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.isRecording else { return }

                // Re-check audio each second — cancel countdown if audio resumes
                let currentRMS = self.captureService.recentPerSourceRMS()
                if currentRMS.mic > aliveThreshold || currentRMS.system > aliveThreshold {
                    Self.logger.info("Auto-stop cancelled: audio resumed during countdown")
                    self.cancelAutoStop()
                    return
                }

                self.autoStopCountdown = remaining
            }

            // Countdown reached zero — stop for real
            guard let self, self.isRecording else { return }
            self.confirmAutoStop()
        }
    }

    /// User chose to keep recording — cancel the pending auto-stop.
    func cancelAutoStop() {
        Self.logger.info("Auto-stop cancelled by user")
        autoStopCountdownTask?.cancel()
        autoStopCountdownTask = nil
        autoStopCountdown = nil
        autoStopReason = nil
    }

    /// Immediately stop recording (from countdown expiry or explicit confirm).
    func confirmAutoStop() {
        autoStopCountdownTask?.cancel()
        autoStopCountdownTask = nil
        autoStopCountdown = nil
        autoStopReason = nil

        guard let ctx = storedModelContext, let settings = storedSettings else { return }

        Task {
            let content = UNMutableNotificationContent()
            content.title = "Meeting Ended"
            content.body = "Recording stopped — processing your transcript"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "lidia.autofinish.\(currentMeeting?.id.uuidString ?? "")",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }

        stopRecording(modelContext: ctx, settings: settings, eventKitManager: storedEventKitManager)
    }

    func stopRecording(modelContext: ModelContext, settings: AppSettings, eventKitManager: EventKitManager? = nil) {
        autoFinishTask?.cancel()
        autoFinishTask = nil
        silenceTask?.cancel()
        silenceTask = nil
        extendedSilenceTask?.cancel()
        extendedSilenceTask = nil
        liveSummaryTask?.cancel()
        liveSummaryTask = nil
        autoStopCountdownTask?.cancel()
        autoStopCountdownTask = nil
        autoStopCountdown = nil
        autoStopReason = nil
        silenceDetector.reset()
        extendedSilenceDetector.reset()

        // Stop window/process-based active monitoring
        storedMeetingDetector?.stopActiveMonitoring()
        storedMeetingDetector = nil

        let drainResult = captureService.stopCaptureAndDrainSamples()
        sourceEvents.append(contentsOf: drainResult.sourceEvents)

        recordingTask?.cancel()
        recordingTask = nil
        isRecording = false
        isPaused = false
        storedModelContext = nil
        storedSettings = nil
        storedEventKitManager = eventKitManager
        let capturedModelManager = storedModelManager
        storedModelManager = nil

        // Free MLX model memory after post-processing completes (see Task below)
        // Model will be re-loaded on next recording start if needed
        pillController.close()

        guard let meeting = currentMeeting else { return }
        meeting.duration = captureService.elapsedTime
        meeting.rawTranscript = normalizeWordTimings(transcriptWords, meetingDuration: meeting.duration)

        if meeting.rawTranscript.isEmpty {
            meeting.status = .complete
            meeting.summary = "No transcript captured."
            currentMeeting = nil
            return
        }

        meeting.status = .processing
        if meeting.userEditedSummary?.isEmpty != false {
            meeting.summary = ""
            startPostProcessingLiveSummary(meeting: meeting, settings: settings)
        }

        Task { [weak self] in
            guard let self else { return }
            await self.postProcessingService.processAfterCapture(
                meeting: meeting,
                micSamples: drainResult.mic,
                systemSamples: drainResult.system,
                sourceEvents: self.sourceEvents,
                modelContext: modelContext,
                settings: settings,
                eventKitManager: eventKitManager,
                modelManager: capturedModelManager
            )
            // Free MLX model memory after post-processing is done
            capturedModelManager?.unloadModel()
        }

        sourceEvents.removeAll()
        currentMeeting = nil
    }

    func resumeQueuedProcessing(modelContext: ModelContext, settings: AppSettings, eventKitManager: EventKitManager?, modelManager: ModelManager? = nil) {
        storedModelContext = modelContext
        storedSettings = settings
        storedEventKitManager = eventKitManager
        storedModelManager = modelManager

        postProcessingService.startQueueDrainLoop { [weak self] in
            guard let self,
                  !self.isRecording,
                  let context = self.storedModelContext,
                  let settings = self.storedSettings else {
                return nil
            }
            return (context, settings, self.storedEventKitManager, self.storedModelManager)
        }

        Task {
            await postProcessingService.drainQueuedMeetings(
                modelContext: modelContext,
                settings: settings,
                eventKitManager: eventKitManager,
                modelManager: modelManager
            )
        }
    }

    // MARK: - Source-Based Word Tagging

    private func tagWordWithSource(_ word: inout TranscriptWord) {
        // Drain new events from capture service
        let newEvents = captureService.drainSourceEvents()
        sourceEvents.append(contentsOf: newEvents)

        let wordStart = recordingStartTime + word.start
        let wordEnd = recordingStartTime + word.end

        var micRMS: Float = 0
        var systemRMS: Float = 0
        var micCount = 0
        var systemCount = 0

        for event in sourceEvents {
            guard event.timestamp >= wordStart - 0.1,
                  event.timestamp <= wordEnd + 0.1 else { continue }
            switch event.source {
            case .mic:
                micRMS += event.rms
                micCount += 1
            case .system:
                systemRMS += event.rms
                systemCount += 1
            case .unknown:
                break
            }
        }

        let avgMic = micCount > 0 ? micRMS / Float(micCount) : 0
        let avgSystem = systemCount > 0 ? systemRMS / Float(systemCount) : 0
        let threshold: Float = 0.005

        if avgMic > threshold && avgMic > avgSystem * 1.5 {
            word.isLocalSpeaker = true
        } else if avgSystem > threshold && avgSystem > avgMic * 1.5 {
            word.isLocalSpeaker = false
        } else {
            word.isLocalSpeaker = nil
        }

        // Trim old events (keep last 30s)
        let cutoff = (sourceEvents.last?.timestamp ?? 0) - 30
        sourceEvents.removeAll { $0.timestamp < cutoff }
    }

    // MARK: - Silence Monitoring

    private func startSilenceMonitoring() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled,
                      let self,
                      self.isRecording,
                      let settings = self.storedSettings,
                      settings.autoStopOnSilence else { continue }

                let rms = self.captureService.currentRMS
                let exceeded = self.silenceDetector.update(
                    rms: rms,
                    timeout: settings.silenceTimeoutSeconds
                )
                if exceeded {
                    Self.logger.info("Auto-stop requested: silence timeout (\(settings.silenceTimeoutSeconds)s)")
                    self.requestAutoStop(reason: "Silence detected")
                    return
                }
            }
        }
    }

    // MARK: - Extended Silence Monitoring (Meeting-End Detection)

    /// Monitors for prolonged silence on BOTH mic and system audio simultaneously.
    /// Unlike the regular silence detector (which catches brief pauses), this detects
    /// when the call has truly ended — both sides silent for 2+ minutes.
    private func startExtendedSilenceMonitoring() {
        extendedSilenceTask?.cancel()
        extendedSilenceDetector.reset()

        extendedSilenceTask = Task { [weak self] in
            // Track how long both channels have been simultaneously silent
            var bothSilentSince: Date?

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled,
                      let self,
                      self.isRecording else { return }

                let perSource = self.captureService.recentPerSourceRMS()
                let silenceThreshold: Float = 0.01

                let micSilent = perSource.mic < silenceThreshold
                let systemSilent = perSource.system < silenceThreshold

                if micSilent && systemSilent {
                    if bothSilentSince == nil {
                        bothSilentSince = Date()
                        Self.logger.debug("Extended silence: both channels silent — tracking started")
                    }

                    let duration = Date().timeIntervalSince(bothSilentSince!)
                    if duration >= self.extendedSilenceTimeout {
                        Self.logger.info("Auto-stop requested: extended silence (\(Int(duration))s on both channels)")
                        self.requestAutoStop(reason: "Extended silence — meeting may have ended")
                        return
                    }
                } else {
                    if bothSilentSince != nil {
                        Self.logger.debug("Extended silence: audio resumed after \(Int(Date().timeIntervalSince(bothSilentSince!)))s")
                        bothSilentSince = nil
                    }
                }
            }
        }
    }

    // MARK: - Live Summary

    private func startPostProcessingLiveSummary(meeting: Meeting, settings: AppSettings) {
        liveSummaryTask?.cancel()
        liveSummaryTask = Task { [weak self] in
            guard let self else { return }
            guard meeting.status == .processing else { return }
            guard meeting.userEditedSummary?.isEmpty != false else { return }

            let transcriptSnippet = buildLiveSummaryTranscript(from: meeting.rawTranscript)
            guard !transcriptSnippet.isEmpty else { return }

            let model = effectiveModel(for: .summary, settings: settings, taskType: .summarization)
            guard !model.isEmpty else { return }

            await streamLiveSummaryDraft(
                meeting: meeting,
                transcriptSnippet: transcriptSnippet,
                settings: settings,
                model: model
            )
        }
    }

    private func buildLiveSummaryTranscript(from words: [TranscriptWord]) -> String {
        guard !words.isEmpty else { return "" }
        let excerptWords: [TranscriptWord]
        if words.count <= liveSummaryMaxContextWords {
            excerptWords = words
        } else {
            let headCount = Int(Double(liveSummaryMaxContextWords) * 0.6)
            let tailCount = liveSummaryMaxContextWords - headCount
            excerptWords = Array(words.prefix(headCount)) + Array(words.suffix(tailCount))
        }
        return excerptWords.map(\.word).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func streamLiveSummaryDraft(
        meeting: Meeting,
        transcriptSnippet: String,
        settings: AppSettings,
        model: String
    ) async {
        let llm = makeLLMClient(settings: settings, modelManager: storedModelManager, taskType: .summarization)
        let existing = meeting.summary.trimmingCharacters(in: .whitespacesAndNewlines)

        let systemPrompt = """
        You are generating a LIVE meeting summary while the call is still in progress.
        Return concise markdown with:
        - A short overview paragraph
        - 3-8 bullet points for key updates
        - Optional section "Open Questions" when unresolved items appear
        Keep it factual, avoid inventing details, and improve the draft incrementally as new transcript arrives.
        Do not mention that you are an AI.
        """

        var userPrompt = "Meeting title: \(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)\n\n"
        if !existing.isEmpty {
            userPrompt += "Current draft summary:\n\(existing)\n\n"
        }
        userPrompt += """
        Latest transcript excerpt:
        \(transcriptSnippet)
        """

        let messages: [LLMChatMessage] = [
            .init(role: "system", content: systemPrompt),
            .init(role: "user", content: userPrompt),
        ]

        var streamed = ""
        var lastUIRefresh = Date.distantPast

        do {
            for try await token in await llm.chatStream(messages: messages, model: model) {
                if Task.isCancelled || meeting.status != .processing {
                    return
                }
                streamed += token

                if Date().timeIntervalSince(lastUIRefresh) > 0.15 {
                    let draft = streamed.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !draft.isEmpty {
                        meeting.summary = draft
                    }
                    lastUIRefresh = .now
                }
            }

            let finalDraft = streamed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !finalDraft.isEmpty, meeting.status == .processing {
                meeting.summary = finalDraft
            }
        } catch {
            Self.logger.debug("Live summary refresh skipped: \(error.localizedDescription)")
        }
    }

    // MARK: - Floating Panel

    private func showFloatingPanel() {
        let view = FloatingTranscriptView(
            session: self,
            onClose: { [weak self] in
                self?.hideFloatingPanel()
            }
        )
        panelController.show(rootView: view)
    }

    func hideFloatingPanel() {
        panelController.close()
    }

    private func normalizeWordTimings(_ words: [TranscriptWord], meetingDuration: TimeInterval) -> [TranscriptWord] {
        guard !words.isEmpty else { return [] }
        var normalized = words

        if let minStart = normalized.map(\.start).min() {
            let looksEpochBased = minStart > max(10_000, meetingDuration + 60)
            if looksEpochBased {
                for i in normalized.indices {
                    normalized[i].start -= minStart
                    normalized[i].end -= minStart
                }
            }
        }

        // If timing is unusable (all zero/negative), synthesize an even timeline.
        let hasUsefulTiming = normalized.contains { $0.end > $0.start || $0.start > 0.01 }
        if !hasUsefulTiming {
            let total = meetingDuration > 1 ? meetingDuration : max(1, Double(normalized.count) * 0.25)
            let step = total / Double(max(1, normalized.count))
            for i in normalized.indices {
                normalized[i].start = Double(i) * step
                normalized[i].end = Double(i + 1) * step
            }
        }

        for i in normalized.indices {
            if normalized[i].start < 0 { normalized[i].start = 0 }
            if normalized[i].end < normalized[i].start {
                normalized[i].end = normalized[i].start + 0.05
            }
        }

        return normalized.sorted { $0.start < $1.start }
    }
}

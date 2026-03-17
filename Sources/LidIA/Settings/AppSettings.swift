import Foundation
import Observation
import os
import Security
import SwiftUI

@MainActor
@Observable
final class AppSettings {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "AppSettings")
    private var isLoading = false

    // MARK: - Domain Settings (composed)

    let llm = LLMSettings()
    let calendar = CalendarSettings()
    let voice = VoiceSettings()
    let integration = IntegrationSettings()
    let recording = RecordingSettings()

    // MARK: - General Settings (remain here)

    var hasCompletedSetup: Bool = false {
        didSet { saveDefault(hasCompletedSetup, forKey: "hasCompletedSetup") }
    }

    var appearanceMode: AppearanceMode = .system {
        didSet { saveDefault(appearanceMode.rawValue, forKey: "appearanceMode") }
    }

    var autoStart: Bool = false {
        didSet { saveDefault(autoStart, forKey: "autoStart") }
    }

    var favoritePersonIDs: Set<String> = [] {
        didSet { saveFavoritePersonIDs() }
    }

    // Templates
    var meetingTemplates: [MeetingTemplate] = MeetingTemplate.builtInTemplates {
        didSet { saveTemplates() }
    }

    // Template recurrence map: recurring event ID or attendee hash -> template ID
    var templateRecurrenceMap: [String: String] = [:] {
        didSet { saveRecurrenceMap() }
    }

    // MARK: - Forwarding Properties (backward compatibility)
    // These forward to domain settings objects so existing code using
    // `settings.llmProvider`, `settings.ollamaURL`, etc. continues to work.

    // --- LLM ---
    var llmProvider: LLMProvider {
        get { llm.llmProvider }
        set { llm.llmProvider = newValue }
    }
    var ollamaURL: String {
        get { llm.ollamaURL }
        set { llm.ollamaURL = newValue }
    }
    var ollamaModel: String {
        get { llm.ollamaModel }
        set { llm.ollamaModel = newValue }
    }
    var openaiBaseURL: String {
        get { llm.openaiBaseURL }
        set { llm.openaiBaseURL = newValue }
    }
    var openaiAPIKey: String {
        get { llm.openaiAPIKey }
        set { llm.openaiAPIKey = newValue }
    }
    var openaiModel: String {
        get { llm.openaiModel }
        set { llm.openaiModel = newValue }
    }
    var selectedMLXModelID: String {
        get { llm.selectedMLXModelID }
        set { llm.selectedMLXModelID = newValue }
    }
    var anthropicAPIKey: String {
        get { llm.anthropicAPIKey }
        set { llm.anthropicAPIKey = newValue }
    }
    var anthropicModel: String {
        get { llm.anthropicModel }
        set { llm.anthropicModel = newValue }
    }
    var queryModel: String {
        get { llm.queryModel }
        set { llm.queryModel = newValue }
    }
    var summaryModel: String {
        get { llm.summaryModel }
        set { llm.summaryModel = newValue }
    }
    var routeOverrides: [String: Data] {
        get { llm.routeOverrides }
        set { llm.routeOverrides = newValue }
    }
    var availableModels: [String] {
        get { llm.availableModels }
        set { llm.availableModels = newValue }
    }
    var cerebrasAPIKey: String {
        get { llm.cerebrasAPIKey }
        set { llm.cerebrasAPIKey = newValue }
    }
    var cerebrasModel: String {
        get { llm.cerebrasModel }
        set { llm.cerebrasModel = newValue }
    }
    var deepseekAPIKey: String {
        get { llm.deepseekAPIKey }
        set { llm.deepseekAPIKey = newValue }
    }
    var deepseekModel: String {
        get { llm.deepseekModel }
        set { llm.deepseekModel = newValue }
    }
    var nvidiaAPIKey: String {
        get { llm.nvidiaAPIKey }
        set { llm.nvidiaAPIKey = newValue }
    }
    var nvidiaModel: String {
        get { llm.nvidiaModel }
        set { llm.nvidiaModel = newValue }
    }
    var openRouterAPIKey: String {
        get { llm.openRouterAPIKey }
        set { llm.openRouterAPIKey = newValue }
    }
    var openRouterModel: String {
        get { llm.openRouterModel }
        set { llm.openRouterModel = newValue }
    }
    var fallbackProvider: String {
        get { llm.fallbackProvider }
        set { llm.fallbackProvider = newValue }
    }
    var fallbackModel: String {
        get { llm.fallbackModel }
        set { llm.fallbackModel = newValue }
    }

    // --- Voice / STT ---
    var sttEngine: STTEngineType {
        get { voice.sttEngine }
        set { voice.sttEngine = newValue }
    }
    var whisperKitModel: String {
        get { voice.whisperKitModel }
        set { voice.whisperKitModel = newValue }
    }
    var enableDiarization: Bool {
        get { voice.enableDiarization }
        set { voice.enableDiarization = newValue }
    }
    var sttLanguage: String {
        get { voice.sttLanguage }
        set { voice.sttLanguage = newValue }
    }
    var voiceEnabled: Bool {
        get { voice.voiceEnabled }
        set { voice.voiceEnabled = newValue }
    }
    var voiceHotkey: String {
        get { voice.voiceHotkey }
        set { voice.voiceHotkey = newValue }
    }
    var ttsProvider: TTSProvider {
        get { voice.ttsProvider }
        set { voice.ttsProvider = newValue }
    }
    var ttsVoiceID: String {
        get { voice.ttsVoiceID }
        set { voice.ttsVoiceID = newValue }
    }
    var selectedTTSModelID: String {
        get { voice.selectedTTSModelID }
        set { voice.selectedTTSModelID = newValue }
    }
    var voiceReadResponses: Bool {
        get { voice.voiceReadResponses }
        set { voice.voiceReadResponses = newValue }
    }
    var voiceSilenceTimeout: Double {
        get { voice.voiceSilenceTimeout }
        set { voice.voiceSilenceTimeout = newValue }
    }
    var assistantPersonality: AssistantPersonality {
        get { voice.assistantPersonality }
        set { voice.assistantPersonality = newValue }
    }
    var customVocabulary: [VocabularyEntry] {
        get { voice.customVocabulary }
        set { voice.customVocabulary = newValue }
    }

    // --- Calendar ---
    var googleCalendarEnabled: Bool {
        get { calendar.googleCalendarEnabled }
        set { calendar.googleCalendarEnabled = newValue }
    }
    var googleClientID: String {
        get { calendar.googleClientID }
        set { calendar.googleClientID = newValue }
    }
    var googleClientSecret: String {
        get { calendar.googleClientSecret }
        set { calendar.googleClientSecret = newValue }
    }
    var calendarEnabled: Bool {
        get { calendar.calendarEnabled }
        set { calendar.calendarEnabled = newValue }
    }
    var remindersEnabled: Bool {
        get { calendar.remindersEnabled }
        set { calendar.remindersEnabled = newValue }
    }
    var showCalendarSection: Bool {
        get { calendar.showCalendarSection }
        set { calendar.showCalendarSection = newValue }
    }
    var notifyUpcomingMeetings: Bool {
        get { calendar.notifyUpcomingMeetings }
        set { calendar.notifyUpcomingMeetings = newValue }
    }
    var calendarRecordPromptEnabled: Bool {
        get { calendar.calendarRecordPromptEnabled }
        set { calendar.calendarRecordPromptEnabled = newValue }
    }
    var prepNotificationsEnabled: Bool {
        get { calendar.prepNotificationsEnabled }
        set { calendar.prepNotificationsEnabled = newValue }
    }
    var meetingNotificationMinutes: Int {
        get { calendar.meetingNotificationMinutes }
        set { calendar.meetingNotificationMinutes = newValue }
    }
    var proactiveMorningDigest: Bool {
        get { calendar.proactiveMorningDigest }
        set { calendar.proactiveMorningDigest = newValue }
    }
    var proactiveMorningDigestTime: Date {
        get { calendar.proactiveMorningDigestTime }
        set { calendar.proactiveMorningDigestTime = newValue }
    }
    var proactiveMorningDigestFrequency: String {
        get { calendar.proactiveMorningDigestFrequency }
        set { calendar.proactiveMorningDigestFrequency = newValue }
    }
    var proactivePreMeetingPrep: Bool {
        get { calendar.proactivePreMeetingPrep }
        set { calendar.proactivePreMeetingPrep = newValue }
    }
    var proactivePreMeetingMinutes: Int {
        get { calendar.proactivePreMeetingMinutes }
        set { calendar.proactivePreMeetingMinutes = newValue }
    }
    var proactivePostMeetingNudge: Bool {
        get { calendar.proactivePostMeetingNudge }
        set { calendar.proactivePostMeetingNudge = newValue }
    }
    var proactivePostMeetingMinutes: Int {
        get { calendar.proactivePostMeetingMinutes }
        set { calendar.proactivePostMeetingMinutes = newValue }
    }
    var proactiveActionItemReminders: Bool {
        get { calendar.proactiveActionItemReminders }
        set { calendar.proactiveActionItemReminders = newValue }
    }
    var proactiveQuietStart: Date {
        get { calendar.proactiveQuietStart }
        set { calendar.proactiveQuietStart = newValue }
    }
    var proactiveQuietEnd: Date {
        get { calendar.proactiveQuietEnd }
        set { calendar.proactiveQuietEnd = newValue }
    }
    var autoDetectMeetings: Bool {
        get { calendar.autoDetectMeetings }
        set { calendar.autoDetectMeetings = newValue }
    }

    // --- Integration ---
    var notionAPIKey: String {
        get { integration.notionAPIKey }
        set { integration.notionAPIKey = newValue }
    }
    var notionDatabaseID: String {
        get { integration.notionDatabaseID }
        set { integration.notionDatabaseID = newValue }
    }
    var notionDatabaseName: String {
        get { integration.notionDatabaseName }
        set { integration.notionDatabaseName = newValue }
    }
    var notionTasksDatabaseID: String {
        get { integration.notionTasksDatabaseID }
        set { integration.notionTasksDatabaseID = newValue }
    }
    var availableDatabases: [DatabaseEntry] {
        get { integration.availableDatabases }
        set { integration.availableDatabases = newValue }
    }
    var n8nEnabled: Bool {
        get { integration.n8nEnabled }
        set { integration.n8nEnabled = newValue }
    }
    var n8nWebhookURL: String {
        get { integration.n8nWebhookURL }
        set { integration.n8nWebhookURL = newValue }
    }
    var n8nAuthHeader: String {
        get { integration.n8nAuthHeader }
        set { integration.n8nAuthHeader = newValue }
    }
    var slackEnabled: Bool {
        get { integration.slackEnabled }
        set { integration.slackEnabled = newValue }
    }
    var slackBotToken: String {
        get { integration.slackBotToken }
        set { integration.slackBotToken = newValue }
    }
    var slackChannel: String {
        get { integration.slackChannel }
        set { integration.slackChannel = newValue }
    }
    var slackAutoSend: Bool {
        get { integration.slackAutoSend }
        set { integration.slackAutoSend = newValue }
    }
    var slackSendSummary: Bool {
        get { integration.slackSendSummary }
        set { integration.slackSendSummary = newValue }
    }
    var slackSendActionItems: Bool {
        get { integration.slackSendActionItems }
        set { integration.slackSendActionItems = newValue }
    }
    var slackSendAttendees: Bool {
        get { integration.slackSendAttendees }
        set { integration.slackSendAttendees = newValue }
    }
    var syncEnabled: Bool {
        get { integration.syncEnabled }
        set { integration.syncEnabled = newValue }
    }
    var syncServerURL: String {
        get { integration.syncServerURL }
        set { integration.syncServerURL = newValue }
    }
    var syncAuthToken: String {
        get { integration.syncAuthToken }
        set { integration.syncAuthToken = newValue }
    }
    var notionAutoSend: Bool {
        get { integration.notionAutoSend }
        set { integration.notionAutoSend = newValue }
    }
    var n8nAutoSend: Bool {
        get { integration.n8nAutoSend }
        set { integration.n8nAutoSend = newValue }
    }
    var remindersAutoSend: Bool {
        get { integration.remindersAutoSend }
        set { integration.remindersAutoSend = newValue }
    }
    var notionSendSummary: Bool {
        get { integration.notionSendSummary }
        set { integration.notionSendSummary = newValue }
    }
    var notionSendActionItems: Bool {
        get { integration.notionSendActionItems }
        set { integration.notionSendActionItems = newValue }
    }
    var n8nSendSummary: Bool {
        get { integration.n8nSendSummary }
        set { integration.n8nSendSummary = newValue }
    }
    var n8nSendActionItems: Bool {
        get { integration.n8nSendActionItems }
        set { integration.n8nSendActionItems = newValue }
    }
    var n8nSendAttendees: Bool {
        get { integration.n8nSendAttendees }
        set { integration.n8nSendAttendees = newValue }
    }
    var n8nSendTranscript: Bool {
        get { integration.n8nSendTranscript }
        set { integration.n8nSendTranscript = newValue }
    }
    var remindersMyItemsOnly: Bool {
        get { integration.remindersMyItemsOnly }
        set { integration.remindersMyItemsOnly = newValue }
    }
    var clickUpAPIKey: String {
        get { integration.clickUpAPIKey }
        set { integration.clickUpAPIKey = newValue }
    }
    var clickUpListID: String {
        get { integration.clickUpListID }
        set { integration.clickUpListID = newValue }
    }
    var autopilotEnabled: Bool {
        get { integration.autopilotEnabled }
        set { integration.autopilotEnabled = newValue }
    }
    var vaultExportEnabled: Bool {
        get { integration.vaultExportEnabled }
        set { integration.vaultExportEnabled = newValue }
    }
    var vaultExportPath: String {
        get { integration.vaultExportPath }
        set { integration.vaultExportPath = newValue }
    }
    var vaultExportIncludeTranscript: Bool {
        get { integration.vaultExportIncludeTranscript }
        set { integration.vaultExportIncludeTranscript = newValue }
    }

    // --- Recording ---
    var audioCaptureMode: AudioCaptureMode {
        get { recording.audioCaptureMode }
        set { recording.audioCaptureMode = newValue }
    }
    var autoStopOnSilence: Bool {
        get { recording.autoStopOnSilence }
        set { recording.autoStopOnSilence = newValue }
    }
    var silenceTimeoutSeconds: Double {
        get { recording.silenceTimeoutSeconds }
        set { recording.silenceTimeoutSeconds = newValue }
    }
    var displayName: String {
        get { recording.displayName }
        set { recording.displayName = newValue }
    }
    var noiseReductionEnabled: Bool {
        get { recording.noiseReductionEnabled }
        set { recording.noiseReductionEnabled = newValue }
    }

    // MARK: - Nested Types

    enum AppearanceMode: String, CaseIterable, Sendable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    enum LLMProvider: String, CaseIterable, Codable, Sendable {
        case ollama = "Ollama"
        case mlx = "Local (MLX)"
        case openai = "OpenAI"
        case anthropic = "Anthropic"
        case cerebras = "Cerebras (Free)"
        case deepseek = "DeepSeek"
        case nvidiaNIM = "NVIDIA NIM"
        case openRouter = "OpenRouter"
    }

    enum TTSProvider: String, CaseIterable, Sendable {
        case automatic = "Automatic"
        case mlx = "Local (MLX)"
        case system = "System Voice"
        case openai = "OpenAI"
    }

    enum AssistantPersonality: String, CaseIterable, Sendable {
        case professional = "Professional"
        case friendly = "Friendly"
        case witty = "Witty"

        var promptFragment: String {
            switch self {
            case .professional:
                return "Be direct and efficient. No small talk."
            case .friendly:
                return "Be warm, encouraging, and supportive. Use a casual tone."
            case .witty:
                return "Be clever and humorous. Add light humor where appropriate, but stay helpful."
            }
        }
    }

    enum STTEngineType: String, CaseIterable, Sendable {
        case parakeet = "Parakeet TDT (Recommended)"
        case graniteSpeech = "Granite Speech 4.0 (Multilingual)"
        case whisperKit = "WhisperKit"
        case appleSpeech = "Apple Speech"
    }

    struct DatabaseEntry: Identifiable, Sendable {
        let id: String
        let title: String
    }

    struct VocabularyEntry: Identifiable, Codable, Sendable, Equatable {
        var id = UUID()
        var heardAs: String    // What the STT engine produces (e.g., "buffer")
        var replaceTo: String  // What it should be (e.g., "WAFR")
        var caseSensitive: Bool = false
    }

    // MARK: - Init

    init() {
        loadFromDefaults()
    }

    private func loadFromDefaults() {
        isLoading = true
        defer { isLoading = false }
        let defaults = UserDefaults.standard

        // General settings loaded directly
        hasCompletedSetup = defaults.bool(forKey: "hasCompletedSetup")

        // Migration: existing users who have used the app before should skip the setup wizard.
        if defaults.object(forKey: "llmProvider") != nil && !hasCompletedSetup {
            hasCompletedSetup = true
            saveDefault(true, forKey: "hasCompletedSetup")
        }

        autoStart = defaults.bool(forKey: "autoStart")
        appearanceMode = AppearanceMode(rawValue: defaults.string(forKey: "appearanceMode") ?? "") ?? .system

        loadFavoritePersonIDs()
        loadRecurrenceMap()
        loadTemplates()
    }

    // MARK: - Forwarding Methods

    func routeConfig(for taskType: LLMTaskType) -> LLMRouteConfig? {
        llm.routeConfig(for: taskType)
    }

    func setRouteConfig(_ config: LLMRouteConfig?, for taskType: LLMTaskType) {
        llm.setRouteConfig(config, for: taskType)
    }

    func applyVocabulary(to word: String) -> String {
        voice.applyVocabulary(to: word)
    }

    // MARK: - Template Persistence

    private func saveTemplates() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(meetingTemplates) {
            UserDefaults.standard.set(data, forKey: "meetingTemplates")
        }
    }

    private func loadTemplates() {
        guard let data = UserDefaults.standard.data(forKey: "meetingTemplates"),
              let saved = try? JSONDecoder().decode([MeetingTemplate].self, from: data) else {
            meetingTemplates = MeetingTemplate.builtInTemplates
            return
        }
        // Merge: keep built-ins current, preserve custom templates
        var merged = MeetingTemplate.builtInTemplates
        let builtInIDs = Set(MeetingTemplate.builtInTemplates.map(\.id))
        for template in saved where !builtInIDs.contains(template.id) {
            merged.append(template)
        }
        meetingTemplates = merged
    }

    // MARK: - Favorite Person IDs Persistence

    private func saveFavoritePersonIDs() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(Array(favoritePersonIDs)) {
            UserDefaults.standard.set(data, forKey: "favoritePersonIDs")
        }
    }

    private func loadFavoritePersonIDs() {
        guard let data = UserDefaults.standard.data(forKey: "favoritePersonIDs"),
              let saved = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }
        favoritePersonIDs = Set(saved)
    }

    // MARK: - Recurrence Map Persistence

    private func saveRecurrenceMap() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(templateRecurrenceMap) {
            UserDefaults.standard.set(data, forKey: "templateRecurrenceMap")
        }
    }

    private func loadRecurrenceMap() {
        guard let data = UserDefaults.standard.data(forKey: "templateRecurrenceMap"),
              let saved = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        templateRecurrenceMap = saved
    }

    // MARK: - Template Resolution

    /// Synchronous template resolution: recurrence memory -> rule matching -> fallback to general.
    func resolveTemplate(for meeting: Meeting) -> MeetingTemplate {
        // Tier 1: Recurrence memory
        if let eventID = meeting.calendarEventID,
           let templateIDStr = templateRecurrenceMap[eventID],
           let templateID = UUID(uuidString: templateIDStr),
           let template = meetingTemplates.first(where: { $0.id == templateID }) {
            return template
        }
        if let hash = meeting.attendeeHash,
           let templateIDStr = templateRecurrenceMap[hash],
           let templateID = UUID(uuidString: templateIDStr),
           let template = meetingTemplates.first(where: { $0.id == templateID }) {
            return template
        }

        // Tier 2: Rule matching
        let attendees = meeting.calendarAttendees?.count ?? 0
        let title = meeting.title
        for template in meetingTemplates where template.id != MeetingTemplate.general.id {
            if template.autoDetectRules.matches(title: title, attendees: attendees) {
                return template
            }
        }

        return MeetingTemplate.general
    }

    /// Async template resolution with LLM fallback for ambiguous cases.
    func resolveTemplateAsync(for meeting: Meeting, transcript: String, llmClient: any LLMClient, model: String) async -> MeetingTemplate {
        let syncResult = resolveTemplate(for: meeting)
        if syncResult.id != MeetingTemplate.general.id {
            return syncResult
        }

        // Tier 3: LLM selection (only when sync falls through to general)
        guard meetingTemplates.count > 1 else { return syncResult }

        let templateList = meetingTemplates.map { t in
            "- \(t.id.uuidString): \(t.name) — \(t.description)"
        }.joined(separator: "\n")

        let excerpt = String(transcript.prefix(2000))
        let prompt = """
        Given this meeting transcript excerpt and the available templates, which template best fits this meeting?
        Return ONLY the template UUID, nothing else.

        Templates:
        \(templateList)

        Transcript excerpt:
        \(excerpt)
        """

        do {
            let response = try await llmClient.chat(
                messages: [.init(role: "user", content: prompt)],
                model: model,
                format: nil
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            if let uuid = UUID(uuidString: response),
               let template = meetingTemplates.first(where: { $0.id == uuid }) {
                return template
            }
        } catch {
            Self.logger.error("LLM template selection failed: \(error)")
        }

        return syncResult
    }

    /// Record template choice for future recurrence matching.
    func rememberTemplateChoice(for meeting: Meeting, templateID: UUID) {
        if let eventID = meeting.calendarEventID {
            templateRecurrenceMap[eventID] = templateID.uuidString
        }
        if let hash = meeting.attendeeHash {
            templateRecurrenceMap[hash] = templateID.uuidString
        }
    }

    // MARK: - Persistence Helpers

    private func saveDefault(_ value: some Any, forKey key: String) {
        guard !isLoading else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
}

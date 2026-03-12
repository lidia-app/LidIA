import AppKit
import os
import SwiftData
import SwiftUI
import UserNotifications

private let appLogger = Logger(subsystem: "io.lidia.app", category: "LidIAApp")

// Ensures the app activates properly when run via `swift run` (bare executable,
// not a .app bundle). Without this, the window may not become "key" and
// TextFields won't receive keyboard input.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by LidIAApp so notification actions can start recording.
    @MainActor static var session: RecordingSession?
    @MainActor static var settings: AppSettings?
    @MainActor static var modelContainer: ModelContainer?
    @MainActor static var meetingDetectorRef: MeetingDetector?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            EventKitManager.registerNotificationCategories()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case "JOIN_AND_RECORD":
            // Merged action: open meeting link AND start recording
            let linkString = userInfo["meetingLink"] as? String
            let eventTitle = userInfo["eventTitle"] as? String
            let eventID = userInfo["eventID"] as? String
            await MainActor.run {
                if let linkString, !linkString.isEmpty, let url = URL(string: linkString) {
                    NSWorkspace.shared.open(url)
                }
                Self.startRecording(eventTitle: eventTitle, eventID: eventID)
            }
        case "JOIN_MEETING":
            // Backward compatibility with already-scheduled notifications
            let linkString = userInfo["meetingLink"] as? String
            let eventTitle = userInfo["eventTitle"] as? String
            let eventID = userInfo["eventID"] as? String
            await MainActor.run {
                if let linkString, !linkString.isEmpty, let url = URL(string: linkString) {
                    NSWorkspace.shared.open(url)
                }
                Self.startRecording(eventTitle: eventTitle, eventID: eventID)
            }
        case "RECORD_MEETING":
            let eventTitle = userInfo["eventTitle"] as? String
            let eventID = userInfo["eventID"] as? String
            await MainActor.run {
                NSApp.activate()
                Self.startRecording(eventTitle: eventTitle, eventID: eventID)
            }
        case "SKIP_RECORDING":
            break
        case NotificationDispatcher.viewActionIdentifier, UNNotificationDefaultActionIdentifier:
            let destination = userInfo[NotificationDispatcher.destinationUserInfoKey] as? String
            let eventID = userInfo[NotificationDispatcher.eventIDUserInfoKey] as? String
            if let destination {
                await MainActor.run {
                    NSApp.activate()
                    NotificationDispatcher.postNavigation(destinationRawValue: destination, eventID: eventID)
                }
            }
        default:
            break
        }
    }

    @MainActor
    static func startRecording(eventTitle: String?, eventID: String?) {
        guard let session, let settings, let container = modelContainer else { return }
        guard !session.isRecording else { return }

        let context = ModelContext(container)
        let meeting = session.startRecording(modelContext: context, settings: settings, meetingDetector: meetingDetectorRef)
        if let eventTitle {
            meeting.title = eventTitle
        }
        if let eventID {
            meeting.calendarEventID = eventID
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if let type = notification.request.content.userInfo["notificationType"] as? String,
           type == "recordPrompt",
           await MainActor.run(body: { Self.session?.isRecording == true }) {
            return UNNotificationPresentationOptions()
        }
        return [.banner, .sound]
    }
}

@main
struct LidIAApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var session = RecordingSession()
    @State private var queryService = MeetingQueryService()
    @State private var eventKitManager = EventKitManager()
    @State private var googleCalendarMonitor = GoogleCalendarMonitor()
    @State private var settings = AppSettings()
    @State private var menuBarController = MenuBarController()
    @State private var meetingDetector = MeetingDetector()
    @State private var modelManager = ModelManager()
    @State private var ttsModelManager = TTSModelManager()
    @State private var proactiveScheduler = ProactiveScheduler()
    @State private var voiceAssistant = VoiceAssistantService()
    @State private var voiceOrbPanel = VoiceOrbPanelController()
    @State private var syncManager = SyncManager()
    @State private var backgroundContext: ModelContext?
    private let bannerController = MeetingDetectionBannerController()
    private let joinBannerController = MeetingJoinBannerController()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: AppSchema.self)
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            appLogger.error("ModelContainer failed: \(error). Attempting recovery without data loss...")

            // Try once more — sometimes the retry alone succeeds after the OS clears locks
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                // Last resort: warn loudly and delete. This should be extremely rare.
                appLogger.error("CRITICAL: ModelContainer failed twice. Deleting store as last resort: \(error)")
                if let url = config.url as URL? {
                    let fm = FileManager.default
                    let related = [url, url.deletingPathExtension().appendingPathExtension("store-shm"),
                                   url.deletingPathExtension().appendingPathExtension("store-wal")]
                    for file in related { try? fm.removeItem(at: file) }
                }
                do {
                    return try ModelContainer(for: schema, configurations: [config])
                } catch {
                    fatalError("FATAL: ModelContainer creation failed after store deletion: \(error)")
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .environment(queryService)
                .environment(eventKitManager)
                .environment(googleCalendarMonitor)
                .environment(settings)
                .environment(meetingDetector)
                .environment(modelManager)
                .environment(proactiveScheduler)
                .environment(voiceAssistant)
                .environment(syncManager)
                .environment(\.backgroundContext, backgroundContext)
                .preferredColorScheme(settings.appearanceMode.colorScheme)
                .onAppear {
                    if backgroundContext == nil {
                        let ctx = ModelContext(sharedModelContainer)
                        ctx.autosaveEnabled = true
                        backgroundContext = ctx
                    }

                    AppDelegate.session = session
                    AppDelegate.settings = settings
                    AppDelegate.modelContainer = sharedModelContainer
                    AppDelegate.meetingDetectorRef = meetingDetector
                    eventKitManager.backgroundContext = backgroundContext

                    menuBarController.setup(
                        session: session,
                        eventKitManager: eventKitManager,
                        googleCalendarMonitor: googleCalendarMonitor,
                        meetingDetector: meetingDetector,
                        settings: settings,
                        modelContainer: sharedModelContainer
                    )
                    googleCalendarMonitor.configure(settings: settings)
                    proactiveScheduler.configure(
                        settings: settings,
                        calendarMonitor: googleCalendarMonitor,
                        eventKitManager: eventKitManager,
                        modelContext: backgroundContext!
                    )

                    appLogger.info("Configuring voiceAssistant with backgroundContext=\(backgroundContext != nil)")
                    voiceAssistant.configure(
                        settings: settings,
                        modelManager: modelManager,
                        ttsModelManager: ttsModelManager,
                        queryService: queryService,
                        backgroundContext: backgroundContext!
                    )
                    appLogger.info("VoiceAssistant configured — voiceEnabled=\(settings.voiceEnabled)")
                    voiceAssistant.inputController.onSilenceDetected = { [weak voiceAssistant] in
                        voiceAssistant?.onUserFinishedSpeaking()
                    }

                    syncManager.configure(settings: settings, modelContext: backgroundContext!)

                    // Warm keepalive: auto-load last-used MLX model on launch
                    if settings.llmProvider == .mlx {
                        modelManager.warmKeepalive()
                    }
                    modelManager.startMemoryPressureMonitoring()

                    if settings.autoDetectMeetings {
                        meetingDetector.startMonitoring()
                    }
                }
                .onChange(of: settings.autoDetectMeetings) { _, enabled in
                    if enabled {
                        meetingDetector.startMonitoring()
                    } else {
                        meetingDetector.stopMonitoring()
                        bannerController.close()
                    }
                }
                .onChange(of: meetingDetector.detectedApp?.bundleID) { _, _ in
                    handleMeetingDetection()
                }
                .onChange(of: proactiveScheduler.pendingBannerMeeting) { _, pending in
                    handlePendingBanner(pending)
                }
                .onChange(of: voiceAssistant.isActive) { _, active in
                    if active {
                        voiceOrbPanel.show(service: voiceAssistant)
                    } else {
                        voiceOrbPanel.close()
                    }
                }
                .onChange(of: voiceAssistant.inputController.state) { _, newState in
                    if newState == .thinking {
                        voiceOrbPanel.playThinkingSound()
                    } else {
                        voiceOrbPanel.stopThinkingSound()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .voiceToggleRequested)) { _ in
                    voiceAssistant.toggle()
                }
                .onChange(of: settings.syncEnabled) { _, _ in
                    syncManager.configure(settings: settings, modelContext: backgroundContext!)
                }
                .onChange(of: settings.syncServerURL) { _, _ in
                    syncManager.configure(settings: settings, modelContext: backgroundContext!)
                }
                .onChange(of: settings.syncAuthToken) { _, _ in
                    syncManager.configure(settings: settings, modelContext: backgroundContext!)
                }
                .onReceive(NotificationCenter.default.publisher(for: .meetingDidFinishProcessing)) { notification in
                    if let meeting = notification.object as? Meeting {
                        syncManager.pushMeeting(meeting)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.automatic)

        Settings {
            SettingsView(settings: settings)
                .environment(settings)
                .environment(googleCalendarMonitor)
                .environment(modelManager)
                .environment(ttsModelManager)
                .environment(proactiveScheduler)
                .environment(voiceAssistant)
                .environment(syncManager)
                .modelContainer(sharedModelContainer)
                .frame(minWidth: 520, minHeight: 440)
        }
    }

    private func handlePendingBanner(_ pending: PendingMeetingBanner?) {
        guard let pending, !session.isRecording else {
            joinBannerController.close()
            return
        }

        joinBannerController.show(
            meeting: pending,
            onJoin: { [session, settings, backgroundContext, proactiveScheduler] in
                guard !session.isRecording, let bgCtx = backgroundContext else { return }

                // Open the meeting link if available
                if let link = pending.meetingLink {
                    NSWorkspace.shared.open(link)
                }

                // Start recording with event metadata
                let meeting = session.startRecording(modelContext: bgCtx, settings: settings, meetingDetector: meetingDetector)
                meeting.title = pending.title
                meeting.calendarEventID = pending.eventID
                meeting.calendarAttendees = pending.attendees
                session.enableAutoFinish(calendarEndTime: pending.end, meetingDetector: meetingDetector)

                proactiveScheduler.dismissBanner(eventID: pending.eventID)
            },
            onDismiss: { [proactiveScheduler] in
                proactiveScheduler.dismissBanner(eventID: pending.eventID)
            }
        )
    }

    private func handleMeetingDetection() {
        guard settings.autoDetectMeetings,
              !session.isRecording,
              !meetingDetector.isDismissed,
              let detected = meetingDetector.detectedApp else {
            bannerController.close()
            return
        }

        bannerController.show(appName: detected.name) { [session, settings, backgroundContext, meetingDetector, googleCalendarMonitor] in
            guard !session.isRecording, let bgCtx = backgroundContext else { return }
            let meeting = session.startRecording(modelContext: bgCtx, settings: settings, meetingDetector: meetingDetector)

            // Try to match a calendar event happening now
            if let matchingEvent = findCurrentCalendarEvent(
                googleCalendarMonitor: googleCalendarMonitor
            ) {
                meeting.title = matchingEvent.title
                meeting.calendarEventID = matchingEvent.id
                meeting.calendarAttendees = matchingEvent.attendees
            } else {
                meeting.title = "Meeting — \(detected.name)"
            }
            meetingDetector.dismiss()
        }
    }

    /// Finds a calendar event that is currently happening (within its start/end window).
    private func findCurrentCalendarEvent(
        googleCalendarMonitor: GoogleCalendarMonitor
    ) -> (title: String, id: String, attendees: [String])? {
        let now = Date()

        // Check Google Calendar events first
        if googleCalendarMonitor.isSignedIn {
            for event in googleCalendarMonitor.upcomingEvents {
                if event.start <= now && event.end >= now {
                    return (title: event.title, id: event.id, attendees: event.attendees)
                }
            }
        }

        // Fall back to Apple Calendar events
        for event in eventKitManager.upcomingEvents {
            if event.start <= now && event.end >= now {
                return (title: event.title, id: event.id, attendees: event.attendees)
            }
        }

        return nil
    }
}

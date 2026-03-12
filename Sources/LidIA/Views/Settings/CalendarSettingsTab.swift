import SwiftUI

struct CalendarSettingsTab: View {
    @Bindable var settings: AppSettings
    @Environment(GoogleCalendarMonitor.self) private var googleCalendarMonitor
    @Environment(ProactiveScheduler.self) private var proactiveScheduler
    @State private var isSigningIn = false

    var body: some View {
        // Google Calendar
        DisclosureGroup("Google Calendar") {
            if googleCalendarMonitor.isSignedIn {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Connected to Google Calendar")
                    Spacer()
                    Button("Sign Out") {
                        Task { await googleCalendarMonitor.signOut() }
                    }
                    .buttonStyle(.glass)
                }

                Toggle("Enable Google Calendar", isOn: $settings.googleCalendarEnabled)

                if settings.googleCalendarEnabled {
                    Toggle("Show in Sidebar", isOn: $settings.showCalendarSection)
                }
            } else {
                SecureField("Client ID", text: $settings.googleClientID)
                SecureField("Client Secret", text: $settings.googleClientSecret)

                Text("Create OAuth credentials at console.cloud.google.com \u{2192} APIs & Services \u{2192} Credentials \u{2192} Desktop app. Enable the Google Calendar API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !settings.googleClientID.isEmpty && !settings.googleClientSecret.isEmpty {
                    Button {
                        isSigningIn = true
                        Task {
                            googleCalendarMonitor.configure(settings: settings)
                            await googleCalendarMonitor.signIn(settings: settings)
                            isSigningIn = false
                        }
                    } label: {
                        if isSigningIn {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Sign In with Google", systemImage: "globe")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSigningIn)
                }
            }

            if let error = googleCalendarMonitor.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }

        // Calendar & Reminders (Apple)
        DisclosureGroup("Apple Calendar & Reminders") {
            Toggle("Enable Calendar", isOn: $settings.calendarEnabled)
            Text("Uses Apple Calendar \u{2014} includes all synced accounts (Google, iCloud, Outlook).")
                .font(.caption)
                .foregroundStyle(.secondary)

            if settings.calendarEnabled {
                Toggle("Show Calendar in Sidebar", isOn: $settings.showCalendarSection)

                Toggle("Notify Before Meetings", isOn: $settings.notifyUpcomingMeetings)
                    .onChange(of: settings.notifyUpcomingMeetings) { _, enabled in
                        if enabled {
                            EventKitManager.requestNotificationPermission()
                        }
                    }

                Toggle("Record Prompt (2 min before)", isOn: $settings.calendarRecordPromptEnabled)
                    .onChange(of: settings.calendarRecordPromptEnabled) { _, enabled in
                        if enabled {
                            EventKitManager.requestNotificationPermission()
                        }
                    }

                Toggle("Prep Notification (5 min before)", isOn: $settings.prepNotificationsEnabled)
                    .onChange(of: settings.prepNotificationsEnabled) { _, enabled in
                        if enabled {
                            EventKitManager.requestNotificationPermission()
                        }
                    }

                if settings.notifyUpcomingMeetings {
                    Picker("Minutes Before", selection: $settings.meetingNotificationMinutes) {
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                    }
                }
            }

            Toggle("Sync Action Items to Reminders", isOn: $settings.remindersEnabled)
            Text("Creates reminders in an \"LidIA\" list. Completion syncs both ways.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if settings.remindersEnabled {
                Toggle("Auto-create after meetings", isOn: $settings.remindersAutoSend)

                Picker("Items to create", selection: $settings.remindersMyItemsOnly) {
                    Text("Assigned to me").tag(true)
                    Text("All items").tag(false)
                }
                .pickerStyle(.segmented)
            }
        }

        DisclosureGroup("Proactive Assistant") {
            Toggle("Morning Digest", isOn: $settings.proactiveMorningDigest)
            if settings.proactiveMorningDigest {
                DatePicker(
                    "Digest Time",
                    selection: $settings.proactiveMorningDigestTime,
                    displayedComponents: .hourAndMinute
                )

                Picker("Frequency", selection: $settings.proactiveMorningDigestFrequency) {
                    Text("Daily").tag("daily")
                    Text("Mondays").tag("monday")
                    Text("Off").tag("off")
                }
            }

            Toggle("Pre-Meeting Prep", isOn: $settings.proactivePreMeetingPrep)
            if settings.proactivePreMeetingPrep {
                Stepper(
                    "Minutes Before: \(settings.proactivePreMeetingMinutes)",
                    value: $settings.proactivePreMeetingMinutes,
                    in: 5...60,
                    step: 5
                )
            }

            Toggle("Post-Meeting Nudge", isOn: $settings.proactivePostMeetingNudge)
            if settings.proactivePostMeetingNudge {
                Stepper(
                    "Minutes After: \(settings.proactivePostMeetingMinutes)",
                    value: $settings.proactivePostMeetingMinutes,
                    in: 5...60,
                    step: 5
                )
            }

            Toggle("Action Item Reminders", isOn: $settings.proactiveActionItemReminders)

            DatePicker(
                "Quiet Hours Start",
                selection: $settings.proactiveQuietStart,
                displayedComponents: .hourAndMinute
            )
            DatePicker(
                "Quiet Hours End",
                selection: $settings.proactiveQuietEnd,
                displayedComponents: .hourAndMinute
            )

            Text("Morning digests, prep nudges, and action item reminders are suppressed during quiet hours.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onChange(of: settings.proactiveMorningDigest) { _, _ in refreshProactiveScheduler() }
        .onChange(of: settings.proactiveMorningDigestTime) { _, _ in refreshProactiveScheduler() }
        .onChange(of: settings.proactiveMorningDigestFrequency) { _, _ in refreshProactiveScheduler() }
        .onChange(of: settings.proactivePreMeetingPrep) { _, _ in refreshProactiveScheduler() }
        .onChange(of: settings.proactivePreMeetingMinutes) { _, _ in refreshProactiveScheduler() }
        .onChange(of: settings.proactivePostMeetingNudge) { _, _ in refreshProactiveScheduler() }
        .onChange(of: settings.proactivePostMeetingMinutes) { _, _ in refreshProactiveScheduler() }
        .onChange(of: settings.proactiveActionItemReminders) { _, _ in refreshProactiveScheduler() }
        .onChange(of: settings.proactiveQuietStart) { _, _ in refreshProactiveScheduler() }
        .onChange(of: settings.proactiveQuietEnd) { _, _ in refreshProactiveScheduler() }

        // Meeting Detection
        DisclosureGroup("Meeting Detection") {
            Toggle("Auto-detect meetings", isOn: $settings.autoDetectMeetings)
            Text("Shows a banner when another app (Zoom, Teams, Chrome, etc.) starts using the microphone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshProactiveScheduler() {
        if settings.proactiveMorningDigest
            || settings.proactivePreMeetingPrep
            || settings.proactivePostMeetingNudge
            || settings.proactiveActionItemReminders {
            Task {
                _ = await NotificationDispatcher.requestPermission()
            }
        }
        proactiveScheduler.startTimers()
    }
}

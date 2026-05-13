import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.backgroundContext) private var backgroundContext
    @Environment(AppSettings.self) private var settings
    @Environment(RecordingSession.self) private var session
    @Environment(EventKitManager.self) private var eventKitManager
    @Environment(GoogleCalendarMonitor.self) private var googleCalendarMonitor
    @Environment(MeetingDetector.self) private var meetingDetector
    @Environment(ModelManager.self) private var modelManager
    @Environment(MeetingQueryService.self) private var queryService
    @Environment(ProactiveScheduler.self) private var proactiveScheduler
    @Environment(VoiceAssistantService.self) private var voiceAssistant

    @State private var nav = NavigationState()
    @State private var chatUI = ChatUIState()
    @State private var chatViewModel = ChatBarViewModel()

    private var showSetupWizard: Binding<Bool> {
        Binding(
            get: { !settings.hasCompletedSetup },
            set: { if !$0 { settings.hasCompletedSetup = true } }
        )
    }

    var body: some View {
        mainContent
            .sheet(isPresented: showSetupWizard) {
                SetupWizardView()
                    .interactiveDismissDisabled()
            }
            .onAppear {
                eventKitManager.startPolling(settings: settings)
                chatViewModel.configure(settings: settings, modelContext: modelContext, modelManager: modelManager, backgroundContext: backgroundContext)
                chatViewModel.updateSelectedMeeting(nav.selectedMeeting)
                queryService.modelManager = modelManager
                session.resumeQueuedProcessing(
                    modelContext: modelContext,
                    settings: settings,
                    eventKitManager: eventKitManager,
                    modelManager: modelManager
                )
            }
            .onDisappear {
                eventKitManager.stopPolling()
            }
            .onChange(of: settings.calendarEnabled) { _, enabled in
                if enabled {
                    eventKitManager.startPolling(settings: settings)
                } else {
                    eventKitManager.stopPolling()
                }
            }
            .onChange(of: session.isRecording) { _, isRecording in
                if isRecording {
                    chatViewModel.recordingState = .recording
                } else if chatViewModel.recordingState == .recording {
                    chatViewModel.recordingState = .justFinished
                }
            }
            .onChange(of: nav.selectedMeeting) { _, meeting in
                chatViewModel.updateSelectedMeeting(meeting)

                guard let meeting else { return }
                nav.detailDestination = .meeting

                switch meeting.status {
                case .recording:
                    nav.selectedTab = meeting.title == "Quick Note" ? "notes" : "transcript"
                case .complete:
                    nav.selectedTab = (meeting.summary.isEmpty && meeting.rawTranscript.isEmpty) ? "notes" : "summary"
                case .queued:
                    nav.selectedTab = "summary"
                default:
                    nav.selectedTab = "summary"
                }
            }
            .onChange(of: nav.detailDestination) { _, _ in
                // Clear any pushed views (PersonDetail, ChatThread, etc.) when switching workspaces
                nav.detailPath = NavigationPath()
            }
            .onChange(of: nav.sidebarTab) { _, tab in
                switch tab {
                case .chat:
                    nav.selectedMeeting = nil
                    nav.detailDestination = .chat
                case .home:
                    if nav.selectedMeeting == nil {
                        nav.detailDestination = .home
                    }
                default:
                    break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .lidiaOpenHomeWorkspace)) { _ in
                nav.selectedMeeting = nil
                nav.selectedCalendarEvent = nil
                nav.sidebarTab = .home
                nav.detailDestination = .home
            }
            .onReceive(NotificationCenter.default.publisher(for: .lidiaOpenActionItemsWorkspace)) { _ in
                nav.selectedMeeting = nil
                nav.detailDestination = .actionItems
            }
            .toolbar {
                if settings.voiceEnabled {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            voiceAssistant.toggle()
                        } label: {
                            Label("Voice Assistant", systemImage: voiceAssistant.isActive ? "waveform.circle.fill" : "waveform.circle")
                        }
                        .help("Voice Assistant (\(voiceAssistant.inputController.hotkeyDisplayString))")
                    }
                }
                if !chatUI.quickChatVisible {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            chatUI.quickChatVisible = true
                            chatUI.chatFocusTrigger.toggle()
                        } label: {
                            Label("Quick Chat", systemImage: "bubble.left.and.bubble.right")
                        }
                        .help("Show Quick Chat")
                    }
                }
            }
            // Keyboard shortcuts via background buttons (no toolbar capsule)
            .background {
                Group {
                    Button {
                        if session.isRecording { stopRecording() } else { startRecording() }
                    } label: { EmptyView() }
                    .keyboardShortcut("r", modifiers: .command)

                    Button { createQuickNote() } label: { EmptyView() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])

                    Button {
                        if !chatUI.quickChatVisible {
                            chatUI.quickChatVisible = true
                        }
                        chatUI.chatFocusTrigger.toggle()
                    } label: { EmptyView() }
                    .keyboardShortcut("k", modifiers: .command)

                    Button {
                        nav.sidebarTab = .search
                    } label: { EmptyView() }
                    .keyboardShortcut("f", modifiers: .command)
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        NavigationSplitView(columnVisibility: $nav.columnVisibility) {
            SidebarView(
                sidebarTab: $nav.sidebarTab,
                selectedFolder: $nav.selectedFolder,
                onSelectMeeting: { meeting in
                    nav.selectedMeeting = meeting
                    nav.detailDestination = .meeting
                },
                onSelectEvent: { event in
                    nav.selectedCalendarEvent = event
                    nav.selectedMeeting = nil
                    nav.detailDestination = .calendarEvent
                },
                onOpenActionItems: {
                    nav.selectedMeeting = nil
                    nav.detailDestination = .actionItems
                },
                onOpenPeople: {
                    nav.selectedMeeting = nil
                    nav.detailDestination = .people
                },
                onRecord: { event in
                    if let link = event.meetingLink {
                        NSWorkspace.shared.open(link)
                    }
                    startRecordingFromGoogleEvent(event)
                },
                onSelectMeetingByID: { meetingID in
                    let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate<Meeting> { $0.id == meetingID })
                    if let meeting = try? modelContext.fetch(descriptor).first {
                        nav.selectedMeeting = meeting
                        nav.detailDestination = .meeting
                    }
                },
                onSelectThread: { threadID in
                    chatUI.chatFullscreenThreadID = threadID
                    nav.detailDestination = .chat
                },
                activeThreadID: chatViewModel.activeThreadID,
                onNewChat: {
                    nav.sidebarTab = .chat
                    nav.selectedMeeting = nil
                    nav.detailDestination = .chat
                },
                onNewNote: {
                    createQuickNote()
                },
                onTabReclick: { tab in
                    switch tab {
                    case .home:
                        nav.selectedMeeting = nil
                        nav.selectedCalendarEvent = nil
                        nav.detailDestination = .home
                    case .chat:
                        chatUI.chatFullscreenThreadID = nil
                        nav.selectedMeeting = nil
                        nav.detailDestination = .chat
                    default:
                        break
                    }
                }
            )
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 300)
            .scrollContentBackground(.hidden)
            .background(.thinMaterial)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    SettingsLink {
                        Label("Settings", systemImage: "gear")
                    }
                    .buttonStyle(.glass)
                }
            }
        } detail: {
            NavigationStack(path: $nav.detailPath) {
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .navigationDestination(for: UUID.self) { threadID in
                        ChatThreadView(
                            viewModel: chatViewModel,
                            threadID: threadID,
                            availableModels: settings.availableModels
                        )
                    }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch nav.detailDestination {
        case .meeting:
            if let meeting = nav.selectedMeeting {
                MeetingDetailView(meeting: meeting, selectedTab: $nav.selectedTab, onBack: {
                    nav.selectedMeeting = nil
                    nav.detailDestination = .home
                })
            } else {
                ContentUnavailableView(
                    "No Meeting Selected",
                    systemImage: "waveform",
                    description: Text("Select a meeting or press Shift+Cmd+N for a quick note")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        case .home:
            HomeView(
                selectedFolder: nav.selectedFolder,
                onSelectEvent: { event in
                    nav.selectedCalendarEvent = event
                    nav.selectedMeeting = nil
                    nav.detailDestination = .calendarEvent
                },
                onRecord: { event in
                    if let link = event.meetingLink {
                        NSWorkspace.shared.open(link)
                    }
                    startRecordingFromGoogleEvent(event)
                },
                onRecordAppleEvent: { event in
                    startRecordingFromEvent(event)
                },
                onSelectMeeting: { meeting in
                    nav.selectedMeeting = meeting
                    nav.detailDestination = .meeting
                },
                onQuickNote: {
                    createQuickNote()
                },
                onOpenActionItems: {
                    nav.selectedMeeting = nil
                    nav.detailDestination = .actionItems
                }
            )

        case .calendarEvent:
            if let event = nav.selectedCalendarEvent {
                CalendarEventDetailView(event: event, onRecord: { notes in
                    startRecordingFromGoogleEvent(event, notes: notes)
                }, onBack: {
                    nav.detailDestination = .home
                })
            }

        case .actionItems:
            ActionItemDashboardView(selectedMeeting: $nav.selectedMeeting)

        case .people:
            PeopleView(selectedMeeting: $nav.selectedMeeting)

        case .chat:
            ChatHomeView(viewModel: chatViewModel, navigateToThreadID: chatUI.chatFullscreenThreadID, path: $nav.detailPath)
                .onDisappear { chatUI.chatFullscreenThreadID = nil }
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        if nav.detailDestination == .home && session.isRecording {
            homeRecordingBar
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if chatUI.quickChatVisible && nav.detailDestination != .chat {
            ChatBarView(
                viewModel: chatViewModel,
                availableModels: settings.availableModels,
                provider: settings.llmProvider,
                onClose: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        chatUI.quickChatVisible = false
                    }
                },
                isExpanded: $chatUI.quickChatExpanded,
                onExpandFullscreen: {
                    chatUI.chatFullscreenThreadID = chatViewModel.activeThreadID
                    nav.detailDestination = .chat
                },
                focusTrigger: $chatUI.chatFocusTrigger
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Home Recording Bar

    private var homeRecordingBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .modifier(PulseEffect())

            Text(formatTime(session.elapsedTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            if let meeting = session.currentMeeting {
                Text(meeting.title.isEmpty ? "Recording" : meeting.title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if !session.transcriptWords.isEmpty {
                let lastWords = session.transcriptWords.suffix(8).map(\.word).joined(separator: " ")
                Text(lastWords)
                    .font(.caption)
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
                    .frame(maxWidth: 200, alignment: .trailing)
            }

            Button {
                if let meeting = session.currentMeeting {
                    nav.selectedMeeting = meeting
                    nav.detailDestination = .meeting
                }
            } label: {
                Text("View")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .glassEffect(.regular, in: .capsule)
            }
            .buttonStyle(.plain)

            Button {
                stopRecording()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular, in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 860)
        .glassEffect(.regular.tint(.red.opacity(0.15)).interactive(), in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 6)
    }

    // MARK: - Actions

    private func startRecording() {
        let meeting = session.startRecording(modelContext: modelContext, settings: settings, modelManager: modelManager, meetingDetector: meetingDetector, eventKitManager: eventKitManager, googleCalendarMonitor: googleCalendarMonitor)
        nav.selectedMeeting = meeting
    }

    private func startRecordingFromEvent(_ event: EventKitManager.CalendarEvent) {
        let meeting = session.startRecordingFromEvent(event, modelContext: modelContext, settings: settings, modelManager: modelManager, meetingDetector: meetingDetector)
        nav.selectedMeeting = meeting
    }

    private func startRecordingFromGoogleEvent(_ event: GoogleCalendarClient.CalendarEvent, notes: String = "") {
        let meeting = session.startRecordingFromGoogleEvent(event, notes: notes, modelContext: modelContext, settings: settings, modelManager: modelManager, meetingDetector: meetingDetector)
        nav.selectedMeeting = meeting
        nav.detailDestination = .meeting
    }

    private func createQuickNote() {
        let meeting = session.startRecording(modelContext: modelContext, settings: settings, modelManager: modelManager, meetingDetector: meetingDetector, eventKitManager: eventKitManager, googleCalendarMonitor: googleCalendarMonitor)
        meeting.title = "Quick Note"
        nav.selectedMeeting = meeting
        nav.detailDestination = .meeting
        withAnimation {
            nav.columnVisibility = .detailOnly
        }
    }

    private func stopRecording() {
        session.stopRecording(modelContext: modelContext, settings: settings, eventKitManager: eventKitManager)
    }
}

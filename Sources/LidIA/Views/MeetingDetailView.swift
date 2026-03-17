import os
import SwiftUI

struct MeetingDetailView: View {
    private static let logger = Logger(subsystem: "io.lidia.app", category: "MeetingDetailView")
    @Bindable var meeting: Meeting
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(EventKitManager.self) private var eventKitManager
    @Environment(ModelManager.self) private var modelManager
    @Binding var selectedTab: String
    var onBack: (() -> Void)?
    @State private var isReprocessing = false
    @State private var isGeneratingTitle = false
    @State private var isGeneratingNotes = false
    @State private var isEditingSummary = false
    @State private var editableSummary = ""
    @State private var isEditingTranscript = false
    @State private var editableTranscript = ""
    @State private var transcriptSearchText = ""
    @State private var isResummarizing = false
    @State private var cachedSegments: [TimedSegment] = []
    @State private var cachedHasSpeakerData = false
    @State private var cachedHasSpeakerNames = false
    @State private var cachedHasSpeakerIDs = false
    @State private var headerCollapsed = false
    @State private var recipeResult = ""
    @State private var isRunningRecipe = false
    @State private var showRecipeResult = false
    @State private var activeRecipeName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Collapsible title area
            titleHeader

            // Tab content with glass tab bar as safe area bar
            tabContent
                .safeAreaBar(edge: .top) {
                    glassTabBar
                }
        }
        .toolbar { detailToolbar }
        .onChange(of: meeting.status, initial: true) { _, newStatus in
                switch newStatus {
                case .recording:
                    // Quick notes show Notes tab during recording so user can type
                    if meeting.title == "Quick Note" {
                        selectedTab = "notes"
                    } else {
                        selectedTab = "transcript"
                    }
                case .complete:
                    // Quick notes (no summary, no transcript) default to Notes tab
                    if meeting.summary.isEmpty && meeting.rawTranscript.isEmpty {
                        selectedTab = "notes"
                    } else {
                        selectedTab = "summary"
                    }
                case .failed:
                    selectedTab = "summary"
                case .queued:
                    selectedTab = "summary"
                default:
                    break
                }
            }
            .background {
                // Invisible keyboard shortcut buttons for tab switching
                Group {
                    Button { selectedTab = "summary" } label: { EmptyView() }
                        .keyboardShortcut("1", modifiers: .command)
                    Button { selectedTab = "transcript" } label: { EmptyView() }
                        .keyboardShortcut("2", modifiers: .command)
                    Button { selectedTab = "notes" } label: { EmptyView() }
                        .keyboardShortcut("3", modifiers: .command)
                    Button { selectedTab = "actions" } label: { EmptyView() }
                        .keyboardShortcut("4", modifiers: .command)
                    Button { selectedTab = "chat" } label: { EmptyView() }
                        .keyboardShortcut("5", modifiers: .command)
                }
                .frame(width: 0, height: 0)
                .opacity(0)
            }
            .onAppear {
                editableSummary = effectiveSummary
                editableTranscript = effectiveTranscript
                recomputeTranscriptCache()
            }
            .onChange(of: meeting.rawTranscript) {
                recomputeTranscriptCache()
            }
            .onChange(of: selectedTab) {
                withAnimation(.smooth(duration: 0.2)) {
                    headerCollapsed = false
                }
            }
            .sheet(isPresented: $isEditingSummary) {
                NavigationStack {
                    TextEditor(text: $editableSummary)
                        .font(.body)
                        .padding()
                        .navigationTitle("Edit Summary")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { isEditingSummary = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    let trimmed = editableSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                                    meeting.userEditedSummary = trimmed.isEmpty ? nil : trimmed
                                    if !trimmed.isEmpty {
                                        meeting.summary = trimmed
                                    }
                                    isEditingSummary = false
                                }
                            }
                        }
                }
                .frame(minWidth: 560, minHeight: 360)
            }
            .sheet(isPresented: $isEditingTranscript) {
                NavigationStack {
                    TextEditor(text: $editableTranscript)
                        .font(.body.monospaced())
                        .padding()
                        .navigationTitle("Edit Transcript")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { isEditingTranscript = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") {
                                    let trimmed = editableTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                                    meeting.userEditedTranscript = trimmed.isEmpty ? nil : trimmed
                                    if !trimmed.isEmpty {
                                        meeting.refinedTranscript = trimmed
                                    }
                                    isEditingTranscript = false
                                }
                            }
                        }
                }
                .frame(minWidth: 700, minHeight: 420)
            }
            .sheet(isPresented: $showRecipeResult) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(activeRecipeName)
                                .font(.title2.bold())
                            MarkdownBlockView(text: recipeResult)
                                .textSelection(.enabled)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .navigationTitle("Recipe Result")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showRecipeResult = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(recipeResult, forType: .string)
                            }
                        }
                    }
                }
                .frame(minWidth: 560, minHeight: 400)
            }
    }

    private var effectiveSummary: String {
        let edited = meeting.userEditedSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return edited.isEmpty ? meeting.summary : edited
    }

    private var effectiveTranscript: String {
        let edited = meeting.userEditedTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return edited.isEmpty ? meeting.refinedTranscript : edited
    }

    // MARK: - Title Header (collapses on scroll)

    private var titleHeader: some View {
        VStack(spacing: 12) {
            // Back button
            if let onBack {
                Button {
                    onBack()
                } label: {
                    Label("Home", systemImage: "chevron.left")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Editable meeting title
            TextField("Meeting Title", text: $meeting.title)
                .font(.title2.bold())
                .textFieldStyle(.plain)

            if let attendees = meeting.calendarAttendees, attendees.count > 1, meeting.duration > 0 {
                let hours = Int(ceil(meeting.duration / 3600))
                let personHours = hours * attendees.count
                Text("\(personHours) person-hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .opacity(headerCollapsed ? 0 : 1)
        .frame(maxHeight: headerCollapsed ? 0 : nil)
        .clipped()
    }

    // MARK: - Glass Tab Bar (overlaid — content scrolls behind it)
    // Uses native Picker which adopts Liquid Glass automatically on macOS 26

    private var glassTabBar: some View {
        Picker("", selection: $selectedTab) {
            Text("Summary").tag("summary")
            Text("Transcript").tag("transcript")
            Text("Notes").tag("notes")
            Text("Action Items").tag("actions")
            Text("Chat").tag("chat")
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var tabContent: some View {
        VStack(spacing: 0) {
            switch selectedTab {
            case "summary":
                summaryView
            case "transcript":
                transcriptView
            case "notes":
                notesView
            case "actions":
                actionItemsView
            case "chat":
                MeetingChatView(meeting: meeting)
            default:
                EmptyView()
            }
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if meeting.status == .failed || meeting.status == .complete || meeting.status == .processing || meeting.status == .queued {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Menu {
                        Button("Auto (current provider)") { reprocess() }
                        Button("Auto (overwrite edits)") { reprocess(overwriteUserEdits: true) }
                        Divider()
                        if !settings.openaiAPIKey.isEmpty {
                            Button("OpenAI") { reprocessWith(provider: .openai) }
                        }
                        if !settings.anthropicAPIKey.isEmpty {
                            Button("Anthropic") { reprocessWith(provider: .anthropic) }
                        }
                        if settings.llmProvider == .ollama || !settings.ollamaURL.isEmpty {
                            Button("Ollama") { reprocessWith(provider: .ollama) }
                        }
                        Button("Local MLX") { reprocessWith(provider: .mlx) }
                        if !settings.nvidiaAPIKey.isEmpty {
                            Button("NVIDIA NIM") { reprocessWith(provider: .nvidiaNIM) }
                        }
                        if !settings.deepseekAPIKey.isEmpty {
                            Button("DeepSeek") { reprocessWith(provider: .deepseek) }
                        }
                        if !settings.openRouterAPIKey.isEmpty {
                            Button("OpenRouter") { reprocessWith(provider: .openRouter) }
                        }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .disabled(isReprocessing)

                    Button {
                        generateTitle()
                    } label: {
                        Label("Generate Title", systemImage: "textformat")
                    }
                    .disabled(isGeneratingTitle)

                    Button {
                        generateNotesFromAI()
                    } label: {
                        Label("Generate Notes", systemImage: "sparkles")
                    }
                    .disabled(isGeneratingNotes)

                    Divider()

                    Button {
                        editableSummary = effectiveSummary
                        isEditingSummary = true
                    } label: {
                        Label("Edit Summary", systemImage: "square.and.pencil")
                    }

                    Button {
                        editableTranscript = effectiveTranscript
                        isEditingTranscript = true
                    } label: {
                        Label("Edit Transcript", systemImage: "text.cursor")
                    }
                } label: {
                    Label("AI", systemImage: "sparkles")
                }
                .help("AI-powered actions")
            }
        }
        ToolbarItem(placement: .automatic) {
            Menu {
                ForEach(Recipe.Category.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(Recipe.builtIn.filter { $0.category == category }) { recipe in
                            Button {
                                runRecipe(recipe)
                            } label: {
                                Text("\(recipe.emoji) \(recipe.name)")
                            }
                            .disabled(isRunningRecipe)
                        }
                    }
                }
            } label: {
                if isRunningRecipe {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Recipes", systemImage: "book")
                }
            }
            .help("Apply a recipe to analyze this meeting")
        }
        ToolbarItem(placement: .automatic) {
            Menu {
                Button("Copy Summary as Markdown") {
                    ExportService.copyToClipboard(ExportService.summaryToMarkdown(meeting))
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Copy Full Export") {
                    ExportService.copyToClipboard(ExportService.meetingToMarkdown(meeting))
                }

                Button("Copy Action Items") {
                    ExportService.copyToClipboard(ExportService.actionItemsToMarkdown(meeting))
                }

                Button("Copy Transcript") {
                    let text = effectiveTranscript.isEmpty
                        ? meeting.rawTranscript.map(\.word).joined(separator: " ")
                        : effectiveTranscript
                    ExportService.copyToClipboard(text)
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
        if meeting.status == .complete {
            ToolbarItem(placement: .automatic) {
                Menu {
                    if !settings.notionAPIKey.isEmpty && !settings.notionDatabaseID.isEmpty {
                        Button {
                            Task { await sendToNotion() }
                        } label: {
                            HStack {
                                Label("Notion", systemImage: "doc.text")
                                if meeting.notionPageID != nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }

                    if settings.n8nEnabled && !settings.n8nWebhookURL.isEmpty {
                        Button {
                            Task { await sendToN8n() }
                        } label: {
                            Label("n8n Webhook", systemImage: "arrow.up.forward.app")
                        }
                    }

                    if settings.remindersEnabled {
                        Button {
                            Task { await sendToReminders() }
                        } label: {
                            Label("Apple Reminders", systemImage: "checklist")
                        }
                        .disabled(meeting.actionItems.isEmpty)
                    }

                    if settings.notionAPIKey.isEmpty && !settings.n8nEnabled && !settings.remindersEnabled {
                        Text("No integrations configured")
                        Button("Open Settings...") {
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        }
                    }
                } label: {
                    Label("Send to", systemImage: "paperplane")
                }
            }
        }
    }

    private var summaryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if meeting.status == .recording {
                    RecordingInlineView()
                } else if meeting.status == .processing {
                    if effectiveSummary.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Processing transcript...")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            MarkdownBlockView(text: effectiveSummary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Finalizing transcript and action items...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if meeting.status == .queued {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 34))
                            .foregroundStyle(.yellow)
                        Text("Queued for processing")
                            .font(.title3.weight(.semibold))
                        Text(meeting.processingError ?? "LidIA will retry automatically when the model provider is available.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 520)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                } else if meeting.status == .failed {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 34))
                            .foregroundStyle(.orange)
                        Text("Summary processing failed")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text("The transcript is still saved. You can retry processing or continue in Notes/Chat.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 420)

                        if let error = meeting.processingError {
                            Text(error)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 520)
                                .textSelection(.enabled)
                                .padding(.horizontal, 12)
                        }
                        Button {
                            reprocess()
                        } label: {
                            Label("Retry Processing", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isReprocessing)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if effectiveSummary.isEmpty {
                    Text("No summary yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        // Template picker
                        HStack(spacing: 8) {
                            Menu {
                                Button {
                                    meeting.templateID = nil
                                    meeting.templateAutoDetected = true
                                } label: {
                                    HStack {
                                        Label("Auto", systemImage: "sparkles")
                                        if meeting.templateAutoDetected || meeting.templateID == nil {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }

                                Divider()

                                ForEach(settings.meetingTemplates) { template in
                                    Button {
                                        resummarizeWithTemplate(template)
                                    } label: {
                                        HStack {
                                            Text("\(template.emoji.isEmpty ? "" : template.emoji + " ")\(template.name)")
                                            if meeting.templateID == template.id && !meeting.templateAutoDetected {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if let templateID = meeting.templateID,
                                       let template = settings.meetingTemplates.first(where: { $0.id == templateID }) {
                                        Text("\(template.emoji.isEmpty ? "📋" : template.emoji) \(template.name)")
                                    } else {
                                        Label("Auto", systemImage: "sparkles")
                                    }
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                }
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .glassEffect(.regular, in: .rect(cornerRadius: 6))
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()

                            if isResummarizing {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Re-summarizing...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }

                        if meeting.userEditedSummary?.isEmpty == false {
                            Label("Using your edited summary", systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.green)
                            MarkdownBlockView(text: effectiveSummary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let data = meeting.structuredSummary,
                                  let structured = try? JSONDecoder().decode(StructuredSummary.self, from: data) {
                            StructuredSummaryView(
                                summary: structured,
                                transcriptWords: meeting.rawTranscript,
                                onCreateActionItem: { item in
                                    item.meeting = meeting
                                    meeting.actionItems.append(item)
                                    try? modelContext.save()
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            MarkdownBlockView(text: effectiveSummary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Provider badge — shown via processingStatus from MeetingPipeline
                    }
                }
            }
            .padding()
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y > 30
        } action: { _, scrolledPastThreshold in
            withAnimation(.smooth(duration: 0.25)) {
                headerCollapsed = scrolledPastThreshold
            }
        }
    }

    private var transcriptView: some View {
        VStack(spacing: 0) {
            if !effectiveTranscript.isEmpty || !cachedSegments.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Find in transcript", text: $transcriptSearchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .rect(cornerRadius: 8))
                .padding(.horizontal)
                .padding(.top, 12)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !cachedSegments.isEmpty {
                            if cachedHasSpeakerData || cachedHasSpeakerNames || cachedHasSpeakerIDs {
                                // Chat bubbles: use isLocalSpeaker if available, fall back to speaker ID for alternating sides
                                ForEach(Array(cachedSegments.enumerated()), id: \.offset) { index, segment in
                                    speakerBubble(segment: segment, index: index)
                                }
                            } else {
                                // No speaker data — show as simple bubbles
                                ForEach(Array(cachedSegments.enumerated()), id: \.offset) { index, segment in
                                    Text(segment.text)
                                        .font(.body)
                                        .textSelection(.enabled)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id("segment-\(index)")
                                }
                            }
                            if let firstMatch = firstMatchingSegmentIndex {
                                Button("Jump to first match") {
                                    withAnimation {
                                        proxy.scrollTo("segment-\(firstMatch)", anchor: .top)
                                    }
                                }
                                .font(.caption)
                                .buttonStyle(.plain)
                            }
                        } else if !effectiveTranscript.isEmpty {
                            Text(effectiveTranscript)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            LiveTranscriptView(
                                words: meeting.rawTranscript,
                                localSpeakerName: settings.displayName.isEmpty ? "Me" : settings.displayName
                            )
                        }
                    }
                    .padding()
                    .padding(.bottom, 80) // Clear space for chat bar overlay
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
                .onScrollGeometryChange(for: Bool.self) { geo in
                    geo.contentOffset.y > 30
                } action: { _, scrolledPastThreshold in
                    withAnimation(.smooth(duration: 0.25)) {
                        headerCollapsed = scrolledPastThreshold
                    }
                }
            }
        }
    }

    private var notesView: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $meeting.notes)
                .font(.body)
                .scrollContentBackground(.hidden)

            if meeting.notes.isEmpty {
                Text("Write your notes...")
                    .foregroundStyle(.tertiary)
                    .font(.body)
                    .padding(.top, 7)
                    .padding(.leading, 7)
                    .allowsHitTesting(false)
            }
        }
        .padding()
    }

    @State private var newActionItemTitle = ""

    private var actionItemsView: some View {
        List {
            ForEach(meeting.actionItems) { item in
                EditableActionItemRow(item: item, meetingTitle: nil, onDelete: {
                    deleteActionItem(item)
                })
            }
            .onDelete { offsets in
                for index in offsets {
                    let item = meeting.actionItems[index]
                    modelContext.delete(item)
                }
                meeting.actionItems.remove(atOffsets: offsets)
                try? modelContext.save()
            }

            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                    .font(.title3)

                TextField("Add action item...", text: $newActionItemTitle)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .onSubmit {
                        addActionItem()
                    }
            }
            .padding(.vertical, 4)
        }
    }

    private func addActionItem() {
        let trimmed = newActionItemTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newItem = ActionItem(title: trimmed)
        newItem.meeting = meeting
        meeting.actionItems.append(newItem)
        try? modelContext.save()
        newActionItemTitle = ""
    }

    private func deleteActionItem(_ item: ActionItem) {
        meeting.actionItems.removeAll { $0.id == item.id }
        modelContext.delete(item)
        try? modelContext.save()
    }

    private func sendToNotion() async {
        guard !settings.notionAPIKey.isEmpty, !settings.notionDatabaseID.isEmpty else { return }
        do {
            let notion = NotionClient(apiKey: settings.notionAPIKey)
            let body = """
            ## Summary
            \(meeting.summary)

            ## Action Items
            \(meeting.actionItems.map {
                var line = "- \($0.title)"
                if let deadline = $0.displayDeadline {
                    line += " (due: \(deadline))"
                }
                return line
            }.joined(separator: "\n"))
            """
            let pageID = try await notion.createMeetingPage(
                databaseID: settings.notionDatabaseID,
                title: meeting.title,
                date: meeting.date,
                duration: meeting.duration,
                bodyMarkdown: body
            )
            meeting.notionPageID = pageID
            try modelContext.save()
        } catch {
            Self.logger.error("Notion send failed: \(error)")
        }
    }

    private func sendToN8n() async {
        let payload = N8nClient.WebhookPayload(
            meetingTitle: meeting.title,
            date: ISO8601DateFormatter().string(from: meeting.date),
            duration: meeting.duration,
            summary: meeting.summary,
            actionItems: meeting.actionItems.map {
                N8nClient.ActionItemPayload(
                    title: $0.title,
                    assignee: $0.assignee,
                    deadline: $0.displayDeadline
                )
            },
            attendees: meeting.calendarAttendees ?? [],
            transcript: effectiveTranscript
        )
        await N8nClient.sendWebhook(
            payload: payload,
            webhookURL: settings.n8nWebhookURL,
            authHeader: settings.n8nAuthHeader.isEmpty ? nil : settings.n8nAuthHeader
        )
    }

    private func sendToReminders() async {
        for actionItem in meeting.actionItems {
            if let reminderID = await eventKitManager.createReminder(
                title: actionItem.title,
                deadline: actionItem.displayDeadline
            ) {
                actionItem.reminderID = reminderID
            }
        }
        try? modelContext.save()
    }

    private struct TimedSegment: Identifiable {
        let id: Int
        let start: TimeInterval
        let end: TimeInterval
        let text: String
        let speaker: Int?
        let speakerName: String?
        let isLocalSpeaker: Bool?
    }

    private var normalizedTimingWords: [TranscriptWord] {
        guard !meeting.rawTranscript.isEmpty else { return [] }
        var words = meeting.rawTranscript
        if let minStart = words.map(\.start).min(),
           minStart > max(10_000, meeting.duration + 60) {
            for i in words.indices {
                words[i].start -= minStart
                words[i].end -= minStart
            }
        }
        return words.sorted { $0.start < $1.start }
    }

    /// True when at least one word has isLocalSpeaker data, enabling left/right bubble alignment.
    /// Speaker names alone (from diarization) are NOT enough — without local speaker info,
    /// all bubbles would appear on the left side.
    private var hasSpeakerData: Bool {
        normalizedTimingWords.contains { $0.isLocalSpeaker != nil }
    }

    /// True when speaker names are available (from diarization) even without local speaker data.
    private var hasSpeakerNames: Bool {
        normalizedTimingWords.contains { $0.speakerName != nil }
    }

    /// True when speaker IDs are available from diarization (even without names or isLocalSpeaker).
    private var hasSpeakerIDs: Bool {
        normalizedTimingWords.contains { $0.speaker != nil }
    }

    private var timedSegments: [TimedSegment] {
        let words = normalizedTimingWords
        guard !words.isEmpty else { return [] }

        var segments: [TimedSegment] = []
        var currentWords: [String] = []
        var segmentStart = max(0, words[0].start)
        var segmentEnd = max(segmentStart, words[0].end)
        var currentSpeaker = words[0].speaker
        var currentSpeakerName = words[0].speakerName
        var currentIsLocal = words[0].isLocalSpeaker
        var nextID = 0

        for word in words {
            let wordStart = max(0, word.start)
            let wordEnd = max(wordStart, word.end)
            let hitDurationLimit = !currentWords.isEmpty && (wordEnd - segmentStart > 12)
            let hitWordLimit = currentWords.count >= 40
            let speakerChanged = word.speaker != nil && word.speaker != currentSpeaker
            let localChanged = word.isLocalSpeaker != currentIsLocal

            if hitDurationLimit || hitWordLimit || speakerChanged || localChanged {
                segments.append(
                    TimedSegment(
                        id: nextID,
                        start: segmentStart,
                        end: segmentEnd,
                        text: currentWords.joined(separator: " "),
                        speaker: currentSpeaker,
                        speakerName: currentSpeakerName,
                        isLocalSpeaker: currentIsLocal
                    )
                )
                nextID += 1
                currentWords.removeAll(keepingCapacity: true)
                segmentStart = wordStart
                currentSpeaker = word.speaker
                currentSpeakerName = word.speakerName
                currentIsLocal = word.isLocalSpeaker
            }

            currentWords.append(word.word)
            segmentEnd = wordEnd
        }

        if !currentWords.isEmpty {
            segments.append(
                TimedSegment(
                    id: nextID,
                    start: segmentStart,
                    end: segmentEnd,
                    text: currentWords.joined(separator: " "),
                    speaker: currentSpeaker,
                    speakerName: currentSpeakerName,
                    isLocalSpeaker: currentIsLocal
                )
            )
        }

        return segments
    }

    // MARK: - Speaker Bubble

    private static let bubbleColors: [Color] = [.blue, .purple, .orange, .teal, .pink, .green]

    private func speakerBubble(segment: TimedSegment, index: Int) -> some View {
        // Determine if this is "me": prefer isLocalSpeaker, fall back to speaker ID 0
        let isLocal: Bool
        if let local = segment.isLocalSpeaker {
            isLocal = local
        } else if let speaker = segment.speaker {
            // Without system audio, assume the most frequent speaker is "me"
            // (already computed by assignLocalSpeaker majority vote)
            isLocal = speaker == 0
        } else {
            isLocal = false
        }

        let bubbleColor: Color = {
            if isLocal { return .accentColor }
            if let speaker = segment.speaker {
                return Self.bubbleColors[speaker % Self.bubbleColors.count]
            }
            return .primary
        }()

        // Show timestamp marker when there's a gap > 30s between segments
        let showTimestamp = index > 0 && (segment.start - cachedSegments[index - 1].end) > 30

        return VStack(spacing: showTimestamp ? 12 : 4) {
            if showTimestamp {
                Text(formatSegmentTime(segment.start))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    highlightBackground(for: segment) == .clear
                        ? bubbleColor.opacity(isLocal ? 0.12 : 0.08)
                        : highlightBackground(for: segment),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .frame(maxWidth: 500, alignment: isLocal ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: isLocal ? .trailing : .leading)
        }
        .id("segment-\(index)")
    }

    private func formatSegmentTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var firstMatchingSegmentIndex: Int? {
        let needle = transcriptSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        return cachedSegments.firstIndex(where: { $0.text.localizedCaseInsensitiveContains(needle) })
    }

    private func highlightBackground(for segment: TimedSegment) -> Color {
        let needle = transcriptSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return .clear }
        return segment.text.localizedCaseInsensitiveContains(needle) ? Color.yellow.opacity(0.18) : .clear
    }

    // MARK: - Transcript Cache

    private func recomputeTranscriptCache() {
        cachedSegments = timedSegments
        cachedHasSpeakerData = hasSpeakerData
        cachedHasSpeakerNames = hasSpeakerNames
        cachedHasSpeakerIDs = hasSpeakerIDs
    }

    // MARK: - AI Actions

    private func generateTitle() {
        guard !isGeneratingTitle else { return }
        isGeneratingTitle = true
        let content = !meeting.notes.isEmpty ? meeting.notes
            : !effectiveSummary.isEmpty ? effectiveSummary
            : !effectiveTranscript.isEmpty ? effectiveTranscript
            : meeting.rawTranscript.map(\.word).joined(separator: " ")

        guard !content.isEmpty else {
            isGeneratingTitle = false
            return
        }

        let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .summarization)
        let model = effectiveModel(for: .summary, settings: settings, taskType: .summarization)

        Task {
            defer { isGeneratingTitle = false }
            do {
                let title = try await client.chat(
                    messages: [
                        .init(role: "system", content: "Generate a short, descriptive title (max 8 words) for the following content. Output ONLY the title, nothing else."),
                        .init(role: "user", content: String(content.prefix(2000))),
                    ],
                    model: model,
                    format: nil
                )
                meeting.title = title.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            } catch {
                Self.logger.error("Title generation failed: \(error)")
            }
        }
    }

    private func generateNotesFromAI() {
        guard !isGeneratingNotes else { return }
        isGeneratingNotes = true

        let transcript = !effectiveTranscript.isEmpty
            ? effectiveTranscript
            : meeting.rawTranscript.map(\.word).joined(separator: " ")

        let source = !transcript.isEmpty ? transcript : meeting.notes
        guard !source.isEmpty else {
            isGeneratingNotes = false
            return
        }

        let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .summarization)
        let model = effectiveModel(for: .summary, settings: settings, taskType: .summarization)

        Task {
            defer { isGeneratingNotes = false }
            do {
                let notes = try await client.chat(
                    messages: [
                        .init(role: "system", content: """
                            Generate clean, well-organized meeting notes from the following content. \
                            Use bullet points, group by topic, highlight key decisions and action items. \
                            Be concise but comprehensive. Output only the notes.
                            """),
                        .init(role: "user", content: source),
                    ],
                    model: model,
                    format: nil
                )
                meeting.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                selectedTab = "notes"
            } catch {
                Self.logger.error("Notes generation failed: \(error)")
            }
        }
    }

    private func resummarizeWithTemplate(_ template: MeetingTemplate) {
        guard !isResummarizing else { return }
        isResummarizing = true
        meeting.templateID = template.id
        meeting.templateAutoDetected = false
        settings.rememberTemplateChoice(for: meeting, templateID: template.id)

        Task {
            defer { isResummarizing = false }
            let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .summarization)
            let model = effectiveModel(for: .summary, settings: settings, taskType: .summarization)
            do {
                let transcript = meeting.userEditedTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let effectiveText = transcript.isEmpty ? meeting.refinedTranscript : transcript
                guard !effectiveText.isEmpty else { return }
                let summary = try await client.summarizeMeeting(
                    transcript: effectiveText,
                    model: model,
                    template: template
                )
                meeting.summary = summary.flatSummary
                meeting.userEditedSummary = nil
                try modelContext.save()
            } catch {
                meeting.processingError = "Re-summarize failed: \(error.localizedDescription)"
            }
        }
    }

    private func runRecipe(_ recipe: Recipe) {
        guard !isRunningRecipe else { return }
        isRunningRecipe = true
        activeRecipeName = "\(recipe.emoji) \(recipe.name)"

        let context = """
        Meeting: \(meeting.title)
        Date: \(meeting.date.formatted())
        Duration: \(Int(meeting.duration / 60)) minutes
        Attendees: \(meeting.calendarAttendees?.joined(separator: ", ") ?? "Unknown")

        Summary:
        \(meeting.userEditedSummary ?? meeting.summary)

        Action Items:
        \(meeting.actionItems.map { "- \($0.title)\($0.assignee.map { " (@\($0))" } ?? "")" }.joined(separator: "\n"))

        Transcript (first 3000 chars):
        \(String((meeting.userEditedTranscript ?? meeting.refinedTranscript).prefix(3000)))
        """

        Task {
            defer { isRunningRecipe = false }
            let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .chat)
            let model = effectiveModel(for: .query, settings: settings, taskType: .chat)
            do {
                let result = try await client.chat(
                    messages: [
                        .init(role: "system", content: recipe.prompt),
                        .init(role: "user", content: context),
                    ],
                    model: model,
                    format: nil
                )
                recipeResult = result
                showRecipeResult = true
            } catch {
                recipeResult = "Recipe failed: \(error.localizedDescription)"
                showRecipeResult = true
            }
        }
    }

    private func reprocess(overwriteUserEdits: Bool = false) {
        guard !isReprocessing else { return }
        isReprocessing = true

        // Clear old action items if reprocessing a complete meeting
        if meeting.status == .complete {
            for item in meeting.actionItems {
                modelContext.delete(item)
            }
            meeting.actionItems.removeAll()
            if overwriteUserEdits {
                meeting.summary = ""
                meeting.userEditedSummary = nil
                meeting.userEditedTranscript = nil
            } else if meeting.userEditedSummary?.isEmpty != false {
                meeting.summary = ""
            }
        }

        let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .summarization)
        let model = effectiveModel(for: .summary, settings: settings, taskType: .summarization)
        let template = settings.resolveTemplate(for: meeting)
        let pipeline = MeetingPipeline(llmClient: client, modelContext: modelContext)

        Task {
            defer { isReprocessing = false }
            try? await pipeline.process(
                meeting: meeting,
                model: model,
                template: template,
                preserveUserEdits: !overwriteUserEdits
            )
        }
    }

    private func reprocessWith(provider: AppSettings.LLMProvider) {
        guard !isReprocessing else { return }
        isReprocessing = true

        // Clear old action items
        if meeting.status == .complete {
            for item in meeting.actionItems {
                modelContext.delete(item)
            }
            meeting.actionItems.removeAll()
            if meeting.userEditedSummary?.isEmpty != false {
                meeting.summary = ""
            }
        }

        guard let client = makeClientForProvider(provider, settings: settings, modelManager: modelManager) else {
            isReprocessing = false
            return
        }
        let model = defaultModelForProvider(provider, settings: settings)
        let template = settings.resolveTemplate(for: meeting)
        let pipeline = MeetingPipeline(llmClient: client, modelContext: modelContext)

        Task {
            defer { isReprocessing = false }
            try? await pipeline.process(
                meeting: meeting,
                model: model,
                template: template,
                preserveUserEdits: true
            )
        }
    }
}

private struct StructuredSummaryView: View {
    let summary: StructuredSummary
    let transcriptWords: [TranscriptWord]
    var onCreateActionItem: ((ActionItem) -> Void)?
    @State private var hoveredBulletID: UUID?
    @State private var selectedBullet: StructuredSummary.SummaryBullet?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(summary.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.heading)
                        .font(.headline)

                    ForEach(section.bullets) { bullet in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(bullet.text)
                                .textSelection(.enabled)

                            // Source quote popover disabled — transcript matching unreliable
                            // TODO: re-enable when TranscriptMatcher accuracy improves
                        }
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredBulletID = hovering ? bullet.id : nil
                            }
                        }
                        .contextMenu {
                            if let onCreateActionItem {
                                Button("Create Action Item") {
                                    let item = ActionItem(title: bullet.text)
                                    item.sourceQuote = bullet.sourceQuote
                                    onCreateActionItem(item)
                                }
                            }
                        }
                    }
                }
            }

            if !summary.decisions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Decisions")
                        .font(.headline)
                    ForEach(summary.decisions, id: \.self) { decision in
                        HStack(alignment: .top, spacing: 6) {
                            Text("✓")
                                .foregroundStyle(.green)
                            Text(decision)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .popover(item: $selectedBullet) { bullet in
            TranscriptExcerptPopover(
                quote: bullet.sourceQuote ?? "",
                transcriptWords: transcriptWords
            )
        }
    }
}

private struct TranscriptExcerptPopover: View {
    let quote: String
    let transcriptWords: [TranscriptWord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Source")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if let result = TranscriptMatcher.findMatchWithTimestamps(quote: quote, in: transcriptWords) {
                let contextWords = Array(transcriptWords[result.contextRange])
                let matchRange = result.match.wordRange

                Text(contextWordsAttributed(contextWords, matchRange: matchRange, contextStart: result.contextRange.lowerBound))
                    .font(.callout)
                    .lineSpacing(4)

                let startTime = transcriptWords[matchRange.lowerBound].start
                Text(formatTimestamp(startTime))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Could not locate in transcript")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: 400)
    }

    private func contextWordsAttributed(_ words: [TranscriptWord], matchRange: Range<Int>, contextStart: Int) -> AttributedString {
        var result = AttributedString()
        for (i, word) in words.enumerated() {
            let globalIndex = contextStart + i
            var attr = AttributedString(word.word + " ")
            if matchRange.contains(globalIndex) {
                attr.backgroundColor = .yellow.opacity(0.3)
                attr.font = .callout.bold()
            }
            result.append(attr)
        }
        return result
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

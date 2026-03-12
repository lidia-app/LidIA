import SwiftUI
import SwiftData

struct GeneralSettingsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        // Appearance
        Section("Appearance") {
            Picker("Theme", selection: $settings.appearanceMode) {
                ForEach(AppSettings.AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }

        // Assistant Personality
        Section("Assistant") {
            TextField("Your name", text: $settings.displayName)
                .textFieldStyle(.roundedBorder)

            Picker("Personality", selection: $settings.assistantPersonality) {
                ForEach(AppSettings.AssistantPersonality.allCases, id: \.self) { personality in
                    Text(personality.rawValue).tag(personality)
                }
            }

            Text("Applies to both voice assistant and chat.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("Soul & Memory")
                Spacer()
                Button("Edit SOUL.md") {
                    openOrCreateSoulFile()
                }
                .buttonStyle(.link)
                Button("View MEMORY.md") {
                    openMemoryFile()
                }
                .buttonStyle(.link)
            }

            Text("SOUL.md \u{2014} your assistant's personality, tone, and instructions (you edit this). MEMORY.md \u{2014} things LidIA remembers about you (it writes this). Both live in ~/.lidia/")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Custom Vocabulary
        Section("Custom Vocabulary") {
            Text("Replace misheard words automatically during transcription.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach($settings.customVocabulary) { $entry in
                HStack(spacing: 8) {
                    TextField("Heard as", text: $entry.heardAs)
                        .frame(maxWidth: 150)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    TextField("Replace with", text: $entry.replaceTo)
                        .frame(maxWidth: 150)
                    let entryID = entry.id
                    Button(role: .destructive) {
                        settings.customVocabulary.removeAll { $0.id == entryID }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button("Add Word") {
                settings.customVocabulary.append(
                    AppSettings.VocabularyEntry(heardAs: "", replaceTo: "")
                )
            }
            .buttonStyle(.glass)
        }

        // Meeting Templates
        Section("Meeting Templates") {
            MeetingTemplatesSection(settings: settings)
        }
    }

    private func openOrCreateSoulFile() {
        let path = VoiceToolExecutor.soulFilePath
        let url = URL(fileURLWithPath: path)
        let dir = URL(fileURLWithPath: VoiceToolExecutor.lidiaDir)

        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: path) {
            let template = """
                # LidIA Soul

                Write any instructions here. LidIA will follow them in voice and chat.
                This is your assistant's personality \u{2014} make it yours.

                Examples:
                - Respond in Spanish
                - I work at Acme Corp on the Platform team
                - When summarizing, focus on action items and decisions
                - Be concise, no fluff
                - Call me by my first name
                """
            try? template.write(toFile: path, atomically: true, encoding: .utf8)
        }

        NSWorkspace.shared.open(url)
    }

    private func openMemoryFile() {
        let path = VoiceToolExecutor.memoryFilePath
        let url = URL(fileURLWithPath: path)

        if !FileManager.default.fileExists(atPath: path) {
            let dir = URL(fileURLWithPath: VoiceToolExecutor.lidiaDir)
            if !FileManager.default.fileExists(atPath: dir.path) {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try? "# LidIA Memory\n\nThings I've learned about you:\n\n".write(toFile: path, atomically: true, encoding: .utf8)
        }

        NSWorkspace.shared.open(url)
    }
}

// MARK: - Meeting Templates Section

struct MeetingTemplatesSection: View {
    @Bindable var settings: AppSettings
    @Environment(\.modelContext) private var modelContext
    @State private var editingTemplateID: UUID?
    @State private var showPreviewSheet = false
    @State private var previewTemplateID: UUID?
    @State private var previewMeeting: Meeting?
    @State private var previewResult: String = ""
    @State private var isPreviewLoading = false

    var body: some View {
        ForEach($settings.meetingTemplates) { $template in
            DisclosureGroup(
                isExpanded: Binding(
                    get: { editingTemplateID == template.id },
                    set: { editingTemplateID = $0 ? template.id : nil }
                )
            ) {
                TemplateEditorView(template: $template)
                if template.isBuiltIn {
                    Button("Duplicate") {
                        var copy = template
                        copy.id = UUID()
                        copy.name = "\(template.name) (Copy)"
                        copy.isBuiltIn = false
                        settings.meetingTemplates.append(copy)
                        editingTemplateID = copy.id
                    }
                    .buttonStyle(.glass)
                }
                if !template.isBuiltIn {
                    let templateID = template.id
                    Button("Delete Template", role: .destructive) {
                        editingTemplateID = nil
                        settings.meetingTemplates.removeAll { $0.id == templateID }
                    }
                    .buttonStyle(.glass)
                }
                Button("Test with Past Meeting...") {
                    previewTemplateID = template.id
                    previewMeeting = nil
                    previewResult = ""
                    showPreviewSheet = true
                }
                .buttonStyle(.glass)
            } label: {
                HStack {
                    if !template.emoji.isEmpty {
                        Text(template.emoji)
                    }
                    Text(template.name.isEmpty ? "Untitled" : template.name)
                        .fontWeight(template.isBuiltIn ? .medium : .regular)
                    Spacer()
                    if template.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        Button("Add Template") {
            let new = MeetingTemplate(name: "", systemPrompt: "")
            settings.meetingTemplates.append(new)
            editingTemplateID = new.id
        }
        .buttonStyle(.glass)
        .sheet(isPresented: $showPreviewSheet) {
            templatePreviewSheet
        }
    }

    @MainActor
    private var templatePreviewSheet: some View {
        VStack(spacing: 16) {
            Text("Test Template")
                .font(.title3.bold())

            if let templateID = previewTemplateID,
               let template = settings.meetingTemplates.first(where: { $0.id == templateID }) {

                let descriptor = FetchDescriptor<Meeting>(sortBy: [SortDescriptor(\.date, order: .reverse)])
                let allMeetings = (try? modelContext.fetch(descriptor)) ?? []
                let meetings = allMeetings.filter { $0.status == .complete }

                if meetings.isEmpty {
                    Text("No completed meetings to test with.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Meeting", selection: $previewMeeting) {
                        Text("Select a meeting...").tag(nil as Meeting?)
                        ForEach(meetings) { meeting in
                            Text("\(meeting.title.isEmpty ? "Untitled" : meeting.title) \u{2014} \(meeting.date.formatted(date: .abbreviated, time: .shortened))")
                                .tag(meeting as Meeting?)
                        }
                    }

                    if previewMeeting != nil {
                        Button("Generate Preview") {
                            generatePreview(template: template)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isPreviewLoading)
                    }
                }

                if isPreviewLoading {
                    ProgressView("Generating preview...")
                }

                if !previewResult.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Preview Result")
                                .font(.headline)
                            Text(previewResult)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                    }
                    .frame(maxHeight: 400)
                }
            }

            Button("Close") {
                showPreviewSheet = false
                previewResult = ""
                previewMeeting = nil
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 300)
    }

    @Environment(ModelManager.self) private var modelManager

    private func generatePreview(template: MeetingTemplate) {
        guard let meeting = previewMeeting else { return }
        isPreviewLoading = true
        previewResult = ""
        Task {
            defer { isPreviewLoading = false }
            let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .chat)
            let model = effectiveModel(for: .summary, settings: settings, taskType: .chat)
            let transcript = meeting.userEditedTranscript?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let effectiveText = transcript.isEmpty ? meeting.refinedTranscript : transcript
            guard !effectiveText.isEmpty else {
                previewResult = "No transcript available for this meeting."
                return
            }
            do {
                let summary = try await client.summarizeMeeting(
                    transcript: effectiveText,
                    model: model,
                    template: template
                )
                previewResult = summary.flatSummary
            } catch {
                previewResult = "Error: \(error.localizedDescription)"
            }
        }
    }
}

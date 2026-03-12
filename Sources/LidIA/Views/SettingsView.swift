import SwiftUI
import SwiftData

struct SettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            GeneralSettingsTab(settings: settings)
            LLMSettingsTab(settings: settings)
            RecordingSettingsTab(settings: settings)
            VoiceSettingsTab(settings: settings)
            Section("Integrations") {
                CalendarSettingsTab(settings: settings)
                IntegrationSettingsTab(settings: settings)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 450, minHeight: 400)
    }
}

// MARK: - Template Editor (Inline)

struct TemplateEditorView: View {
    @Binding var template: MeetingTemplate

    @State private var attendeeMin: String = ""
    @State private var attendeeMax: String = ""
    @State private var keywords: String = ""
    @State private var aiDescription: String = ""
    @State private var isGeneratingFromAI = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name + Emoji
            HStack(spacing: 8) {
                TextField("Emoji", text: $template.emoji)
                    .frame(width: 40)
                    .multilineTextAlignment(.center)
                TextField("Template Name", text: $template.name)
            }

            TextField("Description (shown in picker)", text: $template.description)
                .font(.callout)

            // AI-assisted creation
            if !template.isBuiltIn {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Describe what you want")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("e.g. customer calls focusing on pain points and feature requests", text: $aiDescription)
                        Button {
                            generateFromDescription()
                        } label: {
                            if isGeneratingFromAI {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                        }
                        .disabled(aiDescription.isEmpty || isGeneratingFromAI)
                    }
                }
            }

            // Mode toggle
            if !template.isBuiltIn {
                Toggle("Advanced mode (raw prompt)", isOn: $template.isAdvancedMode)
                    .toggleStyle(.checkbox)
            }

            if template.isAdvancedMode {
                Text("System Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $template.systemPrompt)
                    .font(.body.monospaced())
                    .frame(minHeight: 150)
                    .border(Color.secondary.opacity(0.2))
            } else {
                Text("Sections")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach($template.sections) { $section in
                    HStack(spacing: 8) {
                        TextField("Section name", text: $section.name)
                            .frame(maxWidth: 150)
                        TextField("Description", text: $section.description)
                        Picker("", selection: $section.format) {
                            Text("Bullets").tag(OutputFormat.bullets)
                            Text("Prose").tag(OutputFormat.prose)
                            Text("Table").tag(OutputFormat.table)
                        }
                        .frame(width: 100)
                        let sectionID = section.id
                        Button(role: .destructive) {
                            template.sections.removeAll { $0.id == sectionID }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button("Add Section") {
                    template.sections.append(SectionSpec(name: ""))
                }
                .buttonStyle(.glass)

                if !template.sections.isEmpty {
                    DisclosureGroup("Preview prompt") {
                        Text(template.effectiveSystemPrompt)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Text("Auto-Detection Rules")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Attendees:")
                    .frame(width: 80, alignment: .leading)
                TextField("Min", text: $attendeeMin)
                    .frame(width: 60)
                    .onChange(of: attendeeMin) { _, _ in syncAttendeeRules() }
                Text("to")
                TextField("Max", text: $attendeeMax)
                    .frame(width: 60)
                    .onChange(of: attendeeMax) { _, _ in syncAttendeeRules() }
            }

            HStack(spacing: 8) {
                Text("Keywords:")
                    .frame(width: 80, alignment: .leading)
                TextField("e.g. brainstorm, ideation", text: $keywords)
                    .onChange(of: keywords) { _, _ in syncKeywords() }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            if let range = template.autoDetectRules.attendeeCount {
                attendeeMin = "\(range.lowerBound)"
                attendeeMax = "\(range.upperBound)"
            }
            keywords = template.autoDetectRules.titleKeywords.joined(separator: ", ")
        }
    }

    private func syncAttendeeRules() {
        if let min = Int(attendeeMin), let max = Int(attendeeMax), min <= max {
            template.autoDetectRules.attendeeCount = min...max
        } else {
            template.autoDetectRules.attendeeCount = nil
        }
    }

    private func syncKeywords() {
        template.autoDetectRules.titleKeywords = keywords
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func generateFromDescription() {
        isGeneratingFromAI = true
        Task {
            defer { isGeneratingFromAI = false }
            let parts = aiDescription
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            template.sections = parts.map { part in
                SectionSpec(name: part.capitalized, description: "", format: .bullets)
            }
            template.isAdvancedMode = false
            if template.name.isEmpty {
                template.name = String(aiDescription.prefix(30))
            }
        }
    }
}

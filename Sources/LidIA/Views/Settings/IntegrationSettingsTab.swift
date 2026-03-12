import SwiftUI

struct IntegrationSettingsTab: View {
    @Bindable var settings: AppSettings

    var body: some View {
        // Device Sync
        DisclosureGroup("Device Sync") {
            Toggle("Enable Sync", isOn: $settings.syncEnabled)

            if settings.syncEnabled {
                TextField("Server URL", text: $settings.syncServerURL)
                    .textFieldStyle(.roundedBorder)

                SecureField("Auth Token", text: $settings.syncAuthToken)
                    .textFieldStyle(.roundedBorder)

                Text("Syncs meetings, action items, and files between your devices over your private network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        // Notion
        DisclosureGroup("Notion") {
            SecureField("API Key", text: $settings.notionAPIKey)

            if !settings.notionAPIKey.isEmpty {
                if settings.availableDatabases.isEmpty {
                    Button("Fetch Databases") {
                        Task { await fetchDatabases() }
                    }
                    .buttonStyle(.glass)
                } else {
                    Picker("Meeting Database", selection: $settings.notionDatabaseID) {
                        ForEach(settings.availableDatabases) { db in
                            Text(db.title).tag(db.id)
                        }
                    }

                    Picker("Task Tracker Database", selection: $settings.notionTasksDatabaseID) {
                        Text("None").tag("")
                        ForEach(settings.availableDatabases) { db in
                            Text(db.title).tag(db.id)
                        }
                    }

                    Text("Meeting pages use the meeting database. Action item export buttons use the task tracker database.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Auto-send after meetings", isOn: $settings.notionAutoSend)

                    Section("What to send") {
                        Toggle("Summary", isOn: $settings.notionSendSummary)
                        Toggle("Action Items", isOn: $settings.notionSendActionItems)
                    }
                }
            }
        }

        // Claude MCP
        DisclosureGroup("Claude MCP") {
            Text("Connect LidIA to Claude Desktop so Claude can access your meeting data.")
                .font(.caption)
                .foregroundStyle(.secondary)

            let execPath = Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent("LidiaMCP")
                .path ?? "/path/to/LidiaMCP"

            LabeledContent("Binary Path") {
                Text(execPath)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            LabeledContent("Config Path") {
                Text("~/Library/Application Support/Claude/claude_desktop_config.json")
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }

            Button("Copy MCP Config") {
                let config = """
                {
                  "mcpServers": {
                    "lidia": {
                      "command": "\(execPath)",
                      "args": []
                    }
                  }
                }
                """
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(config, forType: .string)
            }
            .buttonStyle(.glass)
        }

        // Slack
        DisclosureGroup("Slack") {
            Toggle("Enable Slack Integration", isOn: $settings.slackEnabled)

            if settings.slackEnabled {
                SecureField("Bot Token", text: $settings.slackBotToken)
                    .textFieldStyle(.roundedBorder)

                TextField("Channel (e.g. #meeting-notes)", text: $settings.slackChannel)
                    .textFieldStyle(.roundedBorder)

                Text("Create a Slack App with chat:write scope. Install to your workspace and paste the Bot User OAuth Token here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-send after meetings", isOn: $settings.slackAutoSend)

                Section("What to send") {
                    Toggle("Summary", isOn: $settings.slackSendSummary)
                    Toggle("Action Items", isOn: $settings.slackSendActionItems)
                    Toggle("Attendees", isOn: $settings.slackSendAttendees)
                }
            }
        }

        // n8n
        DisclosureGroup("n8n Webhook") {
            Toggle("Enable n8n Integration", isOn: $settings.n8nEnabled)

            if settings.n8nEnabled {
                TextField("Webhook URL", text: $settings.n8nWebhookURL)
                    .textContentType(.URL)

                SecureField("Auth Header (optional)", text: $settings.n8nAuthHeader)

                Text("JSON payload is sent to this URL after each meeting is processed. n8n handles downstream orchestration (Slack, ClickUp, email, etc.).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Auto-send after meetings", isOn: $settings.n8nAutoSend)

                Section("What to send") {
                    Toggle("Summary", isOn: $settings.n8nSendSummary)
                    Toggle("Action Items", isOn: $settings.n8nSendActionItems)
                    Toggle("Attendees", isOn: $settings.n8nSendAttendees)
                    Toggle("Full Transcript", isOn: $settings.n8nSendTranscript)
                }
            }
        }
    }

    @MainActor
    private func fetchDatabases() async {
        let client = NotionClient(apiKey: settings.notionAPIKey)
        if let dbs = try? await client.listDatabases() {
            settings.availableDatabases = dbs.map {
                AppSettings.DatabaseEntry(id: $0.id, title: $0.title)
            }
        }
    }
}

import SwiftUI

struct IntegrationSettingsTab: View {
    @Bindable var settings: AppSettings
    @State private var mcpJustInstalled = false

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
            let configPath = NSString(string: "~/Library/Application Support/Claude/claude_desktop_config.json").expandingTildeInPath
            let claudeDir = NSString(string: "~/Library/Application Support/Claude").expandingTildeInPath
            let isClaudeInstalled = FileManager.default.fileExists(atPath: claudeDir)
            let mcpBinaryPath = Bundle.main.bundlePath + "/Contents/MacOS/LidiaMCP"
            let isMCPInstalled = checkMCPInstalled(configPath: configPath)

            if !isClaudeInstalled {
                Label("Claude Desktop not found", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)

                Text("Install Claude Desktop first, then return here to connect LidIA.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isMCPInstalled {
                Label("MCP connected to Claude Desktop", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)

                Button("Uninstall MCP") {
                    uninstallMCP(configPath: configPath)
                }
                .buttonStyle(.glass)
            } else {
                Text("Connect LidIA to Claude Desktop so Claude can query your meeting data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Install MCP") {
                    print("[MCP] Installing with binary path: \(mcpBinaryPath)")
                    installMCP(configPath: configPath, binaryPath: mcpBinaryPath)
                    mcpJustInstalled = true
                }
                .buttonStyle(.glassProminent)
            }

            if mcpJustInstalled {
                Label("Restart Claude Desktop to activate", systemImage: "arrow.clockwise")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            Button("Copy Config to Clipboard") {
                let config = """
                {
                  "mcpServers": {
                    "lidia": {
                      "command": "\(mcpBinaryPath)"
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

        // Markdown Vault
        DisclosureGroup("Markdown Vault") {
            Toggle("Auto-export meetings as Markdown", isOn: $settings.vaultExportEnabled)

            if settings.vaultExportEnabled {
                HStack {
                    TextField("Export path", text: $settings.vaultExportPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.canCreateDirectories = true
                        if panel.runModal() == .OK, let url = panel.url {
                            settings.vaultExportPath = url.path
                        }
                    }
                }
                Toggle("Include full transcript", isOn: $settings.vaultExportIncludeTranscript)
                Text("Meetings are saved as `.md` files with YAML frontmatter. Compatible with Obsidian, iA Writer, etc.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        // Autopilot
        DisclosureGroup("Autopilot") {
            Toggle("Auto-dispatch action items", isOn: $settings.autopilotEnabled)
            Text("Automatically send action items to their suggested destinations (ClickUp, Notion, Reminders, n8n) after each meeting. Items are dispatched based on AI-suggested destinations.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func checkMCPInstalled(configPath: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else { return false }
        return servers["lidia"] != nil
    }

    private func installMCP(configPath: String, binaryPath: String) {
        var config: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: configPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = existing
        }
        var servers = config["mcpServers"] as? [String: Any] ?? [:]
        servers["lidia"] = ["command": binaryPath]
        config["mcpServers"] = servers

        if let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) {
            let dir = (configPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? data.write(to: URL(fileURLWithPath: configPath))
        }
    }

    private func uninstallMCP(configPath: String) {
        guard let data = FileManager.default.contents(atPath: configPath),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var servers = config["mcpServers"] as? [String: Any] else { return }
        servers.removeValue(forKey: "lidia")
        config["mcpServers"] = servers
        if let updatedData = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: URL(fileURLWithPath: configPath))
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

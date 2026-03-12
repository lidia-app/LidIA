import Foundation
import Observation

@MainActor
@Observable
final class IntegrationSettings {
    private var isLoading = false

    // Notion
    var notionAPIKey: String = "" {
        didSet { SettingsKeychain.save(key: "lidia.notion.apiKey", value: notionAPIKey) }
    }
    var notionDatabaseID: String = "" {
        didSet { saveDefault(notionDatabaseID, forKey: "notionDatabaseID") }
    }
    var notionDatabaseName: String = "" {
        didSet { saveDefault(notionDatabaseName, forKey: "notionDatabaseName") }
    }
    var notionTasksDatabaseID: String = "" {
        didSet { saveDefault(notionTasksDatabaseID, forKey: "notionTasksDatabaseID") }
    }
    var availableDatabases: [AppSettings.DatabaseEntry] = []

    // n8n
    var n8nEnabled: Bool = false {
        didSet { saveDefault(n8nEnabled, forKey: "n8nEnabled") }
    }
    var n8nWebhookURL: String = "" {
        didSet { saveDefault(n8nWebhookURL, forKey: "n8nWebhookURL") }
    }
    var n8nAuthHeader: String = "" {
        didSet { SettingsKeychain.save(key: "lidia.n8n.authHeader", value: n8nAuthHeader) }
    }

    // Slack
    var slackEnabled: Bool = false {
        didSet { saveDefault(slackEnabled, forKey: "slackEnabled") }
    }
    var slackBotToken: String = "" {
        didSet { SettingsKeychain.save(key: "lidia.slack.botToken", value: slackBotToken) }
    }
    var slackChannel: String = "" {
        didSet { saveDefault(slackChannel, forKey: "slackChannel") }
    }
    var slackAutoSend: Bool = true {
        didSet { saveDefault(slackAutoSend, forKey: "slackAutoSend") }
    }
    var slackSendSummary: Bool = true {
        didSet { saveDefault(slackSendSummary, forKey: "slackSendSummary") }
    }
    var slackSendActionItems: Bool = true {
        didSet { saveDefault(slackSendActionItems, forKey: "slackSendActionItems") }
    }
    var slackSendAttendees: Bool = true {
        didSet { saveDefault(slackSendAttendees, forKey: "slackSendAttendees") }
    }

    // ClickUp
    var clickUpAPIKey: String = "" {
        didSet { SettingsKeychain.save(key: "lidia.clickup.apiKey", value: clickUpAPIKey) }
    }
    var clickUpListID: String = "" {
        didSet { saveDefault(clickUpListID, forKey: "clickUpListID") }
    }

    // Sync
    var syncEnabled: Bool = false {
        didSet { saveDefault(syncEnabled, forKey: "syncEnabled") }
    }
    var syncServerURL: String = "" {
        didSet { saveDefault(syncServerURL, forKey: "syncServerURL") }
    }
    var syncAuthToken: String = "" {
        didSet { SettingsKeychain.save(key: "lidia.sync.authToken", value: syncAuthToken) }
    }

    // Integration auto-send
    var notionAutoSend: Bool = true {
        didSet { saveDefault(notionAutoSend, forKey: "notionAutoSend") }
    }
    var n8nAutoSend: Bool = true {
        didSet { saveDefault(n8nAutoSend, forKey: "n8nAutoSend") }
    }
    var remindersAutoSend: Bool = true {
        didSet { saveDefault(remindersAutoSend, forKey: "remindersAutoSend") }
    }

    // Notion field controls
    var notionSendSummary: Bool = true {
        didSet { saveDefault(notionSendSummary, forKey: "notionSendSummary") }
    }
    var notionSendActionItems: Bool = true {
        didSet { saveDefault(notionSendActionItems, forKey: "notionSendActionItems") }
    }

    // n8n field controls
    var n8nSendSummary: Bool = true {
        didSet { saveDefault(n8nSendSummary, forKey: "n8nSendSummary") }
    }
    var n8nSendActionItems: Bool = true {
        didSet { saveDefault(n8nSendActionItems, forKey: "n8nSendActionItems") }
    }
    var n8nSendAttendees: Bool = true {
        didSet { saveDefault(n8nSendAttendees, forKey: "n8nSendAttendees") }
    }
    var n8nSendTranscript: Bool = true {
        didSet { saveDefault(n8nSendTranscript, forKey: "n8nSendTranscript") }
    }

    // Reminders field controls
    var remindersMyItemsOnly: Bool = true {
        didSet { saveDefault(remindersMyItemsOnly, forKey: "remindersMyItemsOnly") }
    }

    // MARK: - Init

    init() {
        loadFromDefaults()
    }

    func loadFromDefaults() {
        isLoading = true
        defer { isLoading = false }
        let defaults = UserDefaults.standard
        notionAPIKey = SettingsKeychain.load(key: "lidia.notion.apiKey") ?? ""
        notionDatabaseID = defaults.string(forKey: "notionDatabaseID") ?? ""
        notionDatabaseName = defaults.string(forKey: "notionDatabaseName") ?? ""
        notionTasksDatabaseID = defaults.string(forKey: "notionTasksDatabaseID") ?? ""
        n8nEnabled = defaults.bool(forKey: "n8nEnabled")
        n8nWebhookURL = defaults.string(forKey: "n8nWebhookURL") ?? ""
        n8nAuthHeader = SettingsKeychain.load(key: "lidia.n8n.authHeader") ?? ""
        slackEnabled = defaults.bool(forKey: "slackEnabled")
        slackBotToken = SettingsKeychain.load(key: "lidia.slack.botToken") ?? ""
        slackChannel = defaults.string(forKey: "slackChannel") ?? ""
        if let val = defaults.object(forKey: "slackAutoSend") as? Bool {
            slackAutoSend = val
        }
        if let val = defaults.object(forKey: "slackSendSummary") as? Bool {
            slackSendSummary = val
        }
        if let val = defaults.object(forKey: "slackSendActionItems") as? Bool {
            slackSendActionItems = val
        }
        if let val = defaults.object(forKey: "slackSendAttendees") as? Bool {
            slackSendAttendees = val
        }
        clickUpAPIKey = SettingsKeychain.load(key: "lidia.clickup.apiKey") ?? ""
        clickUpListID = defaults.string(forKey: "clickUpListID") ?? ""
        syncEnabled = defaults.bool(forKey: "syncEnabled")
        syncServerURL = defaults.string(forKey: "syncServerURL") ?? ""
        syncAuthToken = SettingsKeychain.load(key: "lidia.sync.authToken") ?? ""
        if let autoSend = defaults.object(forKey: "notionAutoSend") as? Bool {
            notionAutoSend = autoSend
        }
        if let autoSend = defaults.object(forKey: "n8nAutoSend") as? Bool {
            n8nAutoSend = autoSend
        }
        if let autoSend = defaults.object(forKey: "remindersAutoSend") as? Bool {
            remindersAutoSend = autoSend
        }
        if let val = defaults.object(forKey: "notionSendSummary") as? Bool {
            notionSendSummary = val
        }
        if let val = defaults.object(forKey: "notionSendActionItems") as? Bool {
            notionSendActionItems = val
        }
        if let val = defaults.object(forKey: "n8nSendSummary") as? Bool {
            n8nSendSummary = val
        }
        if let val = defaults.object(forKey: "n8nSendActionItems") as? Bool {
            n8nSendActionItems = val
        }
        if let val = defaults.object(forKey: "n8nSendAttendees") as? Bool {
            n8nSendAttendees = val
        }
        if let val = defaults.object(forKey: "n8nSendTranscript") as? Bool {
            n8nSendTranscript = val
        }
        if let val = defaults.object(forKey: "remindersMyItemsOnly") as? Bool {
            remindersMyItemsOnly = val
        }
    }

    // MARK: - Persistence Helpers

    private func saveDefault(_ value: some Any, forKey key: String) {
        guard !isLoading else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
}

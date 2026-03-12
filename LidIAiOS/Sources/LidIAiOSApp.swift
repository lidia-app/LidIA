import SwiftUI
import SwiftData
import LidIAKit

@main
struct LidIAiOSApp: App {
    let modelContainer: ModelContainer
    @State private var settings = iOSSettings()
    @State private var syncClient: SyncClient
    @State private var syncEngine: SyncEngine?
    @State private var syncStarted = false

    init() {
        let schema = Schema([Meeting.self, ActionItem.self, TalkingPoint.self])
        let config = ModelConfiguration(
            cloudKitDatabase: .none
        )
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }

        // Use a URLSession that bypasses iCloud Private Relay / proxies.
        // Private Relay intercepts HTTP traffic and can't reach Tailscale hosts.
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.connectionProxyDictionary = [:]
        let directSession = URLSession(configuration: sessionConfig)
        _syncClient = State(initialValue: SyncClient(session: directSession))
    }

    var body: some Scene {
        WindowGroup {
            iOSRootView()
                .environment(settings)
                .onAppear {
                    startSyncIfNeeded()
                }
                .onChange(of: settings.syncEnabled) { _, _ in
                    startSyncIfNeeded()
                }
                .onChange(of: settings.syncServerURL) { _, _ in
                    startSyncIfNeeded()
                }
                .onChange(of: settings.syncAuthToken) { _, _ in
                    startSyncIfNeeded()
                }
        }
        .modelContainer(modelContainer)
    }

    private func startSyncIfNeeded() {
        guard settings.syncEnabled,
              !settings.syncServerURL.isEmpty,
              !settings.syncAuthToken.isEmpty else {
            if syncStarted {
                Task { await syncClient.stopPolling() }
                syncStarted = false
                syncEngine = nil
            }
            return
        }

        guard !syncStarted else { return }
        syncStarted = true

        let engine = SyncEngine(client: syncClient, modelContainer: modelContainer)
        self.syncEngine = engine

        Task { @MainActor in
            await syncClient.configure(
                serverURL: settings.syncServerURL,
                token: settings.syncAuthToken
            )
            await syncClient.startPolling(interval: 30) { [weak engine] response in
                await MainActor.run {
                    engine?.apply(response)
                }
            }
        }
    }
}

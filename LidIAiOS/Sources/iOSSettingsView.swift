import SwiftUI
import LidIAKit

struct iOSSettingsView: View {
    @Environment(iOSSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Profile") {
                TextField("Your Name", text: $settings.displayName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
            }

            Section("Personality") {
                Picker("Style", selection: $settings.personalityMode) {
                    ForEach(iOSSettings.PersonalityMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.personalityMode.promptFragment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("OpenAI API Key") {
                SecureField("sk-...", text: $settings.openaiAPIKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if settings.hasAPIKey {
                    Label("Key configured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Label("Required for voice assistant", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            Section("Voice") {
                Picker("Voice", selection: $settings.ttsVoiceID) {
                    ForEach(TTSVoice.allCases) { voice in
                        Text(voice.label).tag(voice.id)
                    }
                }
            }

            Section("Device Sync") {
                Toggle("Enable Sync", isOn: $settings.syncEnabled)

                if settings.syncEnabled {
                    TextField("Server URL", text: $settings.syncServerURL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Auth Token", text: $settings.syncAuthToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Text("Syncs meetings, action items, SOUL.md and MEMORY.md with your Mac over your private network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("SOUL & Memory") {
                NavigationLink("Edit SOUL.md") {
                    FileEditorView(
                        title: "SOUL.md",
                        filePath: VoiceToolExecutor.soulFilePath(),
                        defaultContent: "# LidIA Soul\n\nInstructions that shape how LidIA behaves:\n\n"
                    )
                }

                NavigationLink("View MEMORY.md") {
                    FileEditorView(
                        title: "MEMORY.md",
                        filePath: VoiceToolExecutor.memoryFilePath(),
                        defaultContent: "# LidIA Memory\n\nThings I've learned about you:\n\n"
                    )
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - TTS Voices

private enum TTSVoice: String, CaseIterable, Identifiable {
    case alloy, ash, ballad, coral, echo, fable, nova, onyx, sage, shimmer, verse

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alloy: "Alloy (neutral)"
        case .ash: "Ash (warm male)"
        case .ballad: "Ballad (expressive)"
        case .coral: "Coral (warm female)"
        case .echo: "Echo (deep male)"
        case .fable: "Fable (British)"
        case .nova: "Nova (bright female)"
        case .onyx: "Onyx (deep male)"
        case .sage: "Sage (calm)"
        case .shimmer: "Shimmer (soft female)"
        case .verse: "Verse (versatile)"
        }
    }
}

// MARK: - File Editor

struct FileEditorView: View {
    let title: String
    let filePath: String
    let defaultContent: String

    @State private var content: String = ""
    @State private var hasLoaded = false

    var body: some View {
        TextEditor(text: $content)
            .font(.system(.body, design: .monospaced))
            .padding(4)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveFile()
                    }
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                loadFile()
            }
    }

    private func loadFile() {
        if FileManager.default.fileExists(atPath: filePath) {
            content = (try? String(contentsOfFile: filePath, encoding: .utf8)) ?? defaultContent
        } else {
            content = defaultContent
        }
    }

    private func saveFile() {
        let dir = (filePath as NSString).deletingLastPathComponent
        let dirURL = URL(fileURLWithPath: dir)
        if !FileManager.default.fileExists(atPath: dir) {
            try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
    }
}

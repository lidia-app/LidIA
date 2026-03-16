import SwiftUI
import LidIAKit

struct SettingsTab: View {
    @Environment(iOSSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Profile") {
                TextField("Your Name", text: $settings.displayName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
            }

            Section("LLM Provider") {
                SecureField("OpenAI API Key", text: $settings.openaiAPIKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if settings.hasAPIKey {
                    Label("Key configured", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }

                Picker("Voice", selection: $settings.ttsVoiceID) {
                    ForEach(TTSVoice.allCases) { voice in
                        Text(voice.label).tag(voice.id)
                    }
                }

                Picker("Personality", selection: $settings.personalityMode) {
                    ForEach(iOSSettings.PersonalityMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.personalityMode.promptFragment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                    Text("Syncs meetings, action items, and files with your Mac over your private network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Soul & Memory") {
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

import SwiftUI

struct VoiceSettingsTab: View {
    @Bindable var settings: AppSettings
    @Environment(VoiceAssistantService.self) private var voiceAssistant
    @Environment(TTSModelManager.self) private var ttsModelManager
    @Environment(ModelManager.self) private var modelManager

    var body: some View {
        Section("Voice Assistant") {
            Toggle("Enable Voice Assistant", isOn: $settings.voiceEnabled)
                .onChange(of: settings.voiceEnabled) { _, _ in
                    voiceAssistant.reconfigure()
                }

            if settings.voiceEnabled {
                HotkeyRecorderRow(
                    hotkey: $settings.voiceHotkey,
                    onChanged: { voiceAssistant.reconfigure() }
                )

                Picker("Text-to-Speech", selection: $settings.ttsProvider) {
                    Text("Automatic (best available)").tag(AppSettings.TTSProvider.automatic)
                    Text("Local MLX").tag(AppSettings.TTSProvider.mlx)
                    Text("System Voice (free, built-in)").tag(AppSettings.TTSProvider.system)
                    Text("OpenAI (requires API key)").tag(AppSettings.TTSProvider.openai)
                }

                if settings.ttsProvider == .mlx || settings.ttsProvider == .automatic {
                    if ttsModelManager.downloadedModelIDs.count > 1 {
                        Picker("TTS Model", selection: $settings.selectedTTSModelID) {
                            Text("Auto (first available)").tag("")
                            ForEach(ttsModelManager.availableModels.filter {
                                ttsModelManager.downloadedModelIDs.contains($0.id)
                            }) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    }
                    ttsModelRow
                }

                if settings.ttsProvider == .openai {
                    Picker("Voice", selection: $settings.ttsVoiceID) {
                        Text("Nova \u{2014} Female (default)").tag("")
                        Text("Alloy \u{2014} Female, neutral").tag("alloy")
                        Text("Echo \u{2014} Male, warm").tag("echo")
                        Text("Fable \u{2014} Male, British").tag("fable")
                        Text("Nova \u{2014} Female, friendly").tag("nova")
                        Text("Onyx \u{2014} Male, deep").tag("onyx")
                        Text("Shimmer \u{2014} Female, expressive").tag("shimmer")
                    }

                    if settings.openaiAPIKey.isEmpty {
                        Text("OpenAI API key required for cloud TTS")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Toggle("Read responses aloud", isOn: $settings.voiceReadResponses)

                HStack {
                    Text("Silence timeout")
                    Slider(value: $settings.voiceSilenceTimeout, in: 0.8...3.0, step: 0.1)
                    Text(String(format: "%.1fs", settings.voiceSilenceTimeout))
                        .monospacedDigit()
                        .frame(width: 36)
                }

                if isFullyLocalPipeline {
                    Text("Fully local pipeline: Parakeet STT \u{2192} MLX LLM \u{2192} \(ttsModelManager.isTTSModelAvailable ? "MLX TTS" : "System TTS"). No API keys needed.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var isFullyLocalPipeline: Bool {
        let localTTS = settings.ttsProvider == .system || settings.ttsProvider == .mlx
            || (settings.ttsProvider == .automatic && settings.openaiAPIKey.isEmpty)
        let localLLM = settings.llmProvider == .mlx
            || (settings.openaiAPIKey.isEmpty && settings.anthropicAPIKey.isEmpty && !modelManager.downloadedModels.isEmpty)
        return localTTS && localLLM
    }

    @ViewBuilder
    private var ttsModelRow: some View {
        ForEach(ttsModelManager.availableModels) { model in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.subheadline)
                    Text(model.sizeDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if ttsModelManager.downloadedModelIDs.contains(model.id) {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Button("Delete") {
                        ttsModelManager.delete(model)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                } else if ttsModelManager.isDownloading {
                    ProgressView(value: ttsModelManager.downloadProgress)
                        .frame(width: 100)
                    Text("\(Int(ttsModelManager.downloadProgress * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                } else {
                    Button("Download") {
                        Task { await ttsModelManager.download(model) }
                    }
                }
            }
        }

        if let error = ttsModelManager.downloadError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}

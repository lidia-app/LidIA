import SwiftUI

struct LLMSettingsTab: View {
    @Bindable var settings: AppSettings
    @Environment(ModelManager.self) private var modelManager
    @State private var modelFetchError: String?
    @AppStorage("settings.showAdvancedModels") private var showAdvancedModels = false

    var body: some View {
        // Transcription
        Section("Transcription") {
            Picker("Engine", selection: $settings.sttEngine) {
                ForEach(AppSettings.STTEngineType.allCases, id: \.self) { engine in
                    Text(engine.rawValue).tag(engine)
                }
            }

            Picker("Language", selection: $settings.sttLanguage) {
                Text("System Default").tag("")
                Divider()
                Text("English (US)").tag("en-US")
                Text("English (UK)").tag("en-GB")
                Text("Spanish").tag("es-ES")
                Text("Spanish (Latin America)").tag("es-419")
                Text("French").tag("fr-FR")
                Text("German").tag("de-DE")
                Text("Portuguese (Brazil)").tag("pt-BR")
                Text("Portuguese (Portugal)").tag("pt-PT")
                Text("Italian").tag("it-IT")
                Text("Japanese").tag("ja-JP")
                Text("Korean").tag("ko-KR")
                Text("Chinese (Simplified)").tag("zh-Hans")
                Text("Chinese (Traditional)").tag("zh-Hant")
                Text("Dutch").tag("nl-NL")
                Text("Russian").tag("ru-RU")
                Text("Arabic").tag("ar-SA")
                Text("Hindi").tag("hi-IN")
                Text("Turkish").tag("tr-TR")
                Text("Polish").tag("pl-PL")
                Text("Swedish").tag("sv-SE")
            }

            if settings.sttEngine == .parakeet && !settings.sttLanguage.isEmpty && !settings.sttLanguage.hasPrefix("en") {
                Text("Parakeet supports English only. The selected language will be ignored.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            switch settings.sttEngine {
            case .parakeet:
                Text("Parakeet TDT 0.6B \u{2014} NVIDIA's state-of-the-art ASR model optimized for Apple Neural Engine. ~110x real-time, 1.93% WER. Streams live during recording, then re-transcribes with full accuracy after.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Speaker Diarization", isOn: $settings.enableDiarization)
                if settings.enableDiarization {
                    Text("Identifies different speakers in the transcript after recording stops. Adds a few seconds of processing time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .whisperKit:
                TextField("Model (blank = auto)", text: $settings.whisperKitModel)
                Text("Leave blank to auto-select the best model for your Mac. Examples: large-v3, base, small. Model is downloaded automatically on first use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .appleSpeech:
                Text("Uses Apple's built-in speech recognition. Works for short recordings but degrades on sessions longer than ~1 minute.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        // LLM Provider
        Section("LLM Provider") {
            Picker("Provider", selection: $settings.llmProvider) {
                ForEach(AppSettings.LLMProvider.allCases, id: \.self) { provider in
                    Text(provider.rawValue).tag(provider)
                }
            }
            .onChange(of: settings.llmProvider) {
                settings.availableModels = []
                settings.queryModel = ""
                settings.summaryModel = ""
            }

            switch settings.llmProvider {
            case .ollama:
                TextField("Ollama URL", text: $settings.ollamaURL)
            case .mlx:
                if modelManager.downloadedModels.isEmpty {
                    Text("No models downloaded yet. Download one below to get started.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Active Model", selection: $settings.selectedMLXModelID) {
                        ForEach(modelManager.downloadedModels) { spec in
                            Text("\(spec.name) (~\(String(format: "%.1f", spec.ramGB))GB RAM)")
                                .tag(spec.id)
                        }
                    }
                }

                ForEach(ModelManager.availableModels) { spec in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(spec.name)
                                    .fontWeight(spec.isDefault ? .semibold : .regular)
                                if spec.isDefault {
                                    Text("Recommended")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.15))
                                        .clipShape(Capsule())
                                }
                            }
                            Text("\(spec.description) \u{2014} \(String(format: "%.1f", spec.sizeGB)) GB download")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if modelManager.isDownloading && modelManager.downloadingModelID == spec.id {
                            HStack(spacing: 8) {
                                ProgressView(value: modelManager.downloadProgress)
                                    .frame(width: 80)
                                Text("\(Int(modelManager.downloadProgress * 100))%")
                                    .font(.caption.monospacedDigit())
                                Button("Cancel") {
                                    modelManager.cancelDownload()
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                            }
                        } else if modelManager.isDownloaded(spec.id) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                if settings.selectedMLXModelID != spec.id {
                                    Button(role: .destructive) {
                                        modelManager.deleteModel(spec.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        } else {
                            Button("Download") {
                                modelManager.downloadModel(spec.id)
                            }
                            .buttonStyle(.glass)
                            .disabled(modelManager.isDownloading)
                        }
                    }
                }

                if let error = modelManager.downloadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                // Auto-select model after download completes
                EmptyView()
                    .onChange(of: modelManager.isDownloading) { _, isDownloading in
                        if !isDownloading, let loaded = modelManager.loadedModelID {
                            if settings.selectedMLXModelID.isEmpty {
                                settings.selectedMLXModelID = loaded
                            }
                        }
                    }
            case .openai:
                if settings.openaiAPIKey.isEmpty {
                    Text("Enter your OpenAI API key in the API Keys section below.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .anthropic:
                if settings.anthropicAPIKey.isEmpty {
                    Text("Enter your Anthropic API key in the API Keys section below.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .cerebras:
                if settings.cerebrasAPIKey.isEmpty {
                    Text("Enter your Cerebras API key in the API Keys section below. Free tier: 1M tokens/day.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .deepseek:
                if settings.deepseekAPIKey.isEmpty {
                    Text("Enter your DeepSeek API key in the API Keys section below.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            case .nvidiaNIM:
                if settings.nvidiaAPIKey.isEmpty {
                    Text("Enter your NVIDIA API key (starts with nvapi-*) in the API Keys section below. Access Kimi K2.5, Llama, Mistral and more through one key.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            if settings.llmProvider != .mlx {
                HStack(spacing: 10) {
                    Button("Fetch Models") {
                        Task { await fetchModels() }
                    }
                    .buttonStyle(.glass)

                    Toggle("Advanced\u{2026}", isOn: $showAdvancedModels)
                        .toggleStyle(.checkbox)
                }

                if let error = modelFetchError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("Auto mode lets LidIA pick the best model for each task.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Default Model", selection: defaultModelBinding) {
                    Text("Auto (Recommended)").tag("")
                    ForEach(modelsForMenu(selection: defaultModelBinding.wrappedValue), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Picker("Query Model", selection: $settings.queryModel) {
                    Text("(Use Default / Auto)").tag("")
                    ForEach(modelsForMenu(selection: settings.queryModel), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                Picker("Summary Model", selection: $settings.summaryModel) {
                    Text("(Use Default / Auto)").tag("")
                    ForEach(modelsForMenu(selection: settings.summaryModel), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }

            // Model Routing (Advanced)
            DisclosureGroup("Model Routing (Advanced)") {
                Text("Route specific tasks to different providers. Leave as \"Default\" to use your main provider.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(LLMTaskType.allCases, id: \.self) { taskType in
                    routeRow(for: taskType)
                }

                Divider()

                Text("If the primary provider fails, automatically retry with a fallback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Fallback Provider", selection: $settings.fallbackProvider) {
                    Text("None").tag("")
                    ForEach(AppSettings.LLMProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider.rawValue)
                    }
                }

                if !settings.fallbackProvider.isEmpty {
                    TextField("Fallback Model (blank = auto)", text: $settings.fallbackModel)
                }
            }
        }

        // API Keys
        Section("API Keys") {
            Text("API keys are stored securely in your macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                SecureField("OpenAI API Key", text: $settings.openaiAPIKey)
                if !settings.openaiAPIKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            if settings.llmProvider == .openai {
                TextField("OpenAI Base URL", text: $settings.openaiBaseURL)
                Text("Default: https://api.openai.com \u{2014} change for compatible endpoints")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                SecureField("Anthropic API Key", text: $settings.anthropicAPIKey)
                if !settings.anthropicAPIKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack {
                SecureField("Cerebras API Key", text: $settings.cerebrasAPIKey)
                if !settings.cerebrasAPIKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack {
                SecureField("DeepSeek API Key", text: $settings.deepseekAPIKey)
                if !settings.deepseekAPIKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            HStack {
                SecureField("NVIDIA API Key", text: $settings.nvidiaAPIKey)
                if !settings.nvidiaAPIKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if settings.openaiAPIKey.isEmpty && settings.anthropicAPIKey.isEmpty && settings.cerebrasAPIKey.isEmpty && settings.deepseekAPIKey.isEmpty && settings.nvidiaAPIKey.isEmpty && settings.llmProvider != .mlx && settings.llmProvider != .ollama {
                Text("Add at least one API key, or use MLX (local, free) as your LLM provider.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Helpers

    private var defaultModelBinding: Binding<String> {
        switch settings.llmProvider {
        case .ollama:
            return $settings.ollamaModel
        case .mlx:
            return $settings.selectedMLXModelID
        case .openai:
            return $settings.openaiModel
        case .anthropic:
            return $settings.anthropicModel
        case .cerebras:
            return $settings.cerebrasModel
        case .deepseek:
            return $settings.deepseekModel
        case .nvidiaNIM:
            return $settings.nvidiaModel
        }
    }

    @ViewBuilder
    private func routeRow(for taskType: LLMTaskType) -> some View {
        let currentConfig = settings.routeConfig(for: taskType)
        let selectedProvider = Binding<String>(
            get: { currentConfig?.provider.rawValue ?? "default" },
            set: { newValue in
                if newValue == "default" {
                    settings.setRouteConfig(nil, for: taskType)
                } else if let provider = AppSettings.LLMProvider(rawValue: newValue) {
                    let autoModel = ModelMenuCatalog.autoModel(for: provider, availableModels: modelsForRouteProvider(provider))
                    settings.setRouteConfig(LLMRouteConfig(provider: provider, model: autoModel), for: taskType)
                }
            }
        )
        let selectedModel = Binding<String>(
            get: { currentConfig?.model ?? "" },
            set: { newValue in
                if let provider = currentConfig?.provider {
                    settings.setRouteConfig(LLMRouteConfig(provider: provider, model: newValue), for: taskType)
                }
            }
        )

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(taskType.rawValue)
                    .frame(width: 160, alignment: .leading)
                Picker("", selection: selectedProvider) {
                    Text("Default").tag("default")
                    ForEach(AppSettings.LLMProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider.rawValue)
                    }
                }
                .frame(width: 140)
            }

            if let config = currentConfig {
                Picker("Model", selection: selectedModel) {
                    Text("Auto").tag("")
                    ForEach(modelsForRouteProvider(config.provider), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()
                .padding(.leading, 160)
            }
        }
    }

    private func modelsForRouteProvider(_ provider: AppSettings.LLMProvider) -> [String] {
        if provider == settings.llmProvider && !settings.availableModels.isEmpty {
            return ModelMenuCatalog.curatedModels(for: provider, availableModels: settings.availableModels)
        }
        return ModelMenuCatalog.knownModels(for: provider)
    }

    private func modelsForMenu(selection: String) -> [String] {
        let baseModels: [String]
        if settings.availableModels.isEmpty {
            baseModels = ModelMenuCatalog.knownModels(for: settings.llmProvider)
        } else if showAdvancedModels {
            baseModels = settings.availableModels
        } else {
            baseModels = ModelMenuCatalog.curatedModels(
                for: settings.llmProvider,
                availableModels: settings.availableModels
            )
        }

        var seen = Set<String>()
        var options: [String] = []
        for model in baseModels where seen.insert(model).inserted {
            options.append(model)
        }

        if !selection.isEmpty, !options.contains(selection) {
            options.insert(selection, at: 0)
        }

        return options
    }

    @MainActor
    private func fetchModels() async {
        modelFetchError = nil
        let client = makeLLMClient(settings: settings, modelManager: modelManager, taskType: .chat)
        do {
            let models = try await client.listModels()
            settings.availableModels = models
        } catch {
            modelFetchError = "Failed to fetch models: \(error.localizedDescription)"
        }
    }
}

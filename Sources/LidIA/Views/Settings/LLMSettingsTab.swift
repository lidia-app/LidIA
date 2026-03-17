import SwiftUI

struct LLMSettingsTab: View {
    @Bindable var settings: AppSettings
    @Environment(ModelManager.self) private var modelManager
    @State private var modelFetchError: String?
    @AppStorage("settings.showAdvancedModels") private var showAdvancedModels = false

    // Custom model entry state
    private static let customSentinel = "__custom__"
    @State private var customDefaultModel = ""
    @State private var customQueryModel = ""
    @State private var customSummaryModel = ""
    @State private var customFallbackModel = ""

    // API key validation state
    @State private var openaiKeyStatus: APIKeyStatus = .untested
    @State private var anthropicKeyStatus: APIKeyStatus = .untested
    @State private var cerebrasKeyStatus: APIKeyStatus = .untested
    @State private var deepseekKeyStatus: APIKeyStatus = .untested
    @State private var nvidiaKeyStatus: APIKeyStatus = .untested
    @State private var openRouterKeyStatus: APIKeyStatus = .untested

    private enum APIKeyStatus: Equatable {
        case untested
        case testing
        case valid
        case invalid(String)
    }

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

            case .graniteSpeech:
                Text("IBM Granite Speech 4.0 \u{2014} 1B-parameter multilingual model running locally via MLX. Supports English, French, German, Spanish, Portuguese, and Japanese. Batch mode: transcribes after recording stops.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
            case .openRouter:
                if settings.openRouterAPIKey.isEmpty {
                    Text("Enter your OpenRouter API key in the API Keys section below. OpenRouter provides access to hundreds of models through a single API key. Free tier available.")
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

                modelPicker(
                    label: "Default Model",
                    binding: defaultModelBinding,
                    customText: $customDefaultModel,
                    emptyLabel: "Auto (Recommended)"
                )

                modelPicker(
                    label: "Query Model",
                    binding: $settings.queryModel,
                    customText: $customQueryModel,
                    emptyLabel: "(Use Default / Auto)"
                )

                modelPicker(
                    label: "Summary Model",
                    binding: $settings.summaryModel,
                    customText: $customSummaryModel,
                    emptyLabel: "(Use Default / Auto)"
                )
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
                    fallbackModelPicker()
                }
            }
        }

        // API Keys
        Section("API Keys") {
            Text("API keys are stored securely in your macOS Keychain.")
                .font(.caption)
                .foregroundStyle(.secondary)

            apiKeyRow(label: "OpenAI API Key", key: $settings.openaiAPIKey, status: $openaiKeyStatus) {
                await testOpenAIKey()
            }
            if settings.llmProvider == .openai {
                TextField("OpenAI Base URL", text: $settings.openaiBaseURL)
                Text("Default: https://api.openai.com \u{2014} change for compatible endpoints")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            apiKeyRow(label: "Anthropic API Key", key: $settings.anthropicAPIKey, status: $anthropicKeyStatus) {
                await testAnthropicKey()
            }

            apiKeyRow(label: "Cerebras API Key", key: $settings.cerebrasAPIKey, status: $cerebrasKeyStatus) {
                await testCerebrasKey()
            }

            apiKeyRow(label: "DeepSeek API Key", key: $settings.deepseekAPIKey, status: $deepseekKeyStatus) {
                await testDeepSeekKey()
            }

            apiKeyRow(label: "NVIDIA API Key", key: $settings.nvidiaAPIKey, status: $nvidiaKeyStatus) {
                await testNVIDIAKey()
            }

            apiKeyRow(label: "OpenRouter API Key", key: $settings.openRouterAPIKey, status: $openRouterKeyStatus) {
                await testOpenRouterKey()
            }

            if settings.openaiAPIKey.isEmpty && settings.anthropicAPIKey.isEmpty && settings.cerebrasAPIKey.isEmpty && settings.deepseekAPIKey.isEmpty && settings.nvidiaAPIKey.isEmpty && settings.openRouterAPIKey.isEmpty && settings.llmProvider != .mlx && settings.llmProvider != .ollama {
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
        case .openRouter:
            return $settings.openRouterModel
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

    // MARK: - Model Picker with Custom Option

    /// A Picker that shows fetched/known models plus a "Custom..." option with inline TextField.
    @ViewBuilder
    private func modelPicker(
        label: String,
        binding: Binding<String>,
        customText: Binding<String>,
        emptyLabel: String
    ) -> some View {
        let models = modelsForMenu(selection: binding.wrappedValue)
        let isCustom = binding.wrappedValue == Self.customSentinel
        let isUnknownModel = !binding.wrappedValue.isEmpty
            && binding.wrappedValue != Self.customSentinel
            && !models.contains(binding.wrappedValue)

        // Picker selection: map unknown custom values to the sentinel
        let pickerSelection = Binding<String>(
            get: {
                if isCustom || isUnknownModel {
                    return Self.customSentinel
                }
                return binding.wrappedValue
            },
            set: { newValue in
                if newValue == Self.customSentinel {
                    // Switching to custom — seed the text field with current value if it was a real model
                    if !binding.wrappedValue.isEmpty && binding.wrappedValue != Self.customSentinel {
                        customText.wrappedValue = binding.wrappedValue
                    }
                    binding.wrappedValue = Self.customSentinel
                } else {
                    customText.wrappedValue = ""
                    binding.wrappedValue = newValue
                }
            }
        )

        VStack(alignment: .leading, spacing: 4) {
            Picker(label, selection: pickerSelection) {
                Text(emptyLabel).tag("")
                if !models.isEmpty {
                    Divider()
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                Divider()
                Text("Custom\u{2026}").tag(Self.customSentinel)
            }

            if isCustom || isUnknownModel {
                TextField("Model ID", text: customText)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        // Seed custom text from the current stored value
                        if isUnknownModel && customText.wrappedValue.isEmpty {
                            customText.wrappedValue = binding.wrappedValue
                        }
                    }
                    .onChange(of: customText.wrappedValue) { _, newText in
                        if !newText.isEmpty {
                            binding.wrappedValue = newText
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func fallbackModelPicker() -> some View {
        let fallbackLLMProvider = AppSettings.LLMProvider(rawValue: settings.fallbackProvider)
        let models: [String] = {
            if let provider = fallbackLLMProvider {
                return modelsForRouteProvider(provider)
            }
            return []
        }()

        let isCustom = settings.fallbackModel == Self.customSentinel
        let isUnknownModel = !settings.fallbackModel.isEmpty
            && settings.fallbackModel != Self.customSentinel
            && !models.contains(settings.fallbackModel)

        let pickerSelection = Binding<String>(
            get: {
                if isCustom || isUnknownModel {
                    return Self.customSentinel
                }
                return settings.fallbackModel
            },
            set: { newValue in
                if newValue == Self.customSentinel {
                    if !settings.fallbackModel.isEmpty && settings.fallbackModel != Self.customSentinel {
                        customFallbackModel = settings.fallbackModel
                    }
                    settings.fallbackModel = Self.customSentinel
                } else {
                    customFallbackModel = ""
                    settings.fallbackModel = newValue
                }
            }
        )

        VStack(alignment: .leading, spacing: 4) {
            Picker("Fallback Model", selection: pickerSelection) {
                Text("Auto").tag("")
                if !models.isEmpty {
                    Divider()
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                Divider()
                Text("Custom\u{2026}").tag(Self.customSentinel)
            }

            if isCustom || isUnknownModel {
                TextField("Model ID", text: $customFallbackModel)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        if isUnknownModel && customFallbackModel.isEmpty {
                            customFallbackModel = settings.fallbackModel
                        }
                    }
                    .onChange(of: customFallbackModel) { _, newText in
                        if !newText.isEmpty {
                            settings.fallbackModel = newText
                        }
                    }
            }
        }
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

    // MARK: - API Key Validation

    @ViewBuilder
    private func apiKeyRow(label: String, key: Binding<String>, status: Binding<APIKeyStatus>, test: @escaping () async -> Void) -> some View {
        HStack {
            SecureField(label, text: key)
            if !key.wrappedValue.isEmpty {
                switch status.wrappedValue {
                case .untested:
                    Button("Test") {
                        Task { await test() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .font(.caption)
                case .testing:
                    ProgressView()
                        .controlSize(.small)
                case .valid:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .invalid(let message):
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .help(message)
                }
            }
        }
        .onChange(of: key.wrappedValue) {
            status.wrappedValue = .untested
        }
    }

    @MainActor
    private func testOpenAIKey() async {
        openaiKeyStatus = .testing
        do {
            let client = OpenAIClient(
                apiKey: settings.openaiAPIKey,
                baseURL: URL(string: settings.openaiBaseURL) ?? URL(string: "https://api.openai.com")!
            )
            _ = try await client.listModels()
            openaiKeyStatus = .valid
        } catch {
            openaiKeyStatus = .invalid(error.localizedDescription)
        }
    }

    @MainActor
    private func testAnthropicKey() async {
        anthropicKeyStatus = .testing
        do {
            let client = AnthropicClient(apiKey: settings.anthropicAPIKey)
            _ = try await client.listModels()
            anthropicKeyStatus = .valid
        } catch {
            anthropicKeyStatus = .invalid(error.localizedDescription)
        }
    }

    @MainActor
    private func testCerebrasKey() async {
        cerebrasKeyStatus = .testing
        do {
            let client = OpenAIClient(apiKey: settings.cerebrasAPIKey, baseURL: URL(string: "https://api.cerebras.ai/v1")!)
            _ = try await client.listModels()
            cerebrasKeyStatus = .valid
        } catch {
            cerebrasKeyStatus = .invalid(error.localizedDescription)
        }
    }

    @MainActor
    private func testDeepSeekKey() async {
        deepseekKeyStatus = .testing
        do {
            let client = OpenAIClient(apiKey: settings.deepseekAPIKey, baseURL: URL(string: "https://api.deepseek.com/v1")!)
            _ = try await client.listModels()
            deepseekKeyStatus = .valid
        } catch {
            deepseekKeyStatus = .invalid(error.localizedDescription)
        }
    }

    @MainActor
    private func testOpenRouterKey() async {
        openRouterKeyStatus = .testing
        do {
            let client = OpenAIClient(apiKey: settings.openRouterAPIKey, baseURL: URL(string: "https://openrouter.ai/api/v1")!)
            _ = try await client.listModels()
            openRouterKeyStatus = .valid
        } catch {
            openRouterKeyStatus = .invalid(error.localizedDescription)
        }
    }

    @MainActor
    private func testNVIDIAKey() async {
        nvidiaKeyStatus = .testing
        do {
            let client = OpenAIClient(apiKey: settings.nvidiaAPIKey, baseURL: URL(string: "https://integrate.api.nvidia.com/v1")!, skipModelFilter: true)
            // NIM may not support /v1/models — try a minimal chat instead
            let messages = [LLMChatMessage(role: "user", content: "hi")]
            _ = try await client.chat(messages: messages, model: "nvidia/llama-3.3-70b-instruct", format: nil)
            nvidiaKeyStatus = .valid
        } catch let error as LLMError {
            if case .httpError(let code, _) = error, code == 401 {
                nvidiaKeyStatus = .invalid("Invalid API key (401 Unauthorized)")
            } else {
                // Non-auth errors mean the key worked but something else failed
                nvidiaKeyStatus = .valid
            }
        } catch {
            nvidiaKeyStatus = .invalid(error.localizedDescription)
        }
    }
}

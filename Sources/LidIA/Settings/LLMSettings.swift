import Foundation
import Observation
import Security

@MainActor
@Observable
final class LLMSettings {
    private var isLoading = false

    // LLM Provider
    var llmProvider: AppSettings.LLMProvider = .ollama {
        didSet { saveDefault(llmProvider.rawValue, forKey: "llmProvider") }
    }
    var ollamaURL: String = "http://localhost:11434" {
        didSet { saveDefault(ollamaURL, forKey: "ollamaURL") }
    }
    var ollamaModel: String = "" {
        didSet { saveDefault(ollamaModel, forKey: "ollamaModel") }
    }
    var openaiBaseURL: String = "https://api.openai.com" {
        didSet { saveDefault(openaiBaseURL, forKey: "openaiBaseURL") }
    }
    var openaiAPIKey: String = "" {
        didSet { SettingsKeychain.save(key: "lidia.openai.apiKey", value: openaiAPIKey) }
    }
    var openaiModel: String = "" {
        didSet { saveDefault(openaiModel, forKey: "openaiModel") }
    }

    // MLX
    var selectedMLXModelID: String = "" {
        didSet { saveDefault(selectedMLXModelID, forKey: "selectedMLXModelID") }
    }

    // Anthropic
    var anthropicAPIKey: String = "" {
        didSet { SettingsKeychain.save(key: "lidia.anthropic.apiKey", value: anthropicAPIKey) }
    }
    var anthropicModel: String = "claude-sonnet-4-20250514" {
        didSet { saveDefault(anthropicModel, forKey: "anthropicModel") }
    }

    // Cerebras
    var cerebrasAPIKey: String = "" {
        didSet { SettingsKeychain.save(key: "lidia.cerebras.apiKey", value: cerebrasAPIKey) }
    }
    var cerebrasModel: String = "llama-3.3-70b" {
        didSet { saveDefault(cerebrasModel, forKey: "cerebrasModel") }
    }

    // DeepSeek
    var deepseekAPIKey: String = "" {
        didSet { SettingsKeychain.save(key: "lidia.deepseek.apiKey", value: deepseekAPIKey) }
    }
    var deepseekModel: String = "deepseek-chat" {
        didSet { saveDefault(deepseekModel, forKey: "deepseekModel") }
    }

    // NVIDIA NIM
    var nvidiaAPIKey: String = "" {
        didSet { SettingsKeychain.save(key: "lidia.nvidia.apiKey", value: nvidiaAPIKey) }
    }
    var nvidiaModel: String = "nvidia/llama-3.3-70b-instruct" {
        didSet { saveDefault(nvidiaModel, forKey: "nvidiaModel") }
    }

    var queryModel: String = "" {
        didSet { saveDefault(queryModel, forKey: "queryModel") }
    }
    var summaryModel: String = "" {
        didSet { saveDefault(summaryModel, forKey: "summaryModel") }
    }
    var routeOverrides: [String: Data] = [:] {
        didSet { saveRouteOverrides() }
    }
    var availableModels: [String] = []

    // Fallback Provider
    var fallbackProvider: String = "" {
        didSet { saveDefault(fallbackProvider, forKey: "fallbackProvider") }
    }
    var fallbackModel: String = "" {
        didSet { saveDefault(fallbackModel, forKey: "fallbackModel") }
    }

    // MARK: - Init

    init() {
        loadFromDefaults()
    }

    func loadFromDefaults() {
        isLoading = true
        defer { isLoading = false }
        let defaults = UserDefaults.standard
        llmProvider = AppSettings.LLMProvider(rawValue: defaults.string(forKey: "llmProvider") ?? "") ?? .ollama
        ollamaURL = defaults.string(forKey: "ollamaURL") ?? "http://localhost:11434"
        ollamaModel = defaults.string(forKey: "ollamaModel") ?? ""
        openaiBaseURL = defaults.string(forKey: "openaiBaseURL") ?? "https://api.openai.com"
        openaiModel = defaults.string(forKey: "openaiModel") ?? ""
        openaiAPIKey = SettingsKeychain.load(key: "lidia.openai.apiKey") ?? ""
        selectedMLXModelID = defaults.string(forKey: "selectedMLXModelID") ?? ""
        anthropicAPIKey = SettingsKeychain.load(key: "lidia.anthropic.apiKey") ?? ""
        anthropicModel = defaults.string(forKey: "anthropicModel") ?? "claude-sonnet-4-20250514"
        cerebrasAPIKey = SettingsKeychain.load(key: "lidia.cerebras.apiKey") ?? ""
        cerebrasModel = defaults.string(forKey: "cerebrasModel") ?? "llama-3.3-70b"
        deepseekAPIKey = SettingsKeychain.load(key: "lidia.deepseek.apiKey") ?? ""
        deepseekModel = defaults.string(forKey: "deepseekModel") ?? "deepseek-chat"
        nvidiaAPIKey = SettingsKeychain.load(key: "lidia.nvidia.apiKey") ?? ""
        nvidiaModel = defaults.string(forKey: "nvidiaModel") ?? "nvidia/llama-3.3-70b-instruct"
        queryModel = defaults.string(forKey: "queryModel") ?? ""
        summaryModel = defaults.string(forKey: "summaryModel") ?? ""
        fallbackProvider = defaults.string(forKey: "fallbackProvider") ?? ""
        fallbackModel = defaults.string(forKey: "fallbackModel") ?? ""
        loadRouteOverrides()
    }

    // MARK: - Route Override Persistence

    func routeConfig(for taskType: LLMTaskType) -> LLMRouteConfig? {
        guard let data = routeOverrides[taskType.rawValue] else { return nil }
        return try? JSONDecoder().decode(LLMRouteConfig.self, from: data)
    }

    func setRouteConfig(_ config: LLMRouteConfig?, for taskType: LLMTaskType) {
        if let config, let data = try? JSONEncoder().encode(config) {
            routeOverrides[taskType.rawValue] = data
        } else {
            routeOverrides.removeValue(forKey: taskType.rawValue)
        }
    }

    private func saveRouteOverrides() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(routeOverrides) {
            UserDefaults.standard.set(data, forKey: "routeOverrides")
        }
    }

    private func loadRouteOverrides() {
        guard let data = UserDefaults.standard.data(forKey: "routeOverrides"),
              let saved = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return
        }
        routeOverrides = saved
    }

    // MARK: - Persistence Helpers

    private func saveDefault(_ value: some Any, forKey key: String) {
        guard !isLoading else { return }
        UserDefaults.standard.set(value, forKey: key)
    }
}

import Foundation

enum ModelMenuCatalog {
    static func curatedModels(for provider: AppSettings.LLMProvider, availableModels: [String]) -> [String] {
        let cleaned = dedupe(availableModels)
        guard !cleaned.isEmpty else {
            return knownModels(for: provider)
        }

        let preferred = preferredModels(for: provider)
        let preferredMatches = preferred.filter { model in
            cleaned.contains(model)
        }

        if !preferredMatches.isEmpty {
            return preferredMatches
        }

        switch provider {
        case .openai:
            return cleaned.filter {
                $0.hasPrefix("gpt-") || $0.hasPrefix("o3") || $0.hasPrefix("o4")
            }
            .prefix(6)
            .map { $0 }

        case .anthropic:
            return cleaned.filter { $0.contains("claude") }
                .prefix(6)
                .map { $0 }

        case .ollama:
            return cleaned.filter {
                let model = $0.lowercased()
                return model.contains("qwen")
                    || model.contains("llama")
                    || model.contains("mistral")
                    || model.contains("gemma")
                    || model.contains("phi")
            }
            .prefix(6)
            .map { $0 }

        case .mlx:
            return Array(cleaned)

        case .cerebras, .deepseek, .nvidiaNIM:
            return cleaned.prefix(6).map { $0 }
        }
    }

    static func knownModels(for provider: AppSettings.LLMProvider) -> [String] {
        preferredModels(for: provider)
    }

    static func autoModel(for provider: AppSettings.LLMProvider, availableModels: [String]) -> String {
        if let firstCurated = curatedModels(for: provider, availableModels: availableModels).first {
            return firstCurated
        }
        if let firstAvailable = availableModels.first {
            return firstAvailable
        }
        return knownModels(for: provider).first ?? preferredModels(for: provider)[0]
    }

    private static func preferredModels(for provider: AppSettings.LLMProvider) -> [String] {
        switch provider {
        case .openai:
            return ["gpt-4o-mini", "o4-mini", "o3-mini", "gpt-4o"]
        case .anthropic:
            return ["claude-3-5-haiku-latest", "claude-3-7-sonnet-latest", "claude-sonnet-4-20250514"]
        case .ollama:
            return ["qwen2.5:7b-instruct", "llama3.2:3b", "mistral-small"]
        case .mlx:
            return ModelManager.availableModels.map(\.id)
        case .cerebras:
            return ["llama-3.3-70b", "llama3.1-8b", "qwen-2.5-32b"]
        case .deepseek:
            return ["deepseek-chat", "deepseek-reasoner"]
        case .nvidiaNIM:
            return ["nvidia/llama-3.3-70b-instruct", "kimi-k2.5", "mistralai/mistral-large-latest"]
        }
    }

    private static func dedupe(_ models: [String]) -> [String] {
        var seen = Set<String>()
        return models.filter { seen.insert($0).inserted }
    }
}

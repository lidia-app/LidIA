import Foundation

@MainActor
enum ModelRouter {
    private static let complexKeywords = [
        "analyze", "compare", "contrast", "why", "explain",
        "plan", "strategy", "evaluate", "synthesize", "recommend",
        "pros and cons", "trade-off", "deep dive", "root cause"
    ]

    static func route(query: String, settings: AppSettings) -> String {
        let lower = query.lowercased()
        let wordCount = query.split(separator: " ").count
        let isComplex = wordCount > 50 || complexKeywords.contains(where: { lower.contains($0) })

        if isComplex {
            return thinkingModel(for: settings)
        } else {
            return defaultModel(for: settings)
        }
    }

    private static func thinkingModel(for settings: AppSettings) -> String {
        switch settings.llmProvider {
        case .openai:
            let thinking = settings.availableModels.first(where: {
                $0.hasPrefix("o3") || $0.hasPrefix("o4") || $0.contains("thinking")
            })
            return thinking ?? (settings.openaiModel.isEmpty ? "gpt-4o" : settings.openaiModel)
        case .ollama:
            return settings.ollamaModel
        case .mlx:
            return settings.selectedMLXModelID
        case .anthropic:
            return settings.anthropicModel
        case .cerebras:
            return settings.cerebrasModel
        case .deepseek:
            return "deepseek-reasoner"
        case .nvidiaNIM:
            return settings.nvidiaModel
        }
    }

    private static func defaultModel(for settings: AppSettings) -> String {
        return effectiveModel(for: .query, settings: settings)
    }
}

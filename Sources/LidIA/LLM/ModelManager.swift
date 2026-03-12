import Foundation
import Dispatch
import MLX
import Observation
import MLXLLM
import MLXLMCommon
import os

// MARK: - ModelSpec

struct ModelSpec: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let sizeGB: Double
    let ramGB: Double
    let isDefault: Bool
}

// MARK: - ModelManagerError

enum ModelManagerError: LocalizedError {
    case notDownloaded(String)
    case notLoaded

    var errorDescription: String? {
        switch self {
        case .notDownloaded(let modelID):
            return "Model '\(modelID)' is not downloaded"
        case .notLoaded:
            return "No model is currently loaded"
        }
    }
}

// MARK: - ModelManager

@MainActor
@Observable
final class ModelManager {
    nonisolated private static let logger = Logger(subsystem: "io.lidia.app", category: "ModelManager")

    /// Memory pressure source for tiered resource shedding.
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // MARK: - Available Models

    nonisolated static let availableModels: [ModelSpec] = [
        // Recommended: non-thinking, text-only, great instruction following
        ModelSpec(
            id: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            name: "Qwen3 4B Instruct (recommended)",
            description: "Fast, no-thinking mode, excellent JSON output — best default",
            sizeGB: 2.3,
            ramGB: 3.0,
            isDefault: true
        ),
        ModelSpec(
            id: "mlx-community/Phi-4-mini-instruct-4bit",
            name: "Phi-4 Mini 3.8B",
            description: "Microsoft's instruction model, fast and reliable",
            sizeGB: 2.2,
            ramGB: 3.0,
            isDefault: false
        ),
        ModelSpec(
            id: "mlx-community/Qwen3-8B-4bit",
            name: "Qwen3 8B",
            description: "Higher quality, has thinking mode (auto-stripped)",
            sizeGB: 4.6,
            ramGB: 6.0,
            isDefault: false
        ),
        ModelSpec(
            id: "mlx-community/gemma-3-4b-it-4bit",
            name: "Gemma 3 4B",
            description: "Google's instruction-tuned model, no thinking overhead",
            sizeGB: 3.4,
            ramGB: 4.0,
            isDefault: false
        ),
        ModelSpec(
            id: "mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit",
            name: "Qwen3 30B MoE (3B active)",
            description: "Best quality — MoE with only 3B active params, no thinking. Needs 24GB+ RAM",
            sizeGB: 17.2,
            ramGB: 20.0,
            isDefault: false
        ),
    ]

    static var defaultModel: ModelSpec {
        availableModels.first(where: { $0.isDefault }) ?? availableModels[0]
    }

    // MARK: - Download State

    var isDownloading: Bool = false
    var downloadProgress: Double = 0.0
    var downloadingModelID: String? = nil
    var downloadError: String? = nil

    // MARK: - Loaded Model State

    var loadedModelID: String? = nil
    var modelContainer: ModelContainer? = nil

    var isModelLoaded: Bool {
        modelContainer != nil && loadedModelID != nil
    }

    // MARK: - Private

    private var downloadTask: Task<Void, Never>? = nil

    // MARK: - Downloaded Check

    func isDownloaded(_ modelID: String) -> Bool {
        let cachePath = NSHomeDirectory() + "/Library/Caches/models/\(modelID)"
        return FileManager.default.fileExists(atPath: cachePath)
    }

    var downloadedModels: [ModelSpec] {
        Self.availableModels.filter { isDownloaded($0.id) }
    }

    // MARK: - Download

    func downloadModel(_ modelID: String) {
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0.0
        downloadingModelID = modelID
        downloadError = nil

        downloadTask = Task {
            // Tell macOS this is a user-initiated, long-running activity so it
            // doesn't kill us for excessive disk writes during model download.
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Downloading MLX model: \(modelID)"
            )
            defer { ProcessInfo.processInfo.endActivity(activity) }

            do {
                let config = ModelConfiguration(id: modelID)
                // Run heavy download+load off main actor
                let container = try await Task.detached {
                    try await LLMModelFactory.shared.loadContainer(
                        configuration: config
                    ) { progress in
                        Task { @MainActor in
                            self.downloadProgress = progress.fractionCompleted
                        }
                    }
                }.value

                self.modelContainer = container
                self.loadedModelID = modelID
                Self.logger.info("Model \(modelID) downloaded and loaded successfully")
            } catch is CancellationError {
                Self.logger.info("Download cancelled for \(modelID)")
            } catch {
                self.downloadError = error.localizedDescription
                Self.logger.error("Failed to download model \(modelID): \(error)")
            }

            self.isDownloading = false
            self.downloadingModelID = nil
            self.downloadTask = nil
        }
    }

    // MARK: - Cancel Download

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        downloadingModelID = nil
        downloadProgress = 0.0
    }

    // MARK: - Load Model

    func loadModel(_ modelID: String) async throws {
        guard isDownloaded(modelID) else {
            throw ModelManagerError.notDownloaded(modelID)
        }

        // Run heavy model loading off the main actor
        let config = ModelConfiguration(id: modelID)
        let container = try await Task.detached {
            try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { _ in }
        }.value

        self.modelContainer = container
        self.loadedModelID = modelID
        Self.logger.info("Model \(modelID) loaded into memory")
    }

    // MARK: - Unload Model

    func unloadModel() {
        modelContainer = nil
        loadedModelID = nil
        // Flush MLX framework caches — without this, GPU/memory buffers stay allocated
        // even after dropping the Swift reference to ModelContainer.
        Memory.clearCache()
        Self.logger.info("Model unloaded from memory, MLX cache cleared")
    }

    // MARK: - Delete Model

    func deleteModel(_ modelID: String) {
        if loadedModelID == modelID {
            unloadModel()
        }

        let cachePath = NSHomeDirectory() + "/Library/Caches/models/\(modelID)"

        do {
            try FileManager.default.removeItem(atPath: cachePath)
            Self.logger.info("Deleted model \(modelID) from disk")
        } catch {
            Self.logger.error("Failed to delete model \(modelID): \(error)")
        }
    }

    // MARK: - Warm Keepalive

    /// Auto-load the last-used model on app launch. Call from onAppear.
    func warmKeepalive() {
        guard modelContainer == nil else { return }

        let settings = AppSettings()
        let modelID: String? = if !settings.selectedMLXModelID.isEmpty, isDownloaded(settings.selectedMLXModelID) {
            settings.selectedMLXModelID
        } else {
            downloadedModels.first?.id
        }

        guard let modelID else {
            Self.logger.info("No downloaded model for warm keepalive")
            return
        }

        Self.logger.info("Warm keepalive: auto-loading \(modelID)")
        Task {
            do {
                try await loadModel(modelID)
                Self.logger.info("Warm keepalive: \(modelID) ready")
            } catch {
                Self.logger.error("Warm keepalive failed: \(error)")
            }
        }
    }

    // MARK: - Memory Pressure Handling

    /// Start monitoring system memory pressure for tiered resource shedding.
    func startMemoryPressureMonitoring() {
        guard memoryPressureSource == nil else { return }

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            Task { @MainActor in
                self.handleMemoryPressure(event)
            }
        }

        source.resume()
        memoryPressureSource = source
        Self.logger.info("Memory pressure monitoring started")
    }

    private func handleMemoryPressure(_ event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) {
            Self.logger.warning("Memory pressure CRITICAL — clearing MLX cache")
            Memory.clearCache()
        } else if event.contains(.warning) {
            Self.logger.warning("Memory pressure WARNING — clearing MLX cache")
            Memory.clearCache()
        }
    }
}
